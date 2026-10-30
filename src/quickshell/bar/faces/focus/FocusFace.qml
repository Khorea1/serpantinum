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

    property real leftPadding: (isSolid && !distinctPills) ? 0 : (barWindow ? barWindow.s(4) : 4)
    property real rightPadding: (isSolid && !distinctPills) ? 0 : (barWindow ? barWindow.s(6) : 6)
    property real maxWidth: barWindow ? barWindow.s(180) : 180
    property real maxTextWidth: Math.max(0, maxWidth - (leftPadding + focusGlyph.width + innerLayout.spacing + rightPadding))
    property real targetWidth: (moduleActive && isFocused) ? Math.min(maxWidth, leftPadding + focusGlyph.width + innerLayout.spacing + titleTextMain.width + rightPadding) : 0

    implicitWidth: targetWidth
    implicitHeight: parent ? parent.height : 0

    Row {
        id: innerLayout
        anchors.left: parent.left
        anchors.leftMargin: root.leftPadding
        anchors.verticalCenter: parent.verticalCenter
        spacing: barWindow ? barWindow.s(4) : 4

        Item {
            id: focusGlyph
            width: barWindow ? barWindow.s(root.isCompact ? 14 : 16) : (root.isCompact ? 14 : 16)
            height: width
            anchors.verticalCenter: parent.verticalCenter

            Text {
                anchors.centerIn: parent
                text: "󱎴"
                font.family: ThemeBackend.iconFont
                font.pixelSize: barWindow ? barWindow.s(root.isCompact ? 13 : 14) : (root.isCompact ? 13 : 14)
                color: glyphArea.containsMouse ? ThemeBackend.text : ThemeBackend.subtext0

                Behavior on color { ColorAnimation { duration: 150 } }
            }

            MouseArea {
                id: glyphArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (Caching.serpantinumDir) {
                        Quickshell.execDetached(["bash", "-c", Caching.serpantinumDir + "/scripts/qs_manager.sh toggle applauncher"])
                    }
                }
            }
        }

        Item {
            id: titleClipRect
            width: Math.min(root.maxTextWidth, titleTextMain.width)
            height: titleTextMain.height
            anchors.verticalCenter: parent.verticalCenter
            clip: true

            Behavior on width {
                enabled: barWindow ? (barWindow.startupCascadeFinished && !barWindow.positionChanging) : true
                NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
            }

            Text {
                id: titleTextMain
                text: root.displayText
                font.family: ThemeBackend.fontFamily
                font.pixelSize: barWindow ? barWindow.s(root.isCompact ? 11 : 12) : (root.isCompact ? 11 : 12)
                font.weight: Font.DemiBold
                color: root.isCompact ? ThemeBackend.text : ThemeBackend.subtext1
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                width: Math.min(implicitWidth, root.maxTextWidth)

                property string targetText: root.displayText
                onTargetTextChanged: {
                    if (titleTextMain.text === "" || targetText === "") {
                        titleTextMain.text = targetText;
                        return;
                    }
                    if (titleFadeAnim.running) titleFadeAnim.stop();
                    titleFadeAnim.start();
                }

                SequentialAnimation {
                    id: titleFadeAnim
                    NumberAnimation { target: titleTextMain; property: "opacity"; to: 0.0; duration: 80; easing.type: Easing.OutQuad }
                    ScriptAction { script: titleTextMain.text = titleTextMain.targetText; }
                    NumberAnimation { target: titleTextMain; property: "opacity"; to: 1.0; duration: 120; easing.type: Easing.InQuad }
                }
            }
        }
    }
}
