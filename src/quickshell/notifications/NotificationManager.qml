pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "../"
import "../reusables"
import "../reusables/markdown2html.js" as Markdown2Html

Item {
    id: root

    // ─── Core state ────────────────────────────────────────────────────
    property var liveNotifs: ({})
    property int popupCounter: 0
    property bool isStartup: true
    property bool sysPanelOpen: false
    property real lastNotifTime: 0
    property bool _isBatchUpdating: false

    // ─── Unread tracking ──────────────────────────────────────────────
    property var seenNotifications: []
    readonly property bool hasUnread: unreadCount > 0
    readonly property int unreadCount: {
        const seen = seenNotifications;
        if (seen.length === 0) return historyList.length;
        let count = 0;
        for (let i = 0; i < historyList.length; i++) {
            if (seen.indexOf(historyList[i].id) === -1) count++;
        }
        return count;
    }

    function markNotificationsSeen() {
        seenNotifications = historyList.map(n => n.id);
    }

    // ─── Model aliases (backward-compatible with popups/box/panel) ─────
    ListModel { id: historyModel }
    ListModel { id: popupsModel }
    ListModel { id: groupedHistoryModel }

    property alias globalNotificationHistory: historyModel
    property alias activePopupsModel: popupsModel
    property alias groupedHistory: groupedHistoryModel

    // ─── App resolution ────────────────────────────────────────────────
    property var _resolveCache: ({})
    property var manualAliasTable: ({
        "telegram": "org.telegram.desktop",
        "discord": "discord",
        "slack": "slack",
        "spotify": "spotify"
    })

    signal popupAdded(int uid, var notif)

    onSysPanelOpenChanged: {
        if (sysPanelOpen) {
            popupsModel.clear();
            _resolveCache = {};
        }
    }

    Timer {
        id: startupGraceTimer
        interval: 500
        running: true
        onTriggered: root.isStartup = false
    }

    // ─── Merged: Dedup system ─────────────────────────────────────────
    property int maxQueueSize: 32
    property int maxIngressPerSecond: 20
    property double _lastIngressSec: 0
    property int _ingressCountThisSec: 0
    readonly property int notificationDedupBurstMs: 5000
    property var _recentDedupKeys: []

    signal notificationDeduplicated(var wrapper)

    function _nowSec() {
        return Date.now() / 1000.0;
    }

    function _normalizeDedupText(text) {
        if (!text) return "";
        let normalized = text.toString();
        normalized = normalized.replace(/<img\b[^>]*>/gi, "");
        normalized = normalized.replace(/<[^>]+>/g, "");
        normalized = normalized.replace(/\s+/g, " ").trim();
        return normalized.toLowerCase();
    }

    function _dedupAppId(source) {
        if (!source) return "";
        const desktopEntry = (source.desktopEntry || "").toString().trim().toLowerCase();
        if (desktopEntry) return desktopEntry;
        return (source.appName || "").toString().trim().toLowerCase();
    }

    function _notificationDedupKey(source) {
        if (!source) return "";
        const app = _dedupAppId(source);
        const summary = _normalizeDedupText(source.summary);
        const body = _normalizeDedupText(source.body);
        const urgency = typeof source.urgency === "number" ? source.urgency : 1;
        if (!app && !summary && !body) return "";
        return app + summary + body + urgency;
    }

    function _pruneRecentDedupKeys() {
        const cutoff = Date.now() - notificationDedupBurstMs;
        _recentDedupKeys = _recentDedupKeys.filter(entry => entry && entry.atMs >= cutoff);
    }

    function _hasRecentDuplicate(key) {
        if (!key) return false;
        _pruneRecentDedupKeys();
        return _recentDedupKeys.some(entry => entry && entry.key === key);
    }

    function _recordDedupKey(key) {
        if (!key) return;
        _pruneRecentDedupKeys();
        _recentDedupKeys.push({ "key": key, "atMs": Date.now() });
    }

    function _ingressAllowed(urgency) {
        const t = _nowSec();
        if (t - _lastIngressSec >= 1.0) {
            _lastIngressSec = t;
            _ingressCountThisSec = 0;
        }
        _ingressCountThisSec += 1;
        if (urgency === 2) return true; // critical bypasses rate limit
        return _ingressCountThisSec <= maxIngressPerSecond;
    }

    // ─── Merged: Policy / rules engine ────────────────────────────────
    function _resolveAppNameForRule(notif) {
        if (!notif) return "";
        if (notif.appName && notif.appName !== "") return notif.appName;
        const entry = DesktopEntries.heuristicLookup(notif.desktopEntry);
        if (entry && entry.name) return entry.name;
        return "";
    }

    function _ruleFieldValue(field, info) {
        switch ((field || "").toString()) {
            case "desktopEntry": return info.desktopEntry;
            case "summary":     return info.summary;
            case "body":        return info.body;
            case "appName":
            default:            return info.appName;
        }
    }

    function _coerceRuleUrgency(value, fallbackUrgency) {
        if (typeof value === "number" && value >= 0 && value <= 2) return value;
        const mapped = (value || "default").toString().toLowerCase();
        switch (mapped) {
            case "low":      return 0;
            case "normal":   return 1;
            case "critical": return 2;
            default:         return fallbackUrgency;
        }
    }

    function _matchesNotificationRule(rule, info) {
        if (!rule) return false;
        if (rule.enabled === false) return false;
        const pattern = (rule.pattern || "").toString();
        if (!pattern.trim()) return false;
        const value = (_ruleFieldValue(rule.field, info) || "").toString();
        const matchType = (rule.matchType || "contains").toString().toLowerCase();
        if (matchType === "exact")
            return value.toLowerCase() === pattern.toLowerCase();
        if (matchType === "regex") {
            try { return new RegExp(pattern, "i").test(value); }
            catch (e) { return false; }
        }
        return value.toLowerCase().includes(pattern.toLowerCase());
    }

    function _evaluateNotificationPolicy(notif) {
        const baseUrgency = typeof notif.urgency === "number" ? notif.urgency : 1;
        const policy = {
            "drop": false, "disablePopup": false, "hideFromCenter": false,
            "disableHistory": false, "bypassDnd": false, "urgency": baseUrgency
        };
        const cfg = (typeof Config !== "undefined" && Config.getSetting)
            ? Config.getSetting("notifications", { rules: [] })
            : { rules: [] };
        const rules = cfg.rules || [];
        if (!rules.length) return policy;

        const info = {
            "appName": _resolveAppNameForRule(notif),
            "desktopEntry": notif.desktopEntry || "",
            "summary": notif.summary || "",
            "body": notif.body || ""
        };

        policy.bypassDnd = rules.some(rule => rule.bypassDnd === true && _matchesNotificationRule(rule, info));

        for (const rule of rules) {
            if (!_matchesNotificationRule(rule, info)) continue;
            const action = (rule.action || "default").toString().toLowerCase();
            switch (action) {
                case "ignore":     policy.drop = true; break;
                case "mute":       policy.disablePopup = true; break;
                case "popup_only": policy.hideFromCenter = true; policy.disableHistory = true; break;
                case "no_history": policy.disableHistory = true; break;
            }
            policy.urgency = _coerceRuleUrgency(rule.urgency, policy.urgency);
            return policy;
        }
        return policy;
    }

    function _allowedInDnd(urgency, bypassDnd) {
        if (bypassDnd) return true;
        const cfg = (typeof Config !== "undefined" && Config.getSetting)
            ? Config.getSetting("notifications", { dndAllowCritical: true })
            : { dndAllowCritical: true };
        if (cfg.dndAllowCritical && urgency === 2) return true;
        return false;
    }

    // ─── DND: permanent toggle + timed snooze ─────────────────────────
    // `notifications.dnd` (bool) is the permanent switch, `notifications.dndUntil`
    // (epoch ms) is an optional timed silence window layered on top of it.
    property real _dndClockTick: 0

    Timer {
        id: dndClockTimer
        interval: 15000
        repeat: true
        running: true
        onTriggered: root._dndClockTick = Date.now()
    }

    readonly property var _dndCfg: {
        root._dndClockTick;
        return (typeof Config !== "undefined" && Config.getSetting)
            ? Config.getSetting("notifications", { dnd: false, dndUntil: 0 })
            : { dnd: false, dndUntil: 0 };
    }

    readonly property bool dndPermanent: !!_dndCfg.dnd
    readonly property real dndUntil: _dndCfg.dndUntil || 0
    readonly property bool dndSnoozed: dndUntil > 0 && Date.now() < dndUntil
    readonly property bool dndActive: dndPermanent || dndSnoozed
    readonly property int dndRemainingMs: dndSnoozed ? Math.max(0, dndUntil - Date.now()) : 0

    function _patchNotificationConfig(patch) {
        const cfg = Object.assign({}, (typeof Config !== "undefined" && Config.getSetting)
            ? Config.getSetting("notifications", {}) : {});
        Object.assign(cfg, patch);
        Config.setSetting("notifications", cfg);
    }

    function setDndSnooze(minutes) {
        _patchNotificationConfig({ dndUntil: Date.now() + Math.max(1, minutes) * 60000 });
    }

    function clearDndSnooze() {
        _patchNotificationConfig({ dndUntil: 0 });
    }

    function toggleDndPermanent() {
        const nextValue = !root.dndPermanent;
        _patchNotificationConfig(nextValue ? { dnd: true } : { dnd: false, dndUntil: 0 });
    }

    function disableDnd() {
        _patchNotificationConfig({ dnd: false, dndUntil: 0 });
    }

    // ─── Merged: History persistence (JSON file) ──────────────────────
    readonly property string historyFile: (typeof Caching !== "undefined" ? Caching.cacheDir : "/tmp") + "/notification_history.json"
    readonly property string imageCacheDir: (typeof Caching !== "undefined" ? Caching.cacheDir : "/tmp") + "/notification_images"
    property var historyList: []
    property bool historyLoaded: false
    property int historyEntryCounter: 0

    FileView {
        id: historyFileView
        path: root.historyFile
        printErrors: false
        onLoaded: root.loadHistory()
        onLoadFailed: error => {
            if (error === 2) {
                root.historyLoaded = true;
                historyFileView.writeAdapter();
            }
        }
        JsonAdapter {
            id: historyAdapter
            property var notifications: []
        }
    }

    Timer {
        id: historySaveTimer
        interval: 200
        onTriggered: root.performSaveHistory()
    }

    function _makeHistoryEntryId(sourceId, timestamp) {
        historyEntryCounter += 1;
        const safeSource = sourceId && sourceId !== "" ? sourceId : "notification";
        return safeSource + "_" + (timestamp || Date.now()) + "_" + historyEntryCounter;
    }

    function addToHistory(notifData) {
        if (!notifData) return;
        const entry = {
            id: notifData.id || _makeHistoryEntryId(notifData.uid || "", notifData.timestamp || Date.now()),
            uid: notifData.uid,
            appName: notifData.appName || "",
            displayName: notifData.displayName || "",
            summary: notifData.summary || "",
            body: notifData.body || "",
            htmlBody: notifData.htmlBody || "",
            iconPath: notifData.iconPath || "",
            image: notifData.image || "",
            urgency: notifData.urgency !== undefined ? notifData.urgency : 1,
            timestamp: notifData.timestamp || Date.now(),
            read: notifData.read !== undefined ? notifData.read : false
        };
        let newList = [entry, ...historyList];
        const maxCount = 500;
        if (newList.length > maxCount) newList = newList.slice(0, maxCount);
        historyList = newList;
        saveHistory();
    }

    function saveHistory() {
        historySaveTimer.restart();
    }

    function performSaveHistory() {
        try {
            historyAdapter.notifications = historyList;
            historyFileView.writeAdapter();
        } catch (e) {
            console.warn("NotificationManager: save history failed:", e);
        }
    }

    function loadHistory() {
        try {
            const loaded = [];
            const seenIds = {};
            for (const item of historyAdapter.notifications || []) {
                let historyId = (item.id || "").toString();
                if (!historyId || seenIds[historyId]) {
                    historyId = _makeHistoryEntryId(item.uid || "", item.timestamp || Date.now());
                }
                seenIds[historyId] = true;
                loaded.push({
                    id: historyId,
                    uid: item.uid,
                    appName: item.appName || "",
                    displayName: item.displayName || "",
                    summary: item.summary || "",
                    body: item.body || "",
                    htmlBody: item.htmlBody || "",
                    iconPath: item.iconPath || "",
                    image: item.image || "",
                    urgency: item.urgency !== undefined ? item.urgency : 1,
                    timestamp: item.timestamp || 0,
                    read: item.read !== undefined ? item.read : false
                });
            }
            historyList = loaded;
            historyLoaded = true;
        } catch (e) {
            console.warn("NotificationManager: load history failed:", e);
            historyLoaded = true;
        }
    }

    function _deleteCachedImage(imagePath) {
        if (!imagePath || !imagePath.startsWith("file://")) return;
        const filePath = imagePath.replace("file://", "");
        if (filePath.startsWith(imageCacheDir)) {
            Quickshell.execDetached(["rm", "-f", filePath]);
        }
    }

    function removeFromHistory(notificationId) {
        const idx = historyList.findIndex(n => n.id === notificationId);
        if (idx >= 0) {
            _deleteCachedImage(historyList[idx].image);
            historyList = historyList.filter((_, i) => i !== idx);
            saveHistory();
            return true;
        }
        return false;
    }

    function clearHistory() {
        for (const item of historyList) _deleteCachedImage(item.image);
        historyList = [];
        historyAdapter.notifications = [];
        historyFileView.writeAdapter();
    }

    // Dismiss one or many persisted history entries by id (used by the
    // Notification Center UI for per-item and per-group dismiss). Also kills
    // the matching live popup/toast if it's still on screen, so dismissing
    // from history never leaves a stale popup behind.
    function dismissHistoryItems(ids) {
        if (!ids || ids.length === 0) return;
        const idSet = {};
        for (const id of ids) idSet[id] = true;

        const toRemove = historyList.filter(n => idSet[n.id]);
        if (toRemove.length === 0) return;

        for (const item of toRemove) {
            if (item.uid !== undefined && root.liveNotifs[item.uid]) {
                dismissNotification(item.uid);
            }
            _deleteCachedImage(item.image);
        }

        historyList = historyList.filter(n => !idSet[n.id]);
        saveHistory();
    }

    // Convenience: nuke everything — persisted history AND any currently
    // visible popups/toasts. Used by the Notification Center's "dismiss all".
    function dismissEverything() {
        dismissAllPopups();
        clearNotifications();
        clearHistory();
    }

    // ─── Batch dismiss ────────────────────────────────────────────────
    property var _dismissQueue: []
    property int _dismissBatchSize: 8
    property int _dismissTickMs: 8

    Timer {
        id: dismissBatchTimer
        interval: root._dismissTickMs
        repeat: true
        running: root._dismissQueue.length > 0
        onTriggered: root._processDismissBatch()
    }

    function _processDismissBatch() {
        if (_dismissQueue.length === 0) { dismissBatchTimer.stop(); return; }
        const batch = _dismissQueue.splice(0, _dismissBatchSize);
        for (const uid of batch) {
            let n = liveNotifs[uid];
            delete liveNotifs[uid];
            if (n) { try { if (typeof n.dismiss === "function") n.dismiss(); else if (typeof n.close === "function") n.close(); } catch (e) {} }
            for (let i = historyModel.count - 1; i >= 0; i--) {
                let nData = historyModel.get(i);
                if (nData && nData.uid === uid) { historyModel.remove(i, 1); break; }
            }
        }
        if (_dismissQueue.length === 0) {
            dismissBatchTimer.stop();
            _isBatchUpdating = false;
            rebuildGroups();
        }
    }

    // ─── Single-popup dismiss (called by auto-dismiss timer in delegate) ──
    function removePopup(uid) {
        // Remove from liveNotifs
        delete liveNotifs[uid];
        // Remove from active popups model
        for (let i = popupsModel.count - 1; i >= 0; i--) {
            let m = popupsModel.get(i);
            if (m && (m.uid === uid || m.latestUid === uid)) {
                popupsModel.remove(i, 1);
                break;
            }
        }
        // Remove from history model
        for (let i = historyModel.count - 1; i >= 0; i--) {
            let nData = historyModel.get(i);
            if (nData && nData.uid === uid) {
                historyModel.remove(i, 1);
                break;
            }
        }
        rebuildGroups();
    }

    function dismissNotification(uid) {
        // Close the underlying notification object if it exists
        let n = liveNotifs[uid];
        if (n) {
            try {
                if (typeof n.dismiss === "function") n.dismiss();
                else if (typeof n.close === "function") n.close();
            } catch (e) {}
        }
        removePopup(uid);
    }

    function dismissAllPopups() {
        const uids = [];
        for (let key in liveNotifs) { uids.push(Number(key)); }
        if (uids.length === 0) return;
        _isBatchUpdating = true;
        _dismissQueue = uids;
        if (!dismissBatchTimer.running) dismissBatchTimer.start();
    }

    // ─── Zombie sweeper ───────────────────────────────────────────────
    Timer {
        id: sweeperTimer
        interval: 2000
        repeat: true
        running: true
        onTriggered: root._sweepStaleNotifs()
    }

    function _sweepStaleNotifs() {
        let changed = false;
        for (let key in liveNotifs) {
            let n = liveNotifs[key];
            if (!n) { delete liveNotifs[key]; changed = true; continue; }
            if (typeof n.dismissed !== "undefined" && n.dismissed) {
                delete liveNotifs[key]; changed = true; continue;
            }
            if (typeof n.expired !== "undefined" && n.expired) {
                delete liveNotifs[key]; changed = true; continue;
            }
        }
        if (changed) rebuildGroups();
    }

    // ─── Markdown body rendering (from DankMaterialShell) ──────────────
    function _decodeEntities(s) {
        if (!s) return "";
        s = s.replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(parseInt(n, 10)));
        s = s.replace(/&#x([0-9a-fA-F]+);/g, (_, n) => String.fromCodePoint(parseInt(n, 16)));
        return s.replace(/&([a-zA-Z][a-zA-Z0-9]*);/g, (match, name) => {
            const entities = { "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " " };
            return entities[name.toLowerCase()] || match;
        });
    }

    function _resolveHtmlBody(body) {
        if (!body) return "";
        let result = body;
        // Already HTML — leave as-is
        if (/<\/?[a-z][\s\S]*>/i.test(body)) {
            result = body;
        } else {
            // Decode URL-encoded content
            let processed = body.replace(/\bhttps?%3A%2F%2F[^\s]+/gi, match => {
                try { return decodeURIComponent(match); } catch (e) { return match; }
            });
            // Decode HTML entities, then convert markdown
            if (/&(#\d+|#x[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]+);/.test(processed)) {
                const decoded = _decodeEntities(processed);
                if (/<\/?[a-z][\s\S]*>/i.test(decoded)) result = decoded;
                else result = Markdown2Html.markdownToHtml(decoded);
            } else {
                result = Markdown2Html.markdownToHtml(processed);
            }
        }
        // Strip images — they're handled separately
        return result.replace(/<img\b[^>]*>/gi, "");
    }

    function _getEffectiveBody(body, htmlBody) {
        if (htmlBody && htmlBody.trim() !== "") return htmlBody;
        if (body && body.trim() !== "") return _resolveHtmlBody(body);
        return "";
    }

    // ─── Notification groups ──────────────────────────────────────────
    property var notificationGroups: []

    function rebuildGroups() {
        if (_isBatchUpdating) return;
        const groups = [];
        const seen = {};
        for (let i = 0; i < historyModel.count; i++) {
            const n = historyModel.get(i);
            if (!n) continue;
            const gk = n.groupKey || n.appName || "System";
            if (!seen[gk]) {
                seen[gk] = { groupKey: gk, appName: n.appName, displayName: n.displayName, items: [], unreadCount: 0 };
                groups.push(seen[gk]);
            }
            seen[gk].items.push(n);
            if (n.read === false) seen[gk].unreadCount++;
        }
        notificationGroups = groups;
    }

    function clearNotifications() {
        historyModel.clear();
        notificationGroups = [];
    }

    function markAsRead(uid) {
        for (let i = 0; i < historyModel.count; i++) {
            const n = historyModel.get(i);
            if (n && n.uid === uid) {
                historyModel.setProperty(i, "read", true);
                break;
            }
        }
        // Also mark in persisted history
        for (let j = 0; j < historyList.length; j++) {
            if (historyList[j].uid === uid) {
                historyList[j].read = true;
                break;
            }
        }
        saveHistory();
        rebuildGroups();
    }

    // ─── App resolution ───────────────────────────────────────────────
    function resolveApp(n) {
        const uid = n._uid || "";
        if (_resolveCache[uid]) return _resolveCache[uid];

        let desktopEntry = "";
        let displayName = n.appName || "System";
        let icon = n.appIcon || "";

        // Try DesktopEntries heuristic
        if (typeof DesktopEntries !== "undefined" && n.desktopEntry) {
            const entry = DesktopEntries.heuristicLookup(n.desktopEntry);
            if (entry) {
                desktopEntry = entry.filename || n.desktopEntry;
                displayName = entry.name || displayName;
                if (entry.icon) icon = entry.icon;
            }
        }

        const result = { desktopEntry: desktopEntry, displayName: displayName, icon: icon, groupKey: desktopEntry || displayName || "System" };
        _resolveCache[uid] = result;
        return result;
    }

    // ─── Search & filter ──────────────────────────────────────────────
    property string searchFilter: ""
    property string appFilter: ""

    function getFilteredHistory() {
        let list = historyList;
        if (searchFilter && searchFilter.length > 0) {
            const q = searchFilter.toLowerCase();
            list = list.filter(n =>
                (n.summary && n.summary.toLowerCase().indexOf(q) !== -1) ||
                (n.body && n.body.toLowerCase().indexOf(q) !== -1) ||
                (n.displayName && n.displayName.toLowerCase().indexOf(q) !== -1) ||
                (n.appName && n.appName.toLowerCase().indexOf(q) !== -1)
            );
        }
        if (appFilter && appFilter.length > 0) {
            const a = appFilter.toLowerCase();
            list = list.filter(n =>
                (n.displayName && n.displayName.toLowerCase().indexOf(a) !== -1) ||
                (n.appName && n.appName.toLowerCase().indexOf(a) !== -1)
            );
        }
        return list;
    }

    function searchHistory(query) {
        searchFilter = query || "";
    }

    function filterByApp(appName) {
        appFilter = appName || "";
    }

    // ─── Time range helpers ───────────────────────────────────────────
    function getHistoryTimeRange(timestamp) {
        if (!timestamp) return 2;
        var now = new Date();
        var notifDate = new Date(timestamp);
        var startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        if (notifDate >= startOfToday) return 0; // Today
        var startOfYesterday = new Date(startOfToday.getTime() - 86400000);
        if (notifDate >= startOfYesterday) return 1; // Yesterday
        return 2; // Older
    }

    function getHistoryTimeRangeLabel(range) {
        switch (range) {
            case 0: return "Today";
            case 1: return "Yesterday";
            case 2: return "Older";
            default: return "All";
        }
    }

    function getHistoryTimeRangeCount(range) {
        if (range === -1) return historyList.length;
        return historyList.filter(n => getHistoryTimeRange(n.timestamp) === range).length;
    }

    function getHistoryApps() {
        const apps = {};
        for (const n of historyList) {
            const key = n.displayName || n.appName || "System";
            if (!apps[key]) apps[key] = { name: key, icon: n.iconPath || "", count: 0 };
            apps[key].count++;
        }
        return Object.values(apps).sort((a, b) => b.count - a.count);
    }

    // ─── App launch ───────────────────────────────────────────────────
    function launchApp(desktopEntry) {
        if (!desktopEntry) return;
        if (typeof DesktopEntries !== "undefined") {
            const entry = DesktopEntries.heuristicLookup(desktopEntry);
            if (entry && entry.execute) {
                Quickshell.execDetached(entry.execute);
                return;
            }
        }
        // Fallback: try to launch by desktop entry name
        Quickshell.execDetached(["gtk-launch", desktopEntry]);
    }

    // ─── Notification actions ─────────────────────────────────────────
    function invokeNotificationAction(uid, actionId) {
        const n = liveNotifs[uid];
        if (!n || !n.actions) return;
        for (const action of n.actions) {
            if (action.identifier === actionId) {
                action.invoke();
                return;
            }
        }
    }

    // ─── NotificationServer ───────────────────────────────────────────
    NotificationServer {
        id: globalNotificationServer
        keepOnReload: false
        actionsSupported: true
        actionIconsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        imageSupported: true
        inlineReplySupported: true
        persistenceSupported: true

        onNotification: (n) => {
            // Startup grace
            if (root.isStartup) { try { n.dismiss(); } catch (e) {} return; }

            // ── Policy evaluation (merged from downloaded) ──
            const policy = root._evaluateNotificationPolicy(n);
            if (policy.drop) { try { n.dismiss(); } catch (e) {} return; }

            // ── Dedup (merged from downloaded, replaces 100ms debounce) ──
            if (typeof Config !== "undefined" && Config.getSetting) {
                const _dCfg = Config.getSetting("notifications", { dedupeEnabled: true });
                if (_dCfg.dedupeEnabled !== false) {
                    const dedupKey = root._notificationDedupKey(n);
                    if (root._hasRecentDuplicate(dedupKey)) {
                        root._recordDedupKey(dedupKey);
                        try { n.dismiss(); } catch (e) {}
                        return;
                    }
                    root._recordDedupKey(dedupKey);
                }
            }

            // ── Rate limiting (merged from downloaded) ──
            if (!root._ingressAllowed(policy.urgency)) {
                if (policy.urgency !== 2) { try { n.dismiss(); } catch (e) {} return; }
            }

            // ── DnD check (permanent toggle OR active timed snooze) ──
            const dndBlocked = root.dndActive && !root._allowedInDnd(policy.urgency, policy.bypassDnd);

            // Sound is handled by Notification.qml — no duplicate here

            // ── Attach to tracker ──
            n.tracked = true;
            root.lastNotifTime = Date.now();

            let extractedActions = [];
            if (n.actions) {
                for (let i = 0; i < n.actions.length; i++) {
                    extractedActions.push({
                        id: n.actions[i].identifier || "",
                        text: n.actions[i].text || n.actions[i].name || "Action"
                    });
                }
            }

            root.popupCounter++;
            let currentUid = root.popupCounter;
            root.liveNotifs[currentUid] = n;

            if (n.closed) {
                n.closed.connect(() => {
                    if (root.liveNotifs[currentUid]) {
                        delete root.liveNotifs[currentUid];
                        for (let i = 0; i < historyModel.count; i++) {
                            let item = historyModel.get(i);
                            if (item && item.uid === currentUid) { historyModel.remove(i, 1); break; }
                        }
                    }
                });
            }

            let hasAct = extractedActions.length > 0;
            let resolved = root.resolveApp(n);
            let summaryText = n.summary !== "" ? n.summary : "No Title";
            let bodyText = n.body !== "" ? n.body : "";
            let htmlBodyText = root._resolveHtmlBody(bodyText);
            let imageVal = (n.image ? n.image.toString() : "") || (n.imagePath ? n.imagePath.toString() : "") || (n.appIcon ? n.appIcon.toString() : "");

            let notifData = {
                appName: n.appName !== "" ? n.appName : "System",
                displayName: resolved.displayName,
                summary: summaryText, body: bodyText, htmlBody: htmlBodyText,
                iconPath: n.appIcon !== "" ? n.appIcon : "",
                image: imageVal, imagePath: imageVal,
                actionsJson: JSON.stringify(extractedActions), hasActions: hasAct,
                uid: currentUid, notif: n, timestamp: Date.now(),
                urgency: policy.urgency, read: false
            };

            // ── History persistence (merged from downloaded) ──
            const shouldKeepInCenter = !n.transient && !policy.hideFromCenter;
            if (shouldKeepInCenter) {
                historyModel.insert(0, notifData);
                if (typeof Config !== "undefined" && Config.getSetting) {
                    const _hiCfg = Config.getSetting("notifications", { historyEnabled: true });
                    if (_hiCfg.historyEnabled !== false && !policy.disableHistory) {
                        root.addToHistory(notifData);
                    }
                } else if (!policy.disableHistory) {
                    root.addToHistory(notifData);
                }
            }

            // ── Popup (from current src) ──
            const shouldShowPopup = !root.sysPanelOpen && !dndBlocked && !policy.disablePopup;
            if (shouldShowPopup) {
                popupsModel.insert(0, {
                    uid: currentUid, latestUid: currentUid,
                    uidsJson: JSON.stringify([currentUid]),
                    groupKey: resolved.groupKey,
                    appName: resolved.displayName, displayName: resolved.displayName,
                    icon: resolved.icon || notifData.iconPath,
                    image: imageVal, imagePath: imageVal,
                    summary: summaryText, body: bodyText, htmlBody: htmlBodyText,
                    combinedBody: bodyText,
                    messagesJson: JSON.stringify(bodyText !== "" ? [bodyText] : []),
                    messagesCount: 1, iconPath: notifData.iconPath,
                    actionsJson: JSON.stringify(extractedActions), hasActions: hasAct,
                    notif: n, urgency: policy.urgency, timestamp: Date.now()
                });
                root.popupAdded(currentUid, n);
            }

            root.rebuildGroups();
        }
    }

    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", historyFile.replace(/\/[^\/]*$/, "")]);
        Quickshell.execDetached(["mkdir", "-p", imageCacheDir]);
    }
}
