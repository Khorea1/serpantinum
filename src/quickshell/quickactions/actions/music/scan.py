#!/usr/bin/env python3
"""Return local audio files as JSON, preserving whitespace in filenames."""
import json
import os
import sys
from pathlib import Path

EXTENSIONS = {".mp3", ".flac", ".ogg", ".opus", ".m4a", ".aac", ".wav", ".wma"}


def scan(folder: str) -> list[str]:
    if not os.path.isdir(folder):
        return []
    paths = []
    for directory, _, files in os.walk(folder):
        for name in files:
            path = Path(directory, name)
            if path.suffix.lower() in EXTENSIONS and path.is_file():
                paths.append(str(path.resolve()))
    return sorted(paths, key=str.casefold)


if __name__ == "__main__":
    print(json.dumps(scan(sys.argv[1]), ensure_ascii=True))
