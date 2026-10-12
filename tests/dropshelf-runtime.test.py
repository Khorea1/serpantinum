"""Exercise the actual DropShelf QML in an isolated offscreen Quickshell instance.

Run with: python3 -B tests/dropshelf-runtime.test.py
Requires qs, bash, base64, file, and the Qt/Quickshell plugins.
"""

import base64
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import zlib


ACTION_DIR = Path(__file__).resolve().parents[1] / "src/quickshell/quickactions/actions"


def tiny_png_base64() -> str:
    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", zlib.crc32(tag + payload)))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(b"\x00\xff\x00\x00"))
           + chunk(b"IEND", b""))
    return base64.b64encode(png).decode("ascii")

SHELL = """import QtQuick
import Quickshell
import "./actions"

ShellRoot {
    id: root
    property string phase: Quickshell.env("SHELF_TEST_PHASE")
    property string imageData: Quickshell.env("SHELF_TEST_IMAGE")
    property int step: 0
    property int attempts: 0


    Item {
        width: 360
        height: 420
        property var mockTheme: themeMock
        property var mockI18n: i18nMock
        QtObject {
            id: themeMock
            property color text: "#f0f0f0"
            property color surface0: "#121212"
            property color mauve: "#a89feb"
            property string fontFamily: "Sans"
            property int borderRadius: 8
        }
        QtObject {
            id: i18nMock
            function t(key, data) { return key }
        }
        DropShelf {
            id: shelf
            width: 360
            height: 420
            onEntriesChanged: console.log("SHELF_RUNTIME_ENTRIES", entries.length,
                "pending=" + pendingSave)
            onPendingSaveChanged: console.log("SHELF_RUNTIME_PENDING", pendingSave)
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            root.attempts++
            if (root.attempts > 28) {
                console.log("SHELF_RUNTIME_FAIL timeout step=" + root.step
                    + " entries=" + shelf.entries.length + " status=" + shelf.statusText)
                stop()
                return
            }
            if (!shelf.stateLoaded || !shelf.stateDirectoryReady) return

            if (root.phase === "add") {
                if (root.step === 0) {
                    if (!shelf.addDrop({ urls: ["file:///tmp/A%20File.txt"], formats: [] })
                            || shelf.entries.length !== 1) {
                        console.log("SHELF_RUNTIME_FAIL add_file")
                        stop()
                        return
                    }
                    shelf.removeAt(0)
                    if (shelf.entries.length !== 0) console.log("SHELF_RUNTIME_FAIL remove")
                    shelf.undoRemove()
                    if (shelf.entries.length !== 1) console.log("SHELF_RUNTIME_FAIL undo")
                    shelf.clearShelf()
                    if (shelf.entries.length !== 0) console.log("SHELF_RUNTIME_FAIL clear")
                    shelf.undoRemove()
                    if (shelf.entries.length !== 1) console.log("SHELF_RUNTIME_FAIL undo_clear")
                    shelf.importBase64Image("png", root.imageData)
                    root.step = 1
                    return
                }
                if (root.step === 1 && shelf.entries.length === 2) {
                    shelf.importBase64Image("png", root.imageData)
                    root.step = 2
                    return
                }
                if (root.step === 2 && shelf.entries.length === 3) {
                    console.log("SHELF_RUNTIME_OK add")
                    stop()
                }
            } else if (root.phase === "remove") {
                if (root.step === 1) {
                    if (shelf.entries.length !== 2) {
                        console.log("SHELF_RUNTIME_FAIL reverted_count=" + shelf.entries.length)
                        stop()
                        return
                    }
                    if (root.attempts >= 16) {
                        console.log("SHELF_RUNTIME_OK remove")
                        stop()
                    }
                    return
                }
                if (shelf.entries.length !== 3) {
                    console.log("SHELF_RUNTIME_FAIL reload_count=" + shelf.entries.length)
                    stop()
                    return
                }
                shelf.removeAt(1)
                shelf.undoRemove()
                if (shelf.entries.length !== 3) console.log("SHELF_RUNTIME_FAIL undo_restart")
                shelf.removeAt(1)
                if (shelf.entries.length !== 2) console.log("SHELF_RUNTIME_FAIL removal_count")
                root.step = 1
            } else if (root.phase === "destroy") {
                if (shelf.entries.length !== 2) {
                    console.log("SHELF_RUNTIME_FAIL destroy_initial_count=" + shelf.entries.length)
                    stop()
                    return
                }
                shelf.addDrop({ urls: ["file:///tmp/After%20Restart.txt"], formats: [] })
                shelf.destroy()
                console.log("SHELF_RUNTIME_OK destroy")
                stop()
            } else if (root.phase === "verify") {
                console.log(shelf.entries.length === 3
                    ? "SHELF_RUNTIME_OK verify" : "SHELF_RUNTIME_FAIL final_count=" + shelf.entries.length)
                stop()
            }
        }
    }
}
"""

def run_phase(shell: Path, root: Path, phase: str) -> str:
    env = os.environ.copy()
    env.update(
        QT_QPA_PLATFORM="offscreen",
        HOME=str(root),
        XDG_CONFIG_HOME=str(root / "config"),
        XDG_DATA_HOME=str(root / "data"),
        XDG_STATE_HOME=str(root / "state"),
        XDG_RUNTIME_DIR=str(root / "runtime"),
        SHELF_TEST_PHASE=phase,
        SHELF_TEST_IMAGE=tiny_png_base64(),
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
        output, _ = process.communicate(timeout=4)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            output, _ = process.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            output, _ = process.communicate()
    if f"SHELF_RUNTIME_OK {phase}" not in output or "SHELF_RUNTIME_FAIL" in output:
        raise AssertionError(f"DropShelf runtime phase {phase} failed:\n{output}")
    return output


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="serpantinum-dropshelf-runtime-", dir="/tmp") as name:
        root = Path(name)
        (root / "runtime").mkdir(mode=0o700)
        project = root / "src/quickshell"
        actions = project / "quickactions/actions"
        actions.mkdir(parents=True)
        shutil.copy2(ACTION_DIR / "DropShelfModel.js", actions / "DropShelfModel.js")
        component = (ACTION_DIR / "DropShelf.qml").read_text()
        component = component.replace("ThemeBackend.", "root.parent.mockTheme.")
        component = component.replace("I18n.", "root.parent.mockI18n.")
        (actions / "DropShelf.qml").write_text(component)
        shell = project / "quickactions/shell.qml"
        shell.write_text(SHELL)

        run_phase(shell, root, "add")
        state = root / "state/serpantinum/dropshelf/shelf.json"
        items = json.loads(state.read_text())["items"]
        assert len(items) == 3, f"Expected file and two imported images: {items}"
        images = [root / "data/serpantinum/dropshelf" / Path(item["uri"]).name
                  for item in items if item["uri"].endswith(".png")]
        assert len(images) == 2 and all(path.exists() for path in images), images
        assert images[0] != images[1], "Repeated imports must get unique filenames"

        remove_output = run_phase(shell, root, "remove")
        assert len(json.loads(state.read_text())["items"]) == 2, (
            f"Removal was not persisted: {state.read_text()}\n{remove_output}"
        )
        assert all(path.exists() for path in images), "Removing an item must not delete files"
        run_phase(shell, root, "destroy")
        assert len(json.loads(state.read_text())["items"]) == 3, (
            "Destroying the tab immediately after a change lost the final save"
        )
        run_phase(shell, root, "verify")
        assert (state.parent.stat().st_mode & 0o777) == 0o700

    print("DropShelf QML runtime: add, images x2, undo, remove, tab destruction, restart passed")


if __name__ == "__main__":
    main()
