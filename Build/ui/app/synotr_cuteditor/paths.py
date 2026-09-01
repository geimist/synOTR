"""Path helpers: no traversal outside allowed dirs."""
from __future__ import annotations

import os
import shutil
from dataclasses import dataclass, field
from typing import Iterable, List, Optional


def _norm(p: str) -> str:
    return os.path.realpath(os.path.abspath(p))


def is_under(path: str, root: str) -> bool:
    if not path or not root:
        return False
    rp = _norm(path)
    rr = _norm(root)
    return rp == rr or rp.startswith(rr + os.sep)


@dataclass
class CutEditorConfig:
    deco_dir: str
    sqlite_path: str
    workdir: str
    ffmpeg: str = "ffmpeg"
    ffprobe: str = "ffprobe"
    mp4box: str = ""
    local_cutlist_dir: str = ""
    otrkey_dir: str = ""
    queue: str = "miss_both"
    otrkey_mp4: str = "off"
    author: str = ""
    config_file: str = ""
    extra_media_dirs: List[str] = field(default_factory=list)

    def editor_dir(self) -> str:
        return os.path.join(self.deco_dir.rstrip("/"), "_cuteditor")

    def frame_cache_dir(self) -> str:
        return os.path.join(self.workdir.rstrip("/"), "tmp_synotr_cutedit")

    def clear_frame_cache(self) -> int:
        """Frame-JPEGs und tmp_synotr_cutedit entfernen (nur unter WORKDIR)."""
        if not self.workdir:
            return 0
        cache = _norm(self.frame_cache_dir())
        work = _norm(self.workdir.rstrip("/"))
        if os.path.basename(cache) != "tmp_synotr_cutedit" or not is_under(cache, work):
            return 0
        if not os.path.isdir(cache):
            return 0
        n = 0
        try:
            for _root, _dirs, files in os.walk(cache):
                n += len(files)
            shutil.rmtree(cache, ignore_errors=True)
        except OSError:
            return n
        return n

    def allowed_roots(self) -> List[str]:
        roots = [self.deco_dir, self.editor_dir(), self.workdir]
        for d in (self.local_cutlist_dir, self.otrkey_dir):
            if d:
                roots.append(d)
        roots.extend(self.extra_media_dirs)
        return [r for r in roots if r]

    def resolve_media(self, name_or_path: str) -> Optional[str]:
        if not name_or_path:
            return None
        if os.path.isabs(name_or_path):
            cand = _norm(name_or_path)
        else:
            base = os.path.basename(name_or_path)
            for root in self.allowed_roots():
                p = os.path.join(root, base)
                if os.path.isfile(p):
                    cand = _norm(p)
                    break
            else:
                p2 = os.path.join(self.editor_dir(), os.path.basename(name_or_path))
                cand = _norm(p2) if os.path.isfile(p2) else None
        if not cand or not os.path.isfile(cand):
            return None
        for root in self.allowed_roots():
            if is_under(cand, root):
                return cand
        return None


def parse_queue(raw: str) -> str:
    v = (raw or "miss_both").strip()
    if v in ("miss_both", "no_local", "all_uncut"):
        return v
    return "miss_both"


def parse_onoff(raw: str) -> str:
    v = (raw or "off").strip().lower()
    if v in ("on", "1", "true", "yes"):
        return "on"
    return "off"


def cutlist_search_dirs(cfg: CutEditorConfig) -> Iterable[str]:
    for d in (cfg.deco_dir, cfg.otrkey_dir, cfg.local_cutlist_dir, cfg.editor_dir()):
        if d and os.path.isdir(d):
            yield d.rstrip("/")
