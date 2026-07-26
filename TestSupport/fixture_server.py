#!/usr/bin/python3

import argparse
import base64
import html
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse


class FixtureState:
    def __init__(self):
        self._lock = threading.Lock()
        self._request_counts = {}

    def record(self, path):
        with self._lock:
            self._request_counts[path] = self._request_counts.get(path, 0) + 1

    def reset(self):
        with self._lock:
            self._request_counts = {}

    def snapshot(self):
        with self._lock:
            return dict(self._request_counts)


STATE = FixtureState()


class FixtureHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    health_token = None

    def do_GET(self):
        parsed_url = urlparse(self.path)
        path = parsed_url.path
        STATE.record(path)

        if path == "/health":
            supplied_token = parse_qs(parsed_url.query).get("token", [None])[0]
            if supplied_token == self.health_token:
                self.send_text("ok")
            else:
                self.send_text("fixture token mismatch", status=409)
        elif path == "/reset":
            STATE.reset()
            self.send_json({"status": "reset"})
        elif path == "/stats":
            self.send_json(STATE.snapshot())
        elif path == "/cookie/set":
            self.send_html(
                "<!doctype html><title>cookie set</title><body>cookie set</body>",
                extra_headers=[
                    (
                        "Set-Cookie",
                        "phase1=persisted; Path=/; Max-Age=3600; "
                        "SameSite=Lax; HttpOnly",
                    ),
                    (
                        "Set-Cookie",
                        "phase1session=transient; Path=/; SameSite=Strict",
                    ),
                ],
            )
        elif path == "/cookie/echo":
            cookie_header = html.escape(self.headers.get("Cookie", ""))
            self.send_html(
                "<!doctype html><title>cookie echo</title>"
                f"<body>{cookie_header}</body>"
            )
        elif path == "/storage":
            self.send_html(
                """<!doctype html>
<title>storage fixture</title>
<body>storage</body>
<script>
localStorage.setItem("phase1-local-storage", "present");
const request = indexedDB.open("phase1-indexed-db", 1);
const indexedDBReady = new Promise((resolve, reject) => {
    request.onupgradeneeded = () => request.result.createObjectStore("values");
    request.onsuccess = () => resolve(true);
    request.onerror = () => reject(request.error);
});
const cacheReady = caches.open("phase1-fetch-cache").then((cache) =>
    cache.add("/cache-resource")
);
const serviceWorkerReady = navigator.serviceWorker
    ? navigator.serviceWorker.register("/service-worker.js").then(() => true)
    : Promise.resolve(false);
window.storageReady = Promise.all([
    indexedDBReady,
    cacheReady,
    serviceWorkerReady,
]);
</script>"""
            )
        elif path == "/cache-resource":
            self.send_text("cacheable fixture")
        elif path == "/service-worker.js":
            self.send_javascript(
                "self.addEventListener('fetch', () => {});",
                extra_headers=[("Service-Worker-Allowed", "/")],
            )
        elif path in ("/normal/", "/exception/"):
            self.send_html(
                """<!doctype html>
<title>blocking fixture</title>
<body>blocking fixture</body>
<script src="/assets/blocked.js"></script>
<script>window.fixtureReady = true;</script>"""
            )
        elif path == "/assets/blocked.js":
            self.send_javascript("window.blockedLoaded = true;")
        elif path == "/popup":
            self.send_html(
                """<!doctype html>
	<title>popup fixture</title>
	<a id="popup" href="/popup-target" target="_blank">open</a>"""
            )
        elif path == "/window-open":
            self.send_html(
                """<!doctype html>
<title>window open fixture</title>
<button id="window-open" onclick="window.open('/popup-target', '_blank')">
open
</button>"""
            )
        elif path == "/popup-target":
            self.send_html("<!doctype html><title>popup target</title><body>popup</body>")
        elif path == "/download":
            self.send_bytes(
                b"phase1-download",
                content_type="application/octet-stream",
                extra_headers=[
                    ("Content-Disposition", 'attachment; filename="phase1.bin"')
                ],
            )
        elif path == "/auth":
            expected = "Basic " + base64.b64encode(b"phase1:browser").decode("ascii")
            if self.headers.get("Authorization") != expected:
                self.send_bytes(
                    b"authentication required",
                    status=401,
                    content_type="text/plain; charset=utf-8",
                    extra_headers=[("WWW-Authenticate", 'Basic realm="phase1"')],
                )
            else:
                self.send_html(
                    "<!doctype html><title>authenticated</title><body>authenticated</body>"
                )
        elif path == "/redirect-loop":
            self.send_bytes(
                b"",
                status=302,
                extra_headers=[("Location", "/redirect-loop")],
            )
        else:
            self.send_bytes(
                b"not found",
                status=404,
                content_type="text/plain; charset=utf-8",
            )

    def send_html(self, body, status=200, extra_headers=None):
        self.send_bytes(
            body.encode("utf-8"),
            status=status,
            content_type="text/html; charset=utf-8",
            extra_headers=extra_headers,
        )

    def send_text(self, body, status=200, extra_headers=None):
        self.send_bytes(
            body.encode("utf-8"),
            status=status,
            content_type="text/plain; charset=utf-8",
            extra_headers=extra_headers,
        )

    def send_javascript(self, body, status=200, extra_headers=None):
        self.send_bytes(
            body.encode("utf-8"),
            status=status,
            content_type="application/javascript; charset=utf-8",
            extra_headers=extra_headers,
        )

    def send_json(self, value, status=200, extra_headers=None):
        self.send_bytes(
            json.dumps(value, sort_keys=True).encode("utf-8"),
            status=status,
            content_type="application/json; charset=utf-8",
            extra_headers=extra_headers,
        )

    def send_bytes(self, body, status=200, content_type=None, extra_headers=None):
        self.send_response(status)
        if content_type:
            self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        for name, value in extra_headers or []:
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format_string, *args):
        return


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=18765)
    parser.add_argument("--token", required=True)
    arguments = parser.parse_args()

    FixtureHandler.health_token = arguments.token
    server = ThreadingHTTPServer(("127.0.0.1", arguments.port), FixtureHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()
