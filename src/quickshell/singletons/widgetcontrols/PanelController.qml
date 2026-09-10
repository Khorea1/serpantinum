pragma Singleton
import QtQuick

// Lightweight bridge so windows other than Main.qml (e.g. the notification
// toast popup, which is its own PanelWindow) can request opening/toggling
// one of the master panel's widgets (the same thing `serpantinum msg toggle
// <widget>` does), without needing a direct reference to Main.qml.
//
// Main.qml listens for requestNonce changes and forwards the request into
// its own existing IPC handleCommand("toggle", widget, arg) logic, so
// behavior stays identical to the CLI/IPC path.
QtObject {
    id: controller

    property string requestWidget: ""
    property string requestArg: ""
    property int requestNonce: 0

    function toggle(widget, arg) {
        controller.requestWidget = widget || "";
        controller.requestArg = arg || "";
        controller.requestNonce = controller.requestNonce + 1;
    }
}
