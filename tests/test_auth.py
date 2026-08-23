#!/usr/bin/env python3
"""Tests for the Keeply OAuth helper PKCE generation."""

import hashlib
import base64
import secrets


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


if __name__ == "__main__":
    test_pkce_generation()
    test_pkce_deterministic()
    print("All tests passed!")
