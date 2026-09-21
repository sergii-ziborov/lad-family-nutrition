"""Loopback-only pilot API for private Lad recipes. No private content lives in this repo."""

from __future__ import annotations

import hashlib
import hmac
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

MAX_CATALOG_BYTES = 2_000_000


def make_server(host: str, port: int, token_sha256: str, catalog_path: Path) -> ThreadingHTTPServer:
    if host not in {"127.0.0.1", "::1"}:
        raise ValueError("The recipe API must listen only on loopback behind HTTPS")
    if len(token_sha256) != 64 or any(char not in "0123456789abcdef" for char in token_sha256):
        raise ValueError("LAD_TOKEN_SHA256 must be a lowercase SHA-256 hex digest")
    if not catalog_path.is_absolute():
        raise ValueError("LAD_PRIVATE_RECIPES_FILE must be an absolute path outside the repo")

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            if self.path == "/healthz":
                self._reply(200, b"ok", "text/plain; charset=utf-8")
                return
            if self.path != "/v1/recipes":
                self._reply(404, b"not found", "text/plain; charset=utf-8")
                return
            auth = self.headers.get("Authorization", "")
            if not auth.startswith("Bearer ") or len(auth) > 256:
                self._reply(401, b"unauthorized", "text/plain; charset=utf-8")
                return
            supplied = hashlib.sha256(auth.removeprefix("Bearer ").encode("utf-8")).hexdigest()
            if not hmac.compare_digest(supplied, token_sha256):
                self._reply(401, b"unauthorized", "text/plain; charset=utf-8")
                return
            try:
                if catalog_path.stat().st_size > MAX_CATALOG_BYTES:
                    raise ValueError("catalog too large")
                body = catalog_path.read_bytes()
                if len(body) > MAX_CATALOG_BYTES:
                    raise ValueError("catalog too large")
                parsed = json.loads(body)
                if not isinstance(parsed, dict) or not isinstance(parsed.get("recipes"), list):
                    raise ValueError("invalid catalog")
            except (OSError, ValueError, UnicodeError):
                self._reply(503, b"catalog unavailable", "text/plain; charset=utf-8")
                return
            self._reply(200, body, "application/json; charset=utf-8")

        def do_POST(self) -> None:
            self._reply(405, b"method not allowed", "text/plain; charset=utf-8")

        def _reply(self, status: int, body: bytes, content_type: str) -> None:
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format: str, *args: object) -> None:
            # Never log bearer credentials or a private recipe body.
            return

    return ThreadingHTTPServer((host, port), Handler)


def main() -> None:
    token_hash = os.environ["LAD_TOKEN_SHA256"]
    catalog = Path(os.environ["LAD_PRIVATE_RECIPES_FILE"])
    port = int(os.environ.get("LAD_PORT", "9823"))
    server = make_server("127.0.0.1", port, token_hash, catalog)
    server.serve_forever(poll_interval=0.5)


if __name__ == "__main__":
    main()
