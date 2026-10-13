"""Test the real Quickactions tab model in an isolated offscreen QML runtime.

Usage: python3 -B tests/quickactions-runtime.test.py [checkout] [enabled_tab_count]
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
CHECKOUT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT
EXPECTED_COUNT = int(sys.argv[2]) if len(sys.argv) > 2 else 6

SHELL = """import QtQuick
import Quickshell
import "./quickactions"

ShellRoot {
    Floating {}
    Timer { interval: 1800; running: true; onTriggered: { console.log("QA_FAIL timeout"); Qt.quit() } }
}
"""

PROBE = """
            Component.onCompleted: console.log("QA_INITIAL", tabCount, activeIndex)
            Timer {
                interval: 110
                repeat: true
                running: true
                property int phase: 0
                onTriggered: {
                    if (!Config.dataReady) return
                    if (phase === 0) {
                        console.log("QA_CONFIGURED", tabCount, activeIndex, moduleRepeater.count)
                        for (let i = 0; i < 3; i++) {
                            if (moduleRepeater.itemAt(i).status !== Loader.Ready)
                                console.log("QA_FAIL core_loader", i)
                        }
                        activeIndex = tabCount - 1
                        Config.setSetting("quickactions", {})
                        phase = 1
                    } else if (phase === 1) {
                        console.log("QA_CLAMPED", tabCount, activeIndex, moduleRepeater.count)
                        Config.setSetting("quickactions", {snakeEnabled: true})
                        phase = 2
                    } else if (phase === 2) {
                        console.log("QA_SNAKE", tabCount, tabModules[3].id)
                        Config.setSetting("quickactions", {snakeEnabled: true, dropShelfEnabled: true})
                        phase = 3
                    } else if (phase === 3) {
                        console.log("QA_DROPSHELF", tabCount, tabModules[4].id)
                        Config.setSetting("quickactions", {snakeEnabled: true, dropShelfEnabled: true, musicEnabled: true})
                        phase = 4
                    } else {
                        console.log("QA_RESTORED", tabCount, tabModules[5].id)
                        stop()
                        Qt.quit()
                    }
                }
            }
"""


def offscreen_qml(source: str) -> str:
    header = ('Variants {\n    model: Quickshell.screens\n\n'
              '    delegate: Component {\n        PanelWindow {\n'
              '            id: floatingWidget\n'
              '            required property var modelData\n'
              '            screen: modelData\n')
    assert header in source
    source = source.replace(header, 'Item {\n'
                            '            id: floatingWidget\n'
                            '            width: 1920\n            height: 1080\n'
                            '            property var screen: ({name: "mock"})\n', 1)
    assert source.endswith('        }\n    }\n}\n')
    source = source[:-len('    }\n}\n')]

    for line in (
        'WlrLayershell.namespace: "qs-floating-overlay"',
        'WlrLayershell.layer: WlrLayer.Overlay',
        'exclusionMode: ExclusionMode.Ignore',
        'color: "transparent"',
        'focusable: isSidebarVisible && (!isPinned || (typeof mainHoverTracker !== "undefined" && mainHoverTracker.hovered))',
    ):
        source = source.replace('            ' + line + '\n', '')
    source = source.replace(
        '            anchors {\n                top: true; bottom: true; left: true; right: true\n            }\n', '')

    start = source.index('            mask: Region {')
    brace = source.index('{', start)
    depth = 0
    for index in range(brace, len(source)):
        depth += (source[index] == '{') - (source[index] == '}')
        if depth == 0:
            break
    source = source[:start] + source[index + 1:]
    return source.replace('            property int hoveredBars: 0',
                          '            property int hoveredBars: 0\n' + PROBE, 1)


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="serpantinum-quickactions-") as name:
        root = Path(name)
        runtime = root / "runtime"
        runtime.mkdir(mode=0o700)
        dest = root / "src/quickshell"
        shutil.copytree(CHECKOUT / "src/quickshell", dest)
        floating = dest / "quickactions/Floating.qml"
        floating.write_text(offscreen_qml(floating.read_text()))
        (dest / "shell.qml").write_text(SHELL)
        settings = root / "settings.json"
        settings.write_text(json.dumps({"quickactions": {
            "snakeEnabled": True,
            "dropShelfEnabled": True,
            "musicEnabled": True,
        }}))
        env = os.environ.copy()
        env.pop("WAYLAND_DISPLAY", None)
        env.update(QT_QPA_PLATFORM="offscreen", HOME=name,
                   XDG_CONFIG_HOME=str(root / "config"),
                   XDG_STATE_HOME=str(root / "state"),
                   XDG_RUNTIME_DIR=str(runtime),
                   SERPANTINUM_DIR=str(root / "src"),
                   QS_SETTINGS=str(settings))
        result = subprocess.run(["qs", "-p", str(dest / "shell.qml"), "--no-color"],
                                env=env, capture_output=True, text=True, timeout=8, check=False)
        output = result.stdout + result.stderr
        expected = ("QA_INITIAL 3 0",
                    f"QA_CONFIGURED {EXPECTED_COUNT} 0 {EXPECTED_COUNT}",
                    "QA_CLAMPED 3 2 3",
                    "QA_SNAKE 4 snake",
                    "QA_DROPSHELF 5 dropshelf",
                    "QA_RESTORED 6 music")
        if result.returncode or any(marker not in output for marker in expected) or "QA_FAIL" in output:
            raise AssertionError(f"Quickactions QML failed:\n{output}")
    print(f"Quickactions QML: initial {EXPECTED_COUNT} tabs, removal clamp, and live re-enabling OK")


if __name__ == "__main__":
    main()
