#!/usr/bin/env python3
"""Own one mpv child, private IPC socket and its exact lifecycle."""
import json
import os
import select
import signal
import socket
import subprocess
import sys
import tempfile
import time


def emit(value):
    sys.stdout.write(json.dumps(value) + "\n")
    sys.stdout.flush()


def stop_child(child):
    if child.poll() is not None:
        return
    os.killpg(child.pid, signal.SIGTERM)
    try:
        child.wait(timeout=2)
    except subprocess.TimeoutExpired:
        os.killpg(child.pid, signal.SIGKILL)
        child.wait()


def run():
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime or not os.path.isdir(runtime):
        runtime = tempfile.gettempdir()

    with tempfile.TemporaryDirectory(prefix="serpantinum-music-", dir=runtime) as folder:
        path = os.path.join(folder, "mpv.sock")
        try:
            child = subprocess.Popen(
                ["mpv", "--no-config", "--load-scripts=no", "--idle=yes", "--no-video",
                 "--audio-display=no", "--force-window=no", "--no-terminal",
                 "--keep-open=no", "--audio-client-name=serpantinum-music",
                 f"--input-ipc-server={path}"],
                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL, start_new_session=True,
            )
        except FileNotFoundError:
            emit({"bridge": "error", "code": "missing_mpv"})
            return 127
        except OSError:
            emit({"bridge": "error", "code": "start_failed"})
            return 1

        try:
            deadline = time.monotonic() + 5
            connected = None
            while time.monotonic() < deadline and child.poll() is None:
                client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                try:
                    client.connect(path)
                    connected = client
                    break
                except OSError:
                    client.close()
                    time.sleep(0.05)
            if connected is None:
                emit({"bridge": "error", "code": "start_failed"})
                return 1

            with connected:
                emit({"bridge": "connected"})
                while child.poll() is None:
                    readable, _, _ = select.select([0, connected], [], [], 0.2)
                    if 0 in readable:
                        data = os.read(0, 65536)
                        if not data:
                            break
                        connected.sendall(data)
                    if connected in readable:
                        data = connected.recv(65536)
                        if not data:
                            break
                        sys.stdout.buffer.write(data)
                        sys.stdout.buffer.flush()
            return 0
        finally:
            stop_child(child)


if __name__ == "__main__":
    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, lambda *_: sys.exit(0))
    try:
        sys.exit(run())
    except (BrokenPipeError, ConnectionError, OSError):
        sys.exit(1)
