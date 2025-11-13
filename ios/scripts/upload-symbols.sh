#!/bin/sh
# Upload iOS dSYMs to Sentry using the CocoaPods-provided upload-symbols script.
# Requires environment variables: SENTRY_AUTH_TOKEN, SENTRY_ORG, SENTRY_PROJECT

set -euo pipefail

echo "[sentry] iOS dSYM upload phase"

if [ -z "${SENTRY_AUTH_TOKEN:-}" ] || [ -z "${SENTRY_ORG:-}" ] || [ -z "${SENTRY_PROJECT:-}" ]; then
  echo "[sentry] Missing Sentry env (SENTRY_AUTH_TOKEN/SENTRY_ORG/SENTRY_PROJECT); skipping upload"
  exit 0
fi

if [ -z "${DWARF_DSYM_FOLDER_PATH:-}" ] || [ -z "${DWARF_DSYM_FILE_NAME:-}" ]; then
  echo "[sentry] Not an Xcode archive/build context; skipping upload"
  exit 0
fi

UPLOAD_SYMBOLS_SCRIPT="${PODS_ROOT:-}/Sentry/upload-symbols"

if [ ! -x "$UPLOAD_SYMBOLS_SCRIPT" ]; then
  echo "[sentry] upload-symbols not found at $UPLOAD_SYMBOLS_SCRIPT"
  exit 0
fi

DSYM_PATH="${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}"
echo "[sentry] Uploading dSYM: $DSYM_PATH"

"$UPLOAD_SYMBOLS_SCRIPT" --no-retries \
  -o "$SENTRY_ORG" -p "$SENTRY_PROJECT" \
  -a "$SENTRY_AUTH_TOKEN" \
  "$DSYM_PATH"

echo "[sentry] dSYM upload completed"

