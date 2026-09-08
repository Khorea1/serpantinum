#!/usr/bin/env bash

source "$SCRIPT_DIR/../caching.sh"

quickshell -p "$MAIN_QML" ipc call theme reloadColors >/dev/null 2>&1 &

kitty @ set-colors --configured 2>/dev/null || killall -USR1 .kitty-wrapped 2>/dev/null || true

wait
