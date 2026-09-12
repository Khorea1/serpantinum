import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../../"
import "../../reusables"
import "../"

Notification {
    id: faceRoot

    fullSummary: model ? (model.summary || I18n.t("notifications.types.default.fallback_summary")) : ""
    fullBody: model ? (model.body || "") : ""

    iconArea: [
        Item {
            anchors.fill: parent

            Image {
                id: notifIcon
                anchors.fill: parent
                asynchronous: true
                source: {
                    let ic = model ? (model.icon || model.iconPath || "") : "";
                    if (!ic) return "";
                    if (ic.startsWith("file://") || ic.startsWith("image://") || ic.startsWith("http://") || ic.startsWith("https://")) return ic;
                    return ic.startsWith("/") ? "file://" + ic : "image://icon/" + ic;
                }
                sourceSize: Qt.size(32, 32)
                fillMode: Image.PreserveAspectFit
                visible: opacity > 0.001
                opacity: status === Image.Ready && source !== "" ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            }

            Text {
		anchors.centerIn: parent
		anchors.horizontalCenterOffset: 1
		anchors.verticalCenterOffset: -1
                visible: !notifIcon.visible
                text: "󰋽"
                font.family: ThemeBackend.fontFamily
                font.pixelSize: s(16)
                color: ThemeBackend.subtext0
            }
        }
    ]

    headerArea: [
        Text {
            Layout.fillWidth: true
            text: model ? (model.displayName || model.appName || "System") : "System"
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Bold
            font.pixelSize: s(11)
            color: faceRoot.titleAccentColor
            Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
            elide: Text.ElideRight
        }
    ]
}
