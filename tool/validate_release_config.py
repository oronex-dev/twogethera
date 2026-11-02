#!/usr/bin/env python3
"""Validate client-safe hosted settings without printing any configured value."""

import base64
import binascii
import json
import os
import sys
from ipaddress import ip_address
from urllib.parse import urlsplit


def valid_origin(value):
    try:
        uri = urlsplit(value)
        host = uri.hostname or ""
        port = uri.port
    except ValueError:
        return False
    if (
        uri.scheme != "https"
        or not host
        or uri.username is not None
        or uri.password is not None
        or port not in (None, 443)
        or uri.path not in ("", "/")
        or uri.query
        or uri.fragment
        or "." not in host
    ):
        return False
    try:
        ip_address(host)
        return False
    except ValueError:
        pass
    host = host.lower()
    return host not in ("localhost",) and not host.endswith((".invalid", ".test", ".example"))


def valid_key(value):
    if not value or value != value.strip() or any(char.isspace() for char in value):
        return False
    if value.startswith("sb_publishable_"):
        return len(value) >= 32
    if value.startswith("sb_secret_"):
        return False
    parts = value.split(".")
    if len(parts) != 3:
        return False
    try:
        payload = parts[1] + "=" * (-len(parts[1]) % 4)
        claims = json.loads(base64.urlsafe_b64decode(payload))
    except (ValueError, json.JSONDecodeError, binascii.Error):
        return False
    return isinstance(claims, dict) and claims.get("role") == "anon"


def fail():
    sys.stderr.write(
        "Release config is invalid. Use HTTPS origins and a Supabase publishable/anon key; values are not displayed.\n"
    )
    raise SystemExit(2)


env = os.environ
if env.get("APP_ENV", "production") not in ("staging", "production"):
    fail()
key = env.get("SUPABASE_PUBLISHABLE_KEY") or env.get("SUPABASE_ANON_KEY", "")
if not valid_origin(env.get("SUPABASE_URL", "")):
    fail()
if not valid_origin(env.get("APP_WEB_URL", "")):
    fail()
if not valid_key(key):
    fail()
sys.stdout.write("Hosted release configuration validated.\n")
