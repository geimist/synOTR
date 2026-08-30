"""stdlib HTTP server for Docker / local use."""
from __future__ import annotations

import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Dict
from urllib.parse import parse_qs, urlparse

from synotr_cuteditor.paths import CutEditorConfig


def serve(cfg: CutEditorConfig, host: str = "127.0.0.1", port: int = 8765) -> None:
    static_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static")

    class Handler(BaseHTTPRequestHandler):
        def _send(self, code: int, body: bytes, ctype: str, extra=None) -> None:
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            if extra:
                for k, v in extra.items():
                    self.send_header(k, v)
            self.end_headers()
            self.wfile.write(body)

        def _json(self, code: int, data: Any) -> None:
            body = json.dumps(data, ensure_ascii=False).encode("utf-8")
            self._send(code, body, "application/json; charset=utf-8")

        def do_GET(self) -> None:  # noqa: N802
            u = urlparse(self.path)
            qs = {k: (v[-1] if v else "") for k, v in parse_qs(u.query).items()}
            os.environ["QUERY_STRING"] = u.query
            os.environ["REQUEST_METHOD"] = "GET"
            os.environ.pop("HTTP_RANGE", None)
            rng = self.headers.get("Range")
            if rng:
                os.environ["HTTP_RANGE"] = rng
            if u.path in ("/", "/editor"):
                path = os.path.join(static_dir, "editor.html")
                with open(path, "rb") as fh:
                    self._send(200, fh.read(), "text/html; charset=utf-8")
                return
            if u.path.startswith("/static/"):
                name = os.path.basename(u.path)
                path = os.path.join(static_dir, name)
                if os.path.isfile(path):
                    ctype = "application/octet-stream"
                    if name.endswith(".css"):
                        ctype = "text/css"
                    elif name.endswith(".js"):
                        ctype = "application/javascript"
                    with open(path, "rb") as fh:
                        self._send(200, fh.read(), ctype)
                    return
            # map REST-ish to CGI actions
            mapping = {
                "/api/waiting": "list",
                "/api/item": "item",
                "/media": "media",
                "/frame": "frame",
                "/strip": "strip",
            }
            action = mapping.get(u.path)
            if action:
                os.environ["QUERY_STRING"] = "action=%s&%s" % (action, u.query)
                from synotr_cuteditor import cli as cmod

                # capture by replacing stdout? easier to call internals
                if action == "list":
                    from synotr_cuteditor.waiting import list_waiting

                    self._json(200, {"ok": True, "queue": cfg.queue, "items": list_waiting(cfg)})
                    return
                if action == "media":
                    from synotr_cuteditor.cli import _play_file, send_media_range
                    import sys

                    path = _play_file(cfg, qs.get("file") or "")
                    if not path:
                        self._json(404, {"ok": False})
                        return
                    # reuse send_media_range via wrapping wfile is hard; stream here
                    size = os.path.getsize(path)
                    start, end, status = 0, size - 1, 200
                    rng = self.headers.get("Range")
                    if rng and rng.startswith("bytes="):
                        spec = rng[6:].split(",")[0]
                        a, _, b = spec.partition("-")
                        try:
                            if a:
                                start = int(a)
                            if b:
                                end = int(b)
                            status = 206
                        except ValueError:
                            pass
                    length = end - start + 1
                    self.send_response(status)
                    self.send_header("Content-Type", "video/mp4")
                    self.send_header("Accept-Ranges", "bytes")
                    if status == 206:
                        self.send_header("Content-Range", "bytes %s-%s/%s" % (start, end, size))
                    self.send_header("Content-Length", str(length))
                    self.end_headers()
                    with open(path, "rb") as fh:
                        fh.seek(start)
                        left = length
                        while left > 0:
                            chunk = fh.read(min(256 * 1024, left))
                            if not chunk:
                                break
                            self.wfile.write(chunk)
                            left -= len(chunk)
                    return
                os.environ["QUERY_STRING"] = "action=%s&%s" % (action, u.query)
                from io import BytesIO
                import sys as _sys
                from synotr_cuteditor.cli import dispatch_cgi

                buf = BytesIO()
                old = _sys.stdout
                class W:
                    buffer = buf
                _sys.stdout = W()  # type: ignore
                try:
                    dispatch_cgi(cfg)
                finally:
                    _sys.stdout = old
                raw = buf.getvalue()
                head, _, body = raw.partition(b"\r\n\r\n")
                status = 200
                ctype = "application/octet-stream"
                extra: Dict[str, str] = {}
                for line in head.decode("latin1", "replace").split("\r\n"):
                    if line.lower().startswith("status:"):
                        try:
                            status = int(line.split(":", 1)[1].strip().split()[0])
                        except ValueError:
                            pass
                    elif line.lower().startswith("content-type:"):
                        ctype = line.split(":", 1)[1].strip()
                    elif ":" in line and not line.lower().startswith("content-length"):
                        k, v = line.split(":", 1)
                        extra[k.strip()] = v.strip()
                self._send(status, body, ctype, extra)
                return
            self._json(404, {"ok": False})

        def do_POST(self) -> None:  # noqa: N802
            u = urlparse(self.path)
            n = int(self.headers.get("Content-Length") or "0")
            body = self.rfile.read(n) if n else b""
            os.environ["CONTENT_LENGTH"] = str(len(body))
            os.environ["REQUEST_METHOD"] = "POST"
            action = "save" if u.path == "/api/cutlist" else ""
            if u.path == "/api/remux":
                action = "remux"
            if not action:
                self._json(404, {"ok": False})
                return
            os.environ["QUERY_STRING"] = "action=%s&%s" % (action, u.query)
            from io import BytesIO
            import sys as _sys
            from synotr_cuteditor.cli import dispatch_cgi

            oldin = _sys.stdin
            class R:
                buffer = BytesIO(body)
                def read(self, n=-1):
                    return body
            _sys.stdin = R()  # type: ignore
            buf = BytesIO()
            old = _sys.stdout
            class W:
                buffer = buf
            _sys.stdout = W()  # type: ignore
            try:
                dispatch_cgi(cfg)
            finally:
                _sys.stdout = old
                _sys.stdin = oldin
            raw = buf.getvalue()
            head, _, b2 = raw.partition(b"\r\n\r\n")
            status = 200
            ctype = "application/json; charset=utf-8"
            for line in head.decode("latin1", "replace").split("\r\n"):
                if line.lower().startswith("status:"):
                    try:
                        status = int(line.split(":", 1)[1].strip().split()[0])
                    except ValueError:
                        pass
                elif line.lower().startswith("content-type:"):
                    ctype = line.split(":", 1)[1].strip()
            self._send(status, b2, ctype)

        def log_message(self, fmt: str, *args: Any) -> None:
            return

    httpd = ThreadingHTTPServer((host, port), Handler)
    httpd.serve_forever()
