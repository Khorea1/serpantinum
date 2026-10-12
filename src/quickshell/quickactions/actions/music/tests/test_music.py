"""Check private mpv ownership and local library scanning without touching desktop playback."""
import json
import os
import select
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "bridge.py"
SCAN = ROOT / "scan.py"

FAKE_MPV = '''#!/usr/bin/env python3
import os
import signal
import socket
import sys
path = next(arg.split("=", 1)[1] for arg in sys.argv[1:] if arg.startswith("--input-ipc-server="))
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(path)
s.listen(1)
with open(os.path.join(os.environ["MPV_TEST_STATE_DIR"], str(os.getpid())), "w") as handle:
    handle.write(path)
conn, _ = s.accept()
with conn:
    while data := conn.recv(65536):
        conn.sendall(b'{"event":"property-change","name":"pause","data":false}\\n')
'''


def event(child, deadline=6):
    ready, _, _ = select.select([child.stdout], [], [], deadline)
    if not ready:
        raise AssertionError("bridge timed out")
    line = child.stdout.readline()
    if not line:
        raise AssertionError(f"bridge exited early: {child.poll()}")
    return json.loads(line)


class MusicTests(unittest.TestCase):
    def test_scan_empty_and_special_filenames(self):
        with tempfile.TemporaryDirectory() as temp:
            self.assertEqual(json.loads(subprocess.check_output([sys.executable, SCAN, temp])), [])
            folder = Path(temp) / "Jazz"
            folder.mkdir()
            for name in ("b song.FLAC", "a\ntrack.mp3", "skip.txt"):
                (folder / name).touch()
            listed = json.loads(subprocess.check_output([sys.executable, SCAN, temp]))
            self.assertEqual({Path(p).name for p in listed}, {"b song.FLAC", "a\ntrack.mp3"})
            self.assertEqual(json.loads(subprocess.check_output([sys.executable, SCAN, str(Path(temp) / 'missing')])), [])

    def test_missing_mpv_has_explicit_error(self):
        with tempfile.TemporaryDirectory() as temp:
            env = dict(os.environ, PATH=temp, XDG_RUNTIME_DIR=temp)
            proc = subprocess.run([sys.executable, BRIDGE], input=b"", stdout=subprocess.PIPE,
                                  env=env, timeout=6)
            self.assertEqual(proc.returncode, 127)
            self.assertEqual(json.loads(proc.stdout), {"bridge": "error", "code": "missing_mpv"})
            self.assertEqual(list(Path(temp).iterdir()), [])

    def test_two_players_are_isolated_and_cleaned(self):
        with tempfile.TemporaryDirectory() as temp:
            binary = Path(temp) / "mpv"
            binary.write_text(FAKE_MPV)
            binary.chmod(0o755)
            runtime = Path(temp) / "runtime"
            runtime.mkdir()
            state = Path(temp) / "state"
            state.mkdir()
            env = dict(os.environ, PATH=temp + os.pathsep + os.environ["PATH"],
                       XDG_RUNTIME_DIR=str(runtime), MPV_TEST_STATE_DIR=str(state))
            players = [subprocess.Popen([sys.executable, BRIDGE], stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, env=env) for _ in range(2)]
            try:
                self.assertEqual([event(p) for p in players], [{"bridge": "connected"}] * 2)
                recorded = [p.read_text() for p in state.iterdir()]
                self.assertEqual(len(recorded), 2)
                self.assertEqual(len(set(recorded)), 2)
                self.assertEqual(len(list(runtime.iterdir())), 2)
                first = players[0]
                first.terminate()
                first.wait(timeout=5)
                self.assertEqual(first.returncode, 0)
                self.assertEqual(len(list(runtime.iterdir())), 1)
                players[1].stdin.write(b'{"command":["get_property","pause"]}\n')
                players[1].stdin.flush()
                self.assertEqual(event(players[1])["name"], "pause")
                players[1].stdin.close()
                players[1].wait(timeout=5)
                self.assertEqual(list(runtime.iterdir()), [])
                for file in state.iterdir():
                    with self.assertRaises(ProcessLookupError):
                        os.kill(int(file.name), 0)
            finally:
                for child in players:
                    if child.poll() is None:
                        child.kill()
                    child.wait(timeout=5)
                    if child.stdin and not child.stdin.closed:
                        child.stdin.close()
                    if child.stdout:
                        child.stdout.close()


if __name__ == "__main__":
    unittest.main()


class MusicQmlTests(unittest.TestCase):
    def test_offscreen_music_component_and_bridge(self):
        import shutil

        qs = shutil.which("qs")
        if not qs:
            self.skipTest("Quickshell is not installed")
        with tempfile.TemporaryDirectory(prefix="serpantinum-music-qml-") as temp:
            root = Path(temp)
            app = root / "src/quickshell"
            actions = app / "quickactions/actions"
            music = actions / "music"
            music.mkdir(parents=True)
            runtime = root / "runtime"
            runtime.mkdir(mode=0o700)
            library = root / "Music"
            library.mkdir()
            (library / "01-song.mp3").touch()
            bin_dir = root / "bin"
            bin_dir.mkdir()
            fake = bin_dir / "mpv"
            fake.write_text(FAKE_MPV)
            fake.chmod(0o755)
            state = root / "state"
            state.mkdir()
            for name in ("MusicEngine.qml", "IconBtn.qml", "qmldir", "bridge.py", "scan.py"):
                shutil.copy2(ROOT / name, music / name)
            source = ROOT.parent / "Music.qml"
            rendered = source.read_text().replace("    id: root\n", "    id: root\n    property alias testEngine: musicEngine\n", 1)
            (actions / "Music.qml").write_text(rendered)
            (app / "qmldir").write_text("singleton ThemeBackend 1.0 ThemeBackend.qml\nsingleton I18n 1.0 I18n.qml\n")
            (app / "ThemeBackend.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property color text: "white"
    property color base: "black"
    property color mauve: "#a898ff"
    property color surface0: "#202020"
    property color surface1: "#303030"
    property color surface2: "#404040"
    property color subtext0: "#aaaaaa"
    property color peach: "#ffc900"
    property string fontFamily: "Sans"
}
''')
            (app / "I18n.qml").write_text('''pragma Singleton
import QtQuick
QtObject { function t(key, args) { return key } }
''')
            shell = app / "quickactions/shell.qml"
            shell.write_text('''import QtQuick
import Quickshell
import "./actions"
ShellRoot {
    Item {
        width: 550; height: 550
        Music { id: music; anchors.fill: parent }
        Timer {
            interval: 100; repeat: true; running: true
            property int attempts: 0
            property bool requested: false
            onTriggered: {
                attempts++
                if (attempts > 35) { console.log("MUSIC_RUNTIME_FAIL timeout"); Qt.quit(); return }
                if (!music.testEngine.scanned) return
                if (music.testEngine.libraryCount !== 1) {
                    console.log("MUSIC_RUNTIME_FAIL library_count", music.testEngine.libraryCount)
                    Qt.quit(); return
                }
                if (!requested) { requested = true; music.testEngine.togglePlay(); return }
                if (music.testEngine.linked) { console.log("MUSIC_RUNTIME_OK linked"); Qt.quit() }
            }
        }
    }
}
''')
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", HOME=temp,
                       XDG_RUNTIME_DIR=str(runtime), SERPANTINUM_MUSIC_DIR=str(library),
                       MPV_TEST_STATE_DIR=str(state), PATH=str(bin_dir) + os.pathsep + os.environ["PATH"])
            result = subprocess.run([qs, "-p", str(shell), "--no-color"], env=env,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, timeout=8)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertIn("MUSIC_RUNTIME_OK linked", result.stdout, result.stdout)
            self.assertNotIn("MUSIC_RUNTIME_FAIL", result.stdout)
            for pid_file in state.iterdir():
                with self.assertRaises(ProcessLookupError):
                    os.kill(int(pid_file.name), 0)
