"""ffprobe / ffmpeg helpers."""
from __future__ import annotations

import json
import os
import subprocess
from typing import Any, Dict, Optional, Tuple


def run_cmd(args, timeout: int = 120) -> Tuple[int, str, str]:
    try:
        p = subprocess.run(
            args,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )
        out = p.stdout.decode("utf-8", "replace")
        err = p.stderr.decode("utf-8", "replace")
        return p.returncode, out, err
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 1, "", str(exc)


def probe(ffprobe: str, path: str) -> Dict[str, Any]:
    rc, out, err = run_cmd(
        [ffprobe, "-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", path],
        timeout=60,
    )
    if rc != 0 or not out.strip():
        return {"error": err or "ffprobe failed"}
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        i = out.find("{")
        if i >= 0:
            try:
                return json.loads(out[i:])
            except json.JSONDecodeError:
                pass
        return {"error": "ffprobe json"}


def fps_from_probe(info: Dict[str, Any]) -> float:
    streams = info.get("streams") or []
    rate = "25/1"
    for s in streams:
        if s.get("codec_type") == "video":
            rate = s.get("r_frame_rate") or s.get("avg_frame_rate") or "25/1"
            break
    if isinstance(rate, (int, float)):
        return float(rate) if rate else 25.0
    if "/" in str(rate):
        a, b = str(rate).split("/", 1)
        try:
            den = float(b)
            if den == 0:
                return 25.0
            return float(a) / den
        except ValueError:
            return 25.0
    try:
        return float(rate)
    except ValueError:
        return 25.0


def duration_from_probe(info: Dict[str, Any]) -> float:
    fmt = info.get("format") or {}
    try:
        d = float(fmt.get("duration") or 0)
        if d > 0:
            return d
    except (TypeError, ValueError):
        pass
    for s in info.get("streams") or []:
        try:
            d = float(s.get("duration") or 0)
            if d > 0:
                return d
        except (TypeError, ValueError):
            continue
    return 0.0


def extract_frame_jpeg(
    ffmpeg: str,
    src: str,
    dest: str,
    t: float,
    timeout: int = 30,
    width: int = 160,
) -> Optional[str]:
    os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
    if t < 0:
        t = 0.0
    cmd = [
        ffmpeg,
        "-hide_banner",
        "-loglevel",
        "error",
        "-ss",
        "%.6f" % t,
        "-i",
        src,
        "-frames:v",
        "1",
        "-q:v",
        "7",
    ]
    if width and width > 0:
        cmd.extend(["-vf", "scale=%d:-2" % int(width)])
    cmd.extend(["-y", dest])
    rc, _out, _err = run_cmd(
        cmd,
        timeout=timeout,
    )
    if rc == 0 and os.path.isfile(dest) and os.path.getsize(dest) > 32:
        return dest
    return None


def parse_keyframe_times(text: str) -> list:
    times = []
    seen = set()
    for raw in (text or "").splitlines():
        line = raw.strip().replace("\r", "")
        if not line or line.lower() in ("n/a", "nan"):
            continue
        part = line.split(",")[0].strip()
        try:
            t = float(part)
        except ValueError:
            continue
        if t < 0:
            continue
        key = round(t, 4)
        if key in seen:
            continue
        seen.add(key)
        times.append(t)
    times.sort()
    return times


def keyframe_times(ffprobe: str, path: str, timeout: int = 300) -> list:
    rc, out, _err = run_cmd(
        [
            ffprobe,
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-skip_frame",
            "nokey",
            "-show_entries",
            "frame=best_effort_timestamp_time,pkt_pts_time",
            "-of",
            "csv=p=0",
            path,
        ],
        timeout=timeout,
    )
    if rc != 0:
        return []
    return parse_keyframe_times(out)
