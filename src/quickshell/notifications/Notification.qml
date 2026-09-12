import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../"
import "../reusables"

Rectangle {
    id: typeRoot
    width: parent ? parent.width : 0
    implicitHeight: visualItem.implicitHeight
    color: "transparent"

    property var model
    property var root
    property var delegateWrapper
    property bool expanded: false
    property real expandProgress: expanded ? 1.0 : 0.0
    Behavior on expandProgress {
        enabled: !cardHover.draggingV
        NumberAnimation { duration: 280; easing.type: Easing.InOutCubic }
    }

    property bool showIcon: true
    property int urgency: model && typeof model.urgency !== "undefined" ? model.urgency : 1

    readonly property bool isDragging: cardHover.draggingH || cardHover.draggingV
    readonly property bool isHovered: cardHover.containsMouse || cardHover.pressed || isDragging
    readonly property bool isPopup: delegateWrapper && delegateWrapper.isPopupContext ? true : false

    property color accentColor: urgency === 2 ? ThemeBackend.red : ThemeBackend.blue

    // ─── Matugen-driven title color ─────────────────────────────────────
    // Picks a color from the current matugen palette, deterministically
    // keyed by app name, so each app keeps a stable but distinct hue as
    // the wallpaper (and therefore the palette) changes. Body text stays
    // on the neutral subtext colors for legibility.
    readonly property var matugenAccentPalette: [
        ThemeBackend.mauve,
        ThemeBackend.blue,
        ThemeBackend.sapphire,
        ThemeBackend.green,
        ThemeBackend.peach,
        ThemeBackend.pink,
        ThemeBackend.yellow,
        ThemeBackend.teal,
        ThemeBackend.maroon
    ]

    function hashAppKey(str) {
        let h = 0;
        for (let i = 0; i < str.length; i++) {
            h = (h * 31 + str.charCodeAt(i)) | 0;
        }
        return Math.abs(h);
    }

    readonly property string appKey: model ? (model.appName || model.displayName || "") : ""

    readonly property color titleAccentColor: {
        if (typeRoot.urgency === 2) return ThemeBackend.red;
        if (typeRoot.appKey === "" || typeRoot.matugenAccentPalette.length === 0) return ThemeBackend.text;
        return typeRoot.matugenAccentPalette[typeRoot.hashAppKey(typeRoot.appKey) % typeRoot.matugenAccentPalette.length];
    }
    property string fullSummary: ""
    property string fullBody: ""
    property string fullHtmlBody: ""
    property string combinedBodyText: fullBody
    property int msgCount: 1
    readonly property bool canExpand: fullBody.length > 50 || fullBody.indexOf("\n") !== -1 || (delegateWrapper && delegateWrapper.actionArray && delegateWrapper.actionArray.length > 0)

    property alias bgContent: bgContainer.data
    property alias iconArea: iconContainer.data
    property alias headerArea: headerContentContainer.data
    default property alias faceContent: innerLayout.data

    property bool overrideClick: false
    signal cardClicked()

    property real timestamp: model && model.timestamp ? model.timestamp : Date.now()
    property string timeText: ""

    // ─── Privacy mode ──────────────────────────────────────────────────
    property bool privacyMode: {
        let cfg = (typeof Config !== "undefined" && Config.getSetting)
            ? Config.getSetting("notifications", { privacyMode: false })
            : { privacyMode: false };
        return Boolean(cfg.privacyMode);
    }
    property bool descriptionExpanded: false

    property bool readState: model && typeof model.read !== "undefined" ? Boolean(model.read) : true
    function forceRead(r) { readState = r; }
    onModelChanged: {
        if (model) {
            readState = typeof model.read !== "undefined" ? Boolean(model.read) : true;
        }
    }

    property bool _soundPlayed: false

    function playPopupSound() {
        if (_soundPlayed) return;
        if (!typeRoot.isPopup) return;
        if (Math.abs(Date.now() - typeRoot.timestamp) > 3000) return;
        let cfg = Config.getSetting("notifications", { "sound": true, "soundFile": "", "dnd": false });
        if (cfg.dnd === true) return;
        let soundEnabled = cfg.sound !== undefined ? cfg.sound : true;
        let soundFile = cfg.soundFile !== undefined ? cfg.soundFile : "";
        if (!soundEnabled || soundFile === "") return;

        if (typeof Sounds !== "undefined") {
            _soundPlayed = true;
            Sounds.play(soundFile);
        }
    }

    onDelegateWrapperChanged: Qt.callLater(playPopupSound)
    onIsPopupChanged: {
        if (isPopup) Qt.callLater(playPopupSound);
    }

    function updateTimeText() {
        let now = new Date();
        let notifDate = new Date(timestamp);
        let diffSec = Math.floor((now.getTime() - notifDate.getTime()) / 1000);

        let fmt = (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar && Config.rawSettings.bar.time && Config.rawSettings.bar.time.format !== undefined) ? Config.rawSettings.bar.time.format : "HH:mm";
        let timePart = "HH:mm";
        if (fmt.includes("hh:")) {
            timePart = Qt.formatDateTime(notifDate, "hh:mm AP");
        } else {
            timePart = Qt.formatDateTime(notifDate, "HH:mm");
        }

        if (diffSec < 60) {
            timeText = "Just now";
            return;
        }

        let diffMin = Math.floor(diffSec / 60);
        if (diffMin < 60) {
            timeText = diffMin + " min ago";
            return;
        }

        let isSameDay = now.getFullYear() === notifDate.getFullYear() &&
                        now.getMonth() === notifDate.getMonth() &&
                        now.getDate() === notifDate.getDate();

        let yesterday = new Date(now);
        yesterday.setDate(yesterday.getDate() - 1);
        let isYesterday = yesterday.getFullYear() === notifDate.getFullYear() &&
                          yesterday.getMonth() === notifDate.getMonth() &&
                          yesterday.getDate() === notifDate.getDate();

        let diffDays = Math.floor(diffSec / 86400);

        if (isSameDay) {
            timeText = timePart;
        } else if (isYesterday) {
            timeText = "Yesterday " + timePart;
        } else if (diffDays < 7) {
            let dayName = Qt.formatDateTime(notifDate, "dddd");
            timeText = dayName + " " + timePart;
        } else {
            timeText = Qt.formatDateTime(notifDate, "yyyy-MM-dd ") + timePart;
        }
    }

    Connections {
        target: typeof Config !== "undefined" ? Config : null
        function onSettingsLoaded() { updateTimeText(); }
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: updateTimeText()
    }

    onTimestampChanged: updateTimeText()
    Component.onCompleted: {
        updateTimeText();
        Qt.callLater(playPopupSound);
    }

    function s(val) { return root && typeof root.s === "function" ? root.s(val) : val; }

    function getActionIcon(idStr, textStr) {
        let i = (idStr || "").toLowerCase();
        let t = (textStr || "").toLowerCase();
        if (i.includes("reply") || t.includes("reply")) return "󰑚";
        if (i.includes("open") || t.includes("open")) return "󰏔";
        if (i.includes("close") || t.includes("close") || i.includes("dismiss") || t.includes("dismiss")) return "󰎟";
        if (i.includes("default")) return "󰍜";
        if (i.includes("accept") || t.includes("accept") || i.includes("join") || t.includes("join")) return "󰄬";
        if (i.includes("decline") || t.includes("decline")) return "󰅖";
        return "󰅂";
    }

    function doClose() {
        var n = delegateWrapper ? delegateWrapper.realNotif : null;
        if (n && typeof n.close === "function") {
            n.close();
        }
        if (delegateWrapper && typeof delegateWrapper.removeThisNotif === "function") {
            delegateWrapper.removeThisNotif();
        }
    }

    RetainableLock {
        object: delegateWrapper && delegateWrapper.realNotif ? delegateWrapper.realNotif : null
        locked: true
    }

    property real dragX: 0
    property real dragY: 0
    property bool isDismissing: false

    NumberAnimation {
        id: cardResetAnim
        target: typeRoot
        property: "dragX"
        from: typeRoot.dragX
        to: 0
        duration: 240
        easing.type: Easing.OutExpo
    }

    NumberAnimation {
        id: cardResetAnimY
        target: typeRoot
        property: "dragY"
        from: typeRoot.dragY
        to: 0
        duration: 240
        easing.type: Easing.OutExpo
    }

    NumberAnimation {
        id: cardDismissAnim
        target: typeRoot
        property: "dragX"
        from: typeRoot.dragX
        duration: 220
        easing.type: Easing.OutCubic
        onFinished: {
            doClose();
        }
    }

    MouseArea {
        id: cardHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        property real startRootX: 0
        property real startRootY: 0
        property bool draggingH: false
        property bool draggingV: false

        function getTrackingRoot() {
            if (root && typeof root.mapFromItem === "function") return root;
            if (typeRoot.Window && typeRoot.Window.contentItem) return typeRoot.Window.contentItem;
            return typeRoot;
        }

        onPressed: (mouse) => {
            let r = getTrackingRoot();
            let pt = mapToItem(r, mouse.x, mouse.y);
            startRootX = pt.x;
            startRootY = pt.y;
            draggingH = false;
            draggingV = false;
            cardResetAnim.stop();
            cardResetAnimY.stop();
        }

        onPositionChanged: (mouse) => {
            if (!pressed) return;
            let r = getTrackingRoot();
            let pt = mapToItem(r, mouse.x, mouse.y);
            let dx = pt.x - startRootX;
            let dy = pt.y - startRootY;

            if (!draggingH && !draggingV) {
                if (Math.abs(dx) > s(6) && Math.abs(dx) > Math.abs(dy)) {
                    draggingH = true;
                    cardHover.preventStealing = true;
                } else if (Math.abs(dy) > s(6) && Math.abs(dy) >= Math.abs(dx)) {
                    if (typeRoot.canExpand) {
                        draggingV = true;
                        cardHover.preventStealing = true;
                    }
                }
            }

            if (draggingH) {
                typeRoot.dragX = dx;
            } else if (draggingV && typeRoot.canExpand) {
                typeRoot.dragY = dy > 0 ? Math.min(s(3.5), Math.sqrt(dy) * s(0.5)) : 0;
                let targetProg = typeRoot.expanded ? Math.max(0.0, Math.min(1.0, 1.0 + (dy / s(90)))) : Math.max(0.0, Math.min(1.0, dy / s(90)));
                typeRoot.expandProgress = targetProg;
            }
        }

        onReleased: (mouse) => {
            cardHover.preventStealing = false;
            if (draggingH) {
                let threshold = typeRoot.width * 0.18;
                if (Math.abs(typeRoot.dragX) > threshold) {
                    typeRoot.isDismissing = true;
                    cardDismissAnim.from = typeRoot.dragX;
                    cardDismissAnim.to = typeRoot.dragX > 0 ? typeRoot.width * 1.2 : -typeRoot.width * 1.2;
                    cardDismissAnim.start();
                } else {
                    cardResetAnim.from = typeRoot.dragX;
                    cardResetAnim.start();
                }
                draggingH = false;
            } else if (draggingV) {
                cardResetAnimY.from = typeRoot.dragY;
                cardResetAnimY.start();
                if (typeRoot.canExpand) {
                    if (!typeRoot.expanded && typeRoot.expandProgress > 0.35) {
                        typeRoot.expanded = true;
                    } else if (typeRoot.expanded && typeRoot.expandProgress < 0.65) {
                        typeRoot.expanded = false;
                    }
                }
                typeRoot.expandProgress = Qt.binding(() => typeRoot.expanded ? 1.0 : 0.0);
                draggingV = false;
            } else {
                if (typeRoot.readState === false) {
                    typeRoot.forceRead(true);
                    if (model && typeof model.uid !== "undefined") {
                        NotificationManager.markAsRead(model.uid);
                    }
                }

                if (overrideClick) {
                    typeRoot.cardClicked();
                } else {
                    var n = delegateWrapper ? delegateWrapper.realNotif : null;
                    if (n && n.actions && n.actions.length > 0) {
                        var mainAction = null;
                        for (var i = 0; i < n.actions.length; i++) {
                            if (n.actions[i].identifier === "default") {
                                mainAction = n.actions[i];
                                break;
                            }
                        }
                        if (!mainAction && n.actions.length > 0) {
                            mainAction = n.actions[0];
                        }
                        if (mainAction && typeof mainAction.invoke === "function") {
                            mainAction.invoke();
                        }
                    }
                }
            }
        }

        onCanceled: {
            cardHover.preventStealing = false;
            if (draggingH) {
                cardResetAnim.from = typeRoot.dragX;
                cardResetAnim.start();
                draggingH = false;
            }
            if (draggingV) {
                cardResetAnimY.from = typeRoot.dragY;
                cardResetAnimY.start();
                typeRoot.expandProgress = Qt.binding(() => typeRoot.expanded ? 1.0 : 0.0);
                draggingV = false;
            }
        }
    }

    Rectangle {
        id: cardShadow
        anchors.fill: parent
        anchors.topMargin: s(1.5) + Math.max(0, typeRoot.dragY * 0.4)
        anchors.bottomMargin: -(s(1.5) + Math.max(0, typeRoot.dragY * 0.4))
        radius: 0
        color: Qt.rgba(0, 0, 0, 0.08 + Math.min(0.04, Math.max(0, typeRoot.dragY / s(3.5)) * 0.04))
        scale: visualItem.scale
        opacity: visualItem.opacity
        transform: Translate {
            x: typeRoot.dragX
            y: typeRoot.dragY
        }
    }

    TextMetrics {
        id: timeMetrics
        font.family: ThemeBackend.fontFamily
        font.pixelSize: s(11)
        text: typeRoot.timeText
    }

    TextMetrics {
        id: collapsedSummaryMetrics
        font.family: ThemeBackend.fontFamily
        font.weight: Font.Bold
        font.pixelSize: typeRoot.isPopup ? s(13) : s(12)
        text: typeRoot.fullSummary
    }

    readonly property real availableTopWidth: Math.max(0, cardContent.width - (typeRoot.showIcon ? s(50) : 0))
    readonly property real expandBtnSpace: (typeRoot.canExpand ? s(22) + s(6) : 0)
    readonly property real dotSpace: s(14)
    readonly property bool timeOnNextRowCollapsed: (collapsedSummaryMetrics.width + dotSpace + timeMetrics.width + expandBtnSpace) > availableTopWidth

    readonly property var summaryWords: {
        let s = (typeRoot.fullSummary || "").trim();
        return s.length > 0 ? s.split(/\s+/) : [];
    }
    readonly property string summaryPrefix: {
        if (summaryWords.length > 1) {
            return summaryWords.slice(0, summaryWords.length - 1).join(" ");
        }
        return typeRoot.fullSummary;
    }
    readonly property string summaryLastWord: {
        if (summaryWords.length > 1) {
            return summaryWords[summaryWords.length - 1];
        }
        return "";
    }

    Rectangle {
        id: visualItem
        anchors.fill: parent
        radius: 0
        clip: true
        implicitHeight: cardContent.implicitHeight + s(14)

        property color baseColor: typeRoot.readState === false ? Qt.lighter(ThemeBackend.mantle, 1.15) : ThemeBackend.mantle
        color: (cardHover.pressed && !cardHover.draggingH && !cardHover.draggingV) ? Qt.darker(baseColor, 1.1) : (cardHover.containsMouse && !cardHover.draggingH && !cardHover.draggingV ? Qt.lighter(baseColor, 1.08) : baseColor)

        scale: (cardHover.pressed && !cardHover.draggingH && !cardHover.draggingV) ? 0.98 : 1.0

        Behavior on implicitHeight {
            enabled: !cardHover.draggingV
            NumberAnimation { duration: 280; easing.type: Easing.InOutCubic }
        }
        Behavior on color { enabled: !cardHover.draggingH && !cardHover.draggingV; ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on scale { enabled: !cardHover.draggingH && !cardHover.draggingV; NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }

        transform: Translate {
            x: typeRoot.dragX
            y: typeRoot.dragY
        }
        opacity: Math.max(0.0, 1.0 - (Math.abs(typeRoot.dragX) / (typeRoot.width * 0.75)))

        Item {
            id: urgencyGlow
            anchors.fill: parent
            visible: opacity > 0
            opacity: typeRoot.urgency === 2 ? pulseFactor : 0.0

            Behavior on opacity {
                enabled: !pulseAnim.running
                NumberAnimation { duration: 280; easing.type: Easing.InOutCubic }
            }

            property real pulseFactor: 1.0
            SequentialAnimation on pulseFactor {
                id: pulseAnim
                running: typeRoot.urgency === 2
                loops: Animation.Infinite
                NumberAnimation { to: 0.40; duration: 2000; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 2000; easing.type: Easing.InOutSine }
            }

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: visualItem.radius + s(1)
                radius: 0
                color: Qt.rgba(ThemeBackend.red.r, ThemeBackend.red.g, ThemeBackend.red.b, 0.7)
            }

            Rectangle {
                anchors.fill: parent
                anchors.topMargin: visualItem.radius
                radius: 0
                color: "transparent"
                border.width: s(1)
                border.color: Qt.rgba(ThemeBackend.red.r, ThemeBackend.red.g, ThemeBackend.red.b, 0.15)
            }
        }

        Item {
            id: bgContainer
            anchors.fill: parent
        }

        ColumnLayout {
            id: cardContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: s(7)
            spacing: s(3)

            RowLayout {
                Layout.fillWidth: true
                spacing: typeRoot.showIcon ? s(8) : 0
                Layout.alignment: Qt.AlignTop

                Item {
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: typeRoot.showIcon ? s(32) : 0
                    Layout.preferredHeight: typeRoot.showIcon ? s(32) : 0
                    visible: typeRoot.showIcon

                    readonly property real boxRadius: 0
                    readonly property real boxPadding: s(4)

                    Rectangle {
                        anchors.fill: parent
                        anchors.topMargin: s(1.5)
                        anchors.bottomMargin: -s(1.5)
                        radius: 0
                        color: Qt.rgba(0, 0, 0, 0.12)
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 0
                        color: typeRoot.urgency === 2 ? Qt.tint(ThemeBackend.surface1, Qt.rgba(ThemeBackend.red.r, ThemeBackend.red.g, ThemeBackend.red.b, 0.10)) : ThemeBackend.surface1

                        Behavior on color { ColorAnimation { duration: 200 } }
                    }

                    Rectangle {
                        id: iconContainer
                        anchors.fill: parent
                        anchors.margins: parent.boxPadding
                        radius: 0
                        color: "transparent"
                        clip: true
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: -s(3)
                    spacing: 0

                    Item {
                        id: topHeaderRow
                        Layout.fillWidth: true
                        Layout.preferredHeight: {
                            let singleH = s(22);
                            if (typeRoot.timeOnNextRowCollapsed && typeRoot.expandProgress < 1.0) {
                                let twoLineH = collapsedTwoLineContainer.implicitHeight + s(4);
                                return Math.max(singleH, twoLineH) * (1.0 - typeRoot.expandProgress) + singleH * typeRoot.expandProgress;
                            }
                            return singleH;
                        }

                        RowLayout {
                            id: headerContentContainer
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: s(6)
                            opacity: Math.max(0.0, (typeRoot.expandProgress - 0.25) / 0.75)
                            visible: opacity > 0.0
                        }

                        // Unread accent dot
                        Rectangle {
                            id: unreadDot
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: s(6)
                            height: s(6)
                            radius: 0
                            color: typeRoot.accentColor
                            visible: typeRoot.readState === false
                            opacity: (!typeRoot.timeOnNextRowCollapsed) ? Math.max(0.0, 1.0 - typeRoot.expandProgress * 3.0) : 0.0
                        }

                        Text {
                            id: collapsedSummary
                            anchors.left: unreadDot.visible ? unreadDot.right : parent.left
                            anchors.leftMargin: unreadDot.visible ? s(5) : 0
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(0, Math.min(implicitWidth, parent.width - typeRoot.expandBtnSpace - timeMetrics.width - typeRoot.dotSpace - (unreadDot.visible ? s(11) : 0)))
                            text: typeRoot.fullSummary
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Bold
                            font.pixelSize: typeRoot.isPopup ? s(11) : s(10)
                            color: typeRoot.titleAccentColor
                            Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            opacity: (!typeRoot.timeOnNextRowCollapsed) ? Math.max(0.0, 1.0 - typeRoot.expandProgress * 3.0) : 0.0
                            visible: opacity > 0.0
                        }

                        Text {
                            id: dotLabel
                            anchors.left: collapsedSummary.right
                            anchors.leftMargin: s(6)
                            anchors.verticalCenter: parent.verticalCenter
                            text: "•"
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: s(9)
                            visible: opacity > 0.0
                        }

                        Text {
                            id: topTimeLabel
                            anchors.verticalCenter: parent.verticalCenter
                            text: typeRoot.timeText
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: s(10)
                            color: ThemeBackend.subtext1

                            readonly property real startX: collapsedSummary.width + s(12) + dotLabel.implicitWidth
                            readonly property real endX: Math.max(0, topHeaderRow.width - typeRoot.expandBtnSpace - implicitWidth)
                            x: typeRoot.timeOnNextRowCollapsed ? endX : (startX + (endX - startX) * typeRoot.expandProgress)

                            opacity: typeRoot.timeOnNextRowCollapsed ? Math.max(0.0, (typeRoot.expandProgress - 0.25) / 0.75) : 1.0
                            visible: opacity > 0.0 && text !== ""
                        }

                        Column {
                            id: collapsedTwoLineContainer
                            anchors.left: parent.left
                            anchors.right: expandButton.visible ? expandButton.left : parent.right
                            anchors.rightMargin: expandButton.visible ? s(6) : 0
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: s(1)
                            opacity: typeRoot.timeOnNextRowCollapsed ? Math.max(0.0, 1.0 - typeRoot.expandProgress * 3.0) : 0.0
                            visible: opacity > 0.0

                            Text {
                                width: parent.width
                                text: typeRoot.summaryPrefix
                                font.family: ThemeBackend.fontFamily
                                font.weight: Font.Bold
                                font.pixelSize: typeRoot.isPopup ? s(11) : s(10)
                                color: typeRoot.titleAccentColor
                                Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            Row {
                                spacing: s(5)
                                width: parent.width

                                Text {
                                    text: typeRoot.summaryLastWord
                                    font.family: ThemeBackend.fontFamily
                                    font.weight: Font.Bold
                                    font.pixelSize: typeRoot.isPopup ? s(11) : s(10)
                                    color: typeRoot.titleAccentColor
                                    Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                    visible: typeRoot.summaryLastWord !== ""
                                }

                                Text {
                                    text: "•"
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: s(10)
                                    color: ThemeBackend.subtext1
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: typeRoot.summaryLastWord !== ""
                                }

                                Text {
                                    text: typeRoot.timeText
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: s(11)
                                    color: ThemeBackend.subtext1
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: typeRoot.timeText !== ""
                                }
                            }
                        }

                        FlipIcon {
                            id: expandButton
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: typeRoot.canExpand
                            size: s(22)
                            cornerRadius: 0
                            accentColor: ThemeBackend.surface1
                            iconColor: isHoveredOrHighlighted ? ThemeBackend.text : ThemeBackend.subtext1
                            autoToggle: false
                            flipped: typeRoot.expandProgress > 0.5
                            onClicked: typeRoot.expanded = !typeRoot.expanded
                        }
                    }

                    Item {
                        id: expandedSummaryContainer
                        Layout.fillWidth: true
                        Layout.topMargin: -s(2) * typeRoot.expandProgress
                        Layout.preferredHeight: (typeRoot.fullSummary !== "") ? expandedSummary.implicitHeight * Math.min(1.0, typeRoot.expandProgress * 1.1) : 0
                        opacity: Math.max(0.0, (typeRoot.expandProgress - 0.15) / 0.85)
                        visible: opacity > 0.001
                        clip: true

                        Text {
                            id: expandedSummary
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            text: typeRoot.fullSummary
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Bold
                            font.pixelSize: typeRoot.isPopup ? s(11) : s(10)
                            color: typeRoot.titleAccentColor
                            Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            wrapMode: Text.Wrap
                        }
                    }

                        Item {
                        Layout.fillWidth: true
                        Layout.topMargin: -s(1)
                        Layout.preferredHeight: {
                            if (typeRoot.fullBody === "") return 0;
                            let cH = collapsedBody.implicitHeight;
                            let eH = expandedBody.implicitHeight;
                            return cH + (eH - cH) * typeRoot.expandProgress;
                        }
                        clip: true
                        visible: typeRoot.fullBody !== ""

                        // Privacy mode overlay — masks body content when privacy enabled
                        Rectangle {
                            id: privacyMask
                            anchors.fill: parent
                            anchors.margins: -s(4)
                            radius: 0
                            color: ThemeBackend.surface1
                            visible: typeRoot.privacyMode && !typeRoot.isHovered
                            z: 10

                            Text {
                                anchors.centerIn: parent
                                text: "•••••••••••"
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: typeRoot.isPopup ? s(11) : s(10)
                                color: ThemeBackend.subtext1
                            }
                        }

                        Text {
                            id: collapsedBody
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            text: typeRoot.fullBody
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Normal
                            font.pixelSize: typeRoot.isPopup ? s(11) : s(10)
                            color: ThemeBackend.subtext0
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            opacity: Math.max(0.0, 1.0 - typeRoot.expandProgress * 2.5)
                            visible: opacity > 0.001
                        }

                        Text {
                            id: expandedBody
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            text: typeRoot.fullHtmlBody !== "" ? typeRoot.fullHtmlBody : typeRoot.fullBody
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Normal
                            font.pixelSize: typeRoot.isPopup ? s(11) : s(10)
                            color: ThemeBackend.subtext0
                            wrapMode: Text.Wrap
                            textFormat: typeRoot.fullHtmlBody !== "" ? Text.StyledText : Text.PlainText
                            opacity: Math.max(0.0, (typeRoot.expandProgress - 0.2) / 0.8)
                            visible: opacity > 0.001
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: innerLayout.implicitHeight * typeRoot.expandProgress
                        opacity: Math.max(0.0, (typeRoot.expandProgress - 0.2) / 0.8)
                        visible: opacity > 0.001
                        clip: true

                        ColumnLayout {
                            id: innerLayout
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: s(2)
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: (delegateWrapper && delegateWrapper.actionArray && delegateWrapper.actionArray.length > 0) ? (actionLayout.implicitHeight + s(12)) * typeRoot.expandProgress : 0
                        opacity: Math.max(0.0, (typeRoot.expandProgress - 0.2) / 0.8)
                        visible: opacity > 0.001
                        clip: true

                        RowLayout {
                            id: actionLayout
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.topMargin: s(10)
                            anchors.rightMargin: s(8)
                            spacing: s(8)

                            Item {
                                Layout.fillWidth: true
                            }

                            Repeater {
                                model: delegateWrapper ? delegateWrapper.actionArray : []
                                delegate: ClickButton {
                                    readonly property bool isPrimary: index === 0
                                    Layout.minimumWidth: s(84)
                                    Layout.preferredHeight: s(28)
                                    cornerRadius: 0
                                    horizontalPadding: s(12)
                                    buttonText: modelData.text || I18n.t("notifications.types.default.action")
                                    textFontSize: typeRoot.isPopup ? s(12) : s(11)
                                    buttonIcon: typeRoot.getActionIcon(modelData.id, modelData.text)
                                    iconFontSize: s(11)
                                    accentColor: isPrimary ? typeRoot.accentColor : ThemeBackend.surface2
                                    textColor: isPrimary ? ThemeBackend.crust : ThemeBackend.subtext1
                                    onTriggered: {
                                        var n = delegateWrapper ? delegateWrapper.realNotif : null;
                                        if (n && n.actions) {
                                            for (var i = 0; i < n.actions.length; i++) {
                                                if (n.actions[i].identifier === modelData.id) {
                                                    n.actions[i].invoke();
                                                    break;
                                                }
                                            }
                                        }
                                        if (delegateWrapper && typeof delegateWrapper.removeThisNotif === "function") {
                                            delegateWrapper.removeThisNotif();
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
}
