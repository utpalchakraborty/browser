#!/usr/bin/python3

import argparse
import base64
import html
import json
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse


class FixtureState:
    def __init__(self):
        self._lock = threading.Lock()
        self._request_counts = {}
        self._reload_count = 0
        self._recovery_port = None
        self._recovery_server = None
        self._recovery_enabled = False
        self._navigation_gates = {}

    def record(self, path):
        with self._lock:
            self._request_counts[path] = self._request_counts.get(path, 0) + 1

    def reset(self):
        with self._lock:
            self._request_counts = {}
            self._reload_count = 0
            navigation_gates = list(self._navigation_gates.values())
            self._navigation_gates = {}
        for navigation_gate in navigation_gates:
            navigation_gate.set()

    def reset_reload_count(self):
        with self._lock:
            self._reload_count = 0

    def next_reload_count(self):
        with self._lock:
            self._reload_count += 1
            return self._reload_count

    def snapshot(self):
        with self._lock:
            return dict(self._request_counts)

    def configure_recovery_port(self, port):
        with self._lock:
            self._recovery_port = port

    def enable_recovery_server(self):
        with self._lock:
            if self._recovery_port is None:
                return None
            if self._recovery_server is None:
                self._recovery_server = ThreadingHTTPServer(
                    ("127.0.0.1", self._recovery_port),
                    RecoveryHandler,
                )
                thread = threading.Thread(
                    target=self._recovery_server.serve_forever,
                    daemon=True,
                )
                thread.start()
            self._recovery_enabled = True
            return self._recovery_port

    def recovery_is_enabled(self):
        with self._lock:
            return self._recovery_enabled

    def wait_for_navigation_release(self, gate_id, timeout):
        with self._lock:
            navigation_gate = self._navigation_gates.setdefault(
                gate_id,
                threading.Event(),
            )
        return navigation_gate.wait(timeout=timeout)

    def release_navigation(self, gate_id):
        with self._lock:
            navigation_gate = self._navigation_gates.setdefault(
                gate_id,
                threading.Event(),
            )
        navigation_gate.set()


STATE = FixtureState()


class RecoveryHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        if not STATE.recovery_is_enabled():
            self.close_connection = True
            try:
                self.connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self.connection.close()
            return

        body = (
            "<!doctype html><title>Recovered</title>"
            "<body>Recovered after retry</body>"
        ).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format_string, *args):
        return


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
        elif path == "/phase2/page-a":
            self.send_html(
                "<!doctype html><title>Page A</title>"
                '<body><main id="page-a">Phase 2 Page A</main>'
                '<a href="/phase2/page-b">Go to Page B</a></body>'
            )
        elif path == "/phase2/page-b":
            self.send_html(
                "<!doctype html><title>Page B</title>"
                '<body><main id="page-b">Phase 2 Page B</main>'
                '<a href="/phase2/page-a">Go to Page A</a></body>'
            )
        elif path == "/phase2/redirect":
            self.send_bytes(
                b"",
                status=302,
                extra_headers=[("Location", "/phase2/page-b")],
            )
        elif path == "/phase2/reload-count":
            count = STATE.next_reload_count()
            self.send_html(
                f"<!doctype html><title>Reload {count}</title>"
                f"<body>Reload count {count}</body>"
            )
        elif path == "/phase2/reload-reset":
            STATE.reset_reload_count()
            self.send_json({"reload_count": 0})
        elif path == "/phase2/slow-response":
            self.send_slow_html()
        elif path == "/performance/scroll":
            rows = "".join(
                f"<section><h2>Scroll row {index}</h2>"
                "<p>Deterministic local scrolling content.</p></section>"
                for index in range(1, 161)
            )
            self.send_html(
                "<!doctype html><title>Scroll Performance</title>"
                "<style>"
                "body{font:16px system-ui;margin:0}"
                "header{position:sticky;top:0;background:#fff;padding:16px}"
                "section{height:120px;padding:16px;border-bottom:1px solid #ddd}"
                "</style>"
                "<header><h1>Controlled Scroll Fixture</h1>"
                "<p id=scroll-state>Scroll position top</p></header>"
                f"<main>{rows}</main>"
                "<script>"
                "const marker=document.getElementById('scroll-state');"
                "let moved=false;"
                "addEventListener('scroll',()=>{"
                "const next=scrollY>10;"
                "if(next!==moved){moved=next;marker.textContent=next?"
                "'Scroll position moved':'Scroll position top'}"
                "},{passive:true});"
                "</script>"
            )
        elif path.startswith("/privacy/navigation-gate/"):
            gate_path = path.removeprefix("/privacy/navigation-gate/")
            gate_components = gate_path.split("/")
            if len(gate_components) == 1 and gate_components[0]:
                gate_id = gate_components[0]
                if STATE.wait_for_navigation_release(gate_id, timeout=10):
                    try:
                        self.send_html(
                            "<!doctype html><title>Navigation Gate</title>"
                            "<body>Navigation gate released</body>"
                        )
                    except (BrokenPipeError, ConnectionResetError):
                        return
                else:
                    self.send_text("navigation gate timed out", status=504)
            elif (
                len(gate_components) == 2
                and gate_components[0]
                and gate_components[1] == "release"
            ):
                STATE.release_navigation(gate_components[0])
                self.send_json({"status": "released"})
            else:
                self.send_text("unknown navigation gate", status=404)
        elif path == "/phase2/recovery-enable":
            recovery_port = STATE.enable_recovery_server()
            if recovery_port is None:
                self.send_json(
                    {"error": "recovery port is not configured"},
                    status=409,
                )
            else:
                self.send_json(
                    {"recovery_origin": f"http://127.0.0.1:{recovery_port}"}
                )
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
        elif path == "/privacy/website-data":
            self.send_html(
                """<!doctype html>
<title>Privacy Website Data</title>
<body><main id="status">Website data preparing</main></body>
<script>
localStorage.setItem("phase4-local-storage", "present");
const request = indexedDB.open("phase4-indexed-db", 1);
const indexedDBReady = new Promise((resolve, reject) => {
    request.onupgradeneeded = () => request.result.createObjectStore("values");
    request.onsuccess = () => resolve(true);
    request.onerror = () => reject(request.error);
});
const cacheReady = caches.open("phase4-fetch-cache").then((cache) =>
    cache.add("/cache-resource")
);
const serviceWorkerReady = navigator.serviceWorker
    ? navigator.serviceWorker.register("/service-worker.js").then(() => true)
    : Promise.resolve(false);
window.storageReady = Promise.all([
    indexedDBReady,
    cacheReady,
    serviceWorkerReady,
]).then(() => {
    document.getElementById("status").textContent = "Website data ready";
    return true;
});
</script>""",
                extra_headers=[
                    (
                        "Set-Cookie",
                        "phase4persistent=privacy-value-sentinel; Path=/; "
                        "Max-Age=3600; SameSite=Lax; HttpOnly",
                    ),
                    (
                        "Set-Cookie",
                        "phase4session=session-value-sentinel; Path=/; "
                        "SameSite=Strict",
                    ),
                ],
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
        elif path == "/privacy/blocking/":
            self.send_html(
                """<!doctype html>
<title>Privacy Blocking</title>
<body>
<main>Privacy Blocking Fixture</main>
<p id="allowed-resource">First-party resource missing</p>
<p id="blocked-resource">Ad resource blocked</p>
<script src="/privacy/allowed.js"></script>
<script src="/privacy/blocked.js"></script>
<p>Blocking fixture complete</p>
</body>"""
            )
        elif path == "/privacy/allowed.js":
            self.send_javascript(
                "document.getElementById('allowed-resource').textContent = "
                "'First-party resource loaded';"
            )
        elif path == "/privacy/blocked.js":
            self.send_javascript(
                "document.getElementById('blocked-resource').textContent = "
                "'Ad resource loaded';"
            )
        elif path == "/privacy/production-blocking/":
            self.send_html(
                """<!doctype html>
<title>Production Privacy Blocking</title>
<body>
<script src="/privacy/production-allowed.js"></script>
<script src="/_xa/ads_probe.js"></script>
<script>window.productionBlockingFixtureComplete = true;</script>
</body>"""
            )
        elif path == "/privacy/production-allowed.js":
            self.send_javascript("window.productionAllowedLoaded = true;")
        elif path == "/_xa/ads_probe.js":
            self.send_javascript("window.productionAdLoaded = true;")
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
        elif path == "/privacy/popup-policy":
            self.send_html(
                """<!doctype html>
<title>Popup Policy</title>
<body>
<main>Popup Policy Fixture</main>
<a href="/privacy/blocking/?tab=background">Open Background Link</a>
<a href="/phase2/page-b" target="_blank">Open Direct Link</a>
<a id="scripted-anchor" href="/phase2/page-b?popup=scripted-anchor"
   target="_blank" hidden>Scripted Anchor Target</a>
<button onclick="window.open('/phase2/page-b?popup=button', '_blank')">
Try Scripted Popup
</button>
<button onclick="document.getElementById('scripted-anchor').click()">
Try Scripted Anchor
</button>
<form action="/phase2/page-b?popup=form" target="_blank">
<button type="submit">Try Targeted Form</button>
</form>
<script>
window.open('/phase2/page-b?popup=load', '_blank');
Promise.resolve().then(() => window.open('/phase2/page-b?popup=promise', '_blank'));
setTimeout(() => window.open('/phase2/page-b?popup=timer', '_blank'), 100);
</script>
</body>"""
            )
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

    def send_slow_html(self):
        self.close_connection = True
        chunks = [
            b"<!doctype html><title>Slow response</title><body>",
            b"<p>Slow response loading</p>",
        ]
        # Keep the final marker well beyond XCTest's UI-interaction overhead so
        # the Stop assertion cannot race a naturally completed response.
        chunks.extend(b"<span>bounded chunk</span>" for _ in range(40))
        chunks.append(b"<p>Slow response complete</p></body>")
        body_length = sum(len(chunk) for chunk in chunks)

        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        self.send_header("Content-Length", str(body_length))
        self.end_headers()

        try:
            for chunk in chunks:
                self.wfile.write(chunk)
                self.wfile.flush()
                time.sleep(0.25)
        except (BrokenPipeError, ConnectionResetError):
            # Stopping the WKWebView load deliberately closes this response.
            return

    def log_message(self, format_string, *args):
        return


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=18765)
    parser.add_argument("--token", required=True)
    parser.add_argument("--recovery-port", type=int)
    arguments = parser.parse_args()

    FixtureHandler.health_token = arguments.token
    if arguments.recovery_port is not None:
        STATE.configure_recovery_port(arguments.recovery_port)
    server = ThreadingHTTPServer(("127.0.0.1", arguments.port), FixtureHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()
