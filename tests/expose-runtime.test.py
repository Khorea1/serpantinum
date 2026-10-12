"""Smoke-test the Exposé QML without a Wayland session or changing the desktop."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile


FACE_DIR = Path(__file__).resolve().parents[1] / "src/quickshell/bar/faces/expose"

SHELL = """import QtQuick
import Quickshell
import "./bar/faces/expose"

ShellRoot {
    Item {
        id: host
        property var mockInfo: info
        property var mockI18n: i18n
        property var mockTheme: theme
        QtObject {
            id: info
            property string desktopEnv: Quickshell.env("EXPOSE_TEST_DESKTOP")
        }
        QtObject {
            id: i18n
            function t(key, fallback) { return fallback }
        }
        QtObject {
            id: theme
            property color text: "#eeeeee"
            property color base: "#171717"
            property color mauve: "#abcdef"
            property color subtext0: "#aaaaaa"
            property color subtext1: "#bbbbbb"
            property color surface0: "#282828"
            property color surface1: "#333333"
            property string fontFamily: "Sans"
        }
        ExposeFace { id: face }

        Timer {
            interval: 200
            running: true
            onTriggered: {
                const enabled = Quickshell.env("EXPOSE_TEST_DESKTOP") === "Hyprland"
                if (face.isFaceVisible !== enabled
                    || face.targetWidth !== (enabled ? 32 : 0)
                    || face.targetHeight !== (enabled ? 32 : 0)) {
                    console.log("EXPOSE_SMOKE_FAIL", face.isFaceVisible, face.targetWidth, face.targetHeight)
                } else {
                    console.log("EXPOSE_SMOKE_PASS", enabled ? "hyprland" : "other")
                }
                Qt.quit()
            }
        }
    }
}
"""


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="serpantinum-expose-runtime-", dir="/tmp") as name:
        root = Path(name)
        (root / "runtime").mkdir(mode=0o700)
        target = root / "quickshell/bar/faces/expose"
        target.mkdir(parents=True)
        for folder in (root / "quickshell", root / "quickshell/bar", root / "quickshell/reusables"):
            folder.mkdir(parents=True, exist_ok=True)
            (folder / "MockImport.qml").write_text("import QtQuick\nItem {}\n")
        component = (FACE_DIR / "ExposeFace.qml").read_text()
        component = component.replace("SystemInfo.", "root.parent.mockInfo.")
        component = component.replace("I18n.", "root.parent.mockI18n.")
        component = component.replace("ThemeBackend.", "root.parent.mockTheme.")
        # Quickshell's offscreen backend has no PanelWindow. The overview is
        # inactive in this smoke test, so substitute its window-only wrapper.
        component = component.replace("PanelWindow {", "Item {")
        component = component.replace('            screen: root.barWindow ? root.barWindow.screen : null\n', "")
        component = component.replace('            focusable: true\n', "")
        component = component.replace('            color: "transparent"\n', "")
        component = component.replace('            WlrLayershell.namespace: "serpantinum-expose-overview"\n', "")
        component = component.replace('            WlrLayershell.layer: WlrLayer.Overlay\n', "")
        component = component.replace('            exclusionMode: ExclusionMode.Ignore\n', "")
        component = component.replace(
            '            anchors {\n                top: true\n                bottom: true\n'
            '                left: true\n                right: true\n            }',
            '            anchors.fill: parent')
        (target / "ExposeFace.qml").write_text(component)
        shutil.copy2(FACE_DIR / "ScreenLayout.js", target / "ScreenLayout.js")
        shell = root / "quickshell/shell.qml"
        shell.write_text(SHELL)

        for desktop in ("niri", "sway", "Hyprland"):
            env = os.environ.copy()
            env.update(QT_QPA_PLATFORM="offscreen", HOME=str(root),
                       XDG_CONFIG_HOME=str(root / "config"),
                       XDG_RUNTIME_DIR=str(root / "runtime"),
                       EXPOSE_TEST_DESKTOP=desktop)
            result = subprocess.run(
                ["qs", "-p", str(shell), "--no-color"],
                env=env, text=True, capture_output=True, timeout=5, check=False)
            output = result.stdout + result.stderr
            expected = "EXPOSE_SMOKE_PASS " + ("hyprland" if desktop == "Hyprland" else "other")
            if expected not in output or "EXPOSE_SMOKE_FAIL" in output:
                raise AssertionError(f"Exposé runtime ({desktop}) failed:\n{output}")

    print("Exposé offscreen QML: Hyprland visible; Niri and Sway hidden")


if __name__ == "__main__":
    main()
