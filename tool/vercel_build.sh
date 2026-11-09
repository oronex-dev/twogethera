#!/usr/bin/env bash
set -euo pipefail

flutter_version='3.47.7'
archive_name="flutter_linux_${flutter_version}-stable.tar.xz"
archive_url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${archive_name}"
archive_sha256='af7455f540df951184c7953fbe3cf884766e7541dacf8571f9f582db03dd6230'

if [[ "$(uname -s)" != 'Linux' ]]; then
  printf '%s\n' 'Vercel Flutter build requires the Linux build environment.' >&2
  exit 2
fi

: "${APP_ENV:?Set APP_ENV to staging or production in Vercel.}"
: "${SUPABASE_URL:?Set SUPABASE_URL in Vercel.}"
: "${SUPABASE_PROJECT_REF:?Set the approved Supabase project reference in Vercel.}"
: "${SUPABASE_PUBLISHABLE_KEY:?Set the client publishable key in Vercel.}"
: "${APP_WEB_URL:?Set the HTTPS app origin in Vercel.}"

if [[ "$APP_ENV" != 'staging' && "$APP_ENV" != 'production' ]]; then
  printf '%s\n' 'APP_ENV must be staging or production.' >&2
  exit 2
fi

python3 tool/validate_release_config.py

workspace="$(mktemp -d "${TMPDIR:-/tmp}/twogethera-flutter-${flutter_version}.XXXXXX")"
trap 'rm -rf "$workspace"' EXIT
archive="$workspace/$archive_name"

curl --fail --location --retry 3 --connect-timeout 20 --max-time 900 \
  --silent --show-error "$archive_url" --output "$archive"
printf '%s  %s\n' "$archive_sha256" "$archive" | sha256sum --check --status || {
  printf '%s\n' 'Flutter archive SHA-256 verification failed; extraction stopped.' >&2
  exit 3
}

tar -xJf "$archive" -C "$workspace"
export FLUTTER_ROOT="$workspace/flutter"
git config --global --add safe.directory "$FLUTTER_ROOT"
export PATH="$FLUTTER_ROOT/bin:$PATH"

version_stdout_file="$workspace/flutter-version.stdout"
version_stderr_file="$workspace/flutter-version.stderr"
version_command_status=0
if flutter --version --machine >"$version_stdout_file" 2>"$version_stderr_file"; then
  version_command_status=0
else
  version_command_status=$?
fi
version_output="$(cat "$version_stdout_file")"
version_error="$(cat "$version_stderr_file")"

if [[ "$version_command_status" -ne 0 ]]; then
  printf 'Flutter SDK version command failed with exit status %s. Actual command output:\n' \
    "$version_command_status" >&2
  if [[ -n "$version_output" ]]; then
    printf 'stdout:\n%s\n' "$version_output" >&2
  else
    printf 'stdout:\n%s\n' '[empty output]' >&2
  fi
  if [[ -n "$version_error" ]]; then
    printf 'stderr:\n%s\n' "$version_error" >&2
  else
    printf 'stderr:\n%s\n' '[empty output]' >&2
  fi
  exit 4
fi

actual_version=''
# Flutter can append its first-run analytics notice to the machine JSON on
# stdout. Locate the JSON object but retain both complete streams for errors.
if actual_version="$(python3 -c '
import json
import sys

output = sys.stdin.read()
decoder = json.JSONDecoder()
for offset, character in enumerate(output):
    if character != "{":
        continue
    try:
        payload, _ = decoder.raw_decode(output[offset:])
    except json.JSONDecodeError:
        continue
    version = payload.get("frameworkVersion") if isinstance(payload, dict) else None
    if isinstance(version, str):
        print(version)
        raise SystemExit(0)
raise SystemExit(1)
' <"$version_stdout_file" 2>/dev/null)"; then
  :
else
  parser_status=$?
  printf 'Flutter SDK version output was empty or invalid JSON (Flutter command exit status %s; JSON parser exit status %s). Actual command output:\n' \
    "$version_command_status" "$parser_status" >&2
  if [[ -n "$version_output" ]]; then
    printf 'stdout:\n%s\n' "$version_output" >&2
  else
    printf 'stdout:\n%s\n' '[empty output]' >&2
  fi
  if [[ -n "$version_error" ]]; then
    printf 'stderr:\n%s\n' "$version_error" >&2
  else
    printf 'stderr:\n%s\n' '[empty output]' >&2
  fi
  exit 4
fi

if [[ "$actual_version" != "$flutter_version" ]]; then
  printf 'Flutter SDK version mismatch: expected %s, received %s.\n' \
    "$flutter_version" "$actual_version" >&2
  exit 4
fi

flutter build web --release --base-href / \
  --dart-define="APP_ENV=$APP_ENV" \
  --dart-define="SUPABASE_URL=$SUPABASE_URL" \
  --dart-define="SUPABASE_PROJECT_REF=$SUPABASE_PROJECT_REF" \
  --dart-define="SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY" \
  --dart-define="APP_WEB_URL=$APP_WEB_URL"

# The beta does not support offline app data; the bootstrap unregisters any
# prior worker and new releases must not publish Flutter's offline precache map.
rm -f build/web/flutter_service_worker.js
