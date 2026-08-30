"""CGI / CLI dispatch for the CutEditor."""
from __future__ import annotations

import json
import os
import sys
from typing import Any, Dict, Optional
from urllib.parse import parse_qs

from synotr_cuteditor.cutlist import write_cutlist
from synotr_cuteditor.media import duration_from_probe, extract_frame_jpeg, fps_from_probe, probe
from synotr_cuteditor.paths import CutEditorConfig, parse_onoff, parse_queue
from synotr_cuteditor.remux import remux_otrkey
from synotr_cuteditor.waiting import item_for, list_waiting


def _cgi_status(status: int) -> None:
    # DSM webman: Status: 200 vor dem Body führt oft zur generischen 404-Seite.
    if status == 206:
        sys.stdout.buffer.write(b"Status: 206 Partial Content\r\n")


def _json(data: Any, status: int = 200) -> None:
    del status  # HTTP-Code nur im JSON (ok/error); kein CGI-Status: 4xx
    body = json.dumps(data, ensure_ascii=False).encode("utf-8")
    sys.stdout.buffer.write(b"Content-Type: application/json; charset=utf-8\r\n")
    sys.stdout.buffer.write(("Content-Length: %s\r\n\r\n" % len(body)).encode("ascii"))
    sys.stdout.buffer.write(body)
    sys.stdout.buffer.flush()


def _bin(body: bytes, ctype: str, status: int = 200, extra: Optional[Dict[str, str]] = None) -> None:
    _cgi_status(status)
    sys.stdout.buffer.write(("Content-Type: %s\r\n" % ctype).encode("ascii"))
    if extra:
        for k, v in extra.items():
            sys.stdout.buffer.write(("%s: %s\r\n" % (k, v)).encode("ascii"))
    sys.stdout.buffer.write(("Content-Length: %s\r\n\r\n" % len(body)).encode("ascii"))
    sys.stdout.buffer.write(body)
    sys.stdout.buffer.flush()


def _read_post() -> bytes:
    n = int(os.environ.get("CONTENT_LENGTH") or "0")
    if n <= 0:
        return b""
    return sys.stdin.buffer.read(n)


def _qs() -> Dict[str, str]:
    raw = os.environ.get("QUERY_STRING") or ""
    parsed = parse_qs(raw, keep_blank_values=True)
    return {k: (v[-1] if v else "") for k, v in parsed.items()}


def load_config_from_env() -> CutEditorConfig:
    return CutEditorConfig(
        deco_dir=os.environ.get("SYNOTR_DECODIR", ""),
        sqlite_path=os.environ.get("SYNOTR_SQLITE", ""),
        workdir=os.environ.get("SYNOTR_WORKDIR", ""),
        ffmpeg=os.environ.get("SYNOTR_FFMPEG", "ffmpeg"),
        ffprobe=os.environ.get("SYNOTR_FFPROBE", "ffprobe"),
        mp4box=os.environ.get("SYNOTR_MP4BOX", ""),
        local_cutlist_dir=os.environ.get("SYNOTR_LOCALCUTLIST", ""),
        otrkey_dir=os.environ.get("SYNOTR_OTRKEYDIR", ""),
        queue=parse_queue(os.environ.get("SYNOTR_CUTEDITOR_QUEUE", "miss_both")),
        otrkey_mp4=parse_onoff(os.environ.get("SYNOTR_CUTEDITOR_OTRKEYMP4", "off")),
        author=os.environ.get("SYNOTR_CUTLIST_AUTHOR", ""),
        config_file=os.environ.get("SYNOTR_CONFIG", ""),
    )


def _play_file(cfg: CutEditorConfig, basename: str) -> Optional[str]:
    it = item_for(cfg, basename)
    if not it:
        return None
    play = it.get("play_path") or ""
    if play and os.path.isfile(play):
        resolved = cfg.resolve_media(play)
        return resolved
    path = it.get("path") or ""
    if path.lower().endswith(".mp4"):
        return cfg.resolve_media(path)
    return None


def send_media_range(path: str) -> None:
    size = os.path.getsize(path)
    rng = os.environ.get("HTTP_RANGE") or os.environ.get("RANGE") or ""
    start = 0
    end = size - 1
    status = 200
    if rng.startswith("bytes="):
        spec = rng[6:].split(",")[0].strip()
        a, _, b = spec.partition("-")
        try:
            if a:
                start = int(a)
            if b:
                end = int(b)
            else:
                end = size - 1
            if start < 0:
                start = 0
            if end >= size:
                end = size - 1
            if start > end:
                start, end = 0, size - 1
            status = 206
        except ValueError:
            start, end, status = 0, size - 1, 200
    length = end - start + 1
    extra = {
        "Accept-Ranges": "bytes",
        "Content-Range": "bytes %s-%s/%s" % (start, end, size) if status == 206 else "",
    }
    extra = {k: v for k, v in extra.items() if v}
    _cgi_status(status)
    sys.stdout.buffer.write(b"Content-Type: video/mp4\r\n")
    sys.stdout.buffer.write(b"Accept-Ranges: bytes\r\n")
    if status == 206:
        sys.stdout.buffer.write(
            ("Content-Range: bytes %s-%s/%s\r\n" % (start, end, size)).encode("ascii")
        )
    sys.stdout.buffer.write(("Content-Length: %s\r\n\r\n" % length).encode("ascii"))
    with open(path, "rb") as fh:
        fh.seek(start)
        left = length
        while left > 0:
            chunk = fh.read(min(1024 * 256, left))
            if not chunk:
                break
            sys.stdout.buffer.write(chunk)
            left -= len(chunk)
    sys.stdout.buffer.flush()


def dispatch_cgi(cfg: CutEditorConfig) -> int:
    qs = _qs()
    action = qs.get("action") or "list"
    if action == "list":
        items = list_waiting(cfg)
        _json({"ok": True, "queue": cfg.queue, "otrkey_mp4": cfg.otrkey_mp4, "items": items})
        return 0
    if action == "item":
        it = item_for(cfg, qs.get("file") or "")
        if not it:
            _json({"ok": False, "error": "Datei nicht gefunden"}, 404)
            return 0
        play = it.get("play_path") or ""
        info: Dict[str, Any] = {}
        fps = 25.0
        dur = 0.0
        if play and os.path.isfile(play):
            info = probe(cfg.ffprobe, play)
            if "error" not in info:
                fps = fps_from_probe(info)
                dur = duration_from_probe(info)
        it["fps"] = fps
        it["duration"] = dur
        _json({"ok": True, "item": it})
        return 0
    if action == "save":
        try:
            payload = json.loads(_read_post().decode("utf-8") or "{}")
        except json.JSONDecodeError:
            _json({"ok": False, "error": "JSON ungültig"}, 400)
            return 0
        basename = os.path.basename(str(payload.get("file") or ""))
        it = item_for(cfg, basename)
        if not it:
            _json({"ok": False, "error": "Datei nicht in der Warteliste"}, 400)
            return 0
        play = it.get("play_path") or ""
        if not play or not os.path.isfile(play):
            _json({"ok": False, "error": "Keine MP4 für den Editor (ggf. zuerst remuxen)"}, 400)
            return 0
        keeps = payload.get("keeps") or []
        if not isinstance(keeps, list) or not keeps:
            _json({"ok": False, "error": "Mindestens ein Keep-Intervall"}, 400)
            return 0
        fps = float(payload.get("fps") or 0) or 25.0
        apply_to = os.path.basename(play)
        size_b = it.get("file_orig_size") or 0
        if it.get("private"):
            size_b = os.path.getsize(play)
        elif not size_b:
            size_b = os.path.getsize(it["path"])
        dest = play + ".cutlist"
        write_cutlist(
            dest,
            apply_to=apply_to,
            size_bytes=int(size_b),
            fps=fps,
            keeps=keeps,
            author=cfg.author,
            private=bool(it.get("private")),
        )
        # otr2: also copy next to original in DECODIR if play is the original
        orig = it["path"]
        if orig.lower().endswith(".mp4") and os.path.realpath(play) == os.path.realpath(orig):
            pass
        elif orig.lower().endswith(".mp4"):
            alt = orig + ".cutlist"
            if alt != dest:
                try:
                    with open(dest, "r", encoding="utf-8") as fh:
                        txt = fh.read()
                    with open(alt, "w", encoding="utf-8") as fh:
                        fh.write(txt)
                except OSError:
                    pass
        _json({"ok": True, "cutlist": dest})
        return 0
    if action == "media":
        path = _play_file(cfg, qs.get("file") or "")
        if not path:
            _json({"ok": False, "error": "Medien-Datei fehlt"}, 404)
            return 0
        send_media_range(path)
        return 0
    if action in ("frame", "strip"):
        path = _play_file(cfg, qs.get("file") or "")
        if not path:
            _json({"ok": False, "error": "Medien-Datei fehlt"}, 404)
            return 0
        try:
            t = float(qs.get("t") or "0")
        except ValueError:
            t = 0.0
        cache = cfg.frame_cache_dir()
        os.makedirs(cache, exist_ok=True)
        if action == "frame":
            dest = os.path.join(cache, "%s_%.3f.jpg" % (os.path.basename(path), t))
            got = extract_frame_jpeg(cfg.ffmpeg, path, dest, t)
            if not got:
                _json({"ok": False, "error": "Frame fehlgeschlagen"}, 500)
                return 0
            with open(got, "rb") as fh:
                _bin(fh.read(), "image/jpeg")
            return 0
        # strip: several frames around t
        try:
            span = int(qs.get("span") or "5")
        except ValueError:
            span = 5
        info = probe(cfg.ffprobe, path)
        fps = fps_from_probe(info) if "error" not in info else 25.0
        if fps <= 0:
            fps = 25.0
        jpegs = []
        for i in range(-span, span + 1):
            ti = t + (i / fps)
            if ti < 0:
                continue
            dest = os.path.join(cache, "%s_%.3f.jpg" % (os.path.basename(path), ti))
            if extract_frame_jpeg(cfg.ffmpeg, path, dest, ti):
                with open(dest, "rb") as fh:
                    import base64

                    jpegs.append({"t": ti, "i": i, "jpeg": base64.b64encode(fh.read()).decode("ascii")})
        _json({"ok": True, "fps": fps, "frames": jpegs})
        return 0
    if action == "remux":
        basename = qs.get("file") or ""
        try:
            payload = json.loads(_read_post().decode("utf-8") or "{}")
        except json.JSONDecodeError:
            payload = {}
        if payload.get("file"):
            basename = str(payload.get("file"))
        it = item_for(cfg, os.path.basename(basename))
        if not it or it.get("source") != "otrkey":
            _json({"ok": False, "error": "Nur otrkey-AVI"}, 400)
            return 0
        ok, msg = remux_otrkey(cfg, it["path"], int(it.get("rowid") or 0))
        if not ok:
            _json({"ok": False, "error": msg}, 500)
            return 0
        accept = os.environ.get("HTTP_ACCEPT") or ""
        if "text/html" in accept:
            loc = "index.cgi?page=cuteditor-api&action=editor&file=%s" % os.path.basename(
                basename
            )
            html = (
                "<!DOCTYPE html><html><head><meta charset='utf-8'/>"
                "<meta http-equiv='refresh' content='0;url=%s'/></head>"
                "<body>Remux fertig. <a href='%s'>Zum Editor</a></body></html>"
                % (loc, loc)
            ).encode("utf-8")
            sys.stdout.buffer.write(b"Content-Type: text/html; charset=utf-8\r\n\r\n")
            sys.stdout.buffer.write(html)
            return 0
        _json({"ok": True, "mp4": msg})
        return 0
    if action == "editor":
        static_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static")
        html_path = os.path.join(static_dir, "editor.html")
        with open(html_path, "rb") as fh:
            sys.stdout.buffer.write(b"Content-Type: text/html; charset=utf-8\r\n\r\n")
            sys.stdout.buffer.write(fh.read())
        return 0
    if action == "static":
        name = os.path.basename(qs.get("name") or "")
        static_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static")
        path = os.path.join(static_dir, name)
        if not os.path.isfile(path) or ".." in name:
            _json({"ok": False, "error": "static missing"}, 404)
            return 0
        ctype = "text/plain"
        if name.endswith(".css"):
            ctype = "text/css"
        elif name.endswith(".js"):
            ctype = "application/javascript"
        elif name.endswith(".html"):
            ctype = "text/html; charset=utf-8"
        with open(path, "rb") as fh:
            _bin(fh.read(), ctype)
        return 0
    _json({"ok": False, "error": "unbekannte action"}, 400)
    return 0


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    cfg = load_config_from_env()
    if argv and argv[0] == "http":
        from synotr_cuteditor.http_app import serve

        host = "127.0.0.1"
        port = 8765
        if len(argv) > 1:
            host = argv[1]
        if len(argv) > 2:
            port = int(argv[2])
        serve(cfg, host, port)
        return 0
    return dispatch_cgi(cfg)
