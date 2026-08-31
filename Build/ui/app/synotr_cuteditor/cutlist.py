"""OTR cutlist INI (keep intervals)."""
from __future__ import annotations

import os
import re
from datetime import datetime
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
    info: Dict[str, str] = {}
    meta: Dict[str, str] = {}
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
        sl = (section or "general").lower()
        if sl == "general" or section is None:
            general[key] = val
        elif sl == "info":
            info[key] = val
        elif sl == "meta":
            meta[key] = val
        elif sl.startswith("cut"):
            current[key] = val
    if section and section.lower().startswith("cut") and current:
        cuts.append(current)
    return {"general": general, "info": info, "meta": meta, "cuts": cuts}


def editor_state_from_cutlist(text: str, fps_fallback: float = 25.0) -> Dict[str, Any]:
    data = parse_cutlist(text)
    g = data.get("general") or {}
    fps = fps_fallback
    try:
        fps = float(g.get("FramesPerSecond") or fps_fallback)
    except (TypeError, ValueError):
        fps = fps_fallback
    if fps <= 0:
        fps = fps_fallback or 25.0
    keeps: List[Dict[str, Any]] = []
    for c in data.get("cuts") or []:
        try:
            start = float(c.get("Start") or 0)
            duration = float(c.get("Duration") or 0)
        except (TypeError, ValueError):
            continue
        if duration < 0:
            duration = 0.0
        keep: Dict[str, Any] = {"start": start, "duration": duration}
        if c.get("StartFrame") not in (None, ""):
            try:
                keep["start_frame"] = int(float(c["StartFrame"]))
            except (TypeError, ValueError):
                pass
        if c.get("DurationFrames") not in (None, ""):
            try:
                keep["duration_frames"] = int(float(c["DurationFrames"]))
            except (TypeError, ValueError):
                pass
        keeps.append(keep)
    return {
        "keeps": keeps,
        "info": dict(data.get("info") or {}),
        "fps": fps,
        "private": g.get("Private", "0") == "1",
        "apply_to": g.get("ApplyToFile", ""),
    }


def is_private_cutlist(path: str) -> bool:
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            data = parse_cutlist(fh.read())
    except OSError:
        return False
    g = data.get("general") or {}
    info = data.get("info") or {}
    if g.get("Private", "0") == "1":
        return True
    comment = info.get("UserComment") or g.get("UserComment", "")
    return "synOTR Eigengebrauch" in comment


def _ini_line(key: str, value: Any) -> str:
    text = str(value if value is not None else "")
    text = text.replace("\r", " ").replace("\n", " ").strip()
    return "%s=%s" % (key, text)


def _flag01(value: Any) -> str:
    if value in (True, 1, "1", "on", "true", "True"):
        return "1"
    return "0"


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
    aspect: str = "",
    info: Optional[Dict[str, Any]] = None,
) -> None:
    if fps <= 0:
        fps = 25.0
    extra = dict(info or {})
    author = str(extra.pop("Author", author) or author)
    comment = str(extra.get("UserComment") or "")
    if private and "synOTR Eigengebrauch" not in comment:
        note = "synOTR Eigengebrauch, nicht zu cutlist.at"
        comment = (comment + " | " + note).strip(" |") if comment else note
    extra["UserComment"] = comment
    lines = [
        "[General]",
        _ini_line("Application", app),
        _ini_line("Version", version),
        "FramesPerSecond=%.6g" % fps,
        _ini_line("DisplayAspectRatio", aspect or extra.pop("DisplayAspectRatio", "")),
        "IntendedCutApplicationName=avcut",
        "IntendedCutApplication=avcut",
        "VDUseSmartRendering=1",
        "comment1=The following parts of the movie will be kept, the rest will be cut out.",
        "comment2=All values are given in seconds.",
        "NoOfCuts=%s" % len(keeps),
        _ini_line("ApplyToFile", apply_to),
        "OriginalFileSizeBytes=%s" % int(size_bytes),
        "Private=%s" % ("1" if private else "0"),
    ]
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
    rating = str(extra.get("RatingByAuthor") or "").strip()
    if rating not in ("1", "2", "3", "4", "5"):
        rating = ""
    lines.append("[Info]")
    lines.append(_ini_line("Author", author))
    lines.append(_ini_line("RatingByAuthor", rating))
    for flag in (
        "EPGError",
        "MissingBeginning",
        "MissingEnding",
        "MissingVideo",
        "MissingAudio",
        "OtherError",
    ):
        lines.append("%s=%s" % (flag, _flag01(extra.get(flag, "0"))))
    lines.append(_ini_line("ActualContent", extra.get("ActualContent", "")))
    lines.append(_ini_line("OtherErrorDescription", extra.get("OtherErrorDescription", "")))
    lines.append(_ini_line("SuggestedMovieName", extra.get("SuggestedMovieName", "")))
    lines.append(_ini_line("UserComment", extra.get("UserComment", "")))
    lines.append("[Meta]")
    lines.append(_ini_line("GeneratedOn", datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
    lines.append("GeneratedBy=synOTR CutEditor")
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
