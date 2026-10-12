import QtQuick
import Quickshell
import "../../../reusables"
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

    property bool showLayout: !barWindow || isPreview
    Timer {
        interval: 100
        running: root.moduleActive && root.barWindow && root.barWindow.isStartupReady && root.barWindow.isDataReady && !root.showLayout
        onTriggered: root.showLayout = true
    }

    property real targetHeight: moduleActive ? pill.height + s(isCompact ? 8 : 10) : 0
    readonly property bool isFaceVisible: showLayout && targetHeight > 0
    implicitHeight: targetHeight
    implicitWidth: parent ? parent.width : 0

    ClickButton {
        id: pill
        anchors.centerIn: parent
        width: root.s(root.isCompact ? 28 : 30)
        height: width
        cornerRadius: Math.max(0, ThemeBackend.borderRadius - root.s(2))
        horizontalPadding: 0
        buttonIcon: "󰍛"
        iconFontSize: root.s(14)
        accentColor: ThemeBackend.blue !== undefined ? ThemeBackend.blue : ThemeBackend.mauve
        textColor: ThemeBackend.base
        onClicked: root.launchMonitor()
    }
}
