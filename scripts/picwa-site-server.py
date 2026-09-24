#!/usr/bin/env python3
"""Serve Picwa's small public site without a third-party web framework."""

from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SITE_ROOT = PROJECT_ROOT / "docs" / "site"
PRIVACY_PAGE = PROJECT_ROOT / "docs" / "privacy-policy.html"
PRIVACY_PAGE_EN = SITE_ROOT / "en" / "privacy" / "index.html"


class PicwaHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(SITE_ROOT), **kwargs)

    def do_GET(self):  # noqa: N802 - required by BaseHTTPRequestHandler
        path = urlsplit(self.path).path.rstrip("/") or "/"
        if path == "/privacy":
            self._serve_file(PRIVACY_PAGE_EN)
            return
        if path == "/zh/privacy":
            self._serve_file(PRIVACY_PAGE)
            return
        if path == "/support":
            self.path = "/en/support/index.html"
            super().do_GET()
            return
        if path == "/zh/support":
            self.path = "/zh/support/index.html"
            super().do_GET()
            return
        if path == "/zh":
            self.path = "/zh/index.html"
            super().do_GET()
            return
        super().do_GET()

    def _serve_file(self, path: Path):
        if not path.is_file():
            self.send_error(404)
            return
        body = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    host = "127.0.0.1"
    port = 3020
    server = ThreadingHTTPServer((host, port), PicwaHandler)
    print(f"Picwa site listening on http://{host}:{port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
