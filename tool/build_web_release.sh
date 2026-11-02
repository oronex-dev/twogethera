#!/usr/bin/env bash
set -euo pipefail

build_env="${APP_ENV:-production}"
if [[ "$build_env" != "production" && "$build_env" != "staging" ]]; then
  printf '%s\n' 'APP_ENV must be production or staging.' >&2
  exit 2
fi
: "${SUPABASE_URL:?Set the hosted Supabase project URL in the build environment.}"
: "${SUPABASE_PUBLISHABLE_KEY:=${SUPABASE_ANON_KEY:-}}"
: "${SUPABASE_PUBLISHABLE_KEY:?Set a Supabase publishable or legacy anon key.}"
: "${APP_WEB_URL:?Set the exact HTTPS web origin for this build.}"

python3 tool/validate_release_config.py

exec flutter build web --release --base-href / \
  --dart-define="APP_ENV=$build_env" \
  --dart-define="SUPABASE_URL=$SUPABASE_URL" \
  --dart-define="SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY" \
  --dart-define="APP_WEB_URL=$APP_WEB_URL"
