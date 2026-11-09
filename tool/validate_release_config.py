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


def valid_project_ref(value):
    return isinstance(value, str) and len(value) == 20 and all(
        char in "abcdefghijklmnopqrstuvwxyz0123456789" for char in value
    )


def project_url_matches_ref(url, project_ref):
    if not valid_project_ref(project_ref):
        return False
    try:
        uri = urlsplit(url)
        host = uri.hostname or ""
        port = uri.port
    except (TypeError, ValueError):
        return False
    return (
        uri.scheme == "https"
        and host.lower() == f"{project_ref}.supabase.co"
        and uri.username is None
        and uri.password is None
        and port in (None, 443)
        and uri.path in ("", "/")
        and not uri.query
        and not uri.fragment
    )


def valid_configuration(env):
    key = env.get("SUPABASE_PUBLISHABLE_KEY") or env.get("SUPABASE_ANON_KEY", "")
    return (
        env.get("APP_ENV", "production") in ("staging", "production")
        and valid_project_ref(env.get("SUPABASE_PROJECT_REF", ""))
        and project_url_matches_ref(
            env.get("SUPABASE_URL", ""), env.get("SUPABASE_PROJECT_REF", "")
        )
        and valid_origin(env.get("SUPABASE_URL", ""))
        and valid_origin(env.get("APP_WEB_URL", ""))
        and valid_key(key)
    )


def fail():
    sys.stderr.write(
        "Release config is invalid. Set the environment, matching Supabase project reference and URL, HTTPS app origin, and client publishable/anon key; values are not displayed.\n"
    )
    raise SystemExit(2)


def main():
    if not valid_configuration(os.environ):
        fail()
    sys.stdout.write("Hosted release configuration validated.\n")


if __name__ == "__main__":
    main()
