pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../../../"
import "SysInfoCommand.js" as SysInfoCommand

Item {
    id: root

    property var module: null
    property var widget: module

    readonly property var activeTarget: widget || module
    readonly property bool isCompact: activeTarget ? activeTarget.isCompact : false
    readonly property var barWindow: activeTarget ? activeTarget.barWindow : null
    readonly property bool moduleActive: !activeTarget || activeTarget.moduleActive
    readonly property bool isPreview: !!(activeTarget && activeTarget.isPreview)

    function s(value) { return barWindow ? barWindow.s(value) : value; }
    function configuredCommand() {
        const settings = (typeof Config !== "undefined" && Config.rawSettings) ? Config.rawSettings.bar : null;
        return SysInfoCommand.resolve(settings);
    }
    function launchMonitor() {
        const command = configuredCommand();
        if (command.length) Quickshell.execDetached(command);
    }

    readonly property string cpuText: SysData.cpu + "%"
    readonly property string ramText: Number(SysData.ramGb).toFixed(1) + "G"
    readonly property string tempText: SysData.temp + "°"

    property bool showLayout: !barWindow || isPreview
    readonly property bool isCollecting: moduleActive && showLayout && visible
    property bool isSubscribed: false

    function updateSubscription() {
        if (isCollecting && !isSubscribed) {
            isSubscribed = true;
            SysData.subscribe();
        } else if (!isCollecting && isSubscribed) {
            isSubscribed = false;
            SysData.unsubscribe();
        }
    }

    Component.onCompleted: updateSubscription()
    Component.onDestruction: {
        if (isSubscribed) {
            isSubscribed = false;
            SysData.unsubscribe();
        }
    }
    onIsCollectingChanged: updateSubscription()

    Timer {
        interval: 100
        running: root.moduleActive && root.barWindow && root.barWindow.isStartupReady && root.barWindow.isDataReady && !root.showLayout
        onTriggered: root.showLayout = true
    }

    property real targetWidth: moduleActive ? statsRow.implicitWidth + s(isCompact ? 20 : 28) : 0
    readonly property bool isFaceVisible: showLayout && targetWidth > 0

    implicitWidth: targetWidth
    implicitHeight: parent ? parent.height : 0

    opacity: showLayout ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
    transform: Translate {
        x: root.showLayout ? 0 : root.s(40)
        Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }
    }

    component Stat: Row {
        property string value: ""
        property string label: ""
        property color accent: ThemeBackend.text
        spacing: root.s(root.isCompact ? 3 : 4)

        Text {
            text: parent.value
            anchors.verticalCenter: parent.verticalCenter
            font.family: ThemeBackend.fontFamily
            font.pixelSize: root.s(root.isCompact ? 14 : 15)
            font.bold: true
            color: parent.accent
        }
        Text {
            text: parent.label
            anchors.verticalCenter: parent.verticalCenter
            font.family: ThemeBackend.fontFamily
            font.pixelSize: root.s(root.isCompact ? 7 : 8)
            font.bold: true
            color: ThemeBackend.subtext0
        }
    }

    Row {
        id: statsRow
        anchors.centerIn: parent
        spacing: root.s(root.isCompact ? 10 : 14)

        Stat {
            value: root.cpuText
            label: "CPU"
            accent: ThemeBackend.mauve
        }
        Stat {
            value: root.ramText
            label: "RAM"
            accent: ThemeBackend.teal
        }
        Stat {
            value: root.tempText
            label: "TEMP"
            accent: ThemeBackend.peach
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: root.configuredCommand().length ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.launchMonitor()
    }
}
