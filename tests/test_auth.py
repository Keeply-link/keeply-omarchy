#!/usr/bin/env python3
"""Tests for the Keeply OAuth helper PKCE generation."""

import hashlib
import base64
import os
import secrets
import socketserver
import threading
import urllib.error
import urllib.request
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader

# The security-critical bits (state/path validation) are imported from the
# real script rather than duplicated here, so a regression in the actual
# implementation can't hide behind a stale copy in the test.
_AUTH_SCRIPT = os.path.join(os.path.dirname(__file__), "..", "bin", "keeply-auth")
_loader = SourceFileLoader("keeply_auth", _AUTH_SCRIPT)
_spec = spec_from_loader("keeply_auth", _loader)
keeply_auth = module_from_spec(_spec)
_loader.exec_module(keeply_auth)


def generate_pkce_pair():
    """Generate PKCE code_verifier and code_challenge (S256)."""
    code_verifier = secrets.token_urlsafe(32)[:128]
    digest = hashlib.sha256(code_verifier.encode("ascii")).digest()
    code_challenge = base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")
    return code_verifier, code_challenge


def test_pkce_generation():
    """Test that PKCE generation produces valid verifier and challenge."""
    code_verifier, code_challenge = generate_pkce_pair()

    # Verifier should be a valid string
    assert isinstance(code_verifier, str)
    assert len(code_verifier) > 0
    assert len(code_verifier) <= 128

    # Challenge should be base64url encoded
    assert isinstance(code_challenge, str)
    assert len(code_challenge) > 0

    # Verify the challenge matches the verifier
    digest = hashlib.sha256(code_verifier.encode("ascii")).digest()
    expected = base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")
    assert code_challenge == expected, f"Challenge mismatch: {code_challenge} != {expected}"


def test_pkce_deterministic():
    """Test that PKCE challenge is deterministic from verifier."""
    for _ in range(10):
        verifier, challenge = generate_pkce_pair()
        digest = hashlib.sha256(verifier.encode("ascii")).digest()
        expected = base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")
        assert challenge == expected


def test_validate_state_accepts_matching():
    assert keeply_auth.validate_state("abc123", "abc123") is True


def test_validate_state_rejects_mismatch():
    assert keeply_auth.validate_state("attacker-state", "real-state") is False


def test_validate_state_rejects_missing():
    assert keeply_auth.validate_state(None, "real-state") is False
    assert keeply_auth.validate_state("", "real-state") is False


def test_is_callback_path():
    assert keeply_auth.is_callback_path("/callback") is True
    assert keeply_auth.is_callback_path("/") is False
    assert keeply_auth.is_callback_path("/favicon.ico") is False
    assert keeply_auth.is_callback_path("/callback/") is False


def test_oauth_handler_rejects_wrong_path():
    """A request to anything but /callback must 404 and must not be able
    to smuggle a code/state pair into the flow."""
    httpd = socketserver.TCPServer(("127.0.0.1", 0), keeply_auth.OAuthHandler)
    port = httpd.server_address[1]
    server_thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    server_thread.start()
    try:
        keeply_auth.OAuthHandler.code = None
        keeply_auth.OAuthHandler.state = None

        try:
            urllib.request.urlopen(f"http://127.0.0.1:{port}/not-callback?code=abc&state=xyz", timeout=2)
            status = 200
        except urllib.error.HTTPError as e:
            status = e.code

        assert status == 404
        assert keeply_auth.OAuthHandler.code is None
        assert keeply_auth.OAuthHandler.state is None
    finally:
        httpd.shutdown()
        httpd.server_close()


def test_oauth_handler_captures_code_and_state_on_callback():
    httpd = socketserver.TCPServer(("127.0.0.1", 0), keeply_auth.OAuthHandler)
    port = httpd.server_address[1]
    server_thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    server_thread.start()
    try:
        keeply_auth.OAuthHandler.code = None
        keeply_auth.OAuthHandler.state = None

        resp = urllib.request.urlopen(f"http://127.0.0.1:{port}/callback?code=real-code&state=real-state", timeout=2)

        assert resp.status == 200
        assert keeply_auth.OAuthHandler.code == "real-code"
        assert keeply_auth.OAuthHandler.state == "real-state"
    finally:
        httpd.shutdown()
        httpd.server_close()


def test_oauth_handler_escapes_error_description_in_html():
    # error_description is attacker-controlled: an authorize link can be
    # crafted with any value and sent to a victim, so it must never be
    # interpolated into the callback's HTML response unescaped.
    httpd = socketserver.TCPServer(("127.0.0.1", 0), keeply_auth.OAuthHandler)
    port = httpd.server_address[1]
    server_thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    server_thread.start()
    try:
        keeply_auth.OAuthHandler.error = None
        payload = "<script>alert(1)</script>"
        url = f"http://127.0.0.1:{port}/callback?" + urllib.parse.urlencode(
            {"error": "access_denied", "error_description": payload}
        )

        try:
            urllib.request.urlopen(url, timeout=2)
            assert False, "expected an HTTPError for the 400 response"
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8")

        assert "<script>alert(1)</script>" not in body
        assert "&lt;script&gt;" in body
        # The raw (unescaped) value is still what's reported internally —
        # only the HTML response is escaped, not the underlying error used
        # for the plugin's own plain-text error display.
        assert keeply_auth.OAuthHandler.error == payload
    finally:
        httpd.shutdown()
        httpd.server_close()


def test_oauth_handler_error_description_falls_back_to_error_code():
    httpd = socketserver.TCPServer(("127.0.0.1", 0), keeply_auth.OAuthHandler)
    port = httpd.server_address[1]
    server_thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    server_thread.start()
    try:
        keeply_auth.OAuthHandler.error = None
        url = f"http://127.0.0.1:{port}/callback?" + urllib.parse.urlencode({"error": "access_denied"})

        try:
            urllib.request.urlopen(url, timeout=2)
            assert False, "expected an HTTPError for the 400 response"
        except urllib.error.HTTPError:
            pass

        # Must be the plain string "access_denied", not a stringified list
        # like "['access_denied']" (a plain str() of parse_qs's list value).
        assert keeply_auth.OAuthHandler.error == "access_denied"
    finally:
        httpd.shutdown()
        httpd.server_close()


class _FakeResponse:
    """Mimics http.client.HTTPResponse's chunked .read(n) interface."""

    def __init__(self, data):
        self._remaining = data

    def read(self, amt):
        chunk = self._remaining[:amt]
        self._remaining = self._remaining[amt:]
        return chunk


def test_read_capped_returns_full_body_under_limit():
    body = b'{"accessToken": "abc123"}'
    result = keeply_auth.read_capped(_FakeResponse(body), 1024)
    assert result == body


def test_read_capped_allows_exactly_the_limit():
    body = b"x" * 1024
    result = keeply_auth.read_capped(_FakeResponse(body), 1024)
    assert result == body


def test_read_capped_rejects_one_byte_over_the_limit():
    body = b"x" * 1025
    try:
        keeply_auth.read_capped(_FakeResponse(body), 1024)
        assert False, "expected ValueError for oversized response"
    except ValueError:
        pass


def test_read_capped_rejects_body_larger_than_a_single_chunk():
    # A response much larger than one 65536-byte read must still be
    # rejected, not accepted just because the overflow spans chunks.
    body = b"x" * (200 * 1024)
    try:
        keeply_auth.read_capped(_FakeResponse(body), 1024)
        assert False, "expected ValueError for oversized response"
    except ValueError:
        pass


def test_oauth_handler_rejects_callback_missing_state():
    httpd = socketserver.TCPServer(("127.0.0.1", 0), keeply_auth.OAuthHandler)
    port = httpd.server_address[1]
    server_thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    server_thread.start()
    try:
        keeply_auth.OAuthHandler.code = None
        keeply_auth.OAuthHandler.state = None

        try:
            urllib.request.urlopen(f"http://127.0.0.1:{port}/callback?code=abc", timeout=2)
            status = 200
        except urllib.error.HTTPError as e:
            status = e.code

        assert status == 400
        assert keeply_auth.OAuthHandler.code is None
    finally:
        httpd.shutdown()
        httpd.server_close()


if __name__ == "__main__":
    test_pkce_generation()
    test_pkce_deterministic()
    test_validate_state_accepts_matching()
    test_validate_state_rejects_mismatch()
    test_validate_state_rejects_missing()
    test_is_callback_path()
    test_oauth_handler_rejects_wrong_path()
    test_oauth_handler_captures_code_and_state_on_callback()
    test_oauth_handler_escapes_error_description_in_html()
    test_oauth_handler_error_description_falls_back_to_error_code()
    test_read_capped_returns_full_body_under_limit()
    test_read_capped_allows_exactly_the_limit()
    test_read_capped_rejects_one_byte_over_the_limit()
    test_read_capped_rejects_body_larger_than_a_single_chunk()
    test_oauth_handler_rejects_callback_missing_state()
    print("All tests passed!")
