import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../"
import "../reusables"

PanelWindow {
    id: popupWindow

    readonly property real sf: Scaler.baseScale

    function s(val) {
        return Math.round(val * popupWindow.sf);
    }

    property bool hasCriticalPopup: {
        for (let i = 0; i < NotificationManager.activePopupsModel.count; i++) {
            let p = NotificationManager.activePopupsModel.get(i);
            if (p && p.urgency === 2) return true;
        }
        return false;
    }

    visible: (!popupWindow.dndEnabled || popupWindow.hasCriticalPopup) && !NotificationManager.sysPanelOpen && NotificationManager.activePopupsModel.count > 0

    function storeNotif(uid, notif) {
        NotificationManager.liveNotifs[uid] = notif;
    }

    function getNotif(uid) {
        return NotificationManager.liveNotifs[uid] || null;
    }

    function removeNotif(uid) {
        delete NotificationManager.liveNotifs[uid];
        NotificationManager.removePopup(uid);
    }

    property var rawBarSettings: Config.getSetting("bar", {})
    property string barPosition: (rawBarSettings && rawBarSettings.position !== undefined) ? rawBarSettings.position : "top"
    property bool barAutohide: (rawBarSettings && rawBarSettings.autohide !== undefined) ? Boolean(rawBarSettings.autohide) : false

    readonly property bool isFullscreenActive: {
        try {
            if (typeof Hyprland !== "undefined" && Hyprland.focusedWorkspace) {
                return Boolean(Hyprland.focusedWorkspace.hasFullscreen || (Hyprland.activeToplevel && Hyprland.activeToplevel.fullscreen));
            }
        } catch (e) {}
        return false;
    }

    readonly property bool isBarEffectivelyHidden: barAutohide || isFullscreenActive

    property string barStyle: {
        if (!rawBarSettings || rawBarSettings.style === undefined) return "modular";
        let st = rawBarSettings.style;
        if (typeof st === "string") return st;
        if (typeof st === "object") {
            if (st.fill || st.mode === "fill") return "fill";
            if (st.solid || st.mode === "solid") return "solid";
        }
        return "modular";
    }
    property bool isBarFill: barStyle === "fill"
    property int barThickness: s(40) + (isBarFill || isBarEffectivelyHidden ? 0 : s(4))

    property var notifSettings: Config.getSetting("notifications", { "dnd": false, "position": "top right", "horizontalPosition": 95, "verticalPosition": 5 })
    property string position: notifSettings.position !== undefined ? notifSettings.position : "top right"
    property real horizontalPosition: notifSettings.horizontalPosition !== undefined ? notifSettings.horizontalPosition : 95
    property real verticalPosition: notifSettings.verticalPosition !== undefined ? notifSettings.verticalPosition : 5

    property bool isPreset: position !== "custom"

    property bool isTop: position.indexOf("top") !== -1
    property bool isBottom: position.indexOf("bottom") !== -1
    property bool isCenter: position.indexOf("center") !== -1
    property bool isLeft: position.indexOf("left") !== -1
    property bool isRight: position.indexOf("right") !== -1 || (!isLeft && !isCenter)

    WlrLayershell.namespace: "qs-popups"
    WlrLayershell.layer: WlrLayer.Overlay

    anchors {
        top: true
        bottom: true
        left: isPreset ? (popupWindow.isCenter || popupWindow.isLeft) : true
        right: isPreset ? (popupWindow.isCenter || popupWindow.isRight) : true
    }

    margins {
        top: isPreset ? ((popupWindow.barPosition === "top" && !popupWindow.isBarEffectivelyHidden ? popupWindow.barThickness : 0) + popupWindow.s(12)) : 0
        bottom: isPreset ? ((popupWindow.barPosition === "bottom" && !popupWindow.isBarEffectivelyHidden ? popupWindow.barThickness : 0) + popupWindow.s(12)) : 0
        left: isPreset ? ((popupWindow.barPosition === "left" && popupWindow.isLeft && !popupWindow.isBarEffectivelyHidden ? popupWindow.barThickness : 0) + (popupWindow.isLeft ? popupWindow.s(16) : 0)) : 0
        right: isPreset ? ((popupWindow.barPosition === "right" && popupWindow.isRight && !popupWindow.isBarEffectivelyHidden ? popupWindow.barThickness : 0) + (popupWindow.isRight ? popupWindow.s(16) : 0)) : 0
    }

    exclusionMode: ExclusionMode.Ignore
    focusable: false
    color: "transparent"

    readonly property real popupWidth: Math.round(Math.min(screen.width * 0.22, s(320)))
    readonly property int effectivePopupWidth: Math.max(s(240), popupWidth)
    implicitWidth: effectivePopupWidth

    mask: Region {
        Region { item: popupContainer }
        Region { item: openCenterPill.visible ? openCenterPill : null }
    }

    // Sourced from NotificationManager so a timed DND snooze (not just the
    // permanent toggle) also hides popups, and re-evaluates as the snooze ticks.
    property bool dndEnabled: NotificationManager.dndActive

    Connections {
        target: Config
        function onSettingsLoaded() {
            let n = Config.getSetting("notifications", { "dnd": false, "position": "top right" });
            popupWindow.position = (n && n.position !== undefined) ? n.position : "top right";
            popupWindow.horizontalPosition = (n && n.horizontalPosition !== undefined) ? n.horizontalPosition : 95;
            popupWindow.verticalPosition = (n && n.verticalPosition !== undefined) ? n.verticalPosition : 5;
            popupWindow.rawBarSettings = Config.getSetting("bar", {});
            popupWindow.barPosition = (popupWindow.rawBarSettings && popupWindow.rawBarSettings.position !== undefined) ? popupWindow.rawBarSettings.position : "top";
            popupWindow.barAutohide = (popupWindow.rawBarSettings && popupWindow.rawBarSettings.autohide !== undefined) ? Boolean(popupWindow.rawBarSettings.autohide) : false;
        }
    }

    Item {
        id: popupRoot
        anchors.fill: parent

        function s(val) {
            return popupWindow.s(val);
        }

        Item {
            id: popupContainer
            width: popupWindow.effectivePopupWidth
            height: popupList.height

            x: popupWindow.isPreset ? (popupWindow.isCenter ? (popupWindow.width - width) / 2 : (popupWindow.isLeft ? 0 : (popupWindow.width - width))) : ((popupWindow.width - width) * (popupWindow.horizontalPosition / 100.0))
            y: popupWindow.isPreset ? (popupWindow.isTop ? 0 : (popupWindow.height - height)) : ((popupWindow.height - height) * (popupWindow.verticalPosition / 100.0))

            ListView {
                id: popupList
                width: parent.width
                height: Math.min(popupWindow.height, contentHeight)
                verticalLayoutDirection: (popupWindow.isPreset ? popupWindow.isBottom : (popupWindow.verticalPosition > 50)) ? ListView.BottomToTop : ListView.TopToBottom
                model: NotificationManager.activePopupsModel
                spacing: popupWindow.s(8)
                interactive: false
                clip: false
                boundsBehavior: Flickable.StopAtBounds

                add: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 260; easing.type: Easing.OutQuint }
                        NumberAnimation {
                            property: "x"
                            from: (popupWindow.isPreset ? (popupWindow.isCenter ? 0 : (popupWindow.isLeft ? -1 : 1)) : (popupWindow.horizontalPosition < 33 ? -1 : (popupWindow.horizontalPosition > 66 ? 1 : 0))) * popupWindow.effectivePopupWidth * 0.35
                            to: 0
                            duration: 300
                            easing.type: Easing.OutExpo
                        }
                        NumberAnimation {
                            property: "y"
                            from: (popupWindow.isPreset ? (popupWindow.isCenter ? (popupWindow.isBottom ? popupWindow.s(24) : -popupWindow.s(24)) : 0) : ((popupWindow.verticalPosition > 50) ? popupWindow.s(24) : -popupWindow.s(24)))
                            to: 0
                            duration: 300
                            easing.type: Easing.OutExpo
                        }
                    }
                }

                remove: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; to: 0.0; duration: 200; easing.type: Easing.OutCubic }
                        NumberAnimation {
                            property: "x"
                            to: (popupWindow.isPreset ? (popupWindow.isCenter ? 0 : (popupWindow.isLeft ? -1 : 1)) : (popupWindow.horizontalPosition < 33 ? -1 : (popupWindow.horizontalPosition > 66 ? 1 : 0))) * popupWindow.effectivePopupWidth * 0.35
                            duration: 220
                            easing.type: Easing.InOutCubic
                        }
                        NumberAnimation {
                            property: "y"
                            to: (popupWindow.isPreset ? (popupWindow.isCenter ? (popupWindow.isBottom ? popupWindow.s(24) : -popupWindow.s(24)) : 0) : ((popupWindow.verticalPosition > 50) ? popupWindow.s(24) : -popupWindow.s(24)))
                            duration: 220
                            easing.type: Easing.InOutCubic
                        }
                    }
                }

                displaced: Transition {
                    NumberAnimation { property: "y"; duration: 260; easing.type: Easing.InOutCubic }
                }

                removeDisplaced: Transition {
                    NumberAnimation { property: "y"; duration: 260; easing.type: Easing.InOutCubic }
                }

                delegate: Item {
                    id: delegateWrapper
                    width: ListView.view.width

                    property bool isSuppressedByDnd: popupWindow.dndEnabled && model.urgency !== 2

                    implicitHeight: isSuppressedByDnd ? 0 : (typeLoader.item ? typeLoader.item.implicitHeight : popupWindow.s(70))
                    height: implicitHeight
                    visible: !isSuppressedByDnd

                    property int popupUid: model.uid || model.latestUid
                    property var realNotif: popupWindow.getNotif(popupUid) || (model.notif ? model.notif : null)
                    property bool isPopupContext: true
                    property var msgModel: model
                    property bool isExpanded: typeLoader.item && typeLoader.item.expanded ? true : false
                    property bool isHovered: typeLoader.item && typeLoader.item.isHovered ? true : false
                    property bool isDragging: typeLoader.item && typeLoader.item.isDragging ? true : false

                    property var actionArray: {
                        try {
                            return model.actionsJson ? JSON.parse(model.actionsJson) : []
                        } catch (e) {
                            return []
                        }
                    }

                    property int effectiveTimeout: {
                        if (model.urgency === 2) return 0;
                        var n = delegateWrapper.realNotif;
                        if (!n) return 5000;
                        var t = typeof n.expireTimeout === "number" ? n.expireTimeout : (typeof n.timeout === "number" ? n.timeout : -1);
                        if (t === 0) return 0;
                        if (t > 0) return t;
                        return 5000;
                    }

                    Connections {
                        target: delegateWrapper.realNotif || null
                        function onClosed() {
                            popupWindow.removeNotif(delegateWrapper.popupUid);
                        }
                    }

                    Timer {
                        id: dismissTimer
                        interval: delegateWrapper.effectiveTimeout > 0 ? delegateWrapper.effectiveTimeout : 5000
                        running: delegateWrapper.effectiveTimeout > 0 && !delegateWrapper.isHovered && !delegateWrapper.isExpanded && !delegateWrapper.isDragging
                        repeat: false
                        onTriggered: popupWindow.removeNotif(delegateWrapper.popupUid)
                    }

                    function removeThisNotif() {
                        popupWindow.removeNotif(delegateWrapper.popupUid);
                    }

                    Loader {
                        id: typeLoader
                        width: parent.width
                        source: {
                            let app = (model.appName || "").toLowerCase();
                            if (app === "weather") return "types/Weather.qml";
                            if (app === "screenshot" || app === "screen recorder") return "types/Screenshot.qml";
                            return "types/Default.qml";
                        }
                        onLoaded: {
                            if (item) {
                                item.model = delegateWrapper.msgModel;
                                item.root = popupRoot;
                                item.delegateWrapper = delegateWrapper;
                            }
                        }
                    }
                }
            }
        }

        // ─── "Open notification center" pill ──────────────────────────
        // Docked to whichever edge the toasts themselves are configured to
        // appear at, so opening the full manager feels like a continuation
        // of the popup stack rather than a disconnected action.
        Rectangle {
            id: openCenterPill
            visible: NotificationManager.activePopupsModel.count > 0
            opacity: pillArea.containsMouse ? 1.0 : 0.82
            scale: pillArea.containsMouse ? 1.04 : 1.0
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }

            readonly property bool dockBottom: popupWindow.isPreset ? popupWindow.isBottom : (popupWindow.verticalPosition > 50)
            readonly property real gap: popupWindow.s(8)

            width: pillRow.implicitWidth + popupWindow.s(16)
            height: popupWindow.s(24)
            radius: 0
            color: Qt.rgba(ThemeBackend.mantle.r, ThemeBackend.mantle.g, ThemeBackend.mantle.b, 0.92)
            border.width: 1
            border.color: ThemeBackend.surface0

            x: {
                if (popupContainer.width <= 0) return popupContainer.x;
                if (popupWindow.isPreset && popupWindow.isCenter) return popupContainer.x + (popupContainer.width - width) / 2;
                if (!popupWindow.isPreset) {
                    if (popupWindow.horizontalPosition < 33) return popupContainer.x;
                    if (popupWindow.horizontalPosition > 66) return popupContainer.x + popupContainer.width - width;
                    return popupContainer.x + (popupContainer.width - width) / 2;
                }
                return popupWindow.isLeft ? popupContainer.x : (popupContainer.x + popupContainer.width - width);
            }
            y: dockBottom ? (popupContainer.y - height - gap) : (popupContainer.y + popupContainer.height + gap)

            Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.InOutCubic } }
            Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.InOutCubic } }

            RowLayout {
                id: pillRow
                anchors.centerIn: parent
                spacing: popupWindow.s(5)

                Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: "󰂚"
                    font.family: ThemeBackend.iconFamily || "Iosevka Nerd Font"
                    font.pixelSize: popupWindow.s(12)
                    color: ThemeBackend.subtext1
                }

                Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: NotificationManager.activePopupsModel.count
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: popupWindow.s(10)
                    color: ThemeBackend.subtext1
                }
            }

            MouseArea {
                id: pillArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: PanelController.toggle("notifications", "")
            }
        }
    }

    Connections {
        target: NotificationManager
        function onPopupAdded(uid, notif) {
            popupWindow.storeNotif(uid, notif);
        }
    }
}
