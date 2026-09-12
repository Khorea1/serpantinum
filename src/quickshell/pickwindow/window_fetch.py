#!/usr/bin/env python3
import json
import os
import shutil
import subprocess


def _pgrep(name):
    try:
        result = subprocess.run(
            ["pgrep", "-x", name],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return result.returncode == 0
    except Exception:
        return False


def detect_compositor():
    if os.environ.get("NIRI_SOCKET"):
        return "niri"
    if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        return "hyprland"
    if shutil.which("niri") and _pgrep("niri"):
        return "niri"
    if shutil.which("hyprctl") and _pgrep("Hyprland"):
        return "hyprland"
    return "unknown"


def _run_json(cmd):
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=2)
        if out.returncode != 0 or not out.stdout.strip():
            return None
        return json.loads(out.stdout)
    except Exception:
        return None


def _is_shell_own_window(cls, title):
    cls_lower = (cls or "").lower()
    title_lower = (title or "").lower()
    return (
        "quickshell" in cls_lower
        or "qs-master" in cls_lower
        or "qs-master" in title_lower
        or cls_lower.startswith("qs-")
    )


def get_windows_hyprland():
    clients = _run_json(["hyprctl", "clients", "-j"]) or []
    active = _run_json(["hyprctl", "activewindow", "-j"]) or {}
    active_addr = active.get("address", "") if isinstance(active, dict) else ""

    windows = []
    for c in clients:
        if not isinstance(c, dict):
            continue
        if c.get("mapped") is False:
            continue

        cls = c.get("initialClass") or c.get("class") or ""
        title = c.get("initialTitle") or c.get("title") or cls
        if not cls and not title:
            continue
        if _is_shell_own_window(cls, title):
            continue

        addr = c.get("address", "")
        workspace = c.get("workspace") or {}
        workspace_label = workspace.get("name") or str(workspace.get("id", ""))

        windows.append(
            {
                "id": addr,
                "class": cls,
                "title": title,
                "workspace": workspace_label,
                "focused": bool(addr) and addr == active_addr,
                "_rank": c.get("focusHistoryID", 9999),
            }
        )

    windows.sort(key=lambda w: w["_rank"])
    for w in windows:
        w.pop("_rank", None)
    return windows


def get_windows_niri():
    wins = _run_json(["niri", "msg", "-j", "windows"]) or []

    windows = []
    for w in wins:
        if not isinstance(w, dict):
            continue

        app_id = w.get("app_id") or ""
        title = w.get("title") or app_id
        if not app_id and not title:
            continue
        if _is_shell_own_window(app_id, title):
            continue

        is_focused = bool(w.get("is_focused"))
        windows.append(
            {
                "id": str(w.get("id", "")),
                "class": app_id,
                "title": title,
                "workspace": str(w.get("workspace_id", "")),
                "focused": is_focused,
                "_rank": 0 if is_focused else 1,
            }
        )

    windows.sort(key=lambda w: w["_rank"])
    for w in windows:
        w.pop("_rank", None)
    return windows


def get_windows():
    compositor = detect_compositor()
    if compositor == "niri":
        return {"compositor": "niri", "windows": get_windows_niri()}
    if compositor == "hyprland":
        return {"compositor": "hyprland", "windows": get_windows_hyprland()}
    return {"compositor": "unknown", "windows": []}


if __name__ == "__main__":
    print(json.dumps(get_windows()))
