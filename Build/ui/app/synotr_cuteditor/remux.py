"""AVI→MP4 sidecar for the CutEditor (otrkey Eigengebrauch)."""
from __future__ import annotations

import os
import subprocess
from typing import Optional, Tuple

from synotr_cuteditor.paths import CutEditorConfig
from synotr_cuteditor.waiting import set_editor_mp4


def remux_otrkey(cfg: CutEditorConfig, avi_path: str, rowid: int) -> Tuple[bool, str]:
    if not avi_path or not os.path.isfile(avi_path):
        return False, "AVI fehlt"
    os.makedirs(cfg.editor_dir(), exist_ok=True)
    stem = os.path.splitext(os.path.basename(avi_path))[0]
    dst = os.path.join(cfg.editor_dir(), stem + ".mp4")
    helper = os.environ.get("SYNOTR_CUTEDITOR_REMUX", "")
    if helper and os.path.isfile(helper):
        env = os.environ.copy()
        rc = subprocess.call([helper, avi_path, dst], env=env)
        if rc != 0 or not os.path.isfile(dst) or os.path.getsize(dst) < 1024:
            return False, "Remux-Skript fehlgeschlagen (exit %s)" % rc
        if rowid:
            set_editor_mp4(cfg.sqlite_path, rowid, dst)
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
    return True, dst
