import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../"

Item {
    id: root

    property var module: null
    property var widget: module

    readonly property bool isCompact: module ? module.isCompact : false
    readonly property var barWindow: module ? module.barWindow : null
    readonly property bool moduleActive: module ? module.moduleActive : true
    readonly property bool isSolid: module ? module.isSolid : false
    readonly property bool distinctPills: module ? module.distinctPills : false

    readonly property string displayText: CurrentFocus.displayText
    readonly property bool isFocused: CurrentFocus.isFocused
    readonly property bool isFaceVisible: isFocused

    property real topPadding: (isSolid && !distinctPills) ? 0 : (barWindow ? barWindow.s(4) : 4)
    property real bottomPadding: (isSolid && !distinctPills) ? 0 : (barWindow ? barWindow.s(6) : 6)
    property real maxHeight: barWindow ? barWindow.s(180) : 180
    property real maxTextHeight: Math.max(0, maxHeight - (topPadding + focusGlyph.height + innerLayout.spacing + bottomPadding))
    property real targetHeight: (moduleActive && isFocused) ? Math.min(maxHeight, topPadding + focusGlyph.height + innerLayout.spacing + titleClipRect.height + bottomPadding) : 0

    implicitHeight: targetHeight
    implicitWidth: parent ? parent.width : 0

    Column {
        id: innerLayout
        anchors.top: parent.top
        anchors.topMargin: root.topPadding
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: (isSolid && !distinctPills) ? 0 : (barWindow ? barWindow.s(4) : 4)

        Item {
            id: focusGlyph
            width: barWindow ? barWindow.s(root.isCompact ? 14 : 16) : (root.isCompact ? 14 : 16)
            height: width
            anchors.horizontalCenter: parent.horizontalCenter

            Text {
                anchors.centerIn: parent
                text: "󱎴"
                font.family: ThemeBackend.iconFont
                font.pixelSize: barWindow ? barWindow.s(root.isCompact ? 13 : 14) : (root.isCompact ? 13 : 14)
                color: faceArea.containsMouse ? ThemeBackend.text : ThemeBackend.subtext0

                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }

        Item {
            id: titleClipRect
            width: focusGlyph.width
            height: Math.min(titleTextMain.implicitWidth, root.maxTextHeight)
            clip: true
            anchors.horizontalCenter: parent.horizontalCenter

            Item {
                id: rotator
                anchors.centerIn: parent
                width: titleClipRect.height
                height: titleClipRect.width
                rotation: 90

                Text {
                    id: titleTextMain
                    anchors.verticalCenter: parent.verticalCenter
                    width: rotator.width
                    text: root.displayText
                    color: ThemeBackend.text
                    font.pixelSize: barWindow ? barWindow.s(root.isCompact ? 11 : 12) : (root.isCompact ? 11 : 12)
                    elide: Text.ElideRight
                }
            }
        }
    }

    MouseArea {
        id: faceArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        z: -1
        onClicked: {
            if (Caching.serpantinumDir) {
                Quickshell.execDetached(["bash", "-c", Caching.serpantinumDir + "/scripts/qs_manager.sh toggle applauncher"])
            }
        }
    }
}
