import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import "../"
import "../reusables"
import "../reusables/RofiKeyNav.js" as RofiKeyNav
import "EmojiSearch.js" as ESearch

PanelWindow {
    id: emojiWindow

    screen: EmojiController.screen

    WlrLayershell.namespace: "qs-emoji"
    WlrLayershell.layer: WlrLayer.Overlay
    focusable: emojiWindow.isVisible
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    mask: Region { item: topBarHole; intersection: Intersection.Xor }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    function s(val) {
        return (typeof Scaler !== "undefined" && Scaler.s) ? Scaler.s(val) : val;
    }

    function closeEmoji() {
        EmojiController.hide();
    }

    property bool isVisible: EmojiController.isVisible
    property int configRevision: 0

    // ── Bar-relative attach chrome (same convention as Clipboard/Launcher) ──
    property var rawBarSettings: {
        let dummy = configRevision;
        return (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar) ? Config.rawSettings.bar : ({});
    }
    property string barPosition: (rawBarSettings && rawBarSettings.position !== undefined) ? rawBarSettings.position : "top"
    property bool barAutohide: (rawBarSettings && rawBarSettings.autohide !== undefined) ? Boolean(rawBarSettings.autohide) : false

    Connections {
        target: (typeof Config !== "undefined") ? Config : null
        function onSettingsLoaded() {
            EmojiController.hide();
            emojiWindow.configRevision++;
        }
    }

    readonly property bool isFullscreenActive: {
        try {
            if (typeof Hyprland !== "undefined" && Hyprland.focusedWorkspace) {
                return Boolean(Hyprland.focusedWorkspace.hasFullscreen || (Hyprland.activeToplevel && Hyprland.activeToplevel.fullscreen));
            }
        } catch (e) {}
        return false;
    }

    readonly property bool isBarEffectivelyHidden: barAutohide || isFullscreenActive

    property string attachEdge: {
        if (barPosition === "bottom") return "top";
        if (barPosition === "left") return "right";
        if (barPosition === "right") return "left";
        return "bottom";
    }

    onBarPositionChanged: EmojiController.hide()

    property bool isSideAttached: attachEdge === "left" || attachEdge === "right"
    property real cornerRadius: ThemeBackend.borderRadius <= 16 ? ThemeBackend.borderRadius * 2 : Math.min(32, 32 - 16 * Math.exp(-(ThemeBackend.borderRadius - 16) / 12))

    property real basePickerWidth: isSideAttached ? Math.round(s(400)) : Math.round(s(640))
    property real basePickerHeight: isSideAttached ? Math.round(s(620)) : Math.round(s(500))

    visible: isVisible || container.animProgress > 0.001

    // ─────────────────────────── State ───────────────────────────
    property string activeTab: "emoji"        // "emoji" | "nerd" | "kao"
    property string activeCategory: "all"
    property string searchText: ""
    property int selIndex: 0
    property int hoveredIndex: -1
    property bool keepOpenChecked: false
    property bool nerdEscapeMode: false

    readonly property var tabOrder: ["emoji", "nerd", "kao"]

    property bool wantEmoji: true
    property bool wantNerd: false
    property bool wantKao: false

    property bool emojiLoaded: false
    property bool nerdLoaded: false
    property bool kaoLoaded: false

    property var emojiRaw: []
    property var nerdRaw: []
    property var kaoRaw: []

    property var emojiLookup: ({})
    property var nerdLookup: ({})
    property var kaoLookup: ({})

    property var resultsModel: []
    property var categoriesModel: []
    property var shelfModel: []

    readonly property int halfLifeDays: 10
    readonly property int shelfLimit: 18

    function activateFromController(mode) {
        if (mode === "nerd" || mode === "nerdfont" || mode === "nerd-font") {
            emojiWindow.setActiveTab("nerd");
        } else if (mode === "kao" || mode === "kaomoji") {
            emojiWindow.setActiveTab("kao");
        } else if (mode === "emoji") {
            emojiWindow.setActiveTab("emoji");
        }
    }

    Connections {
        target: EmojiController
        function onRequestNonceChanged() {
            emojiWindow.activateFromController(EmojiController.requestedMode);
        }
    }

    function setActiveTab(tab) {
        if (emojiWindow.activeTab === tab) return;
        emojiWindow.activeTab = tab;
        emojiWindow.activeCategory = "all";
        emojiWindow.selIndex = 0;
        emojiWindow.hoveredIndex = -1;
        if (tab === "nerd") emojiWindow.wantNerd = true;
        if (tab === "kao") emojiWindow.wantKao = true;
        emojiWindow.rebuildCategories();
        emojiWindow.rebuildResults();
        emojiWindow.rebuildShelf();
    }

    function cycleTab(delta) {
        let current = emojiWindow.tabOrder.indexOf(emojiWindow.activeTab);
        let next = (current + delta + emojiWindow.tabOrder.length) % emojiWindow.tabOrder.length;
        emojiWindow.setActiveTab(emojiWindow.tabOrder[next]);
    }

    // ───────────────────── History (frecency store) ─────────────────────
    readonly property string historyFile: (typeof Caching !== "undefined" ? Caching.getCacheDir("emoji") : "/tmp") + "/history.json"

    FileView {
        id: historyFileView
        path: emojiWindow.historyFile
        printErrors: false
        onLoaded: emojiWindow.rebuildShelf()
        onLoadFailed: error => {
            if (error === 2) {
                historyFileView.writeAdapter();
            }
        }
        JsonAdapter {
            id: historyAdapter
            property var entries: ({})
        }
    }

    Timer {
        id: historySaveTimer
        interval: 250
        repeat: false
        onTriggered: historyFileView.writeAdapter()
    }

    function recordUsage(key) {
        if (!key) return;
        let now = Date.now();
        let entries = Object.assign({}, historyAdapter.entries || {});
        let cur = entries[key] || { c: 0, t: 0 };
        entries[key] = { c: (cur.c || 0) + 1, t: now };

        let keys = Object.keys(entries);
        if (keys.length > 400) {
            let scored = keys.map(k => ({ k: k, sc: ESearch.decayedScore(entries[k], emojiWindow.halfLifeDays, now) }));
            scored.sort((a, b) => a.sc - b.sc);
            let dropCount = keys.length - 400;
            for (let i = 0; i < dropCount; i++) delete entries[scored[i].k];
        }

        historyAdapter.entries = entries;
        historySaveTimer.restart();
        emojiWindow.rebuildShelf();
    }

    function clearHistory() {
        historyAdapter.entries = {};
        historyFileView.writeAdapter();
        emojiWindow.rebuildShelf();
    }

    function currentLookup() {
        if (emojiWindow.activeTab === "nerd") return emojiWindow.nerdLookup;
        if (emojiWindow.activeTab === "kao") return emojiWindow.kaoLookup;
        return emojiWindow.emojiLookup;
    }

    function rebuildShelf() {
        emojiWindow.shelfModel = ESearch.topUsed(historyAdapter.entries, emojiWindow.currentLookup(), emojiWindow.shelfLimit, emojiWindow.halfLifeDays);
    }

    // ───────────────────────── Dataset loading ─────────────────────────
    FileView {
        id: emojiDataView
        path: emojiWindow.wantEmoji ? (Caching.qsDir + "/emoji/data/emoji.json") : ""
        printErrors: false
        onLoaded: emojiWindow.onEmojiDataLoaded(typeof emojiDataView.text === "function" ? emojiDataView.text() : emojiDataView.text)
    }

    FileView {
        id: nerdDataView
        path: emojiWindow.wantNerd ? (Caching.qsDir + "/emoji/data/nerdfont.json") : ""
        printErrors: false
        onLoaded: emojiWindow.onNerdDataLoaded(typeof nerdDataView.text === "function" ? nerdDataView.text() : nerdDataView.text)
    }

    FileView {
        id: kaoDataView
        path: emojiWindow.wantKao ? (Caching.qsDir + "/emoji/data/kaomoji.json") : ""
        printErrors: false
        onLoaded: emojiWindow.onKaoDataLoaded(typeof kaoDataView.text === "function" ? kaoDataView.text() : kaoDataView.text)
    }

    function onEmojiDataLoaded(txt) {
        try {
            let arr = JSON.parse(txt);
            let lookup = {};
            for (let i = 0; i < arr.length; i++) lookup["e:" + arr[i].u] = arr[i];
            emojiWindow.emojiRaw = arr;
            emojiWindow.emojiLookup = lookup;
        } catch (e) {
            emojiWindow.emojiRaw = [];
        }
        emojiWindow.emojiLoaded = true;
        if (emojiWindow.activeTab === "emoji") {
            emojiWindow.rebuildCategories();
            emojiWindow.rebuildResults();
        }
        emojiWindow.rebuildShelf();
    }

    function onNerdDataLoaded(txt) {
        try {
            let arr = JSON.parse(txt);
            let lookup = {};
            for (let i = 0; i < arr.length; i++) lookup["n:" + arr[i].n] = arr[i];
            emojiWindow.nerdRaw = arr;
            emojiWindow.nerdLookup = lookup;
        } catch (e) {
            emojiWindow.nerdRaw = [];
        }
        emojiWindow.nerdLoaded = true;
        if (emojiWindow.activeTab === "nerd") {
            emojiWindow.rebuildCategories();
            emojiWindow.rebuildResults();
        }
        emojiWindow.rebuildShelf();
    }

    function onKaoDataLoaded(txt) {
        try {
            let arr = JSON.parse(txt);
            let lookup = {};
            for (let i = 0; i < arr.length; i++) lookup["k:" + arr[i].e] = arr[i];
            emojiWindow.kaoRaw = arr;
            emojiWindow.kaoLookup = lookup;
        } catch (e) {
            emojiWindow.kaoRaw = [];
        }
        emojiWindow.kaoLoaded = true;
        if (emojiWindow.activeTab === "kao") {
            emojiWindow.rebuildCategories();
            emojiWindow.rebuildResults();
        }
        emojiWindow.rebuildShelf();
    }

    // ───────────────────────── Categories ─────────────────────────
    readonly property var emojiCategoryIcons: ({
        smileys: "\ud83d\ude00",
        people: "\ud83e\uddd1",
        nature: "\ud83d\udc3b",
        food: "\ud83c\udf54",
        travel: "\ud83d\ude97",
        activities: "\u26bd",
        objects: "\ud83d\udca1",
        symbols: "\ud83d\udd23",
        flags: "\ud83d\udea9"
    })

    readonly property var kaoCategoryLabels: ({
        happy: "Happy", sad: "Sad", love: "Love", angry: "Angry",
        tableflip: "Table Flip", surprised: "Surprised", confused: "Confused",
        smug: "Smug", sleepy: "Sleepy", thumbsup: "Thumbs Up", flex: "Flex",
        dance: "Dance", food: "Food", shrug: "Shrug", greeting: "Greeting",
        apology: "Apology", embarrassed: "Embarrassed", laughing: "Laughing",
        disapproval: "Disapproval", cat: "Cat", bear: "Bear", animal: "Animal",
        excited: "Excited", determined: "Determined", cool: "Cool", dead: "Dead"
    })

    function labelizeCode(code) {
        return code.split("-").map(w => w.length ? (w.charAt(0).toUpperCase() + w.slice(1)) : w).join(" ");
    }

    function rebuildCategories() {
        let out = [{ code: "all", label: "All", icon: "" }];
        if (emojiWindow.activeTab === "emoji") {
            let order = ["smileys", "people", "nature", "food", "travel", "activities", "objects", "symbols", "flags"];
            for (let i = 0; i < order.length; i++) {
                out.push({ code: order[i], label: emojiWindow.labelizeCode(order[i]), icon: emojiWindow.emojiCategoryIcons[order[i]] || "" });
            }
        } else if (emojiWindow.activeTab === "nerd") {
            let set = {};
            for (let i = 0; i < emojiWindow.nerdRaw.length; i++) set[emojiWindow.nerdRaw[i].g] = true;
            let codes = Object.keys(set).sort();
            for (let i = 0; i < codes.length; i++) out.push({ code: codes[i], label: emojiWindow.labelizeCode(codes[i]), icon: "" });
        } else if (emojiWindow.activeTab === "kao") {
            let set = {};
            for (let i = 0; i < emojiWindow.kaoRaw.length; i++) set[emojiWindow.kaoRaw[i].c] = true;
            let codes = Object.keys(set).sort();
            for (let i = 0; i < codes.length; i++) out.push({ code: codes[i], label: emojiWindow.kaoCategoryLabels[codes[i]] || emojiWindow.labelizeCode(codes[i]), icon: "" });
        }
        emojiWindow.categoriesModel = out;
    }

    // ───────────────────────── Search + ranking ─────────────────────────
    function activeDataset() {
        if (emojiWindow.activeTab === "nerd") return emojiWindow.nerdRaw;
        if (emojiWindow.activeTab === "kao") return emojiWindow.kaoRaw;
        return emojiWindow.emojiRaw;
    }

    function fieldsForActiveTab() {
        if (emojiWindow.activeTab === "nerd") {
            return [
                { get: i => i.n, weight: 3 },
                { get: i => i.g, weight: 1 },
                { get: i => i.u, weight: 1 },
                { get: i => i.e, weight: 5 }
            ];
        }
        if (emojiWindow.activeTab === "kao") {
            return [
                { get: i => i.n, weight: 3 },
                { get: i => i.k, weight: 2 },
                { get: i => i.c, weight: 1 },
                { get: i => i.e, weight: 5 }
            ];
        }
        return [
            { get: i => i.n, weight: 3 },
            { get: i => i.k, weight: 2 },
            { get: i => i.c, weight: 1 },
            { get: i => i.u, weight: 1 },
            { get: i => i.e, weight: 5 }
        ];
    }

    function keyOfActiveTab(item) {
        if (emojiWindow.activeTab === "nerd") return "n:" + item.n;
        if (emojiWindow.activeTab === "kao") return "k:" + item.e;
        return "e:" + item.u;
    }

    function rebuildResults() {
        let dataset = emojiWindow.activeDataset();
        if (emojiWindow.activeCategory !== "all") {
            let cat = emojiWindow.activeCategory;
            let field = emojiWindow.activeTab === "nerd" ? "g" : "c";
            dataset = dataset.filter(it => it[field] === cat);
        }

        let q = ESearch.normalizeHexQuery(emojiWindow.searchText.trim().toLowerCase());
        if (q.length === 0) {
            emojiWindow.resultsModel = dataset;
        } else {
            emojiWindow.resultsModel = ESearch.filterAndSort(
                dataset, q, emojiWindow.fieldsForActiveTab(),
                emojiWindow.keyOfActiveTab, historyAdapter.entries, emojiWindow.halfLifeDays
            );
        }

        emojiWindow.selIndex = emojiWindow.resultsModel.length > 0 ? 0 : -1;
        emojiWindow.hoveredIndex = -1;
    }

    Timer {
        id: searchDebounce
        interval: 80
        repeat: false
        onTriggered: emojiWindow.rebuildResults()
    }

    function setCategory(code) {
        if (emojiWindow.activeCategory === code) return;
        emojiWindow.activeCategory = code;
        emojiWindow.rebuildResults();
    }

    function cycleCategory(delta) {
        if (emojiWindow.categoriesModel.length <= 1) return;
        let idx = -1;
        for (let i = 0; i < emojiWindow.categoriesModel.length; i++) {
            if (emojiWindow.categoriesModel[i].code === emojiWindow.activeCategory) {
                idx = i;
                break;
            }
        }
        if (idx < 0) idx = 0;
        let next = (idx + delta + emojiWindow.categoriesModel.length) % emojiWindow.categoriesModel.length;
        emojiWindow.setCategory(emojiWindow.categoriesModel[next].code);
    }

    // ───────────────────────── Item description ─────────────────────────
    function toUnicodeEscape(hex) {
        try {
            let cp = parseInt(hex.split("-")[0], 16);
            if (isNaN(cp)) return "";
            if (cp > 0xFFFF) return "\\u{" + hex + "}";
            return "\\u" + ("0000" + hex).slice(-4);
        } catch (e) {
            return "";
        }
    }

    function describeItem(item) {
        if (!item) return null;
        if (emojiWindow.activeTab === "nerd") {
            return {
                copyText: emojiWindow.nerdEscapeMode ? emojiWindow.toUnicodeEscape(item.u) : item.e,
                glyph: item.e,
                key: "n:" + item.n,
                label: item.n,
                sub: "\\u" + item.u
            };
        }
        if (emojiWindow.activeTab === "kao") {
            return {
                copyText: item.e,
                glyph: item.e,
                key: "k:" + item.e,
                label: item.n,
                sub: emojiWindow.kaoCategoryLabels[item.c] || item.c
            };
        }
        return {
            copyText: item.e,
            glyph: item.e,
            key: "e:" + item.u,
            label: item.n,
            sub: "U+" + item.u.toUpperCase()
        };
    }

    function copyDescribed(desc, keepOpen) {
        if (!desc || !desc.copyText) return;
        Quickshell.execDetached(["wl-copy", "--", desc.copyText]);
        if (typeof Sounds !== "undefined") Sounds.playSfx("system/quick_click.wav");
        emojiWindow.recordUsage(desc.key);
        if (!keepOpen) emojiWindow.closeEmoji();
    }

    function activateIndex(idx, keepOpen) {
        if (idx < 0 || idx >= emojiWindow.resultsModel.length) return;
        emojiWindow.copyDescribed(emojiWindow.describeItem(emojiWindow.resultsModel[idx]), keepOpen);
    }

    function handleActivateKey(event) {
        if (event.modifiers & Qt.AltModifier) {
            emojiWindow.typeIndex(emojiWindow.selIndex);
        } else {
            emojiWindow.activateIndex(emojiWindow.selIndex, emojiWindow.keepOpenChecked);
        }
        event.accepted = true;
    }

    function activateShelf(item, keepOpen) {
        emojiWindow.copyDescribed(emojiWindow.describeItem(item), keepOpen);
    }

    // ───────────────────── Direct typing (Ctrl+Enter / Ctrl+click) ─────────────────────
    // Instead of going through the clipboard, this types the glyph straight into
    // whatever window regains keyboard focus once the picker closes. Wayland has
    // no xdotool-equivalent that works everywhere, so we shell out to `wtype`
    // (the wlroots/virtual-keyboard analogue), same convention as wl-copy above.
    Timer {
        id: typeDispatchTimer
        interval: 120 // give the compositor time to hand focus back before typing
        repeat: false
        property string pendingText: ""
        onTriggered: {
            if (typeDispatchTimer.pendingText.length > 0) {
                Quickshell.execDetached(["wtype", "--", typeDispatchTimer.pendingText]);
                typeDispatchTimer.pendingText = "";
            }
        }
    }

    function typeDescribed(desc) {
        if (!desc || !desc.copyText) return;
        if (typeof Sounds !== "undefined") Sounds.playSfx("system/quick_click.wav");
        emojiWindow.recordUsage(desc.key);
        typeDispatchTimer.pendingText = desc.copyText;
        // Typing only makes sense once focus has left the picker, so this
        // always closes -- unlike copy, "keep open" doesn't apply here.
        emojiWindow.closeEmoji();
        typeDispatchTimer.restart();
    }

    function typeIndex(idx) {
        if (idx < 0 || idx >= emojiWindow.resultsModel.length) return;
        emojiWindow.typeDescribed(emojiWindow.describeItem(emojiWindow.resultsModel[idx]));
    }

    function typeShelf(item) {
        emojiWindow.typeDescribed(emojiWindow.describeItem(item));
    }

    // ───────────────────────── Keyboard navigation ─────────────────────────
    readonly property int effGridColumns: Math.max(1, pickerGrid.cellWidth > 0 ? Math.floor(pickerGrid.width / pickerGrid.cellWidth) : 1)
    readonly property int effRowStep: emojiWindow.activeTab === "kao" ? 1 : emojiWindow.effGridColumns

    function moveSelection(delta) {
        if (emojiWindow.resultsModel.length === 0) return;
        let next = emojiWindow.selIndex + delta;
        if (next < 0) next = 0;
        if (next >= emojiWindow.resultsModel.length) next = emojiWindow.resultsModel.length - 1;
        emojiWindow.selIndex = next;
        emojiWindow.hoveredIndex = -1;
        if (emojiWindow.activeTab === "kao") {
            pickerList.positionViewAtIndex(next, ListView.Contain);
        } else {
            pickerGrid.positionViewAtIndex(next, GridView.Contain);
        }
    }

    function grabInputFocus() {
        searchInput.forceActiveFocus();
        if (typeof searchInput.forceInputFocus === "function") searchInput.forceInputFocus();
    }

    Timer { id: focusTimer; interval: 30; onTriggered: emojiWindow.grabInputFocus() }
    Timer { id: focusRetryTimer; interval: 120; onTriggered: emojiWindow.grabInputFocus() }
    Timer { id: focusFinalTimer; interval: 250; onTriggered: emojiWindow.grabInputFocus() }

    onIsVisibleChanged: {
        if (isVisible) {
            searchInput.clear();
            emojiWindow.searchText = "";
            // nerdEscapeMode is a QML property, not a FileView-backed setting: it
            // survives across opens because this window is only hidden, never
            // destroyed. Left as-is, toggling it on once (e.g. to grab a "\uXXXX"
            // literal for a config file) silently makes every later devicon copy
            // return an escape sequence instead of the actual glyph, which is
            // exactly the "copies \u1234 instead of the icon" bug reported for
            // Nerd Font/devicon entries. Reset it on every open so the default
            // action is always "copy the glyph as-is".
            emojiWindow.nerdEscapeMode = false;
            emojiWindow.rebuildCategories();
            emojiWindow.rebuildResults();
            emojiWindow.rebuildShelf();
            emojiWindow.grabInputFocus();
            focusTimer.restart();
            focusRetryTimer.restart();
            focusFinalTimer.restart();
        } else {
            focusTimer.stop();
            focusRetryTimer.stop();
            focusFinalTimer.stop();
        }
    }

    Component.onCompleted: {
        emojiWindow.rebuildCategories();
    }

    // ───────────────────────── Chrome (bar-hole mask) ─────────────────────────
    Item {
        id: topBarHole
        property int barThickness: 48
        property string bp: emojiWindow.barPosition
        property bool activeBar: !emojiWindow.isBarEffectivelyHidden

        x: {
            if (!activeBar) return 0;
            if (bp === "left") return 0;
            if (bp === "right") return emojiWindow.width - barThickness;
            return 0;
        }
        y: {
            if (!activeBar) return 0;
            if (bp === "top") return 0;
            if (bp === "bottom") return emojiWindow.height - barThickness;
            return 0;
        }
        width: {
            if (!activeBar) return 0;
            if (bp === "left" || bp === "right") return barThickness;
            return emojiWindow.width;
        }
        height: {
            if (!activeBar) return 0;
            if (bp === "top" || bp === "bottom") return barThickness;
            return emojiWindow.height;
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: emojiWindow.isVisible
        onClicked: emojiWindow.closeEmoji()
    }

    Item {
        id: container
        property real animProgress: emojiWindow.isVisible ? 1.0 : 0.0
        Behavior on animProgress {
            NumberAnimation { duration: emojiWindow.isVisible ? 300 : 200; easing.type: Easing.OutCubic }
        }

        x: {
            if (emojiWindow.attachEdge === "left") return 0;
            if (emojiWindow.attachEdge === "right") return emojiWindow.width - width;
            return Math.floor((emojiWindow.width - width) / 2);
        }
        y: {
            if (emojiWindow.attachEdge === "top") return 0;
            if (emojiWindow.attachEdge === "bottom") return emojiWindow.height - height;
            return Math.floor((emojiWindow.height - height) / 2);
        }
        width: emojiWindow.basePickerWidth * (emojiWindow.isSideAttached ? animProgress : 1.0)
        height: emojiWindow.basePickerHeight * (!emojiWindow.isSideAttached ? animProgress : 1.0)
        opacity: (emojiWindow.isVisible || animProgress > 0.001) ? 1.0 : 0.0

        MouseArea { anchors.fill: parent }

        Rectangle {
            id: bgCard
            anchors.fill: parent
            radius: emojiWindow.cornerRadius
            color: ThemeBackend.base
            clip: true

            Item {
                id: contentContainer
                anchors.fill: parent
                anchors.margins: emojiWindow.s(14)

                ColumnLayout {
                    anchors.fill: parent
                    spacing: emojiWindow.s(8)

                    // ── Tabs ──
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: emojiWindow.s(32)
                        spacing: emojiWindow.s(6)

                        ClickButton {
                            Layout.fillWidth: true
                            Layout.preferredHeight: emojiWindow.s(32)
                            buttonText: emojiWindow.isSideAttached ? "" : (typeof I18n !== "undefined" ? I18n.t("emoji.tabEmoji", "Emoji") : "Emoji")
                            buttonIcon: "\ud83d\ude00"
                            iconFontSize: emojiWindow.s(14)
                            textFontSize: emojiWindow.s(11)
                            cornerRadius: Math.min(ThemeBackend.borderRadius, emojiWindow.s(10))
                            accentColor: emojiWindow.activeTab === "emoji" ? ThemeBackend.mauve : ThemeBackend.surface0
                            textColor: emojiWindow.activeTab === "emoji" ? ThemeBackend.crust : ThemeBackend.text
                            onTriggered: emojiWindow.setActiveTab("emoji")
                        }
                        ClickButton {
                            Layout.fillWidth: true
                            Layout.preferredHeight: emojiWindow.s(32)
                            buttonText: emojiWindow.isSideAttached ? "" : (typeof I18n !== "undefined" ? I18n.t("emoji.tabNerd", "Nerd Font") : "Nerd Font")
                            buttonIcon: "󰌌"
                            iconFontSize: emojiWindow.s(14)
                            textFontSize: emojiWindow.s(11)
                            cornerRadius: Math.min(ThemeBackend.borderRadius, emojiWindow.s(10))
                            accentColor: emojiWindow.activeTab === "nerd" ? ThemeBackend.mauve : ThemeBackend.surface0
                            textColor: emojiWindow.activeTab === "nerd" ? ThemeBackend.crust : ThemeBackend.text
                            onTriggered: emojiWindow.setActiveTab("nerd")
                        }
                        ClickButton {
                            Layout.fillWidth: true
                            Layout.preferredHeight: emojiWindow.s(32)
                            buttonText: emojiWindow.isSideAttached ? "" : (typeof I18n !== "undefined" ? I18n.t("emoji.tabKaomoji", "Kaomoji") : "Kaomoji")
                            buttonIcon: "(\u30fb\u2200\u30fb)"
                            iconFontSize: emojiWindow.s(11)
                            textFontSize: emojiWindow.s(11)
                            cornerRadius: Math.min(ThemeBackend.borderRadius, emojiWindow.s(10))
                            accentColor: emojiWindow.activeTab === "kao" ? ThemeBackend.mauve : ThemeBackend.surface0
                            textColor: emojiWindow.activeTab === "kao" ? ThemeBackend.crust : ThemeBackend.text
                            onTriggered: emojiWindow.setActiveTab("kao")
                        }
                    }

                    // ── Search row ──
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: emojiWindow.s(36)
                        spacing: emojiWindow.s(8)

                        Input {
                            id: searchInput
                            focus: true
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.preferredHeight: emojiWindow.s(36)

                            baseColor: ThemeBackend.surface0
                            accentColor: ThemeBackend.mauve
                            textColor: ThemeBackend.text
                            subTextColor: ThemeBackend.subtext0
                            borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                            cornerRadius: Math.min(ThemeBackend.borderRadius, emojiWindow.s(10))
                            fontPixelSize: emojiWindow.s(12)
                            leadingIcon: ""
                            showClearButton: true

                            placeholderText: typeof I18n !== "undefined" ? I18n.t("emoji.search", "Search by name, tag or unicode") : "Search by name, tag or unicode"

                            onTextEdited: function(newText) {
                                emojiWindow.searchText = newText;
                                searchDebounce.restart();
                            }
                            onCleared: {
                                emojiWindow.searchText = "";
                                emojiWindow.rebuildResults();
                            }

                            Keys.onDownPressed: function(event) { emojiWindow.moveSelection(emojiWindow.effRowStep); event.accepted = true; }
                            Keys.onUpPressed: function(event) { emojiWindow.moveSelection(-emojiWindow.effRowStep); event.accepted = true; }
                            Keys.onTabPressed: function(event) { emojiWindow.cycleTab(1); event.accepted = true; }
                            Keys.onBacktabPressed: function(event) { emojiWindow.cycleTab(-1); event.accepted = true; }
                            onKeyPressed: function(event) {
                                // Ctrl+H / Ctrl+L: cycle subcategories (Smileys/People/...,
                                // devicons/codicons/..., Happy/Sad/...), vim-style and
                                // consistent with the existing Ctrl+J/K row nav below.
                                // Handled here (Input's early keyPressed signal) rather than
                                // an outer Keys.onPressed because QQuickTextInput treats
                                // Ctrl+H as a native backspace shortcut and would otherwise
                                // consume it first.
                                if (event.modifiers & Qt.AltModifier) {
                                    if (event.key === Qt.Key_L) {
                                        emojiWindow.cycleCategory(1);
                                        event.accepted = true;
                                        return;
                                    }
                                    if (event.key === Qt.Key_H) {
                                        emojiWindow.cycleCategory(-1);
                                        event.accepted = true;
                                        return;
                                    }
                                }
                                if (event.key === Qt.Key_Left) {
                                    emojiWindow.moveSelection(-1);
                                    event.accepted = true;
                                    return;
                                }
                                if (event.key === Qt.Key_Right) {
                                    emojiWindow.moveSelection(1);
                                    event.accepted = true;
                                    return;
                                }
                                if (RofiKeyNav.handlePressed(event, function() { emojiWindow.moveSelection(emojiWindow.effRowStep); }, function() { emojiWindow.moveSelection(-emojiWindow.effRowStep); })) {
                                    event.accepted = true;
                                }
                            }
                            Keys.onReturnPressed: function(event) { emojiWindow.handleActivateKey(event); }
                            Keys.onEnterPressed: function(event) { emojiWindow.handleActivateKey(event); }
                            Keys.onEscapePressed: function(event) {
                                emojiWindow.closeEmoji();
                                event.accepted = true;
                            }
                        }

                        Toggle {
                            id: keepOpenToggle
                            Layout.preferredHeight: emojiWindow.s(32)
                            buttonText: emojiWindow.isSideAttached ? "" : (typeof I18n !== "undefined" ? I18n.t("emoji.keepOpen", "Keep open") : "Keep open")
                            textFontSize: emojiWindow.s(10.5)
                            checked: emojiWindow.keepOpenChecked
                            accentColor: ThemeBackend.mauve
                            baseColor: ThemeBackend.surface0
                            textColor: ThemeBackend.text
                            onToggled: (v) => emojiWindow.keepOpenChecked = v
                        }

                        Toggle {
                            id: escapeToggle
                            visible: emojiWindow.activeTab === "nerd"
                            Layout.preferredHeight: emojiWindow.s(32)
                            buttonText: emojiWindow.isSideAttached ? "" : (typeof I18n !== "undefined" ? I18n.t("emoji.escapeMode", "\\u code") : "\\u code")
                            textFontSize: emojiWindow.s(10.5)
                            checked: emojiWindow.nerdEscapeMode
                            accentColor: ThemeBackend.peach
                            baseColor: ThemeBackend.surface0
                            textColor: ThemeBackend.text
                            onToggled: (v) => emojiWindow.nerdEscapeMode = v
                        }

                        IconButton {
                            id: clearHistoryBtn
                            size: emojiWindow.s(32)
                            cornerRadius: Math.min(ThemeBackend.borderRadius, emojiWindow.s(10))
                            buttonIcon: ""
                            iconFontSize: emojiWindow.s(14)
                            accentColor: ThemeBackend.surface0
                            textColor: ThemeBackend.text
                            onClicked: emojiWindow.clearHistory()
                        }
                    }

                    // ── Category chips ──
                    Flickable {
                        id: categoryFlick
                        Layout.fillWidth: true
                        Layout.preferredHeight: emojiWindow.s(26)
                        visible: emojiWindow.categoriesModel.length > 1
                        contentWidth: categoryRow.implicitWidth
                        contentHeight: height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.HorizontalFlick

                        Row {
                            id: categoryRow
                            height: parent.height
                            spacing: emojiWindow.s(6)

                            Repeater {
                                model: emojiWindow.categoriesModel
                                delegate: Rectangle {
                                    required property var modelData
                                    height: emojiWindow.s(26)
                                    width: chipLabel.implicitWidth + emojiWindow.s(16)
                                    radius: height / 2
                                    color: emojiWindow.activeCategory === modelData.code ? ThemeBackend.mauve : ThemeBackend.surface0

                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    Text {
                                        id: chipLabel
                                        anchors.centerIn: parent
                                        text: (modelData.icon ? modelData.icon + " " : "") + modelData.label
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: emojiWindow.s(10.5)
                                        color: emojiWindow.activeCategory === modelData.code ? ThemeBackend.crust : ThemeBackend.subtext1
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: emojiWindow.setCategory(modelData.code)
                                    }
                                }
                            }
                        }
                    }

                    // ── Frequently used shelf ──
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: emojiWindow.searchText.trim().length === 0 && emojiWindow.shelfModel.length > 0
                        spacing: emojiWindow.s(3)

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: emojiWindow.s(4)
                            Text {
                                text: "󰓎"
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: emojiWindow.s(10)
                                color: ThemeBackend.yellow
                            }
                            Text {
                                text: typeof I18n !== "undefined" ? I18n.t("emoji.frequent", "Frequently used") : "Frequently used"
                                font.family: ThemeBackend.fontFamily
                                font.weight: Font.Bold
                                font.pixelSize: emojiWindow.s(10.5)
                                color: ThemeBackend.subtext0
                                opacity: 0.85
                            }
                        }

                        ListView {
                            id: shelfList
                            Layout.fillWidth: true
                            Layout.preferredHeight: emojiWindow.s(38)
                            orientation: ListView.Horizontal
                            spacing: emojiWindow.s(4)
                            model: emojiWindow.shelfModel
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Rectangle {
                                required property var modelData
                                width: emojiWindow.s(36)
                                height: emojiWindow.s(36)
                                radius: emojiWindow.s(8)
                                color: shelfMa.containsMouse ? ThemeBackend.surface1 : "transparent"

                                Behavior on color { ColorAnimation { duration: 120 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.e
                                    font.family: emojiWindow.activeTab === "nerd" ? "Iosevka Nerd Font" : (emojiWindow.activeTab === "kao" ? "JetBrains Mono" : ThemeBackend.fontFamily)
                                    font.pixelSize: emojiWindow.activeTab === "kao" ? emojiWindow.s(9) : emojiWindow.s(18)
                                    color: ThemeBackend.text
                                    elide: Text.ElideNone
                                }

                                MouseArea {
                                    id: shelfMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: (mouse) => {
                                        if (mouse.modifiers & Qt.AltModifier) {
                                            emojiWindow.typeShelf(modelData);
                                            return;
                                        }
                                        let keepOpen = mouse.button === Qt.RightButton ? true : emojiWindow.keepOpenChecked;
                                        emojiWindow.activateShelf(modelData, keepOpen);
                                    }
                                }
                            }
                        }
                    }

                    // ── Main results area ──
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        Text {
                            anchors.centerIn: parent
                            visible: emojiWindow.resultsModel.length === 0
                            text: typeof I18n !== "undefined" ? I18n.t("emoji.empty", "Nothing found") : "Nothing found"
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: emojiWindow.s(12)
                            color: ThemeBackend.subtext0
                        }

                        GridView {
                            id: pickerGrid
                            anchors.fill: parent
                            visible: emojiWindow.activeTab !== "kao"
                            model: visible ? emojiWindow.resultsModel : []
                            currentIndex: emojiWindow.selIndex
                            cellWidth: emojiWindow.s(44)
                            cellHeight: emojiWindow.s(44)
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            cacheBuffer: emojiWindow.s(400)

                            ScrollBar.vertical: ScrollBar {
                                active: pickerGrid.moving || pickerGrid.movingVertically
                                width: emojiWindow.s(4)
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle { implicitWidth: emojiWindow.s(4); radius: emojiWindow.s(2); color: ThemeBackend.surface2 }
                            }

                            delegate: Item {
                                id: gridDelegate
                                required property var modelData
                                required property int index
                                width: pickerGrid.cellWidth
                                height: pickerGrid.cellHeight

                                readonly property bool isSel: index === emojiWindow.selIndex

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: emojiWindow.s(2)
                                    radius: emojiWindow.s(8)
                                    color: gridDelegate.isSel ? ThemeBackend.mauve : (gridMa.containsMouse ? ThemeBackend.surface1 : "transparent")
                                    scale: gridMa.pressed ? 0.92 : 1.0

                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuint } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: gridDelegate.modelData.e
                                        font.family: emojiWindow.activeTab === "nerd" ? "Iosevka Nerd Font" : undefined
                                        font.pixelSize: emojiWindow.s(20)
                                        color: gridDelegate.isSel ? ThemeBackend.crust : ThemeBackend.text
                                    }

                                    MouseArea {
                                        id: gridMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: {
                                            emojiWindow.selIndex = gridDelegate.index;
                                            emojiWindow.hoveredIndex = gridDelegate.index;
                                        }
                                        onExited: {
                                            if (emojiWindow.hoveredIndex === gridDelegate.index) emojiWindow.hoveredIndex = -1;
                                        }
                                        onClicked: (mouse) => {
                                            emojiWindow.selIndex = gridDelegate.index;
                                            if (mouse.modifiers & Qt.AltModifier) {
                                                emojiWindow.typeIndex(gridDelegate.index);
                                                return;
                                            }
                                            let keepOpen = mouse.button === Qt.RightButton ? true : emojiWindow.keepOpenChecked;
                                            emojiWindow.activateIndex(gridDelegate.index, keepOpen);
                                        }
                                    }
                                }
                            }
                        }

                        ListView {
                            id: pickerList
                            anchors.fill: parent
                            visible: emojiWindow.activeTab === "kao"
                            model: visible ? emojiWindow.resultsModel : []
                            currentIndex: emojiWindow.selIndex
                            spacing: emojiWindow.s(3)
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            cacheBuffer: emojiWindow.s(400)

                            ScrollBar.vertical: ScrollBar {
                                active: pickerList.moving || pickerList.movingVertically
                                width: emojiWindow.s(4)
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle { implicitWidth: emojiWindow.s(4); radius: emojiWindow.s(2); color: ThemeBackend.surface2 }
                            }

                            delegate: Item {
                                id: listDelegate
                                required property var modelData
                                required property int index
                                width: ListView.view ? ListView.view.width : 0
                                height: emojiWindow.s(38)

                                readonly property bool isSel: index === emojiWindow.selIndex

                                Rectangle {
                                    anchors.fill: parent
                                    radius: emojiWindow.s(8)
                                    color: listDelegate.isSel ? ThemeBackend.mauve : (listMa.containsMouse ? ThemeBackend.surface1 : "transparent")
                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: emojiWindow.s(10)
                                        anchors.rightMargin: emojiWindow.s(10)
                                        spacing: emojiWindow.s(10)

                                        Text {
                                            text: listDelegate.modelData.e
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: emojiWindow.s(14)
                                            color: listDelegate.isSel ? ThemeBackend.crust : ThemeBackend.text
                                            Layout.preferredWidth: emojiWindow.s(220)
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: listDelegate.modelData.n
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: emojiWindow.s(11)
                                            color: listDelegate.isSel ? ThemeBackend.crust : ThemeBackend.subtext0
                                            opacity: 0.85
                                            elide: Text.ElideRight
                                        }
                                    }

                                    MouseArea {
                                        id: listMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: {
                                            emojiWindow.selIndex = listDelegate.index;
                                            emojiWindow.hoveredIndex = listDelegate.index;
                                        }
                                        onExited: {
                                            if (emojiWindow.hoveredIndex === listDelegate.index) emojiWindow.hoveredIndex = -1;
                                        }
                                        onClicked: (mouse) => {
                                            emojiWindow.selIndex = listDelegate.index;
                                            if (mouse.modifiers & Qt.AltModifier) {
                                                emojiWindow.typeIndex(listDelegate.index);
                                                return;
                                            }
                                            let keepOpen = mouse.button === Qt.RightButton ? true : emojiWindow.keepOpenChecked;
                                            emojiWindow.activateIndex(listDelegate.index, keepOpen);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Footer preview / hints ──
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: emojiWindow.s(24)
                        spacing: emojiWindow.s(8)

                        readonly property var previewIdx: emojiWindow.hoveredIndex >= 0 ? emojiWindow.hoveredIndex : emojiWindow.selIndex
                        readonly property var previewItem: (previewIdx >= 0 && previewIdx < emojiWindow.resultsModel.length) ? emojiWindow.resultsModel[previewIdx] : null
                        readonly property var previewDesc: previewItem ? emojiWindow.describeItem(previewItem) : null

                        Text {
                            visible: parent.previewDesc !== null
                            text: parent.previewDesc ? parent.previewDesc.glyph : ""
                            font.family: emojiWindow.activeTab === "nerd" ? "Iosevka Nerd Font" : (emojiWindow.activeTab === "kao" ? "JetBrains Mono" : undefined)
                            font.pixelSize: emojiWindow.s(16)
                            color: ThemeBackend.text
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: parent.previewDesc !== null
                            text: parent.previewDesc ? (parent.previewDesc.label + "  \u00b7  " + parent.previewDesc.sub) : ""
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: emojiWindow.s(10.5)
                            color: ThemeBackend.subtext0
                            elide: Text.ElideRight
                        }
                        Text {
                            text: typeof I18n !== "undefined" ? I18n.t("emoji.hint", "Arrows: select \u00b7 Ctrl+H/L: category \u00b7 Tab: mode \u00b7 Enter: copy \u00b7 Ctrl+Enter: type") : "Arrows: select \u00b7 Ctrl+H/L: category \u00b7 Tab: mode \u00b7 Enter: copy \u00b7 Ctrl+Enter: type"
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: emojiWindow.s(9.5)
                            color: ThemeBackend.overlay1
                            elide: Text.ElideLeft
                        }
                    }
                }
            }
        }
    }
}
