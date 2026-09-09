pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "../"
import "../reusables"

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

    Timer {
        id: pruneHistoryTimer
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.pruneHistory()
    }

    function _makeHistoryEntryId(sourceId, timestamp) {
        historyEntryCounter += 1;
        const safe = sourceId && sourceId !== "" ? sourceId : "notification";
        return safe + "_" + (timestamp || Date.now()) + "_" + historyEntryCounter;
    }

    function addToHistory(notifData) {
        if (!notifData) return;
        const data = {
            id: _makeHistoryEntryId(notifData.uid, notifData.timestamp),
            uid: notifData.uid,
            appName: notifData.appName || "",
            displayName: notifData.displayName || "",
            summary: notifData.summary || "",
            body: notifData.body || "",
            image: notifData.image || "",
            iconPath: notifData.iconPath || "",
            urgency: typeof notifData.urgency === "number" ? notifData.urgency : 1,
            timestamp: notifData.timestamp || Date.now(),
            read: false
        };
        let newList = [data, ...historyList];
        const _hCfg = (typeof Config !== "undefined" && Config.getSetting) ? Config.getSetting("notifications", { maxCount: 200, maxAgeDays: 30 }) : {};
        const maxCount = _hCfg.maxCount || 200;
        if (newList.length > maxCount) newList = newList.slice(0, maxCount);
        historyList = newList;
        saveHistory();
    }

    function saveHistory() { historySaveTimer.restart(); }

    function performSaveHistory() {
        try {
            historyAdapter.notifications = historyList;
            historyFileView.writeAdapter();
        } catch (e) {
            if (root.log) root.log.warn("save history failed:", e);
        }
    }

    function loadHistory() {
        try {
            const _lCfg = (typeof Config !== "undefined" && Config.getSetting) ? Config.getSetting("notifications", { maxAgeDays: 30 }) : {};
            const maxAgeDays = _lCfg.maxAgeDays || 30;
            const now = Date.now();
            const maxAgeMs = maxAgeDays > 0 ? maxAgeDays * 24 * 60 * 60 * 1000 : 0;
            const loaded = [];
            const seenIds = {};
            let needsRewrite = false;
            for (const item of historyAdapter.notifications || []) {
                if (maxAgeMs > 0 && (now - item.timestamp) > maxAgeMs) continue;
                let historyId = (item.id || "").toString();
                if (!historyId || seenIds[historyId]) {
                    historyId = _makeHistoryEntryId(item.uid, item.timestamp || now);
                    needsRewrite = true;
                }
                seenIds[historyId] = true;
                loaded.push({
                    id: historyId,
                    uid: item.uid,
                    appName: item.appName || "",
                    displayName: item.displayName || "",
                    summary: item.summary || "",
                    body: item.body || "",
                    image: item.image || "",
                    iconPath: item.iconPath || "",
                    urgency: typeof item.urgency === "number" ? item.urgency : 1,
                    timestamp: item.timestamp || 0,
                    read: item.read || false
                });
            }
            historyList = loaded;
            historyLoaded = true;
            if (needsRewrite) saveHistory();
        } catch (e) {
            if (root.log) root.log.warn("load history failed:", e);
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
                delete liveNotifs[key]; changed = true;
            } else if (typeof n.closed !== "undefined" && n.closed) {
                delete liveNotifs[key]; changed = true;
            }
        }
        if (changed) rebuildGroups();
    }

    // ─── Image persistence ────────────────────────────────────────────
    function getImageCachePath(notifData) {
        const ts = notifData.timestamp || Date.now();
        const uid = notifData.uid || "0";
        return imageCacheDir + "/notif_" + ts + "_" + uid + ".png";
    }

    function persistNotificationImage(notifData) {
        if (!notifData || !notifData.image) return;
        const imgUrl = notifData.image.toString();
        if (!imgUrl || imgUrl === "" || imgUrl.startsWith("image://")) return;
        const cachePath = getImageCachePath(notifData);
        if (imgUrl.startsWith("http://") || imgUrl.startsWith("https://")) {
            Quickshell.execDetached(["bash", "-c",
                "curl -sL '" + imgUrl.replace(/'/g, "'\\''") + "' -o '" + cachePath + "' 2>/dev/null || true"]);
        } else if (imgUrl.startsWith("file://")) {
            const src = imgUrl.replace("file://", "");
            Quickshell.execDetached(["cp", "--", src, cachePath]);
        }
    }

    // ─── Convenience helpers ──────────────────────────────────────────
    function getHistoryCountForRange(range) {
        if (range === -1) return historyList.length;
        return historyList.filter(n => getHistoryTimeRange(n.timestamp) === range).length;
    }

    function markGroupNotificationsSeen(groupKey) {
        const newSeen = seenNotifications.slice();
        for (let i = 0; i < historyList.length; i++) {
            const n = historyList[i];
            let resolved = resolveApp(n);
            let gKey = resolved.groupKey;
            if (n.urgency === 2) gKey += "_crit_" + n.uid;
            if (gKey === groupKey && newSeen.indexOf(n.id) === -1) {
                newSeen.push(n.id);
            }
        }
        seenNotifications = newSeen;
    }

    readonly property bool hasUnread: unreadCount > 0

    function pruneHistory() {
        const _pCfg = (typeof Config !== "undefined" && Config.getSetting) ? Config.getSetting("notifications", { maxAgeDays: 30 }) : {};
        const maxAgeDays = _pCfg.maxAgeDays || 30;
        if (maxAgeDays <= 0) return;
        const now = Date.now();
        const maxAgeMs = maxAgeDays * 24 * 60 * 60 * 1000;
        const pruned = historyList.filter(item => (now - item.timestamp) <= maxAgeMs);
        if (pruned.length !== historyList.length) {
            historyList = pruned;
            saveHistory();
        }
    }

    function deleteHistory() { clearHistory(); }

    // ─── Search / filter (for NotificationCenter) ─────────────────────
    property string searchFilter: ""
    property string appFilter: ""

    function searchHistory(query) {
        searchFilter = (query || "").trim().toLowerCase();
    }

    function filterByApp(appName) {
        appFilter = (appName || "").trim().toLowerCase();
    }

    function getFilteredHistory() {
        let list = historyList;
        if (searchFilter !== "") {
            list = list.filter(function(n) {
                let s = (n.summary || "").toLowerCase();
                let b = (n.body || "").toLowerCase();
                let a = (n.appName || "").toLowerCase();
                let d = (n.displayName || "").toLowerCase();
                return s.indexOf(searchFilter) !== -1 || b.indexOf(searchFilter) !== -1 || a.indexOf(searchFilter) !== -1 || d.indexOf(searchFilter) !== -1;
            });
        }
        if (appFilter !== "") {
            list = list.filter(function(n) {
                let a = (n.appName || "").toLowerCase();
                let d = (n.displayName || "").toLowerCase();
                return a.indexOf(appFilter) !== -1 || d.indexOf(appFilter) !== -1;
            });
        }
        return list;
    }

    function getHistoryTimeRange(timestamp) {
        var now = new Date();
        var today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        var itemDate = new Date(timestamp);
        var itemDay = new Date(itemDate.getFullYear(), itemDate.getMonth(), itemDate.getDate());
        var diffMs = today.getTime() - itemDay.getTime();
        var diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));
        if (diffDays === 0) return 0;  // today
        if (diffDays === 1) return 1;  // yesterday
        return 2;                      // older
    }

    function getHistoryTimeRangeLabel(range) {
        if (range === 0) return "Today";
        if (range === 1) return "Yesterday";
        return "Older";
    }

    function getHistoryTimeRangeCount(range) {
        var list = getFilteredHistory();
        if (range === -1) return list.length;
        return list.filter(function(n) { return getHistoryTimeRange(n.timestamp) === range; }).length;
    }

    function getHistoryApps() {
        var apps = {};
        for (var i = 0; i < historyList.length; i++) {
            var n = historyList[i];
            var name = n.displayName || n.appName || "";
            if (name && !apps[name]) apps[name] = true;
        }
        return Object.keys(apps).sort();
    }

    // ─── App launch (click-to-open) ──────────────────────────────────
    function launchApp(desktopEntry) {
        if (!desktopEntry) return;
        var entry = null;
        if (typeof desktopEntry === "string") {
            entry = DesktopEntries.byId(desktopEntry);
        } else {
            entry = desktopEntry;
        }
        if (entry && entry.launch) {
            entry.launch();
        } else if (typeof desktopEntry === "string" && desktopEntry !== "") {
            Quickshell.execDetached(["gtk-launch", desktopEntry]);
        }
    }

    function invokeNotificationAction(uid, actionId) {
        var n = liveNotifs[uid];
        if (!n || !n.actions) return;
        for (var i = 0; i < n.actions.length; i++) {
            if (n.actions[i].identifier === actionId) {
                n.actions[i].invoke();
                return;
            }
        }
    }

    // ─── App resolution (from current src) ────────────────────────────
    function resolveApp(n) {
        if (!n) return { groupKey: "system", displayName: "System", icon: "", desktopEntry: null };
        let rawAppName = n.appName || "";
        let appName = rawAppName.toLowerCase().trim();
        appName = appName.replace(/\s*(canary|beta|nightly|-git|git|dev|development)\s*$/g, "");
        let desktopEntry = (n.desktopEntry || "").trim();
        let key = desktopEntry + "|" + appName;
        if (_resolveCache[key] !== undefined) return _resolveCache[key];
        let entry = null;
        if (desktopEntry) entry = DesktopEntries.byId(desktopEntry);
        if (!entry && appName) {
            let alias = manualAliasTable[appName];
            if (alias) entry = DesktopEntries.byId(alias);
            else entry = DesktopEntries.heuristicLookup(rawAppName);
        }
        let resolved = {
            groupKey: entry ? entry.id : (appName || "system"),
            displayName: entry ? entry.name : (rawAppName || "System"),
            icon: n.appIcon || (entry ? entry.icon : ""),
            desktopEntry: entry
        };
        _resolveCache[key] = resolved;
        return resolved;
    }

    // ─── Grouping (from current src, unchanged) ───────────────────────
    function markGroupRead(groupKey) {
        let changed = false;
        for (let i = 0; i < historyModel.count; i++) {
            let nData = historyModel.get(i);
            if (!nData) continue;
            let resolved = resolveApp(nData);
            let gKey = resolved.groupKey;
            if (nData.urgency === 2) gKey += "_crit_" + nData.uid;
            if (gKey === groupKey && !nData.read) {
                historyModel.setProperty(i, "read", true);
                changed = true;
            }
        }
        if (changed) rebuildGroups();
    }

    function markAsRead(uid) {
        let changed = false;
        for (let i = 0; i < historyModel.count; i++) {
            let nData = historyModel.get(i);
            if (nData && nData.uid === uid && !nData.read) {
                historyModel.setProperty(i, "read", true);
                changed = true;
                break;
            }
        }
        if (changed) rebuildGroups();
    }

    function rebuildGroups() {
        let groupedMap = {};
        let newOrder = [];
        for (let i = 0; i < historyModel.count; i++) {
            let nData = historyModel.get(i);
            if (!nData) continue;
            let n = root.liveNotifs[nData.uid] || nData.notif;
            let resolved = resolveApp(n || nData);
            let gKey = resolved.groupKey;
            if (nData.urgency === 2) gKey += "_crit_" + nData.uid;
            if (!groupedMap[gKey]) {
                groupedMap[gKey] = {
                    groupKey: gKey, displayName: resolved.displayName, icon: resolved.icon,
                    members: [], count: 0, unreadCount: 0,
                    latestSummary: nData.summary, latestBody: nData.body,
                    latestTimestamp: (n && n.timestamp) ? n.timestamp : (nData.timestamp || Date.now())
                };
                newOrder.push(gKey);
            }
            let ts = (n && n.timestamp) ? n.timestamp : (nData.timestamp || Date.now());
            if (ts >= groupedMap[gKey].latestTimestamp) {
                groupedMap[gKey].latestTimestamp = ts;
                groupedMap[gKey].latestSummary = nData.summary;
                groupedMap[gKey].latestBody = nData.body;
            }
            groupedMap[gKey].members.push({
                appName: nData.appName, summary: nData.summary, body: nData.body,
                iconPath: nData.iconPath, image: nData.image, imagePath: nData.imagePath,
                actionsJson: nData.actionsJson, hasActions: nData.hasActions,
                uid: nData.uid, notif: nData.notif, timestamp: ts,
                urgency: nData.urgency, read: nData.read
            });
            groupedMap[gKey].count = groupedMap[gKey].members.length;
            if (!nData.read) groupedMap[gKey].unreadCount++;
        }
        for (let i = groupedHistoryModel.count - 1; i >= 0; i--) {
            let item = groupedHistoryModel.get(i);
            if (!item || !groupedMap[item.groupKey]) groupedHistoryModel.remove(i, 1);
        }
        for (let i = 0; i < newOrder.length; i++) {
            let gKey = newOrder[i];
            let gData = groupedMap[gKey];
            let itemsJsonStr = JSON.stringify(gData.members);
            let existingIndex = -1;
            for (let j = 0; j < groupedHistoryModel.count; j++) {
                if (groupedHistoryModel.get(j)?.groupKey === gKey) { existingIndex = j; break; }
            }
            let modelEntry = {
                groupKey: gKey, displayName: gData.displayName, icon: gData.icon,
                count: gData.count, unreadCount: gData.unreadCount,
                latestSummary: gData.latestSummary, latestBody: gData.latestBody,
                latestTimestamp: gData.latestTimestamp, itemsJson: itemsJsonStr
            };
            if (existingIndex === -1) {
                groupedHistoryModel.insert(i, modelEntry);
            } else {
                if (existingIndex !== i && existingIndex < groupedHistoryModel.count && i < groupedHistoryModel.count) {
                    groupedHistoryModel.move(existingIndex, i, 1);
                }
                let item = groupedHistoryModel.get(i);
                if (item) {
                    for (const field of ["displayName","icon","count","unreadCount","latestSummary","latestBody","latestTimestamp","itemsJson"]) {
                        if (item[field] !== modelEntry[field]) item[field] = modelEntry[field];
                    }
                }
            }
        }
    }

    Connections {
        target: historyModel
        function onCountChanged() {
            if (!root._isBatchUpdating) root.rebuildGroups();
        }
    }

    // ─── Public API (backward-compatible with all consumers) ──────────
    function clearNotifications() {
        root._isBatchUpdating = true;
        for (let key in root.liveNotifs) {
            let n = root.liveNotifs[key];
            if (n) { try { if (typeof n.dismiss === "function") n.dismiss(); else if (typeof n.close === "function") n.close(); } catch (e) {} }
        }
        root.liveNotifs = {};
        historyModel.clear();
        popupsModel.clear();
        groupedHistoryModel.clear();
        root._isBatchUpdating = false;
    }

    function dismissNotification(uid) {
        let n = root.liveNotifs[uid];
        delete root.liveNotifs[uid];
        if (n) { try { if (typeof n.dismiss === "function") n.dismiss(); else if (typeof n.close === "function") n.close(); } catch (e) {} }
        for (let i = 0; i < historyModel.count; i++) {
            let nData = historyModel.get(i);
            if (nData && nData.uid === uid) { historyModel.remove(i, 1); break; }
        }
    }

    function dismissGroup(groupKey) {
        if (!historyModel || historyModel.count === 0) return;
        root._isBatchUpdating = true;
        for (let i = historyModel.count - 1; i >= 0; i--) {
            let nData = historyModel.get(i);
            if (!nData) continue;
            let n = root.liveNotifs[nData.uid] || nData.notif;
            let resolved = resolveApp(n || nData);
            let gKey = resolved.groupKey;
            if (nData.urgency === 2) gKey += "_crit_" + nData.uid;
            if (gKey === groupKey) {
                delete root.liveNotifs[nData.uid];
                if (n) { try { if (typeof n.dismiss === "function") n.dismiss(); else if (typeof n.close === "function") n.close(); } catch (e) {} }
                if (i < historyModel.count) historyModel.remove(i, 1);
            }
        }
        root._isBatchUpdating = false;
        rebuildGroups();
    }

    function removePopup(uid) {
        if (!popupsModel || popupsModel.count === 0) return;
        for (let i = popupsModel.count - 1; i >= 0; i--) {
            let p = popupsModel.get(i);
            if (!p) continue;
            let matches = (p.uid === uid || p.latestUid === uid);
            if (!matches && p.uidsJson) {
                try { let uList = JSON.parse(p.uidsJson); if (Array.isArray(uList) && uList.indexOf(uid) !== -1) matches = true; } catch (e) {}
            }
            if (matches) { popupsModel.remove(i, 1); break; }
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
            let imageVal = (n.image ? n.image.toString() : "") || (n.imagePath ? n.imagePath.toString() : "") || (n.appIcon ? n.appIcon.toString() : "");

            let notifData = {
                appName: n.appName !== "" ? n.appName : "System",
                displayName: resolved.displayName,
                summary: summaryText, body: bodyText,
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
                    summary: summaryText, body: bodyText,
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
