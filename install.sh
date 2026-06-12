#!/bin/bash
set -eu

# Standalone installer. Also used by install-with-tetra.sh in the sten repo,
# which sets APP_NAME / APP_REPO / APP_OPEN env vars to install either app.
APP_NAME="${APP_NAME:-Tetra}"
APP_REPO="${APP_REPO:-vladstudio/tetra}"
APP_OPEN="${APP_OPEN:-1}"
APP_PATH="/Applications/$APP_NAME.app"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

URL="https://github.com/$APP_REPO/releases/latest/download/$APP_NAME.zip"
echo "↓ Downloading $APP_NAME"
if ! curl -fsSL "$URL" -o "$TMP/$APP_NAME.zip"; then
  echo "✗ Download failed: $URL" >&2
  echo "  Check that a release has been published and the repo name is correct." >&2
  exit 1
fi

echo "Extracting"
ditto -xk "$TMP/$APP_NAME.zip" "$TMP"
if [ ! -d "$TMP/$APP_NAME.app" ]; then
  echo "✗ Archive did not contain $APP_NAME.app" >&2
  exit 1
fi

if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
  echo "Closing running $APP_NAME"
  pkill -x "$APP_NAME"
  sleep 1
fi

[ -w /Applications ] && SUDO= || SUDO=sudo
$SUDO rm -rf "$APP_PATH"
$SUDO ditto "$TMP/$APP_NAME.app" "$APP_PATH"

if [ "$APP_OPEN" = "1" ]; then
  open "$APP_PATH"
fi
echo "✓ $APP_NAME installed"
