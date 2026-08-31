"""Waiting queue from DECODIR + SQLite."""
from __future__ import annotations

import os
import sqlite3
from typing import Any, Dict, List, Optional

from synotr_cuteditor.cutlist import find_local_cutlist
from synotr_cuteditor.paths import CutEditorConfig, cutlist_search_dirs, parse_onoff, parse_queue


def _connect(path: str) -> Optional[sqlite3.Connection]:
    if not path or not os.path.isfile(path):
        return None
    con = sqlite3.connect(path)
    con.row_factory = sqlite3.Row
    return con


_ROW_SQL = (
    "SELECT rowid, file_original, COALESCE(file_source,'') AS file_source, "
    "COALESCE(file_encrypted,'') AS file_encrypted, "
    "COALESCE(OTRtitle,'') AS OTRtitle, COALESCE(titel,'') AS titel, "
    "COALESCE(sender,'') AS sender, "
    "COALESCE(file_orig_size,'') AS file_orig_size, "
    "COALESCE(cutlist_online,'') AS cutlist_online, "
    "COALESCE(file_editor_mp4,'') AS file_editor_mp4 "
    "FROM raw WHERE %s=? ORDER BY rowid DESC LIMIT 1"
)
_ROW_SQL_LEGACY = (
    "SELECT rowid, file_original, COALESCE(file_source,'') AS file_source, "
    "COALESCE(file_encrypted,'') AS file_encrypted, "
    "COALESCE(OTRtitle,'') AS OTRtitle, COALESCE(titel,'') AS titel, "
    "COALESCE(sender,'') AS sender "
    "FROM raw WHERE %s=? ORDER BY rowid DESC LIMIT 1"
)


def _fetch(con: sqlite3.Connection, col: str, val: str) -> Optional[sqlite3.Row]:
    try:
        return con.execute(_ROW_SQL % col, (val,)).fetchone()
    except sqlite3.OperationalError:
        row = con.execute(_ROW_SQL_LEGACY % col, (val,)).fetchone()
        return row


def deco_play_mp4(cfg: CutEditorConfig, basename: str) -> Optional[str]:
    """Player-MP4: nach dem Remux liegt sie im Dekodierordner (gleicher Stem) oder in _cuteditor/."""
    base = os.path.basename(basename or "")
    if not base:
        return None
    deco = (cfg.deco_dir or "").rstrip("/")
    if not deco:
        return None
    stem, ext = os.path.splitext(base)
    names = []
    if ext.lower() == ".mp4":
        names.append(base)
    names.append(stem + ".mp4")
    seen = set()
    for name in names:
        if name in seen:
            continue
        seen.add(name)
        for folder in (deco, os.path.join(deco, "_cuteditor")):
            cand = os.path.join(folder, name)
            if os.path.isfile(cand):
                return os.path.realpath(cand)
    return None


def lookup_row(con: sqlite3.Connection, basename: str) -> Optional[sqlite3.Row]:
    esc = basename
    for col in ("file_original", "file_encrypted"):
        row = _fetch(con, col, esc)
        if row:
            return row
    stem, ext = os.path.splitext(basename)
    if ext.lower() == ".mp4":
        for try_avi in (stem + ".avi", stem + ".AVI"):
            row = _fetch(con, "file_original", try_avi)
            if row:
                return row
        for try_name in (basename + ".otr2", stem + ".mp4.otr2", stem + ".otr2"):
            row = _fetch(con, "file_encrypted", try_name)
            if row:
                return row
    if ext.lower() == ".avi":
        for try_name in (basename + ".otrkey", stem + ".avi.otrkey", stem + ".otrkey"):
            row = _fetch(con, "file_encrypted", try_name)
            if row:
                return row
    return None


def _source_of(row: Optional[sqlite3.Row], basename: str) -> str:
    src = _row_get(row, "file_source") if row else ""
    if src:
        return src
    low = basename.lower()
    if low.endswith(".avi"):
        return "otrkey"
    return ""


def _row_get(row: Optional[sqlite3.Row], key: str, default: str = "") -> str:
    if not row:
        return default
    try:
        v = row[key]
    except (IndexError, KeyError):
        return default
    if v is None:
        return default
    text = str(v)
    if text in ("null", "None", "NULL"):
        return default
    return text


def _online_of(row: Optional[sqlite3.Row]) -> str:
    if not row:
        return "unset"
    v = _row_get(row, "cutlist_online").strip()
    if v in ("none", "found", "unset"):
        return v
    if not v:
        return "unset"
    return v


def _editor_mp4(row: Optional[sqlite3.Row]) -> str:
    return _row_get(row, "file_editor_mp4").strip()


def _local_cutlist(cfg: CutEditorConfig, path: str, row: Optional[sqlite3.Row]) -> str:
    extra = []
    sidecar = _editor_mp4(row)
    if sidecar:
        extra.append(os.path.basename(sidecar))
    search = list(cutlist_search_dirs(cfg))
    local = find_local_cutlist(path, search, extra_names=extra)
    if not local and sidecar and os.path.isfile(sidecar):
        local = find_local_cutlist(sidecar, search)
    return local or ""


def list_waiting(cfg: CutEditorConfig) -> List[Dict[str, Any]]:
    queue = parse_queue(cfg.queue)
    otrkey_on = parse_onoff(cfg.otrkey_mp4) == "on"
    deco = cfg.deco_dir
    out: List[Dict[str, Any]] = []
    if not deco or not os.path.isdir(deco):
        return out
    con = _connect(cfg.sqlite_path)
    try:
        names = sorted(os.listdir(deco))
    except OSError:
        names = []
    for name in names:
        low = name.lower()
        if low.endswith("-cut.mp4") or low.endswith("-cut.avi"):
            continue
        if not (low.endswith(".mp4") or low.endswith(".avi")):
            continue
        path = os.path.join(deco, name)
        if not os.path.isfile(path):
            continue
        row = lookup_row(con, name) if con else None
        src = _source_of(row, name)
        if low.endswith(".avi"):
            if src and src != "otrkey":
                continue
            if not otrkey_on:
                continue
            src = "otrkey"
        else:
            avi_sib = os.path.join(deco, os.path.splitext(name)[0] + ".avi")
            if src == "otrkey":
                if os.path.isfile(avi_sib):
                    continue
            elif not src:
                src = "otr2"
            elif src != "otr2":
                continue
        sidecar = _editor_mp4(row)
        local = _local_cutlist(cfg, path, row)
        has_local = bool(local)
        online = _online_of(row)
        if queue == "miss_both":
            # unset = noch keine Online-Suche (frisch dekodiert) → wie „keine Online-Cutlist“.
            if has_local or online not in ("none", "unset"):
                continue
        elif queue == "no_local":
            if has_local:
                continue
        # all_uncut: keep
        play = path
        needs_remux = False
        if src == "otrkey" and low.endswith(".avi"):
            found = deco_play_mp4(cfg, name)
            if found:
                play = found
                sidecar = found
            else:
                needs_remux = True
                play = ""
        item = {
            "file": name,
            "path": path,
            "play_path": play,
            "source": src,
            "has_local": has_local,
            "cutlist_online": online,
            "title": _row_get(row, "OTRtitle") or _row_get(row, "titel"),
            "sender": _row_get(row, "sender"),
            "file_orig_size": int(_row_get(row, "file_orig_size") or "0") if _row_get(row, "file_orig_size").isdigit() else 0,
            "size": os.path.getsize(path),
            "needs_remux": needs_remux,
            "private": src == "otrkey",
            "rowid": int(row["rowid"]) if row else 0,
            "editor_mp4": sidecar,
            "local_cutlist": local,
        }
        out.append(item)
    if con:
        con.close()
    return out


def item_for(cfg: CutEditorConfig, basename: str) -> Optional[Dict[str, Any]]:
    base = os.path.basename(basename)
    for it in list_waiting(cfg):
        if it["file"] == base:
            return it
    # all_uncut-style lookup even if filtered out
    deco = cfg.deco_dir or ""
    path = os.path.join(deco, base) if deco else base
    if not os.path.isfile(path):
        stem, ext = os.path.splitext(base)
        if ext.lower() == ".avi":
            alt = os.path.join(deco, stem + ".mp4")
            if deco and os.path.isfile(alt):
                return item_for(cfg, os.path.basename(alt))
            legacy = os.path.join(cfg.editor_dir(), stem + ".mp4")
            if os.path.isfile(legacy):
                path = legacy
            else:
                return None
        elif ext.lower() == ".mp4":
            legacy = os.path.join(cfg.editor_dir(), base)
            if os.path.isfile(legacy):
                path = legacy
            else:
                return None
        else:
            return None
    con = _connect(cfg.sqlite_path)
    row = lookup_row(con, os.path.basename(path)) if con else None
    if con:
        con.close()
    src = _source_of(row, os.path.basename(path))
    sidecar = _editor_mp4(row)
    local = _local_cutlist(cfg, path, row)
    low = path.lower()
    found = deco_play_mp4(cfg, os.path.basename(path)) or deco_play_mp4(cfg, base)
    play = found or path
    needs_remux = False
    if low.endswith(".avi") and not found:
        play = ""
        needs_remux = True
    elif found:
        play = found
    return {
        "file": os.path.basename(path),
        "path": path,
        "play_path": play,
        "source": src or ("otrkey" if low.endswith(".avi") else "otr2"),
        "has_local": bool(local),
        "cutlist_online": _online_of(row),
        "title": _row_get(row, "OTRtitle") or _row_get(row, "titel"),
        "sender": _row_get(row, "sender"),
        "file_orig_size": int(_row_get(row, "file_orig_size") or "0") if _row_get(row, "file_orig_size").isdigit() else 0,
        "size": os.path.getsize(path),
        "needs_remux": needs_remux,
        "private": (src or "") == "otrkey" or low.endswith(".avi"),
        "rowid": int(row["rowid"]) if row else 0,
        "editor_mp4": sidecar,
        "local_cutlist": local,
    }


def set_editor_mp4(sqlite_path: str, rowid: int, mp4_path: str) -> None:
    if not rowid:
        return
    con = _connect(sqlite_path)
    if not con:
        return
    try:
        con.execute("UPDATE raw SET file_editor_mp4=? WHERE rowid=?", (mp4_path, rowid))
        con.commit()
    except sqlite3.OperationalError:
        pass
    finally:
        con.close()
