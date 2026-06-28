#!/usr/bin/env bash
# Codex 对话管家 · 一行命令安装 / one-line installer
#
#   curl -fsSL https://raw.githubusercontent.com/daYangjiao/codex-vault/main/scripts/quick-install.sh | bash
#
# 通过 curl 下载 DMG（不会被打上 quarantine 隔离标记），装到「应用程序」后可直接打开，
# 无需 Apple 开发者签名 / 公证。
# Downloads the DMG via curl (no quarantine flag), installs into /Applications, and
# opens cleanly — no Apple Developer signing / notarization required.
set -euo pipefail

REPO="daYangjiao/codex-vault"
APP_NAME="Codex 对话管家"
DMG_URL="https://github.com/$REPO/releases/latest/download/Codex-Vault.dmg"
TARGET="/Applications/$APP_NAME.app"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "仅支持 macOS / macOS only." >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
DMG_PATH="$WORK_DIR/Codex-Vault.dmg"
MOUNT_POINT=""

cleanup() {
  [[ -n "$MOUNT_POINT" ]] && hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo "下载安装包 / Downloading…"
curl -fL --progress-bar "$DMG_URL" -o "$DMG_PATH"

echo "挂载 DMG / Mounting…"
MOUNT_POINT="$(hdiutil attach "$DMG_PATH" -nobrowse -noverify -readonly | grep -o '/Volumes/.*' | head -1)"
if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT/$APP_NAME.app" ]]; then
  echo "在 DMG 中未找到 $APP_NAME.app / app not found in DMG." >&2
  exit 1
fi

echo "安装到「应用程序」/ Installing into /Applications…"
[[ -d "$TARGET" ]] && rm -rf "$TARGET"
ditto --noextattr --noqtn "$MOUNT_POINT/$APP_NAME.app" "$TARGET"
xattr -cr "$TARGET" 2>/dev/null || true

echo "完成，正在打开 / Done, launching…"
open "$TARGET"
echo "$TARGET"
