#!/usr/bin/env python3
"""iTunes/QuickTime-Tags in MP4 schreiben (Ersatz für AtomicParsley).

Leere Felder werden nicht gesetzt. Staffel/Folge nur, wenn sie Zahlen sind.
Kein Remux – mutagen ändert die Atome in der Datei.
"""
from __future__ import annotations

import argparse
import sys


def _uint(raw: str) -> int | None:
    s = (raw or "").strip()
    if not s:
        return None
    try:
        return int(s, 10)
    except ValueError:
        return None


def main() -> int:
    try:
        from mutagen.mp4 import MP4
    except ImportError:
        sys.stderr.write("mutagen fehlt (venv: pip install mutagen)\n")
        return 1

    p = argparse.ArgumentParser(description="MP4-iTunes-Tags schreiben")
    p.add_argument("file")
    p.add_argument("--title", default="")
    p.add_argument("--tv-network", default="")
    p.add_argument("--tv-show", default="")
    p.add_argument("--tv-episode", default="")
    p.add_argument("--tv-season", default="")
    p.add_argument("--tv-episode-num", default="")
    args = p.parse_args()

    try:
        mp4 = MP4(args.file)
    except Exception as exc:
        sys.stderr.write("MP4 lesen: %s\n" % exc)
        return 1

    if mp4.tags is None:
        mp4.add_tags()

    def set_str(key: str, val: str) -> None:
        if val:
            mp4[key] = [val]

    set_str("\xa9nam", args.title)
    set_str("tvnn", args.tv_network)
    set_str("tvsh", args.tv_show)
    set_str("tven", args.tv_episode)

    season = _uint(args.tv_season)
    if season is not None:
        mp4["tvsn"] = [season]
    episode = _uint(args.tv_episode_num)
    if episode is not None:
        mp4["tves"] = [episode]

    try:
        mp4.save()
    except Exception as exc:
        sys.stderr.write("MP4 speichern: %s\n" % exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
