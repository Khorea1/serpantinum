import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"

Item {
    id: root
    focus: true

    function s(val) {
        return Scaler.s(val);
    }

    property real introContent: 0.0
    readonly property real slideDistance: root.s(52)
    property string searchText: ""
    property string selectedApp: ""
    property int selectedTimeRange: -1 // -1 = all, 0 = today, 1 = yesterday, 2 = older

    onVisibleChanged: {
        NotificationManager.sysPanelOpen = visible;
        if (visible) {
            closeSequence.stop();
            introContent = 0.0;
            startupSequence.restart();
            focusTimer.start();
        } else {
            startupSequence.stop();
            closeSequence.stop();
        }
    }

    // Which screen edge this panel is currently docked to — mirrors the
    // same rule Main.qml uses to place the panel, so the decorative "docked
    // edge" border flattens the correct side instead of always the left.
    readonly property string dockSide: {
        var notifCfg = (typeof Config !== "undefined" && Config.getSetting)
            ? Config.getSetting("notifications", { position: "top right", horizontalPosition: 95 })
            : { position: "top right", horizontalPosition: 95 };
        var pos = (notifCfg && notifCfg.position !== undefined) ? notifCfg.position : "top right";
        if (pos === "custom") {
            var hp = (notifCfg && notifCfg.horizontalPosition !== undefined) ? notifCfg.horizontalPosition : 95;
            return hp < 33 ? "left" : (hp > 66 ? "right" : "center");
        }
        if (pos.indexOf("left") !== -1) return "left";
        if (pos.indexOf("center") !== -1) return "center";
        return "right";
    }
    readonly property var timeRanges: [-1, 0, 1, 2]
    readonly property var timeRangeLabels: ["All", "Today", "Yesterday", "Older"]

    // Filtered + grouped data
    property var filteredEntries: []
    property var groupedEntries: []

    // DND snooze menu
    property bool showDndMenu: false
    readonly property var dndSnoozeOptions: [
        { label: "15m", minutes: 15 },
        { label: "1h", minutes: 60 },
        { label: "4h", minutes: 240 },
        { label: "8h", minutes: 480 }
    ]

    function formatDndRemaining(ms) {
        if (ms <= 0) return "";
        var totalMin = Math.ceil(ms / 60000);
        var h = Math.floor(totalMin / 60);
        var m = totalMin % 60;
        if (h > 0) return h + "h " + (m > 0 ? m + "m" : "");
        return m + "m";
    }

    Timer {
        id: focusTimer
        interval: 50
        running: true
        repeat: false
        onTriggered: searchInput.forceActiveFocus()
    }

    Component.onCompleted: {
        if (visible) startupSequence.start();
        focusTimer.start();
        refreshFilteredEntries();
    }

    Connections {
        target: NotificationManager
        function onHistoryListChanged() { refreshFilteredEntries(); }
    }

    function refreshFilteredEntries() {
        if (typeof NotificationManager === "undefined") {
            filteredEntries = [];
            groupedEntries = [];
            return;
        }

        NotificationManager.searchFilter = searchText.toLowerCase();
        NotificationManager.appFilter = selectedApp.toLowerCase();
        var list = NotificationManager.getFilteredHistory();

        // Time range filter
        if (selectedTimeRange >= 0) {
            list = list.filter(function(n) {
                return NotificationManager.getHistoryTimeRange(n.timestamp) === selectedTimeRange;
            });
        }

        filteredEntries = list;
        rebuildGroupedList();
    }

    function rebuildGroupedList() {
        var groups = {};
        var groupOrder = [];

        for (var i = 0; i < filteredEntries.length; i++) {
            var n = filteredEntries[i];
            var range = NotificationManager.getHistoryTimeRange(n.timestamp);
            var rangeLabel = NotificationManager.getHistoryTimeRangeLabel(range);
            var appKey = (n.displayName || n.appName || "System");
            var gKey = rangeLabel + "::" + appKey;

            if (!groups[gKey]) {
                groups[gKey] = {
                    range: range,
                    rangeLabel: rangeLabel,
                    appName: appKey,
                    items: [],
                    icon: n.iconPath || "",
                    unreadCount: 0
                };
                groupOrder.push(gKey);
            }

            groups[gKey].items.push(n);
            if (!n.read) groups[gKey].unreadCount++;
        }

        var result = [];
        for (var j = 0; j < groupOrder.length; j++) {
            var gd = groups[groupOrder[j]];
            result.push({
                groupKey: groupOrder[j],
                range: gd.range,
                rangeLabel: gd.rangeLabel,
                appName: gd.appName,
                icon: gd.icon,
                count: gd.items.length,
                unreadCount: gd.unreadCount,
                items: gd.items
            });
        }

        groupedEntries = result;
    }

    NumberAnimation {
        id: startupSequence
        target: root
        property: "introContent"
        to: 1.0
        duration: 320
        easing.type: Easing.OutCubic
    }

    SequentialAnimation {
        id: closeSequence
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "introContent"
                to: 0.0
                duration: 260
                easing.type: Easing.InCubic
            }
        }
        ScriptAction {
            script: {
                Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "close"]);
            }
        }
    }

    Keys.onEscapePressed: (event) => {
        closeSequence.start();
        event.accepted = true;
    }

    Rectangle {
        id: sidebarPanel
        anchors.fill: parent
        color: Qt.rgba(ThemeBackend.base.r, ThemeBackend.base.g, ThemeBackend.base.b, 0.97)
        radius: 0
        border.width: 1
        border.color: Qt.rgba(ThemeBackend.surface1.r, ThemeBackend.surface1.g, ThemeBackend.surface1.b, 0.9)
        clip: true
        opacity: root.introContent
        transform: Translate {
            x: (root.dockSide === "left" ? -root.slideDistance : (root.dockSide === "right" ? root.slideDistance : 0)) * (1.0 - root.introContent)
        }

        Rectangle {
            visible: root.dockSide !== "center"
            anchors.left: root.dockSide === "left" ? parent.left : undefined
            anchors.right: root.dockSide === "right" ? parent.right : undefined
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: root.s(16)
            color: sidebarPanel.color
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: sidebarPanel.border.color }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: sidebarPanel.border.color }
            Rectangle {
                anchors.left: root.dockSide === "left" ? parent.left : undefined
                anchors.right: root.dockSide === "right" ? parent.right : undefined
                width: 1
                height: parent.height
                color: sidebarPanel.border.color
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.s(16)
            spacing: root.s(12)

            // ─── Header ────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: root.s(8)

                Text {
                    text: I18n.t("syspanel.notifications.title")
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Bold
                    font.pixelSize: root.s(16)
                    color: ThemeBackend.text
                }

                Item { Layout.fillWidth: true }

                // Active popups indicator + quick dismiss
                Rectangle {
                    Layout.preferredHeight: root.s(26)
                    Layout.preferredWidth: activePopupsRow.implicitWidth + root.s(16)
                    radius: 0
                    color: ThemeBackend.surface0
                    border.width: 1
                    border.color: ThemeBackend.surface1
                    visible: NotificationManager.activePopupsModel && NotificationManager.activePopupsModel.count > 0

                    RowLayout {
                        id: activePopupsRow
                        anchors.centerIn: parent
                        spacing: root.s(6)

                        Rectangle {
                            width: root.s(6)
                            height: root.s(6)
                            radius: 0
                            Layout.alignment: Qt.AlignVCenter
                            color: ThemeBackend.green
                        }

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: I18n.t("notifications.center.active_count", { count: NotificationManager.activePopupsModel.count })
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: root.s(10)
                            color: ThemeBackend.subtext1
                        }

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: "󰅗"
                            font.family: ThemeBackend.iconFamily || "Iosevka Nerd Font"
                            font.pixelSize: root.s(12)
                            color: ThemeBackend.subtext1
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: NotificationManager.dismissAllPopups()
                    }
                }

                // DND button (tap = toggle permanent, tap the caret = snooze menu)
                Rectangle {
                    Layout.preferredHeight: root.s(30)
                    Layout.preferredWidth: dndRow.implicitWidth + root.s(18)
                    radius: 0
                    color: NotificationManager.dndActive ? ThemeBackend.blue : ThemeBackend.surface1

                    RowLayout {
                        id: dndRow
                        anchors.centerIn: parent
                        spacing: root.s(4)

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: NotificationManager.dndActive ? "󰂛" : "󰂚"
                            font.family: ThemeBackend.iconFamily || "Iosevka Nerd Font"
                            font.pixelSize: root.s(15)
                            color: NotificationManager.dndActive ? ThemeBackend.crust : ThemeBackend.subtext1
                        }

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            visible: NotificationManager.dndSnoozed
                            text: root.formatDndRemaining(NotificationManager.dndRemainingMs)
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: root.s(9)
                            color: NotificationManager.dndActive ? ThemeBackend.crust : ThemeBackend.subtext1
                        }

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: root.showDndMenu ? "󰅃" : "󰅀"
                            font.family: ThemeBackend.iconFamily || "Iosevka Nerd Font"
                            font.pixelSize: root.s(11)
                            color: NotificationManager.dndActive ? ThemeBackend.crust : ThemeBackend.subtext1
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showDndMenu = !root.showDndMenu
                    }
                }

                // Unread count badge
                Rectangle {
                    Layout.preferredHeight: root.s(22)
                    Layout.preferredWidth: Math.max(unreadBadgeText.implicitWidth + root.s(12), root.s(22))
                    radius: 0
                    color: NotificationManager.hasUnread ? ThemeBackend.blue : "transparent"
                    visible: NotificationManager.hasUnread

                    Text {
                        id: unreadBadgeText
                        anchors.centerIn: parent
                        text: NotificationManager.unreadCount.toString()
                        font.family: ThemeBackend.fontFamily
                        font.weight: Font.Bold
                        font.pixelSize: root.s(10)
                        color: ThemeBackend.crust
                    }
                }

                // Mark all read button
                ClickButton {
                    Layout.preferredWidth: root.s(36)
                    Layout.preferredHeight: root.s(30)
                    cornerRadius: 0
                    buttonIcon: "󰑇"
                    iconFontSize: root.s(16)
                    accentColor: ThemeBackend.surface1
                    textColor: ThemeBackend.subtext1
                    visible: NotificationManager.hasUnread

                    onTriggered: {
                        NotificationManager.markNotificationsSeen();
                        for (var i = 0; i < NotificationManager.historyList.length; i++) {
                            NotificationManager.historyList[i].read = true;
                        }
                        NotificationManager.historyList = NotificationManager.historyList.slice();
                        NotificationManager.saveHistory();
                        refreshFilteredEntries();
                    }
                }

                // Dismiss all button — clears the persisted history AND kills
                // any popups/toasts still on screen.
                ClickButton {
                    Layout.preferredWidth: root.s(36)
                    Layout.preferredHeight: root.s(30)
                    cornerRadius: 0
                    buttonIcon: "󰎟"
                    iconFontSize: root.s(16)
                    accentColor: ThemeBackend.surface1
                    textColor: ThemeBackend.subtext1
                    visible: (NotificationManager.historyList && NotificationManager.historyList.length > 0)
                        || (NotificationManager.activePopupsModel && NotificationManager.activePopupsModel.count > 0)

                    onTriggered: {
                        NotificationManager.dismissEverything();
                        refreshFilteredEntries();
                    }
                }

                // Close button
                ClickButton {
                    Layout.preferredWidth: root.s(36)
                    Layout.preferredHeight: root.s(30)
                    cornerRadius: 0
                    buttonIcon: "󰖭"
                    iconFontSize: root.s(16)
                    accentColor: ThemeBackend.surface1
                    textColor: ThemeBackend.subtext1

                    onTriggered: closeSequence.start()
                }
            }

            // ─── DND snooze menu ─────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: root.showDndMenu ? (dndMenuColumn.implicitHeight + root.s(16)) : 0
                clip: true
                radius: 0
                color: ThemeBackend.surface0
                border.width: root.showDndMenu ? 1 : 0
                border.color: ThemeBackend.surface1
                visible: height > 0

                Behavior on Layout.preferredHeight {
                    NumberAnimation { duration: 220; easing.type: Easing.InOutCubic }
                }

                ColumnLayout {
                    id: dndMenuColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: root.s(8)
                    spacing: root.s(6)

                    Text {
                        text: NotificationManager.dndActive
                            ? (NotificationManager.dndPermanent
                                ? I18n.t("notifications.center.dnd.on_permanent")
                                : I18n.t("notifications.center.dnd.on_snoozed", { time: root.formatDndRemaining(NotificationManager.dndRemainingMs) }))
                            : I18n.t("notifications.center.dnd.off_prompt")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: root.s(11)
                        color: ThemeBackend.subtext1
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.s(6)

                        Repeater {
                            model: root.dndSnoozeOptions

                            ClickButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(28)
                                cornerRadius: 0
                                buttonText: modelData.label
                                textFontSize: root.s(10)
                                accentColor: ThemeBackend.surface1
                                textColor: ThemeBackend.text
                                onTriggered: {
                                    NotificationManager.setDndSnooze(modelData.minutes);
                                    root.showDndMenu = false;
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.s(6)

                        ClickButton {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.s(28)
                            cornerRadius: 0
                            buttonText: NotificationManager.dndPermanent
                                ? I18n.t("notifications.center.dnd.disable_permanent")
                                : I18n.t("notifications.center.dnd.enable_permanent")
                            textFontSize: root.s(10)
                            accentColor: ThemeBackend.surface1
                            textColor: ThemeBackend.text
                            onTriggered: {
                                NotificationManager.toggleDndPermanent();
                                root.showDndMenu = false;
                            }
                        }

                        ClickButton {
                            Layout.preferredWidth: root.s(70)
                            Layout.preferredHeight: root.s(28)
                            cornerRadius: 0
                            buttonText: I18n.t("notifications.center.dnd.off")
                            textFontSize: root.s(10)
                            accentColor: ThemeBackend.surface1
                            textColor: ThemeBackend.overlay0
                            visible: NotificationManager.dndActive
                            onTriggered: {
                                NotificationManager.disableDnd();
                                root.showDndMenu = false;
                            }
                        }
                    }
                }
            }

            // ─── Search bar ────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: root.s(36)
                radius: 0
                color: ThemeBackend.surface0
                border.width: 1
                border.color: searchInput.activeFocus ? ThemeBackend.blue : ThemeBackend.surface1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: root.s(10)
                    anchors.rightMargin: root.s(10)
                    spacing: root.s(6)

                    Text {
                        text: "󰍉"
                        font.family: ThemeBackend.iconFamily || "Iosevka Nerd Font"
                        font.pixelSize: root.s(14)
                        color: ThemeBackend.overlay0
                    }

                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: root.s(12)
                        color: ThemeBackend.text
                        clip: true
                        selectByMouse: true
                        selectionColor: ThemeBackend.blue

                        property string placeholder: "Search notifications..."
                        property string displayText: text === "" ? placeholder : text

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: searchInput.placeholder
                            font: searchInput.font
                            color: ThemeBackend.overlay0
                            visible: searchInput.text === "" && !searchInput.activeFocus
                        }

                        onTextChanged: {
                            root.searchText = text;
                            root.refreshFilteredEntries();
                        }

                        Keys.onEscapePressed: {
                            text = "";
                            root.forceActiveFocus();
                        }
                    }

                    Text {
                        text: "󰑓"
                        font.family: ThemeBackend.iconFamily || "Iosevka Nerd Font"
                        font.pixelSize: root.s(12)
                        color: ThemeBackend.overlay0
                        visible: searchInput.text !== ""
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: searchInput.text = ""
                        }
                    }
                }
            }

            // ─── Time range chips ──────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: root.s(6)

                Repeater {
                    model: root.timeRangeLabels

                    Rectangle {
                        Layout.preferredHeight: root.s(26)
                        Layout.preferredWidth: timeChipLabel.implicitWidth + root.s(16)
                        radius: 0
                        color: root.selectedTimeRange === root.timeRanges[index]
                            ? ThemeBackend.blue : ThemeBackend.surface0
                        border.width: 1
                        border.color: root.selectedTimeRange === root.timeRanges[index]
                            ? ThemeBackend.blue : ThemeBackend.surface1

                        Text {
                            id: timeChipLabel
                            anchors.centerIn: parent
                            text: modelData
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: root.s(10)
                            font.weight: Font.Medium
                            color: root.selectedTimeRange === root.timeRanges[index]
                                ? ThemeBackend.crust : ThemeBackend.subtext1
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selectedTimeRange = root.timeRanges[index];
                                root.refreshFilteredEntries();
                            }
                        }
                    }
                }
            }

            // ─── App filter chips ──────────────────────────────────────
            Flow {
                Layout.fillWidth: true
                spacing: root.s(6)
                visible: root.groupedEntries.length > 0

                // "All" chip
                Rectangle {
                    height: root.s(24)
                    width: allLabel.implicitWidth + root.s(14)
                    radius: 0
                    color: root.selectedApp === "" ? ThemeBackend.blue : ThemeBackend.surface0
                    border.width: 1
                    border.color: root.selectedApp === "" ? ThemeBackend.blue : ThemeBackend.surface1

                    Text {
                        id: allLabel
                        anchors.centerIn: parent
                        text: "All apps"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: root.s(10)
                        color: root.selectedApp === "" ? ThemeBackend.crust : ThemeBackend.subtext1
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.selectedApp = "";
                            root.refreshFilteredEntries();
                        }
                    }
                }

                Repeater {
                    model: NotificationManager.getHistoryApps ? NotificationManager.getHistoryApps() : []

                    Rectangle {
                        height: root.s(24)
                        width: appChipLabel.implicitWidth + root.s(14)
                        radius: 0

                        readonly property string appName: {
                            var d = modelData;
                            if (!d) return "";
                            if (typeof d === "string") return d.toLowerCase();
                            if (d.name) return d.name.toString().toLowerCase();
                            return "";
                        }
                        readonly property string appIcon: {
                            var d = modelData;
                            if (!d) return "";
                            if (typeof d === "string") return "";
                            return d.icon || "";
                        }

                        color: root.selectedApp === appName ? ThemeBackend.blue : ThemeBackend.surface0
                        border.width: 1
                        border.color: root.selectedApp === appName ? ThemeBackend.blue : ThemeBackend.surface1

                        Text {
                            id: appChipLabel
                            anchors.centerIn: parent
                            text: (modelData && modelData.name) ? modelData.name : (typeof modelData === "string" ? modelData : "")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: root.s(10)
                            color: root.selectedApp === appName ? ThemeBackend.crust : ThemeBackend.subtext1
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selectedApp = (root.selectedApp === appName) ? "" : appName;
                                root.refreshFilteredEntries();
                            }
                        }
                    }
                }
            }

            // ─── Divider ───────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: ThemeBackend.surface1
            }

            // ─── Notification list ─────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                // Empty state — pusheen GIF (same as system panel)
                Item {
                    anchors.centerIn: parent
                    visible: root.groupedEntries.length === 0
                    width: root.s(160)
                    height: emptyCol.implicitHeight

                    ColumnLayout {
                        id: emptyCol
                        anchors.centerIn: parent
                        spacing: root.s(12)

                        ImageBox {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: root.s(120)
                            Layout.preferredHeight: root.s(120)
                            source: Caching.serpantinumDir ? ("file://" + Caching.serpantinumDir + "/assets/pushy2.gif") : Qt.resolvedUrl("../../assets/pushy2.gif")
                            isGif: true
                            playing: true
                            fillMode: Image.PreserveAspectFit
                            cornerRadius: 0
                            imageRadius: 0
                            interactive: false
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.searchText !== "" ? I18n.t("notifications.center.empty_search") : I18n.t("notifications.center.empty")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: root.s(13)
                            color: ThemeBackend.overlay0
                        }
                    }
                }

                // List
                ListView {
                    id: notifList
                    anchors.fill: parent
                    spacing: root.s(8)
                    clip: true
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: ScrollBar {
                        active: notifList.moving || notifList.movingVertically
                        width: root.s(4)
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle { implicitWidth: root.s(4); radius: 0; color: ThemeBackend.surface2 }
                    }

                    add: Transition {
                        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 240; easing.type: Easing.OutQuint }
                        NumberAnimation { property: "scale"; from: 0.97; to: 1.0; duration: 240; easing.type: Easing.OutQuint }
                    }
                    remove: Transition {
                        NumberAnimation { property: "opacity"; to: 0.0; duration: 180; easing.type: Easing.OutCubic }
                    }
                    displaced: Transition {
                        NumberAnimation { properties: "x,y"; duration: 260; easing.type: Easing.OutCubic }
                    }

                    model: root.groupedEntries

                    delegate: Item {
                        id: groupDelegate
                        width: notifList ? notifList.width : 0
                        height: groupContent.implicitHeight
                        implicitHeight: height

                        property var groupData: modelData

                        ColumnLayout {
                            id: groupContent
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: root.s(4)

                            // Group header
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(8)

                                // App icon
                                Rectangle {
                                    Layout.preferredWidth: root.s(24)
                                    Layout.preferredHeight: root.s(24)
                                    radius: 0
                                    color: ThemeBackend.surface0

                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: root.s(3)
                                        source: groupDelegate.groupData.icon || ""
                                        fillMode: Image.PreserveAspectFit
                                        visible: status === Image.Ready
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰂚"
                                        font.family: ThemeBackend.iconFamily || "Iosevka Nerd Font"
                                        font.pixelSize: root.s(12)
                                        color: ThemeBackend.overlay0
                                        visible: !parent.children[1].visible
                                    }
                                }

                                // App name + count
                                Text {
                                    Layout.fillWidth: true
                                    text: groupDelegate.groupData.appName
                                    font.family: ThemeBackend.fontFamily
                                    font.weight: Font.Bold
                                    font.pixelSize: root.s(11)
                                    color: ThemeBackend.text
                                    elide: Text.ElideRight
                                }

                                // Unread badge
                                Rectangle {
                                    Layout.preferredWidth: root.s(18)
                                    Layout.preferredHeight: root.s(18)
                                    radius: 0
                                    color: ThemeBackend.blue
                                    visible: groupDelegate.groupData.unreadCount > 0

                                    Text {
                                        anchors.centerIn: parent
                                        text: groupDelegate.groupData.unreadCount
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: root.s(9)
                                        font.weight: Font.Bold
                                        color: ThemeBackend.crust
                                    }
                                }

                                // Count
                                Text {
                                    text: groupDelegate.groupData.count
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: root.s(10)
                                    color: ThemeBackend.overlay0
                                    visible: groupDelegate.groupData.unreadCount === 0
                                }

                                // Dismiss whole group
                                Rectangle {
                                    Layout.preferredWidth: root.s(22)
                                    Layout.preferredHeight: root.s(22)
                                    radius: 0
                                    color: groupDismissArea.containsMouse ? ThemeBackend.surface1 : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰅖"
                                        font.family: ThemeBackend.iconFamily || "Iosevka Nerd Font"
                                        font.pixelSize: root.s(11)
                                        color: ThemeBackend.overlay0
                                    }

                                    MouseArea {
                                        id: groupDismissArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var ids = groupDelegate.groupData.items.map(function(it) { return it.id; });
                                            NotificationManager.dismissHistoryItems(ids);
                                            refreshFilteredEntries();
                                        }
                                    }
                                }
                            }

                            // Individual notifications
                            Repeater {
                                model: groupDelegate.groupData.items

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: notifContent.implicitHeight + root.s(12)
                                    radius: 0
                                    color: notifArea.containsMouse ? ThemeBackend.surface0 : "transparent"

                                    ColumnLayout {
                                        id: notifContent
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: root.s(8)
                                        anchors.rightMargin: root.s(28)
                                        spacing: root.s(2)

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: root.s(6)

                                            // Unread dot
                                            Rectangle {
                                                Layout.preferredWidth: root.s(6)
                                                Layout.preferredHeight: root.s(6)
                                                radius: 0
                                                color: modelData.read ? "transparent" : ThemeBackend.blue
                                                visible: !modelData.read
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.summary || "No title"
                                                font.family: ThemeBackend.fontFamily
                                                font.weight: modelData.read ? Font.Normal : Font.Bold
                                                font.pixelSize: root.s(11)
                                                color: ThemeBackend.text
                                                elide: Text.ElideRight
                                                maximumLineCount: 1
                                            }

                                            Text {
                                                text: {
                                                    var ts = modelData.timestamp || 0;
                                                    var now = Date.now();
                                                    var diffSec = Math.floor((now - ts) / 1000);
                                                    if (diffSec < 60) return "now";
                                                    var diffMin = Math.floor(diffSec / 60);
                                                    if (diffMin < 60) return diffMin + "m";
                                                    var diffH = Math.floor(diffMin / 60);
                                                    if (diffH < 24) return diffH + "h";
                                                    var diffD = Math.floor(diffH / 24);
                                                    return diffD + "d";
                                                }
                                                font.family: ThemeBackend.fontFamily
                                                font.pixelSize: root.s(9)
                                                color: ThemeBackend.overlay0
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.body || ""
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: root.s(10)
                                            color: ThemeBackend.subtext0
                                            elide: Text.ElideRight
                                            maximumLineCount: 2
                                            wrapMode: Text.Wrap
                                            visible: text !== ""
                                        }

                                        // Urgency indicator for critical
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: modelData.urgency === 2 ? root.s(2) : 0
                                            radius: 0
                                            color: ThemeBackend.red
                                            visible: modelData.urgency === 2
                                        }
                                    }

                                    MouseArea {
                                        id: notifArea
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        hoverEnabled: true

                                        onClicked: {
                                            // Mark as read
                                            if (!modelData.read) {
                                                NotificationManager.markAsRead(modelData.uid);
                                                // Also update the history entry
                                                for (var i = 0; i < NotificationManager.historyList.length; i++) {
                                                    if (NotificationManager.historyList[i].id === modelData.id) {
                                                        var newList = NotificationManager.historyList.slice();
                                                        newList[i] = Object.assign({}, newList[i], { read: true });
                                                        NotificationManager.historyList = newList;
                                                        NotificationManager.saveHistory();
                                                        break;
                                                    }
                                                }
                                            }

                                            // Invoke default action if available
                                            var n = NotificationManager.liveNotifs ? NotificationManager.liveNotifs[modelData.uid] : null;
                                            if (n && n.actions && n.actions.length > 0) {
                                                var mainAction = null;
                                                for (var j = 0; j < n.actions.length; j++) {
                                                    if (n.actions[j].identifier === "default") {
                                                        mainAction = n.actions[j];
                                                        break;
                                                    }
                                                }
                                                if (!mainAction) mainAction = n.actions[0];
                                                if (mainAction && typeof mainAction.invoke === "function") {
                                                    mainAction.invoke();
                                                }
                                            } else {
                                                // Fallback: launch the app via desktopEntry
                                                var resolved = NotificationManager.resolveApp ? NotificationManager.resolveApp(modelData) : null;
                                                if (resolved && resolved.desktopEntry) {
                                                    NotificationManager.launchApp(resolved.desktopEntry);
                                                }
                                            }

                                            refreshFilteredEntries();
                                        }
                                    }

                                    // Per-notification dismiss button (hover-revealed)
                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.margins: root.s(6)
                                        width: root.s(18)
                                        height: root.s(18)
                                        radius: 0
                                        opacity: notifArea.containsMouse || itemDismissArea.containsMouse ? 1.0 : 0.0
                                        scale: itemDismissArea.containsMouse ? 1.08 : 1.0
                                        color: itemDismissArea.containsMouse ? ThemeBackend.surface1 : "transparent"

                                        Behavior on opacity {
                                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                        }
                                        Behavior on scale {
                                            NumberAnimation { duration: 180; easing.type: Easing.OutQuint }
                                        }
                                        Behavior on color {
                                            ColorAnimation { duration: 180 }
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰅖"
                                            font.family: ThemeBackend.iconFamily || "Iosevka Nerd Font"
                                            font.pixelSize: root.s(10)
                                            color: ThemeBackend.overlay0
                                        }

                                        MouseArea {
                                            id: itemDismissArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                NotificationManager.dismissHistoryItems([modelData.id]);
                                                refreshFilteredEntries();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ─── Footer ────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: root.s(6)

                Text {
                    text: filteredEntries.length + " notification" + (filteredEntries.length !== 1 ? "s" : "")
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: root.s(10)
                    color: ThemeBackend.overlay0
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "ESC to close"
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: root.s(10)
                    color: ThemeBackend.overlay0
                }
            }
        }
    }
}
