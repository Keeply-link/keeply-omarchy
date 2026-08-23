#!/usr/bin/env python3
"""Tests for the Keeply API helper (bin/keeply-api).

Runs against the real script's functions — including the real main(), with
stdin/stdout/exit code driven directly — rather than duplicating its logic
here. API_BASE is monkeypatched on the imported module for each test rather
than adding any test-only override hook to the script itself.
"""

import http.server
import io
import json
import os
import socketserver
import sys
import threading
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader

_API_SCRIPT = os.path.join(os.path.dirname(__file__), "..", "bin", "keeply-api")
_loader = SourceFileLoader("keeply_api", _API_SCRIPT)
_spec = spec_from_loader("keeply_api", _loader)
keeply_api = module_from_spec(_spec)
_loader.exec_module(keeply_api)


class _FakeResponse:
    """Mimics http.client.HTTPResponse's chunked .read(n) interface."""

    def __init__(self, data):
        self._remaining = data

    def read(self, amt):
        chunk = self._remaining[:amt]
        self._remaining = self._remaining[amt:]
        return chunk


def test_read_capped_returns_full_body_under_limit():
    body = b'{"data": []}'
    assert keeply_api.read_capped(_FakeResponse(body), 1024) == body


def test_read_capped_allows_exactly_the_limit():
    body = b"x" * 1024
    assert keeply_api.read_capped(_FakeResponse(body), 1024) == body


def test_read_capped_rejects_one_byte_over_the_limit():
    body = b"x" * 1025
    try:
        keeply_api.read_capped(_FakeResponse(body), 1024)
        assert False, "expected ValueError for oversized response"
    except ValueError:
        pass


def test_read_capped_rejects_body_larger_than_a_single_chunk():
    body = b"x" * (200 * 1024)
    try:
        keeply_api.read_capped(_FakeResponse(body), 1024)
        assert False, "expected ValueError for oversized response"
    except ValueError:
        pass


class _TestServer:
    """A local HTTP server whose behavior is controlled per-test via a
    handler function, so the real script can be exercised against real
    socket I/O rather than mocks."""

    def __init__(self, handler_fn):
        outer = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                outer.last_headers = dict(self.headers)
                handler_fn(self)

            def do_POST(self):
                length = int(self.headers.get("Content-Length", 0))
                outer.last_body = self.rfile.read(length)
                self.do_GET()

            def log_message(self, format, *args):
                pass

        self._httpd = socketserver.TCPServer(("127.0.0.1", 0), Handler)
        self.port = self._httpd.server_address[1]
        self.last_headers = None
        self.last_body = None

    def __enter__(self):
        self._thread = threading.Thread(target=self._httpd.serve_forever, daemon=True)
        self._thread.start()
        return self

    def __exit__(self, *exc):
        self._httpd.shutdown()
        self._httpd.server_close()


def _json_handler(status, payload):
    def handler(req):
        body = json.dumps(payload).encode("utf-8")
        req.send_response(status)
        req.send_header("Content-Type", "application/json")
        req.end_headers()
        req.wfile.write(body)

    return handler


def _with_local_base(server, fn):
    original_base = keeply_api.API_BASE
    keeply_api.API_BASE = f"http://127.0.0.1:{server.port}"
    try:
        return fn()
    finally:
        keeply_api.API_BASE = original_base


def test_make_request_success_returns_status_and_body():
    with _TestServer(_json_handler(200, {"data": [1, 2, 3]})) as server:
        status, body = _with_local_base(server, lambda: keeply_api.make_request("GET", "/bookmarks", "tok", None))
        assert status == 200
        assert json.loads(body) == {"data": [1, 2, 3]}
        assert server.last_headers["Authorization"] == "ApiKey tok"


def test_make_request_non_2xx_returns_status_with_empty_body():
    with _TestServer(_json_handler(404, {"message": "not found"})) as server:
        status, body = _with_local_base(server, lambda: keeply_api.make_request("GET", "/bookmarks/x", "tok", None))
        assert status == 404
        assert body == b""


def test_make_request_oversized_raises_value_error():
    huge_payload = {"data": "x" * (keeply_api.MAX_RESPONSE_BYTES + 1)}
    with _TestServer(_json_handler(200, huge_payload)) as server:
        def call():
            try:
                keeply_api.make_request("GET", "/bookmarks", "tok", None)
                assert False, "expected ValueError for oversized response"
            except ValueError:
                pass

        _with_local_base(server, call)


def _run_main(stdin_text):
    """Drive the real main() end to end: real stdin parsing, real request
    dispatch, real stdout/stderr/exit-code protocol."""
    old_stdin, old_stdout, old_stderr = sys.stdin, sys.stdout, sys.stderr
    sys.stdin = io.StringIO(stdin_text)
    sys.stdout = io.StringIO()
    sys.stderr = io.StringIO()
    exit_code = 0
    try:
        keeply_api.main()
    except SystemExit as e:
        exit_code = e.code if e.code is not None else 0
    finally:
        stdout_val = sys.stdout.getvalue()
        stderr_val = sys.stderr.getvalue()
        sys.stdin, sys.stdout, sys.stderr = old_stdin, old_stdout, old_stderr
    return exit_code, stdout_val, stderr_val


def test_end_to_end_success():
    with _TestServer(_json_handler(200, {"data": [{"id": 1}]})) as server:
        request_line = json.dumps({"method": "GET", "path": "/bookmarks", "token": "tok", "body": None}) + "\n"
        exit_code, stdout, stderr = _with_local_base(server, lambda: _run_main(request_line))
        assert exit_code == 0, stderr
        assert json.loads(stdout) == {"data": [{"id": 1}]}


def test_end_to_end_http_error():
    with _TestServer(_json_handler(404, {"message": "nope"})) as server:
        request_line = json.dumps({"method": "GET", "path": "/missing", "token": "tok", "body": None}) + "\n"
        exit_code, stdout, stderr = _with_local_base(server, lambda: _run_main(request_line))
        assert exit_code == 3
        assert stderr.strip() == "http_status:404"
        assert stdout == ""


def test_end_to_end_oversized():
    huge_payload = {"data": "x" * (keeply_api.MAX_RESPONSE_BYTES + 1)}
    with _TestServer(_json_handler(200, huge_payload)) as server:
        request_line = json.dumps({"method": "GET", "path": "/bookmarks", "token": "tok", "body": None}) + "\n"
        exit_code, stdout, stderr = _with_local_base(server, lambda: _run_main(request_line))
        assert exit_code == 2
        assert stderr.strip() == "Response too large"
        assert stdout == ""


def test_end_to_end_invalid_request_line():
    exit_code, stdout, stderr = _run_main("not valid json\n")
    assert exit_code == 4
    assert "Invalid request" in stderr
    assert stdout == ""


def test_end_to_end_post_body_is_forwarded():
    with _TestServer(_json_handler(200, {"ok": True})) as server:
        request_line = (
            json.dumps({"method": "POST", "path": "/bookmarks", "token": "tok", "body": {"url": "https://example.com"}})
            + "\n"
        )
        exit_code, stdout, stderr = _with_local_base(server, lambda: _run_main(request_line))
        assert exit_code == 0, stderr
        assert json.loads(stdout) == {"ok": True}
        assert json.loads(server.last_body) == {"url": "https://example.com"}


def test_end_to_end_non_json_response_is_reported():
    def handler(req):
        req.send_response(200)
        req.send_header("Content-Type", "text/html")
        req.end_headers()
        req.wfile.write(b"<html>not json</html>")

    with _TestServer(handler) as server:
        request_line = json.dumps({"method": "GET", "path": "/bookmarks", "token": "tok", "body": None}) + "\n"
        exit_code, stdout, stderr = _with_local_base(server, lambda: _run_main(request_line))
        assert exit_code == 4
        assert stderr.strip() == "Invalid response from server"
        assert stdout == ""


if __name__ == "__main__":
    test_read_capped_returns_full_body_under_limit()
    test_read_capped_allows_exactly_the_limit()
    test_read_capped_rejects_one_byte_over_the_limit()
    test_read_capped_rejects_body_larger_than_a_single_chunk()
    test_make_request_success_returns_status_and_body()
    test_make_request_non_2xx_returns_status_with_empty_body()
    test_make_request_oversized_raises_value_error()
    test_end_to_end_success()
    test_end_to_end_http_error()
    test_end_to_end_oversized()
    test_end_to_end_invalid_request_line()
    test_end_to_end_post_body_is_forwarded()
    test_end_to_end_non_json_response_is_reported()
    print("All tests passed!")
