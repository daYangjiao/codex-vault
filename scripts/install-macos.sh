#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Codex 对话管家"
SOURCE_APP="$ROOT_DIR/dist/$APP_NAME.app"
TARGET_APP="/Applications/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -d "$SOURCE_APP" ]]; then
  "$ROOT_DIR/scripts/package-macos.sh" >/dev/null
fi

if [[ -d "$TARGET_APP" ]]; then
  rm -rf "$TARGET_APP"
fi

ditto --noextattr --noqtn "$SOURCE_APP" "$TARGET_APP"
xattr -cr "$TARGET_APP" 2>/dev/null || true
touch "$TARGET_APP"

if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -u "$TARGET_APP" 2>/dev/null || true
  "$LSREGISTER" -u "$ROOT_DIR/dist/Codex Vault.app" 2>/dev/null || true
  "$LSREGISTER" -u "$ROOT_DIR/dist/staging/Codex Vault.app" 2>/dev/null || true
  "$LSREGISTER" -f "$TARGET_APP"
fi

mdimport -i "$TARGET_APP" 2>/dev/null || true

echo "$TARGET_APP"
