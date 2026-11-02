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
export PATH="$FLUTTER_ROOT/bin:$PATH"

if [[ "$(flutter --version --machine | python3 -c 'import json,sys; print(json.load(sys.stdin)["frameworkVersion"])')" != "$flutter_version" ]]; then
  printf '%s\n' 'Downloaded Flutter SDK version does not match the required version.' >&2
  exit 4
fi

flutter build web --release --base-href / \
  --dart-define="APP_ENV=$APP_ENV" \
  --dart-define="SUPABASE_URL=$SUPABASE_URL" \
  --dart-define="SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY" \
  --dart-define="APP_WEB_URL=$APP_WEB_URL"
