import QtQuick
import QtQuick.Layouts
import "../../../../reusables"
import "../../../../"

Item {
    id: pillsFaceRoot
    property var widget: null

    implicitWidth: wsLayout.implicitWidth
    implicitHeight: wsLayout.implicitHeight

    Rectangle {
        id: activeHighlight
        z: 3
        radius: 0
        color: (widget && widget.isCompact) ? Qt.lighter(ThemeBackend.mauve, 1.05) : ThemeBackend.mauve

        property int curIdx: widget ? widget.activeIndex : -1
        property int prevIdx: curIdx

        readonly property real leadSpring: 5.5
        readonly property real leadDamping: 0.7
        readonly property real trailSpring: 2.0
        readonly property real trailDamping: 0.5
        readonly property real springMass: 1.0

        onCurIdxChanged: {
            if (curIdx > prevIdx) {
                leftAnim.spring = trailSpring;
                leftAnim.damping = trailDamping;
                rightAnim.spring = leadSpring;
                rightAnim.damping = leadDamping;
            } else if (curIdx < prevIdx) {
                leftAnim.spring = leadSpring;
                leftAnim.damping = leadDamping;
                rightAnim.spring = trailSpring;
                rightAnim.damping = trailDamping;
            }
            prevIdx = curIdx;
        }

        function getX(index, activeIndex) {
            if (index < 0 || !widget) return 0;
            let xPos = 0;
            let spacing = widget.s(widget.isCompact ? 7 : 8);
            let activeW = widget.s(widget.isCompact ? 34 : 28);
            let inactiveW = widget.s(widget.isCompact ? 16 : 18);
            for (let i = 0; i < index; i++) {
                xPos += (i === activeIndex ? activeW : inactiveW) + spacing;
            }
            return xPos;
        }

        property real targetLeft: (curIdx >= 0 && widget) ? getX(curIdx, curIdx) : 0
        property real targetRight: (curIdx >= 0 && widget) ? targetLeft + widget.s(widget.isCompact ? 34 : 28) : 0
        property real actualLeft: targetLeft
        property real actualRight: targetRight

        Behavior on actualLeft {
            SpringAnimation { id: leftAnim; spring: activeHighlight.leadSpring; damping: activeHighlight.leadDamping; mass: activeHighlight.springMass; epsilon: 0.05 }
        }
        Behavior on actualRight {
            SpringAnimation { id: rightAnim; spring: activeHighlight.leadSpring; damping: activeHighlight.leadDamping; mass: activeHighlight.springMass; epsilon: 0.05 }
        }

        x: wsLayout.x + actualLeft
        y: wsLayout.y + (wsLayout.height - height) / 2
        width: actualRight - actualLeft
        height: widget ? widget.s(widget.isCompact ? 16 : 18) : 18
        opacity: (widget && widget.workspaceCount > 0 && widget.activeIndex >= 0) ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 180 } }
    }

    Row {
        id: wsLayout
        z: 2
        anchors.centerIn: parent
        spacing: widget ? widget.s(widget.isCompact ? 7 : 8) : 8

        Repeater {
            model: widget ? widget.workspaceCount : 0

            delegate: Item {
                id: wsPill
                required property int index

                property bool isOccupied: widget ? widget.isOccupied(index) : false
                property bool isActive: widget ? (index === widget.activeIndex) : false
                property bool initAnimTrigger: false

                width: isActive ? (widget ? widget.s(widget.isCompact ? 34 : 28) : 28) : (widget ? widget.s(widget.isCompact ? 16 : 18) : 18)
                height: widget ? widget.s(widget.isCompact ? 16 : 18) : 18
                anchors.verticalCenter: parent.verticalCenter

                Behavior on width { SpringAnimation { spring: 4.4; damping: 0.6; mass: 0.9; epsilon: 0.05 } }

                Rectangle {
                    id: wsVisualShape
                    anchors.fill: parent
                    radius: 0
                    color: wsPill.isActive ? "transparent" : (wsPill.isOccupied ? ThemeBackend.surface2 : ((widget && widget.isCompact) ? ThemeBackend.surface1 : ThemeBackend.surface0))
                    border.width: 0

                    Behavior on color { ColorAnimation { duration: 250 } }

                    scale: wsPillMouse.pressed ? 0.88 : (wsPillMouse.containsMouse ? 1.08 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
                }

                opacity: initAnimTrigger ? 1.0 : 0.0
                transform: Translate {
                    y: wsPill.initAnimTrigger ? 0 : (widget ? widget.s(15) : 15)
                    Behavior on y { NumberAnimation { duration: 650; easing.type: Easing.OutQuint } }
                }

                Component.onCompleted: {
                    if (widget && widget.barWindow && !widget.barWindow.startupCascadeFinished) {
                        animTimer.interval = index * 50 + 100;
                        if (widget.moduleActive) animTimer.start();
                    } else {
                        initAnimTrigger = true;
                    }
                }

                Timer {
                    id: animTimer
                    running: false
                    repeat: false
                    onTriggered: wsPill.initAnimTrigger = true
                }

                Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

                MouseArea {
                    id: wsPillMouse
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    anchors.fill: parent
                    onClicked: {
                        if (widget) widget.focusWorkspace(wsPill.index);
                    }
                }
            }
        }
    }
}
