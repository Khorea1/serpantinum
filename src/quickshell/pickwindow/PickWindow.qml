import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import "../"
import "../reusables"
import "../reusables/RofiKeyNav.js" as RofiKeyNav

PanelWindow {
    id: pickWindowRoot

    screen: PickWindowController.screen

    WlrLayershell.namespace: "qs-pickwindow"
    WlrLayershell.layer: WlrLayer.Overlay
    focusable: pickWindowRoot.isVisible
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

    function closePickWindow() {
        PickWindowController.hide();
    }

    property bool isVisible: PickWindowController.isVisible
    property int configRevision: 0
    property bool windowsLoaded: false

    Component.onCompleted: {
        executeFilter("");
    }

    Connections {
        target: (typeof Config !== "undefined") ? Config : null
        function onSettingsLoaded() {
            PickWindowController.hide();
            pickWindowRoot.configRevision++;
        }
    }

    property var defaultPickWindowSettings: ({
        "position": "center",
        "width": 640,
        "itemCount": 8
    })

    property var rawPickWindowSettings: {
        let dummy = configRevision;
        if (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.pickwindow) {
            return Config.rawSettings.pickwindow;
        }
        if (typeof Config !== "undefined" && typeof Config.getSetting === "function") {
            return Config.getSetting("pickwindow", defaultPickWindowSettings);
        }
        return defaultPickWindowSettings;
    }

    property string pickWindowPosition: (rawPickWindowSettings && rawPickWindowSettings.position !== undefined) ? rawPickWindowSettings.position : "center"
    property real customWidth: (rawPickWindowSettings && rawPickWindowSettings.width !== undefined && !isNaN(rawPickWindowSettings.width) && rawPickWindowSettings.width > 0) ? rawPickWindowSettings.width : 640
    property int customItemCount: (rawPickWindowSettings && rawPickWindowSettings.itemCount !== undefined && !isNaN(rawPickWindowSettings.itemCount) && rawPickWindowSettings.itemCount > 0) ? rawPickWindowSettings.itemCount : 8

    property var rawBarSettings: {
        let dummy = configRevision;
        return (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar) ? Config.rawSettings.bar : ({});
    }

    property string barStyle: {
        let dummy = configRevision;
        if (typeof Config === "undefined" || !Config.rawSettings || !Config.rawSettings.bar) return "modular";
        let s = Config.rawSettings.bar.style;
        if (typeof s === "string") return s;
        if (s && typeof s === "object") {
            if (s.fill || s.mode === "fill") return "fill";
            if (s.solid || s.mode === "solid") return "solid";
        }
        return "modular";
    }

    property string barPosition: {
        let dummy = configRevision;
        if (typeof Config === "undefined" || !Config.rawSettings || !Config.rawSettings.bar) return "top";
        return Config.rawSettings.bar.position || "top";
    }

    property real barOpacity: {
        let dummy = configRevision;
        if (!rawBarSettings || rawBarSettings.opacity === undefined) return 1.0;
        let op = Number(rawBarSettings.opacity);
        return op > 1.0 ? (op / 100.0) : op;
    }

    property bool barAutohide: (rawBarSettings && rawBarSettings.autohide !== undefined) ? Boolean(rawBarSettings.autohide) : false

    readonly property bool isOsdFullscreen: (typeof OsdController !== "undefined") ? Boolean(OsdController.isFullscreen) : false

    readonly property bool isToplevelFullscreen: {
        try {
            if (typeof ToplevelManager !== "undefined" && ToplevelManager.activeToplevel && ToplevelManager.activeToplevel.fullscreen) {
                let atl = ToplevelManager.activeToplevel;
                if (atl.screens && atl.screens.length > 0) {
                    return atl.screens.indexOf(pickWindowRoot.screen) !== -1;
                }
                return true;
            }
        } catch (e) {}
        return false;
    }

    readonly property bool isHyprlandFullscreen: {
        try {
            if (typeof Hyprland !== "undefined" && Hyprland.focusedWorkspace) {
                return Boolean(Hyprland.focusedWorkspace.hasFullscreen || (Hyprland.activeToplevel && Hyprland.activeToplevel.fullscreen));
            }
        } catch (e) {}
        return false;
    }

    readonly property bool isFullscreenActive: isOsdFullscreen || isToplevelFullscreen || isHyprlandFullscreen

    readonly property bool isBarEffectivelyHidden: barAutohide || isFullscreenActive

    property real barHeight: {
        let dummy = configRevision;
        return (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar && Config.rawSettings.bar.height) ? s(Config.rawSettings.bar.height) : s(40);
    }

    property bool isBarSolid: (barStyle === "solid" || barStyle === "fill") && Math.round(barOpacity * 100) >= 100
    property bool barMatchesPicker: isBarSolid && (attachEdge === barPosition) && !isBarEffectivelyHidden

    property string attachEdge: pickWindowPosition
    property bool isSideAttached: attachEdge === "left" || attachEdge === "right"
    property bool isCentered: attachEdge === "center"

    onAttachEdgeChanged: {
        PickWindowController.hide();
    }

    onBarStyleChanged: {
        PickWindowController.hide();
    }

    onBarPositionChanged: {
        PickWindowController.hide();
    }

    property real cornerRadius: ThemeBackend.borderRadius <= 16 ? ThemeBackend.borderRadius * 2 : Math.min(32, 32 - 16 * Math.exp(-(ThemeBackend.borderRadius - 16) / 12))
    property real outerCornerRadius: cornerRadius

    property real basePickerWidth: s(customWidth)
    property real collapsedCenterHeight: s(64)

    property real targetPickerHeight: {
        let count = Math.min(windowModel.count, customItemCount);
        if (count <= 0) {
            return s(64);
        }
        return s(70) + (count * s(48));
    }

    property real animatedPickerHeight: targetPickerHeight
    Behavior on animatedPickerHeight {
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutCubic
        }
    }

    visible: isVisible || container.animProgress > 0.001

    property var allWindows: []
    property var rawWindowData: []
    property string compositor: ""
    property bool isKeyboardNav: false
    property string pendingQuery: ""

    function grabInputFocus() {
        searchInput.forceActiveFocus();
        if (typeof searchInput.forceInputFocus === "function") {
            searchInput.forceInputFocus();
        }
    }

    // Fetches the current list of open windows (Hyprland or niri, whichever
    // is running) as JSON: { compositor: "hyprland"|"niri", windows: [...] }
    Process {
        id: windowFetcher
        running: false
        command: Caching.qsDir ? ["python3", Caching.qsDir + "/pickwindow/window_fetch.py"] : []

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (this.text && this.text.trim().length > 0) {
                        let data = JSON.parse(this.text);
                        pickWindowRoot.compositor = data.compositor || "";
                        pickWindowRoot.rawWindowData = data.windows || [];
                        pickWindowRoot.loadWindows();
                        executeFilter(searchInput.text);
                    }
                } catch(e) {}
            }
        }
    }

    Timer {
        id: focusTimer
        interval: 30
        repeat: false
        onTriggered: {
            pickWindowRoot.grabInputFocus();
        }
    }

    Timer {
        id: focusRetryTimer
        interval: 120
        repeat: false
        onTriggered: {
            pickWindowRoot.grabInputFocus();
        }
    }

    Timer {
        id: focusFinalTimer
        interval: 250
        repeat: false
        onTriggered: {
            pickWindowRoot.grabInputFocus();
        }
    }

    Timer {
        id: keyboardNavTimer
        interval: 500
        repeat: false
        onTriggered: {
            pickWindowRoot.isKeyboardNav = false;
        }
    }

    Timer {
        id: filterDebounceTimer
        interval: 80
        repeat: false
        onTriggered: {
            executeFilter(pickWindowRoot.pendingQuery);
        }
    }

    // Keeps the list fresh while the picker stays open (a window may be
    // closed by its app while the user is still browsing).
    Timer {
        id: refreshTimer
        interval: 1500
        repeat: true
        running: pickWindowRoot.isVisible
        onTriggered: {
            windowFetcher.running = false;
            windowFetcher.running = true;
        }
    }

    onIsVisibleChanged: {
        if (isVisible) {
            windowFetcher.running = false;
            windowFetcher.running = true;
            if (searchInput.text !== "") {
                searchInput.clear();
                filterDebounceTimer.stop();
                executeFilter("");
            } else {
                filterDebounceTimer.stop();
            }
            pickWindowRoot.grabInputFocus();
            focusTimer.restart();
            focusRetryTimer.restart();
            focusFinalTimer.restart();
        } else {
            filterDebounceTimer.stop();
            focusTimer.stop();
            focusRetryTimer.stop();
            focusFinalTimer.stop();
            keyboardNavTimer.stop();
        }
    }

    // Best-effort match of a window's class/app-id to an installed desktop
    // entry, so we can reuse its icon (same heuristic as the launcher: try
    // StartupWMClass, then the desktop file id, then the display name).
    function resolveIcon(cls) {
        if (!cls) return "";
        let target = cls.toLowerCase();

        if (typeof DesktopEntries !== "undefined" && DesktopEntries.applications && DesktopEntries.applications.values) {
            let entries = DesktopEntries.applications.values;
            for (let i = 0; i < entries.length; i++) {
                let e = entries[i];
                let wmclass = (e.startupClass || "").toLowerCase();
                let baseName = (e.id || "").toLowerCase().replace(".desktop", "");
                let appNameLower = (e.name || "").toLowerCase();
                if (wmclass === target || baseName === target || appNameLower === target) {
                    return e.icon || target;
                }
            }
        }

        // Fall back to the icon theme entry that (very often) shares the
        // app's own class/app-id, e.g. "firefox", "code", "spotify".
        return target;
    }

    function loadWindows() {
        let arr = [];

        for (let i = 0; i < rawWindowData.length; i++) {
            let w = rawWindowData[i];
            if (!w) continue;

            let cls = w["class"] || "";
            let title = w.title || cls || "";
            if (!title) continue;

            let workspace = w.workspace !== undefined && w.workspace !== null ? String(w.workspace) : "";
            let desc = cls;
            if (workspace !== "") desc = desc !== "" ? (desc + "  ·  " + workspace) : workspace;
            if (w.focused) desc = desc !== "" ? (desc + "  ·  current") : "current";

            arr.push({
                name: title,
                description: desc,
                icon: pickWindowRoot.resolveIcon(cls),
                fontIcon: "",
                windowId: w.id || "",
                className: cls,
                focused: !!w.focused,
                score: 0
            });
        }

        pickWindowRoot.allWindows = arr;
    }

    ListModel {
        id: windowModel
    }

    function filterWindows(query) {
        pickWindowRoot.pendingQuery = query;
        filterDebounceTimer.restart();
    }

    function isSubsequence(sub, str) {
        let i = 0;
        let j = 0;
        while (i < sub.length && j < str.length) {
            if (sub[i] === str[j]) {
                i++;
            }
            j++;
        }
        return i === sub.length;
    }

    function getItemKey(item) {
        if (!item) return "";
        return item.windowId ? ("win:" + item.windowId) : ("name:" + item.name);
    }

    function executeFilter(query) {
        pickWindowRoot.isKeyboardNav = false;
        if (keyboardNavTimer.running) keyboardNavTimer.stop();

        let q = query.toLowerCase().trim();
        let filtered = [];

        for (let i = 0; i < allWindows.length; i++) {
            let win = allWindows[i];
            let nameLower = win.name ? win.name.toLowerCase() : "";
            let descLower = win.description ? win.description.toLowerCase() : "";

            let matchQuality = 0;
            let matches = false;

            if (q.length === 0) {
                matches = true;
            } else if (nameLower === q) {
                matchQuality = 100000;
                matches = true;
            } else if (nameLower.startsWith(q)) {
                matchQuality = 50000;
                matches = true;
            } else if (nameLower.includes(q)) {
                matchQuality = 10000;
                matches = true;
            } else if (descLower.includes(q)) {
                matchQuality = 5000;
                matches = true;
            } else if (isSubsequence(q, nameLower)) {
                matchQuality = 1000;
                matches = true;
            }

            if (matches) {
                filtered.push({
                    name: win.name,
                    description: win.description,
                    icon: win.icon,
                    fontIcon: win.fontIcon || "",
                    windowId: win.windowId,
                    className: win.className,
                    focused: win.focused,
                    score: win.score + matchQuality
                });
            }
        }

        if (q.length > 0) {
            filtered.sort(function(a, b) {
                return b.score - a.score;
            });
        }

        let newKeys = {};
        for (let i = 0; i < filtered.length; i++) {
            newKeys[getItemKey(filtered[i])] = true;
        }

        for (let i = windowModel.count - 1; i >= 0; i--) {
            let key = getItemKey(windowModel.get(i));
            if (!newKeys[key]) {
                windowModel.remove(i);
            }
        }

        for (let i = 0; i < filtered.length; i++) {
            let item = filtered[i];
            let targetKey = getItemKey(item);

            if (i < windowModel.count) {
                let currentKey = getItemKey(windowModel.get(i));
                if (currentKey === targetKey) {
                    windowModel.set(i, item);
                } else {
                    let foundIndex = -1;
                    for (let j = i + 1; j < windowModel.count; j++) {
                        if (getItemKey(windowModel.get(j)) === targetKey) {
                            foundIndex = j;
                            break;
                        }
                    }
                    if (foundIndex !== -1) {
                        windowModel.move(foundIndex, i, 1);
                        windowModel.set(i, item);
                    } else {
                        windowModel.insert(i, item);
                    }
                }
            } else {
                windowModel.append(item);
            }
        }

        while (windowModel.count > filtered.length) {
            windowModel.remove(windowModel.count - 1);
        }

        if (windowModel.count > 0) {
            pickList.currentIndex = 0;
        } else {
            pickList.currentIndex = -1;
        }
    }

    function activateIndex(index) {
        if (index < 0 || index >= windowModel.count) return;
        let item = windowModel.get(index);
        if (!item || !item.windowId) return;

        focusWindow(item.windowId);
    }

    function focusWindow(windowId) {
        if (!windowId) return;

        if (pickWindowRoot.compositor === "niri") {
            Quickshell.execDetached(["niri", "msg", "action", "focus-window", "--id", String(windowId)]);
        } else {
            // Standard hyprctl dispatcher: works regardless of any extra
            // shell-side "hl.dsp.*" syntax used elsewhere in this config.
            Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "address:" + windowId]);
        }

        closePickWindow();
    }

    Item {
        id: topBarHole

        property int barThickness: pickWindowRoot.barHeight
        property string bp: pickWindowRoot.barPosition
        property bool activeBar: !pickWindowRoot.isBarEffectivelyHidden

        x: {
            if (!activeBar) return 0;
            if (bp === "left") return 0;
            if (bp === "right") return pickWindowRoot.width - barThickness;
            return 0;
        }

        y: {
            if (!activeBar) return 0;
            if (bp === "top") return 0;
            if (bp === "bottom") return pickWindowRoot.height - barThickness;
            return 0;
        }

        width: {
            if (!activeBar) return 0;
            if (bp === "left" || bp === "right") return barThickness;
            return pickWindowRoot.width;
        }

        height: {
            if (!activeBar) return 0;
            if (bp === "top" || bp === "bottom") return barThickness;
            return pickWindowRoot.height;
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: pickWindowRoot.isVisible
        onClicked: closePickWindow()
    }

    Item {
        id: container

        MouseArea {
            anchors.fill: parent
        }

        property real animProgress: pickWindowRoot.isVisible ? 1.0 : 0.0
        Behavior on animProgress {
            NumberAnimation {
                duration: pickWindowRoot.isVisible ? (pickWindowRoot.isCentered ? 320 : 220) : (pickWindowRoot.isCentered ? 200 : 150)
                easing.type: pickWindowRoot.isVisible ? Easing.OutBack : Easing.InQuad
                easing.overshoot: 1.15
            }
        }

        property real dynamicCornerRadius: Math.max(0, Math.min(pickWindowRoot.outerCornerRadius, (pickWindowRoot.isSideAttached ? width : height) * 0.5))

        x: {
            if (pickWindowRoot.attachEdge === "left") {
                return pickWindowRoot.barMatchesPicker ? pickWindowRoot.barHeight : 0;
            }
            if (pickWindowRoot.attachEdge === "right") {
                let offset = pickWindowRoot.barMatchesPicker ? pickWindowRoot.barHeight : 0;
                return (pickWindowRoot.width - offset) - width;
            }
            return Math.floor((pickWindowRoot.width - width) / 2);
        }

        y: {
            if (pickWindowRoot.attachEdge === "top") {
                return pickWindowRoot.barMatchesPicker ? pickWindowRoot.barHeight : 0;
            }
            if (pickWindowRoot.attachEdge === "bottom") {
                let offset = pickWindowRoot.barMatchesPicker ? pickWindowRoot.barHeight : 0;
                return (pickWindowRoot.height - offset) - height;
            }
            return Math.floor((pickWindowRoot.height - height) / 2);
        }

        width: pickWindowRoot.isSideAttached
               ? (pickWindowRoot.basePickerWidth * animProgress)
               : pickWindowRoot.basePickerWidth

        height: {
            if (pickWindowRoot.isCentered) {
                let baseH = pickWindowRoot.collapsedCenterHeight;
                let targetH = Math.max(baseH, pickWindowRoot.animatedPickerHeight);
                return baseH + (targetH - baseH) * animProgress;
            }
            if (!pickWindowRoot.isSideAttached) {
                return pickWindowRoot.animatedPickerHeight * animProgress;
            }
            return pickWindowRoot.animatedPickerHeight;
        }

        opacity: pickWindowRoot.isCentered
                 ? Math.max(0.0, Math.min(1.0, animProgress * 1.5))
                 : ((pickWindowRoot.isVisible || animProgress > 0.001) ? 1.0 : 0.0)

        transformOrigin: Item.Center

        Shape {
            visible: pickWindowRoot.attachEdge === "top" && container.dynamicCornerRadius > 0.5
            x: -container.dynamicCornerRadius
            y: 0
            width: container.dynamicCornerRadius
            height: container.dynamicCornerRadius
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: ThemeBackend.base
                strokeColor: "transparent"
                startX: 0
                startY: 0
                PathLine { x: container.dynamicCornerRadius; y: 0 }
                PathLine { x: container.dynamicCornerRadius; y: container.dynamicCornerRadius }
                PathArc {
                    x: 0
                    y: 0
                    radiusX: container.dynamicCornerRadius
                    radiusY: container.dynamicCornerRadius
                    direction: PathArc.Counterclockwise
                }
            }
        }

        Shape {
            visible: pickWindowRoot.attachEdge === "top" && container.dynamicCornerRadius > 0.5
            x: parent.width
            y: 0
            width: container.dynamicCornerRadius
            height: container.dynamicCornerRadius
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: ThemeBackend.base
                strokeColor: "transparent"
                startX: container.dynamicCornerRadius
                startY: 0
                PathLine { x: 0; y: 0 }
                PathLine { x: 0; y: container.dynamicCornerRadius }
                PathArc {
                    x: container.dynamicCornerRadius
                    y: 0
                    radiusX: container.dynamicCornerRadius
                    radiusY: container.dynamicCornerRadius
                    direction: PathArc.Clockwise
                }
            }
        }

        Shape {
            visible: pickWindowRoot.attachEdge === "bottom" && container.dynamicCornerRadius > 0.5
            x: -container.dynamicCornerRadius
            y: parent.height - container.dynamicCornerRadius
            width: container.dynamicCornerRadius
            height: container.dynamicCornerRadius
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: ThemeBackend.base
                strokeColor: "transparent"
                startX: 0
                startY: container.dynamicCornerRadius
                PathLine { x: container.dynamicCornerRadius; y: container.dynamicCornerRadius }
                PathLine { x: container.dynamicCornerRadius; y: 0 }
                PathArc {
                    x: 0
                    y: container.dynamicCornerRadius
                    radiusX: container.dynamicCornerRadius
                    radiusY: container.dynamicCornerRadius
                    direction: PathArc.Clockwise
                }
            }
        }

        Shape {
            visible: pickWindowRoot.attachEdge === "bottom" && container.dynamicCornerRadius > 0.5
            x: parent.width
            y: parent.height - container.dynamicCornerRadius
            width: container.dynamicCornerRadius
            height: container.dynamicCornerRadius
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: ThemeBackend.base
                strokeColor: "transparent"
                startX: container.dynamicCornerRadius
                startY: container.dynamicCornerRadius
                PathLine { x: 0; y: container.dynamicCornerRadius }
                PathLine { x: 0; y: 0 }
                PathArc {
                    x: container.dynamicCornerRadius
                    y: 0
                    radiusX: container.dynamicCornerRadius
                    radiusY: container.dynamicCornerRadius
                    direction: PathArc.Counterclockwise
                }
            }
        }

        Shape {
            visible: pickWindowRoot.attachEdge === "left" && container.dynamicCornerRadius > 0.5
            x: 0
            y: -container.dynamicCornerRadius
            width: container.dynamicCornerRadius
            height: container.dynamicCornerRadius
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: ThemeBackend.base
                strokeColor: "transparent"
                startX: 0
                startY: 0
                PathLine { x: 0; y: container.dynamicCornerRadius }
                PathLine { x: container.dynamicCornerRadius; y: container.dynamicCornerRadius }
                PathArc {
                    x: 0
                    y: 0
                    radiusX: container.dynamicCornerRadius
                    radiusY: container.dynamicCornerRadius
                    direction: PathArc.Clockwise
                }
            }
        }

        Shape {
            visible: pickWindowRoot.attachEdge === "left" && container.dynamicCornerRadius > 0.5
            x: 0
            y: parent.height
            width: container.dynamicCornerRadius
            height: container.dynamicCornerRadius
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: ThemeBackend.base
                strokeColor: "transparent"
                startX: 0
                startY: container.dynamicCornerRadius
                PathLine { x: 0; y: 0 }
                PathLine { x: container.dynamicCornerRadius; y: 0 }
                PathArc {
                    x: 0
                    y: container.dynamicCornerRadius
                    radiusX: container.dynamicCornerRadius
                    radiusY: container.dynamicCornerRadius
                    direction: PathArc.Counterclockwise
                }
            }
        }

        Shape {
            visible: pickWindowRoot.attachEdge === "right" && container.dynamicCornerRadius > 0.5
            x: parent.width - container.dynamicCornerRadius
            y: -container.dynamicCornerRadius
            width: container.dynamicCornerRadius
            height: container.dynamicCornerRadius
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: ThemeBackend.base
                strokeColor: "transparent"
                startX: container.dynamicCornerRadius
                startY: 0
                PathLine { x: container.dynamicCornerRadius; y: container.dynamicCornerRadius }
                PathLine { x: 0; y: container.dynamicCornerRadius }
                PathArc {
                    x: container.dynamicCornerRadius
                    y: 0
                    radiusX: container.dynamicCornerRadius
                    radiusY: container.dynamicCornerRadius
                    direction: PathArc.Counterclockwise
                }
            }
        }

        Shape {
            visible: pickWindowRoot.attachEdge === "right" && container.dynamicCornerRadius > 0.5
            x: parent.width - container.dynamicCornerRadius
            y: parent.height
            width: container.dynamicCornerRadius
            height: container.dynamicCornerRadius
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: ThemeBackend.base
                strokeColor: "transparent"
                startX: container.dynamicCornerRadius
                startY: container.dynamicCornerRadius
                PathLine { x: container.dynamicCornerRadius; y: 0 }
                PathLine { x: 0; y: 0 }
                PathArc {
                    x: container.dynamicCornerRadius
                    y: container.dynamicCornerRadius
                    radiusX: container.dynamicCornerRadius
                    radiusY: container.dynamicCornerRadius
                    direction: PathArc.Clockwise
                }
            }
        }

        Rectangle {
            id: bgCard
            anchors.fill: parent
            radius: container.dynamicCornerRadius
            color: ThemeBackend.base
            border.width: pickWindowRoot.isCentered ? 1 : 0
            border.color: pickWindowRoot.isCentered ? Qt.alpha(ThemeBackend.surface2, 0.6) : "transparent"
            clip: true

            Rectangle {
                visible: pickWindowRoot.attachEdge === "top" && container.dynamicCornerRadius > 0.5
                x: 0
                y: 0
                width: container.dynamicCornerRadius
                height: container.dynamicCornerRadius
                color: ThemeBackend.base
            }

            Rectangle {
                visible: pickWindowRoot.attachEdge === "top" && container.dynamicCornerRadius > 0.5
                x: parent.width - container.dynamicCornerRadius
                y: 0
                width: container.dynamicCornerRadius
                height: container.dynamicCornerRadius
                color: ThemeBackend.base
            }

            Rectangle {
                visible: pickWindowRoot.attachEdge === "bottom" && container.dynamicCornerRadius > 0.5
                x: 0
                y: parent.height - container.dynamicCornerRadius
                width: container.dynamicCornerRadius
                height: container.dynamicCornerRadius
                color: ThemeBackend.base
            }

            Rectangle {
                visible: pickWindowRoot.attachEdge === "bottom" && container.dynamicCornerRadius > 0.5
                x: parent.width - container.dynamicCornerRadius
                y: parent.height - container.dynamicCornerRadius
                width: container.dynamicCornerRadius
                height: container.dynamicCornerRadius
                color: ThemeBackend.base
            }

            Rectangle {
                visible: pickWindowRoot.attachEdge === "left" && container.dynamicCornerRadius > 0.5
                x: 0
                y: 0
                width: container.dynamicCornerRadius
                height: container.dynamicCornerRadius
                color: ThemeBackend.base
            }

            Rectangle {
                visible: pickWindowRoot.attachEdge === "left" && container.dynamicCornerRadius > 0.5
                x: 0
                y: parent.height - container.dynamicCornerRadius
                width: container.dynamicCornerRadius
                height: container.dynamicCornerRadius
                color: ThemeBackend.base
            }

            Rectangle {
                visible: pickWindowRoot.attachEdge === "right" && container.dynamicCornerRadius > 0.5
                x: parent.width - container.dynamicCornerRadius
                y: 0
                width: container.dynamicCornerRadius
                height: container.dynamicCornerRadius
                color: ThemeBackend.base
            }

            Rectangle {
                visible: pickWindowRoot.attachEdge === "right" && container.dynamicCornerRadius > 0.5
                x: parent.width - container.dynamicCornerRadius
                y: parent.height - container.dynamicCornerRadius
                width: container.dynamicCornerRadius
                height: container.dynamicCornerRadius
                color: ThemeBackend.base
            }

            Item {
                id: contentContainer
                anchors.fill: parent
                anchors.margins: pickWindowRoot.s(14)
                visible: width > 0 && height > 0
                clip: true

                readonly property bool isSearchAtBottom: pickWindowRoot.attachEdge === "bottom"

                Input {
                    id: searchInput
                    z: 10
                    focus: true
                    anchors.left: parent.left
                    anchors.right: parent.right
                    y: contentContainer.isSearchAtBottom ? Math.max(0, parent.height - height) : 0
                    height: pickWindowRoot.s(36)

                    baseColor: ThemeBackend.surface0
                    accentColor: ThemeBackend.mauve
                    textColor: ThemeBackend.text
                    subTextColor: ThemeBackend.subtext0
                    borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                    cornerRadius: ThemeBackend.borderRadius
                    fontPixelSize: pickWindowRoot.s(12)
                    charSpacing: 1

                    placeholderText: "Search open windows..."
                    showClearButton: true

                    onTextEdited: function(newText) {
                        filterWindows(newText);
                    }
                    onCleared: filterWindows("")

                    function moveSelectionDown() {
                        pickWindowRoot.isKeyboardNav = true;
                        keyboardNavTimer.restart();
                        if (pickList.currentIndex < windowModel.count - 1) {
                            pickList.currentIndex++;
                        }
                    }

                    function moveSelectionUp() {
                        pickWindowRoot.isKeyboardNav = true;
                        keyboardNavTimer.restart();
                        if (pickList.currentIndex > 0) {
                            pickList.currentIndex--;
                        }
                    }

                    Keys.onDownPressed: function(event) {
                        moveSelectionDown();
                        event.accepted = true;
                    }
                    Keys.onUpPressed: function(event) {
                        moveSelectionUp();
                        event.accepted = true;
                    }
                    Keys.onReturnPressed: function(event) {
                        activateIndex(pickList.currentIndex);
                        event.accepted = true;
                    }
                    Keys.onEscapePressed: function(event) {
                        closePickWindow();
                        event.accepted = true;
                    }
                    // rofi-style secondary navigation keybindings (shared with
                    // every other selection widget via RofiKeyNav.js).
                    // NOTE: this listens on Input's `keyPressed` signal (fired
                    // from innerInput's own Keys.onPressed), not on
                    // Keys.onPressed here on the wrapper. TextInput has a
                    // built-in Ctrl+K "delete to end of line" shortcut on
                    // Linux (QKeySequence::DeleteEndOfLine) that swallows the
                    // event before it would ever bubble up to this wrapper.
                    // row-up:   "Up,Control+k"
                    // row-down: "Down,Control+j"
                    onKeyPressed: function(event) {
                        if (RofiKeyNav.handlePressed(event, moveSelectionDown, moveSelectionUp)) {
                            event.accepted = true;
                        }
                    }
                }

                Item {
                    id: listContainer
                    z: 1
                    anchors.left: parent.left
                    anchors.right: parent.right
                    y: contentContainer.isSearchAtBottom ? 0 : (searchInput.height + pickWindowRoot.s(10))
                    height: Math.max(0, parent.height - searchInput.height - pickWindowRoot.s(10))
                    clip: true

                    opacity: pickWindowRoot.isCentered
                             ? Math.max(0.0, Math.min(1.0, (container.animProgress - 0.2) / 0.8))
                             : 1.0

                    Transition {
                        id: listAddTrans
                        NumberAnimation {
                            property: "opacity"
                            from: 0.0
                            to: 1.0
                            duration: 250
                            easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            property: "scale"
                            from: 0.96
                            to: 1.0
                            duration: 270
                            easing.type: Easing.OutCubic
                        }
                    }

                    Transition {
                        id: listRemoveTrans
                        NumberAnimation {
                            property: "opacity"
                            to: 0.0
                            duration: 170
                            easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            property: "scale"
                            to: 0.96
                            duration: 170
                            easing.type: Easing.OutCubic
                        }
                    }

                    Transition {
                        id: listDisplacedTrans
                        NumberAnimation {
                            properties: "y"
                            duration: 280
                            easing.type: Easing.OutCubic
                        }
                    }

                    Transition {
                        id: listMoveTrans
                        NumberAnimation {
                            properties: "y"
                            duration: 280
                            easing.type: Easing.OutCubic
                        }
                    }

                    ListView {
                        id: pickList
                        anchors.fill: parent
                        clip: true
                        model: windowModel
                        spacing: pickWindowRoot.s(4)
                        currentIndex: 0
                        boundsBehavior: Flickable.StopAtBounds

                        highlightFollowsCurrentItem: false

                        property bool transitionsEnabled: pickWindowRoot.isVisible && container.animProgress > 0.98

                        add: transitionsEnabled ? listAddTrans : null
                        remove: transitionsEnabled ? listRemoveTrans : null
                        displaced: transitionsEnabled ? listDisplacedTrans : null
                        move: transitionsEnabled ? listMoveTrans : null
                        moveDisplaced: transitionsEnabled ? listDisplacedTrans : null

                        onCurrentIndexChanged: {
                            if (currentIndex >= 0) {
                                positionViewAtIndex(currentIndex, ListView.Contain);
                            }
                        }

                        Rectangle {
                            id: morphHighlight
                            parent: pickList.contentItem
                            z: 0
                            visible: opacity > 0.001
                            opacity: (pickList.count > 0 && pickList.currentIndex >= 0 && pickList.currentItem !== null) ? 1.0 : 0.0
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 170
                                    easing.type: Easing.OutCubic
                                }
                            }
                            x: 0
                            width: pickList.width
                            height: pickWindowRoot.s(44)
                            radius: ThemeBackend.borderRadius
                            color: ThemeBackend.mauve

                            property real targetY: (pickList.currentIndex >= 0 && pickList.currentItem) ? pickList.currentItem.y : 0
                            y: targetY

                            Behavior on y {
                                enabled: pickList.transitionsEnabled
                                NumberAnimation {
                                    duration: 260
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        delegate: Item {
                            id: delegateRoot
                            width: ListView.view ? ListView.view.width : 0
                            height: pickWindowRoot.s(44)
                            clip: true
                            z: 1

                            property bool isSelected: index === pickList.currentIndex

                            Item {
                                id: delegateContent
                                anchors.fill: parent

                                scale: ma.pressed ? 0.98 : 1.0
                                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: ThemeBackend.borderRadius
                                    color: ThemeBackend.surface0
                                    opacity: ma.containsMouse && !delegateRoot.isSelected ? 0.45 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutSine } }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: pickWindowRoot.s(6)
                                    anchors.leftMargin: pickWindowRoot.s(10) + (delegateRoot.isSelected ? pickWindowRoot.s(2) : 0)
                                    anchors.rightMargin: pickWindowRoot.s(10)
                                    spacing: pickWindowRoot.s(10)

                                    Behavior on anchors.leftMargin {
                                        NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.15 }
                                    }

                                    Item {
                                        id: delegateIconArea
                                        Layout.preferredWidth: pickWindowRoot.s(32)
                                        Layout.preferredHeight: pickWindowRoot.s(32)
                                        Layout.alignment: Qt.AlignVCenter

                                        readonly property real boxRadius: pickWindowRoot.s(8)
                                        readonly property real boxPadding: pickWindowRoot.s(4)

                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.topMargin: pickWindowRoot.s(1.5)
                                            anchors.bottomMargin: -pickWindowRoot.s(1.5)
                                            radius: parent.boxRadius
                                            color: Qt.rgba(0, 0, 0, 0.12)
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: parent.boxRadius
                                            color: delegateRoot.isSelected ? Qt.tint(ThemeBackend.surface2, Qt.rgba(ThemeBackend.mauve.r, ThemeBackend.mauve.g, ThemeBackend.mauve.b, 0.2)) : ThemeBackend.surface2

                                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                        }

                                        Rectangle {
                                            id: iconContainer
                                            anchors.fill: parent
                                            anchors.margins: parent.boxPadding
                                            radius: Math.max(0, parent.boxRadius - parent.boxPadding)
                                            color: "transparent"
                                            clip: true

                                            Image {
                                                id: delegateIcon
                                                anchors.fill: parent
                                                property bool failedLoad: false

                                                visible: (!model.fontIcon || model.fontIcon === "") && source !== "" && status === Image.Ready && !failedLoad

                                                source: {
                                                    if (model.fontIcon && model.fontIcon !== "") return "";
                                                    let ic = model.icon || "";
                                                    if (!ic) return "";
                                                    if (ic.startsWith("file://") || ic.startsWith("image://") || ic.startsWith("http://") || ic.startsWith("https://")) return ic;
                                                    return ic.startsWith("/") ? "file://" + ic : "image://icon/" + ic;
                                                }

                                                sourceSize: Qt.size(64, 64)
                                                fillMode: Image.PreserveAspectFit
                                                asynchronous: true
                                                smooth: true
                                                mipmap: true

                                                onStatusChanged: {
                                                    if (status === Image.Error) {
                                                        failedLoad = true;
                                                    }
                                                }
                                            }

                                            Text {
                                                id: delegateFontIcon
                                                anchors.centerIn: parent
                                                visible: !delegateIcon.visible
                                                text: {
                                                    if (model.fontIcon && model.fontIcon !== "") return model.fontIcon;
                                                    return model.focused ? "󰖯" : "󰖲";
                                                }
                                                font.family: ThemeBackend.fontFamily
                                                font.pixelSize: pickWindowRoot.s(16)
                                                color: delegateRoot.isSelected ? ThemeBackend.mauve : ThemeBackend.subtext0
                                                verticalAlignment: Text.AlignVCenter
                                                horizontalAlignment: Text.AlignHCenter

                                                Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                            }
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: pickWindowRoot.s(1)

                                        Text {
                                            id: delegateText
                                            Layout.fillWidth: true
                                            text: model.name
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: pickWindowRoot.s(12)
                                            font.weight: delegateRoot.isSelected ? Font.Bold : Font.Medium
                                            color: delegateRoot.isSelected ? ThemeBackend.crust : ThemeBackend.text
                                            elide: Text.ElideRight
                                            verticalAlignment: Text.AlignVCenter

                                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                        }

                                        Text {
                                            id: delegateDesc
                                            Layout.fillWidth: true
                                            visible: model.description !== undefined && model.description !== null && model.description !== ""
                                            text: model.description || ""
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: pickWindowRoot.s(10)
                                            font.weight: Font.Normal
                                            color: delegateRoot.isSelected ? ThemeBackend.crust : ThemeBackend.subtext0
                                            opacity: delegateRoot.isSelected ? 0.9 : 0.85
                                            elide: Text.ElideRight
                                            verticalAlignment: Text.AlignVCenter

                                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: ma
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        pickList.currentIndex = index;
                                        activateIndex(index);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
