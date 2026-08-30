"""OTR cutlist INI (keep intervals)."""
from __future__ import annotations

import os
import re
from typing import Any, Dict, List, Optional


def cutlist_stem(name: str) -> str:
    stem = os.path.basename(name)
    if stem.endswith(".cutlist"):
        stem = stem[: -len(".cutlist")]
    for ext in (".avi", ".mpg", ".mp4", ".mkv", ".ac3"):
        if stem.lower().endswith(ext):
            stem = stem[: -len(ext)]
    stem = re.sub(r"\.(HQ|HD|LQ)$", "", stem)
    stem = re.sub(r"^DivFix(\+\+)?\.", "", stem)
    return stem


def parse_cutlist(text: str) -> Dict[str, Any]:
    general: Dict[str, str] = {}
    cuts: List[Dict[str, str]] = []
    section = None
    current: Dict[str, str] = {}
    for raw in text.splitlines():
        line = raw.strip().replace("\r", "")
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        if line.startswith("[") and line.endswith("]"):
            if section and section.lower().startswith("cut") and current:
                cuts.append(current)
            section = line[1:-1]
            current = {}
            continue
        if "=" not in line:
            continue
        key, val = line.split("=", 1)
        key = key.strip()
        val = val.strip()
        if section is None or section.lower() == "general":
            general[key] = val
        elif section.lower().startswith("cut"):
            current[key] = val
    if section and section.lower().startswith("cut") and current:
        cuts.append(current)
    return {"general": general, "cuts": cuts}


def is_private_cutlist(path: str) -> bool:
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            data = parse_cutlist(fh.read())
    except OSError:
        return False
    g = data.get("general") or {}
    if g.get("Private", "0") == "1":
        return True
    comment = g.get("UserComment", "")
    return "synOTR Eigengebrauch" in comment


def write_cutlist(
    path: str,
    apply_to: str,
    size_bytes: int,
    fps: float,
    keeps: List[Dict[str, float]],
    author: str = "",
    private: bool = False,
    app: str = "synOTR CutEditor",
    version: str = "1.0",
) -> None:
    if fps <= 0:
        fps = 25.0
    lines = [
        "[General]",
        "Application=%s" % app,
        "Version=%s" % version,
        "FramesPerSecond=%.6g" % fps,
        "IntendedCutApplicationName=avcut",
        "ApplyToFile=%s" % apply_to,
        "OriginalFileSizeBytes=%s" % int(size_bytes),
        "Author=%s" % (author or ""),
        "NoOfCuts=%s" % len(keeps),
    ]
    if private:
        lines.append("Private=1")
        lines.append("UserComment=synOTR Eigengebrauch, nicht zu cutlist.at")
    else:
        lines.append("Private=0")
        lines.append("UserComment=")
    for i, k in enumerate(keeps):
        start = float(k["start"])
        duration = float(k["duration"])
        if duration < 0:
            duration = 0.0
        sf = int(round(start * fps))
        df = int(round(duration * fps))
        if "start_frame" in k:
            sf = int(k["start_frame"])
        if "duration_frames" in k:
            df = int(k["duration_frames"])
        lines.append("[Cut%d]" % i)
        lines.append("Start=%.6f" % start)
        lines.append("Duration=%.6f" % duration)
        lines.append("StartFrame=%d" % sf)
        lines.append("DurationFrames=%d" % df)
    text = "\n".join(lines) + "\n"
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def find_local_cutlist(
    film_path: str,
    search_dirs: List[str],
    extra_names: Optional[List[str]] = None,
) -> Optional[str]:
    """Return first matching .cutlist path (same rules as synotr_pick_local_cutlist)."""
    if not film_path or not os.path.isfile(film_path):
        return None
    film_base = os.path.basename(film_path)
    try:
        filesize = str(os.path.getsize(film_path))
    except OSError:
        filesize = ""
    film_stem = cutlist_stem(film_base)
    names = [film_base]
    if extra_names:
        names.extend(extra_names)

    for d in search_dirs:
        if not d or not os.path.isdir(d):
            continue
        for n in names:
            exact = os.path.join(d, n + ".cutlist")
            if os.path.isfile(exact):
                return exact

        apply_hit = None
        size_hit = None
        stem_hit = None
        try:
            entries = os.listdir(d)
        except OSError:
            continue
        for ent in entries:
            if not ent.endswith(".cutlist"):
                continue
            f = os.path.join(d, ent)
            if not os.path.isfile(f):
                continue
            try:
                with open(f, "r", encoding="utf-8", errors="replace") as fh:
                    parsed = parse_cutlist(fh.read())
            except OSError:
                continue
            g = parsed.get("general") or {}
            apply_to = g.get("ApplyToFile", "")
            cl_size = g.get("OriginalFileSizeBytes", "")
            if apply_to in names and apply_hit is None:
                apply_hit = f
            if cl_size and cl_size == filesize and size_hit is None:
                size_hit = f
            cl_stem = cutlist_stem(ent)
            apply_stem = cutlist_stem(apply_to) if apply_to else ""
            if (cl_stem == film_stem or apply_stem == film_stem) and stem_hit is None:
                has_time = any("Start" in c and "StartFrame" not in c for c in parsed.get("cuts") or [])
                has_start = any("Start" in c for c in parsed.get("cuts") or [])
                if has_start:
                    if has_time or True:
                        stem_hit = f
        if apply_hit:
            return apply_hit
        if size_hit:
            return size_hit
        if stem_hit:
            return stem_hit
    return None
