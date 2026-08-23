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
    test_oauth_handler_rejects_callback_missing_state()
    print("All tests passed!")
