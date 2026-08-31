"""CGI / CLI dispatch for the CutEditor."""
from __future__ import annotations

import json
import os
import sys
from typing import Any, Dict, Optional
from urllib.parse import parse_qs, quote

from synotr_cuteditor.cutlist import editor_state_from_cutlist, write_cutlist
from synotr_cuteditor.media import (
    duration_from_probe,
    extract_frame_jpeg,
    fps_from_probe,
    keyframe_times,
    probe,
)
from synotr_cuteditor.paths import CutEditorConfig, parse_onoff, parse_queue
from synotr_cuteditor.remux import remux_otrkey
from synotr_cuteditor.waiting import deco_play_mp4, item_for, list_waiting


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
    # Zuerst Dateisystem (Dekodierordner), nicht die Warteliste: nach dem Remux
    # liegt die MP4 neben dem alten AVI-Namen, file_editor_mp4 kann noch auf
    # das verschobene _cuteditor-File zeigen.
    found = deco_play_mp4(cfg, basename)
    if found:
        got = cfg.resolve_media(found)
        if got:
            return got
        return found
    it = item_for(cfg, basename)
    if not it:
        return None
    for cand in (it.get("play_path") or "", it.get("editor_mp4") or "", it.get("path") or ""):
        if not cand or not os.path.isfile(cand):
            continue
        if not str(cand).lower().endswith(".mp4"):
            continue
        got = cfg.resolve_media(cand)
        if got:
            return got
        return os.path.realpath(cand)
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
    action = qs.get("action") or ""
    accept = os.environ.get("HTTP_ACCEPT") or ""
    if not action:
        if "text/html" in accept:
            html = (
                b"<!DOCTYPE html><html><head><meta charset='utf-8'/>"
                b"<meta http-equiv='refresh' content='0;url=index.cgi?page=cuteditor'/></head>"
                b"<body><a href='index.cgi?page=cuteditor'>Zum CutEditor</a></body></html>"
            )
            sys.stdout.buffer.write(b"Content-Type: text/html; charset=utf-8\r\n\r\n")
            sys.stdout.buffer.write(html)
            return 0
        action = "list"
    if action == "list":
        items = list_waiting(cfg)
        _json({"ok": True, "queue": cfg.queue, "otrkey_mp4": cfg.otrkey_mp4, "items": items})
        return 0
    if action == "item":
        it = item_for(cfg, qs.get("file") or "")
        if not it:
            _json({"ok": False, "error": "Datei nicht gefunden"}, 404)
            return 0
        # Kein ffprobe und kein zweites Cutlist-CGI: DSM bedient oft nur ein CGI,
        # paralleles action=cutlist + action=media bricht den Player ab.
        play = _play_file(cfg, qs.get("file") or "") or (it.get("play_path") or "")
        if play and os.path.isfile(play) and str(play).lower().endswith(".mp4"):
            it["play_path"] = play
            it["needs_remux"] = False
        it["fps"] = 25.0
        it["duration"] = 0.0
        it["author"] = cfg.author
        it["aspect"] = ""
        cl = it.get("local_cutlist") or ""
        if cl and os.path.isfile(cl):
            try:
                with open(cl, "r", encoding="utf-8", errors="replace") as fh:
                    state = editor_state_from_cutlist(fh.read(), 25.0)
                if state.get("keeps"):
                    it["loaded_cutlist"] = {"cutlist": cl, **state}
                    author = (state.get("info") or {}).get("Author") or ""
                    if author:
                        it["author"] = author
            except OSError:
                pass
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
        overwrite = bool(payload.get("overwrite"))
        if os.path.isfile(dest) and not overwrite:
            _json(
                {
                    "ok": False,
                    "exists": True,
                    "error": "Cutlist existiert bereits",
                    "cutlist": dest,
                },
                409,
            )
            return 0
        meta = payload.get("info") if isinstance(payload.get("info"), dict) else {}
        write_cutlist(
            dest,
            apply_to=apply_to,
            size_bytes=int(size_b),
            fps=fps,
            keeps=keeps,
            author=str(meta.get("Author") or cfg.author or ""),
            private=bool(it.get("private")),
            aspect=str(payload.get("aspect") or it.get("aspect") or ""),
            info=meta,
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
        elif orig.lower().endswith(".avi"):
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
    if action == "cutlist":
        it = item_for(cfg, qs.get("file") or "")
        if not it:
            _json({"ok": False, "error": "Datei nicht gefunden"}, 404)
            return 0
        cl = it.get("local_cutlist") or ""
        if not cl or not os.path.isfile(cl):
            _json({"ok": False, "error": "Keine lokale Cutlist gefunden"}, 404)
            return 0
        try:
            with open(cl, "r", encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError as exc:
            _json({"ok": False, "error": str(exc)}, 500)
            return 0
        fps_fb = float(it.get("fps") or 0) or 25.0
        state = editor_state_from_cutlist(text, fps_fb)
        if not state.get("keeps"):
            _json({"ok": False, "error": "Cutlist ohne Keep-Intervalle", "cutlist": cl}, 400)
            return 0
        _json({"ok": True, "cutlist": cl, **state})
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
        thumb_w = 160
        if action == "frame":
            dest = os.path.join(cache, "%s_w%s_%.3f.jpg" % (os.path.basename(path), thumb_w, t))
            got = extract_frame_jpeg(cfg.ffmpeg, path, dest, t, width=thumb_w)
            if not got:
                _json({"ok": False, "error": "Frame fehlgeschlagen"}, 500)
                return 0
            with open(got, "rb") as fh:
                _bin(fh.read(), "image/jpeg")
            return 0
        # strip: several frames around t
        try:
            span = int(qs.get("span") or "10")
        except ValueError:
            span = 10
        if span < 1:
            span = 1
        if span > 15:
            span = 15
        info = probe(cfg.ffprobe, path)
        fps = fps_from_probe(info) if "error" not in info else 25.0
        if fps <= 0:
            fps = 25.0
        jpegs = []
        for i in range(-span, span + 1):
            ti = t + (i / fps)
            if ti < 0:
                continue
            dest = os.path.join(cache, "%s_w%s_%.3f.jpg" % (os.path.basename(path), thumb_w, ti))
            if extract_frame_jpeg(cfg.ffmpeg, path, dest, ti, width=thumb_w):
                with open(dest, "rb") as fh:
                    import base64

                    jpegs.append({"t": ti, "i": i, "jpeg": base64.b64encode(fh.read()).decode("ascii")})
        _json({"ok": True, "fps": fps, "frames": jpegs})
        return 0
    if action == "keyframes":
        path = _play_file(cfg, qs.get("file") or "")
        if not path:
            _json({"ok": False, "error": "Medien-Datei fehlt"}, 404)
            return 0
        times = keyframe_times(cfg.ffprobe, path, timeout=120)
        _json({"ok": True, "keyframes": times})
        return 0
    if action == "purgecache":
        path = _play_file(cfg, qs.get("file") or "")
        cache = cfg.frame_cache_dir()
        n = 0
        if os.path.isdir(cache):
            prefix = os.path.basename(path) if path else ""
            try:
                names = os.listdir(cache)
            except OSError:
                names = []
            for name in names:
                if prefix and not name.startswith(prefix):
                    continue
                if not prefix and not name.lower().endswith(".jpg"):
                    continue
                fp = os.path.join(cache, name)
                if not os.path.isfile(fp):
                    continue
                try:
                    os.remove(fp)
                    n += 1
                except OSError:
                    pass
        _json({"ok": True, "removed": n})
        return 0
    if action == "remux":
        basename = qs.get("file") or ""
        try:
            payload = json.loads(_read_post().decode("utf-8") or "{}")
        except json.JSONDecodeError:
            payload = {}
        if payload.get("file"):
            basename = str(payload.get("file"))
        # Browser-GET: nicht in dieser CGI remuxen (Timeout → DSM-404 / nacktes JSON).
        if "text/html" in accept:
            loc = "index.cgi?page=cuteditor-remux&file=%s" % quote(os.path.basename(basename), safe="")
            html = (
                "<!DOCTYPE html><html><head><meta charset='utf-8'/>"
                "<meta http-equiv='refresh' content='0;url=%s'/></head>"
                "<body>Weiter zur Konvertierung. <a href='%s'>Weiter</a></body></html>"
                % (loc, loc)
            ).encode("utf-8")
            sys.stdout.buffer.write(b"Content-Type: text/html; charset=utf-8\r\n\r\n")
            sys.stdout.buffer.write(html)
            return 0
        it = item_for(cfg, os.path.basename(basename))
        if not it or it.get("source") != "otrkey":
            _json({"ok": False, "error": "Nur otrkey-AVI"}, 400)
            return 0
        ok, msg = remux_otrkey(cfg, it["path"], int(it.get("rowid") or 0))
        if not ok:
            _json({"ok": False, "error": msg}, 500)
            return 0
        _json({"ok": True, "mp4": msg})
        return 0
    if action == "editor":
        static_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static")
        html_path = os.path.join(static_dir, "editor.html")
        with open(html_path, "rb") as fh:
            sys.stdout.buffer.write(b"Content-Type: text/html; charset=utf-8\r\n")
            sys.stdout.buffer.write(b"Cache-Control: no-store, no-cache, must-revalidate\r\n\r\n")
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
            sys.stdout.buffer.write(("Content-Type: %s\r\n" % ctype).encode("ascii"))
            sys.stdout.buffer.write(b"Cache-Control: no-store\r\n")
            sys.stdout.buffer.write(("Content-Length: %s\r\n\r\n" % os.path.getsize(path)).encode("ascii"))
            sys.stdout.buffer.write(fh.read())
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
    if argv and argv[0] == "remux":
        basename = os.path.basename(argv[1] if len(argv) > 1 else "")
        it = item_for(cfg, basename)
        if not it or it.get("source") != "otrkey":
            sys.stderr.write("Nur otrkey-AVI\n")
            return 1
        ok, msg = remux_otrkey(cfg, it["path"], int(it.get("rowid") or 0))
        sys.stdout.write(msg + "\n")
        return 0 if ok else 1
    return dispatch_cgi(cfg)
