import QtQuick
import QtQuick.Controls
import "../../"

Item {
    id: root

    required property string currentWidget

    readonly property var widgetOrder: ["launcher", "emoji", "clipboard", "pickwindow"]
    property string pendingWidget: ""
    property var pendingScreen: null
    implicitWidth: modeRow.implicitWidth
    implicitHeight: 32

    function controllerFor(name) {
        switch (name) {
        case "launcher": return LauncherController;
        case "emoji": return EmojiController;
        case "clipboard": return ClipboardController;
        case "pickwindow": return PickWindowController;
        default: return null;
        }
    }

    function select(name) {
        if (!root.enabled || name === currentWidget || widgetOrder.indexOf(name) < 0) return;

        pendingScreen = controllerFor(currentWidget).screen;
        pendingWidget = name;
        for (const widget of widgetOrder) controllerFor(widget).hide();
        switchDelay.restart();
    }

    function cycle(direction) {
        const index = widgetOrder.indexOf(currentWidget);
        if (index >= 0) select(widgetOrder[(index + direction + widgetOrder.length) % widgetOrder.length]);
    }

    function handleKey(event) {
        if (!(event.modifiers & Qt.ControlModifier) ||
            (event.modifiers & (Qt.AltModifier | Qt.ShiftModifier | Qt.MetaModifier))) return false;
        if (event.key !== Qt.Key_H && event.key !== Qt.Key_L) return false;
        cycle(event.key === Qt.Key_L ? 1 : -1);
        event.accepted = true;
        return true;
    }

    Timer {
        id: switchDelay
        interval: 90
        onTriggered: {
            // An independently opened selector takes precedence over a pending cycle.
            const next = root.pendingWidget;
            root.pendingWidget = "";
            if (next && !root.widgetOrder.some(name => root.controllerFor(name).isVisible)) {
                root.controllerFor(next).show(root.pendingScreen);
            }
        }
    }

    Row {
        id: modeRow
        anchors.centerIn: parent
        spacing: 4

        Repeater {
            model: [
                { name: "launcher", glyph: "󱓞", label: "Launcher" },
                { name: "emoji", glyph: "󰞅", label: "Emoji" },
                { name: "clipboard", glyph: "󰅌", label: "Clipboard" },
                { name: "pickwindow", glyph: "", label: "Window picker" }
            ]

            delegate: Rectangle {
                required property var modelData
                readonly property bool selected: modelData.name === root.currentWidget
                width: 29
                height: 29
                radius: 9
                color: selected ? ThemeBackend.mauve : (modeMouse.containsMouse ? ThemeBackend.surface1 : ThemeBackend.surface0)
                border.width: selected ? 0 : 1
                border.color: Qt.alpha(ThemeBackend.surface2, 0.55)

                Behavior on color { ColorAnimation { duration: 130 } }

                Text {
                    anchors.centerIn: parent
                    text: modelData.glyph
                    font.family: ThemeBackend.iconFont
                    font.pixelSize: 17
                    color: selected ? ThemeBackend.crust : ThemeBackend.subtext0
                }

                MouseArea {
                    id: modeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.select(modelData.name)
                    ToolTip.visible: containsMouse && root.enabled
                    ToolTip.delay: 500
                    ToolTip.text: I18n.isReady ? I18n.t("selector." + modelData.name) : modelData.label
                }
            }
        }
    }

    Shortcut {
        sequence: "Ctrl+L"
        context: Qt.WindowShortcut
        enabled: root.enabled
        autoRepeat: false
        onActivated: root.cycle(1)
    }

    Shortcut {
        sequence: "Ctrl+H"
        context: Qt.WindowShortcut
        enabled: root.enabled
        autoRepeat: false
        onActivated: root.cycle(-1)
    }
}
