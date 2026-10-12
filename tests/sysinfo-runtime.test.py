"""Verify SysInfo faces and SysData subscriber lifecycle in isolated offscreen Quickshell."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile


FACE_DIR = Path(__file__).resolve().parents[1] / "src/quickshell/bar/faces/sysinfo"

SHELL = """import QtQuick
import Quickshell
import "./bar/faces/sysinfo"

ShellRoot {
    Item {
        id: host
        width: 360
        height: 160
        property var mockSysData: sys
        property var mockTheme: theme
        property var mockConfig: config
        property int phase: 0
        property var launches: []
        function recordCommand(args) { launches = launches.concat([args.join("/")]) }
        QtObject {
            id: sys
            property int subscribers: 0
            property int cpu: 34
            property real ramGb: 5.75
            property int temp: 55
            function subscribe() { subscribers++ }
            function unsubscribe() { subscribers-- }
        }
        QtObject {
            id: config
            property var rawSettings: ({bar: {sysinfoCommand: ["foot", "-e", "btop"]}})
        }
        QtObject {
            id: theme
            property color text: "#ffffff"
            property color mauve: "#b49fff"
            property color teal: "#a0cccc"
            property color peach: "#ffd3a0"
            property color blue: "#9cabcf"
            property color subtext0: "#a0a0a0"
            property color base: "#181818"
            property string fontFamily: "Sans"
            property int borderRadius: 10
        }
        QtObject {
            id: module
            property bool moduleActive: true
            property bool isCompact: false
            property var barWindow: null
        }
        SysInfoFace { id: face; width: 300; height: 40; module: module }
        SideSysInfoFace { id: side; width: 40; y: 70; module: module }
        Timer {
            interval: 70
            repeat: true
            running: true
            onTriggered: {
                let good = true
                if (host.phase === 0) {
                    good = sys.subscribers === 1 && face.cpuText === "34%"
                        && face.ramText === "5.8G" && face.tempText === "55°"
                        && face.targetWidth > 0 && side.targetHeight > 0
                        && face.configuredCommand().join("/") === "foot/-e/btop"
                    face.launchMonitor()
                    side.launchMonitor()
                    good = good && host.launches.length === 2
                        && host.launches[0] === "foot/-e/btop"
                        && host.launches[1] === "foot/-e/btop"
                    config.rawSettings = {bar: {sysinfoCommand: "foot -e btop"}}
                    face.launchMonitor()
                    side.launchMonitor()
                    good = good && host.launches.length === 2
                    module.moduleActive = false
                } else if (host.phase === 1) {
                    good = sys.subscribers === 0 && face.targetWidth === 0 && side.targetHeight === 0
                    module.moduleActive = true
                } else if (host.phase === 2) {
                    good = sys.subscribers === 1
                    face.visible = false
                } else if (host.phase === 3) {
                    good = sys.subscribers === 0
                    face.visible = true
                } else if (host.phase === 4) {
                    good = sys.subscribers === 1
                    face.destroy()
                } else if (host.phase === 5) {
                    good = sys.subscribers === 0
                    console.log(good ? "SYSINFO_RUNTIME_PASS" : "SYSINFO_RUNTIME_FAIL cleanup", sys.subscribers)
                    Qt.quit()
                    return
                }
                if (!good) {
                    console.log("SYSINFO_RUNTIME_FAIL phase=" + host.phase + " subscribers=" + sys.subscribers)
                    Qt.quit()
                    return
                }
                host.phase++
            }
        }
    }
}
"""


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="serpantinum-sysinfo-runtime-", dir="/tmp") as tmp:
        root = Path(tmp)
        (root / "runtime").mkdir(mode=0o700)
        target = root / "quickshell/bar/faces/sysinfo"
        target.mkdir(parents=True)
        for folder in (root / "quickshell", root / "quickshell/bar", root / "quickshell/reusables"):
            folder.mkdir(parents=True, exist_ok=True)
            (folder / "MockImport.qml").write_text("import QtQuick\nItem {}\n")
        for name in ("SysInfoFace.qml", "SideSysInfoFace.qml"):
            component = (FACE_DIR / name).read_text()
            component = component.replace("SysData.", "root.parent.mockSysData.")
            component = component.replace("ThemeBackend.", "root.parent.mockTheme.")
            component = component.replace("Config.rawSettings", "root.parent.mockConfig.rawSettings")
            component = component.replace("typeof Config", "typeof root.parent.mockConfig")
            component = component.replace("Quickshell.execDetached(", "root.parent.recordCommand(")
            (target / name).write_text(component)
        shutil.copy2(FACE_DIR / "SysInfoCommand.js", target / "SysInfoCommand.js")
        (root / "quickshell/reusables/ClickButton.qml").write_text('''import QtQuick
Item {
    property real cornerRadius: 0
    property real horizontalPadding: 0
    property string buttonIcon: ""
    property real iconFontSize: 0
    property color accentColor: "#ffffff"
    property color textColor: "#000000"
    signal clicked()
}
''')
        shell = root / "quickshell/shell.qml"
        shell.write_text(SHELL)
        env = os.environ.copy()
        env.update(QT_QPA_PLATFORM="offscreen", HOME=str(root),
                   XDG_CONFIG_HOME=str(root / "config"),
                   XDG_RUNTIME_DIR=str(root / "runtime"))
        run = subprocess.run(["qs", "-p", str(shell), "--no-color"], env=env,
                             text=True, capture_output=True, timeout=8, check=False)
        output = run.stdout + run.stderr
        if "SYSINFO_RUNTIME_PASS" not in output or "SYSINFO_RUNTIME_FAIL" in output:
            raise AssertionError(f"SysInfo offscreen runtime failed:\n{output}")
    print("SysInfo offscreen QML: measurements, argv, visibility, subscription cleanup PASS")


if __name__ == "__main__":
    main()
