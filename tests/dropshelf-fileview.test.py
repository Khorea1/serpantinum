"""Exercise Quickshell FileView persistence without launching the desktop shell.

Run with: python3 tests/dropshelf-fileview.test.py
Requires the `qs` executable and its Qt/Quickshell plugins.
"""

import json
import os
from pathlib import Path
import subprocess
import tempfile


SHELL = """import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    property string folder: Quickshell.env("XDG_STATE_HOME") + "/serpantinum/dropshelf"
    property string expected: Quickshell.env("SHELF_TEST_EXPECTED")
    property string replacement: Quickshell.env("SHELF_TEST_REPLACEMENT")
    property string nextReplacement: Quickshell.env("SHELF_TEST_NEXT_REPLACEMENT")

    function writeReplacement() {
        if (root.replacement) {
            stateFile.setText(root.replacement)
            if (root.nextReplacement) {
                followupWrite.start()
                return
            }
        }
        console.log("SHELF_TEST_OK")
    }

    Timer {
        id: followupWrite
        interval: 100
        repeat: false
        onTriggered: {
            stateFile.setText(root.nextReplacement)
            console.log("SHELF_TEST_OK")
        }
    }

    Process {
        id: directoryCreator
        command: ["mkdir", "-p", "-m", "0700", root.folder]
        onExited: function(exitCode) {
            if (exitCode !== 0) {
                console.log("SHELF_TEST_DIRECTORY_FAILED")
                return
            }
            stateFile.reload()
            stateFile.text() // FileView preload:false needs its first read triggered.
        }
    }

    FileView {
        id: stateFile
        path: root.folder + "/shelf.json"
        preload: false
        atomicWrites: true
        watchChanges: true
        printErrors: false

        onLoaded: {
            if (text() !== root.expected) {
                console.log("SHELF_TEST_UNEXPECTED_CONTENT")
                return
            }
            root.writeReplacement()
        }
        onLoadFailed: function(error) {
            if (error !== FileViewError.FileNotFound || root.expected !== "MISSING") {
                console.log("SHELF_TEST_UNEXPECTED_READ_ERROR", error)
                return
            }
            root.writeReplacement()
        }
        onSaveFailed: function(error) { console.log("SHELF_TEST_SAVE_FAILED", error) }
    }

    Component.onCompleted: directoryCreator.running = true
}
"""


def run_quickshell(
    shell: Path, root: Path, expected: str, replacement: str, next_replacement: str = ""
) -> None:
    env = os.environ.copy()
    env.update(
        QT_QPA_PLATFORM="offscreen",
        XDG_CONFIG_HOME=str(root / "config"),
        XDG_STATE_HOME=str(root / "state"),
        XDG_DATA_HOME=str(root / "data"),
        SHELF_TEST_EXPECTED=expected,
        SHELF_TEST_REPLACEMENT=replacement,
        SHELF_TEST_NEXT_REPLACEMENT=next_replacement,
    )
    process = subprocess.Popen(
        ["qs", "-p", str(shell), "--no-color"],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    try:
        output, _ = process.communicate(timeout=3)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            output, _ = process.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            output, _ = process.communicate()

    if "SHELF_TEST_OK" not in output or "SHELF_TEST_" in output.replace("SHELF_TEST_OK", ""):
        raise AssertionError(f"Isolated Quickshell FileView check failed:\n{output}")


def main() -> None:
    initial = json.dumps({"version": 1, "items": [{"uri": "file:///tmp/a"}]})
    updated = json.dumps({"version": 1, "items": [{"uri": "file:///tmp/b"}]})
    final = json.dumps({"version": 1, "items": [{"uri": "file:///tmp/c"}]})
    with tempfile.TemporaryDirectory(prefix="serpantinum-fileview-", dir="/tmp") as temporary:
        root = Path(temporary)
        shell = root / "shell.qml"
        shell.write_text(SHELL)
        state = root / "state/serpantinum/dropshelf/shelf.json"

        run_quickshell(shell, root, "MISSING", initial)
        assert state.read_text() == initial, "Initial write did not persist"
        run_quickshell(shell, root, initial, updated, final)
        assert state.read_text() == final, "Consecutive writes did not persist the latest state"
        run_quickshell(shell, root, final, "")
        assert (state.parent.stat().st_mode & 0o777) == 0o700, "State directory must be private"

    print("Drop Shelf FileView persistence: initial write, consecutive updates and restart passed")


if __name__ == "__main__":
    main()
