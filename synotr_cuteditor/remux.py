"""AVI→MP4 in DECODIR for the CutEditor (otrkey Eigengebrauch)."""
from __future__ import annotations

import os
import shutil
import subprocess
from typing import Tuple

from synotr_cuteditor.paths import CutEditorConfig, parse_onoff
from synotr_cuteditor.waiting import set_editor_mp4


def _archive_source(avi_path: str) -> None:
    if not avi_path or not os.path.isfile(avi_path):
        return
    wipe = parse_onoff(os.environ.get("SYNOTR_ENDGUELTIG", "off")) == "on"
    if wipe:
        try:
            os.remove(avi_path)
        except OSError:
            pass
        return
    trash = (os.environ.get("SYNOTR_OTRKEYDELDIR") or "").rstrip("/")
    if not trash:
        return
    try:
        os.makedirs(trash, exist_ok=True)
        dest = os.path.join(trash, os.path.basename(avi_path))
        if os.path.realpath(avi_path) != os.path.realpath(dest):
            if os.path.exists(dest):
                os.remove(dest)
            shutil.move(avi_path, dest)
    except OSError:
        pass


def remux_otrkey(cfg: CutEditorConfig, avi_path: str, rowid: int) -> Tuple[bool, str]:
    if not avi_path or not os.path.isfile(avi_path):
        return False, "AVI fehlt"
    deco = cfg.deco_dir.rstrip("/")
    if not deco:
        return False, "Dekodierordner fehlt"
    os.makedirs(deco, exist_ok=True)
    stem = os.path.splitext(os.path.basename(avi_path))[0]
    dst = os.path.join(deco, stem + ".mp4")
    legacy = os.path.join(cfg.editor_dir(), stem + ".mp4")
    if os.path.isfile(legacy) and os.path.realpath(legacy) != os.path.realpath(dst):
        if not os.path.isfile(dst) or os.path.getsize(dst) < 1024:
            try:
                shutil.move(legacy, dst)
            except OSError:
                pass

    helper = os.environ.get("SYNOTR_CUTEDITOR_REMUX", "")
    if helper and os.path.isfile(helper):
        env = os.environ.copy()
        rc = subprocess.call([helper, avi_path, dst], env=env)
        if rc != 0 or not os.path.isfile(dst) or os.path.getsize(dst) < 1024:
            return False, "Remux-Skript fehlgeschlagen (exit %s)" % rc
        if rowid:
            set_editor_mp4(cfg.sqlite_path, rowid, dst)
        _archive_source(avi_path)
        return True, dst

    if not cfg.ffmpeg:
        return False, "ffmpeg fehlt"
    tmp = dst + ".part.mp4"
    cmd = [
        cfg.ffmpeg,
        "-hide_banner",
        "-loglevel",
        "error",
        "-y",
        "-i",
        avi_path,
        "-c:v",
        "copy",
        "-c:a",
        "aac",
        "-movflags",
        "+faststart",
        tmp,
    ]
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=7200)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return False, str(exc)
    if p.returncode != 0 or not os.path.isfile(tmp):
        err = p.stderr.decode("utf-8", "replace")[-800:]
        return False, err or "ffmpeg remux fehlgeschlagen"
    os.replace(tmp, dst)
    if rowid:
        set_editor_mp4(cfg.sqlite_path, rowid, dst)
    _archive_source(avi_path)
    return True, dst
