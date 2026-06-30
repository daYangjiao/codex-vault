#!/usr/bin/env bash
# Codex 对话管家 · 一行命令安装 / one-line installer
#
#   curl -fsSL https://raw.githubusercontent.com/daYangjiao/codex-vault/main/scripts/quick-install.sh | bash
#
# 下载预编译 .app 压缩包并安装到「应用程序」，装完自动打开。
# Download the prebuilt .app zip, install into /Applications, and launch it.
set -euo pipefail

REPO="daYangjiao/codex-vault"
APP_NAME="Codex 对话管家"
ASSET_URL="${CODEX_VAULT_ASSET_URL:-https://github.com/$REPO/releases/latest/download/Codex-Vault.app.zip}"
TARGET="/Applications/$APP_NAME.app"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "仅支持 macOS / macOS only." >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

echo "下载安装包 / Downloading…"
if ! curl -fL --progress-bar "$ASSET_URL" -o "$WORK_DIR/app.zip"; then
  echo "下载失败：请确认 GitHub 最新 Release 已上传 Codex-Vault.app.zip。" >&2
  echo "Download failed: make sure the latest GitHub Release includes Codex-Vault.app.zip." >&2
  exit 1
fi

echo "解压 / Extracting…"
ditto -x -k "$WORK_DIR/app.zip" "$WORK_DIR/out"
APP_SRC="$WORK_DIR/out/$APP_NAME.app"
if [[ ! -d "$APP_SRC" ]]; then
  echo "压缩包中未找到 $APP_NAME.app / app not found in archive." >&2
  exit 1
fi

echo "安装到「应用程序」/ Installing into /Applications…"
[[ -d "$TARGET" ]] && rm -rf "$TARGET"
ditto --noextattr --noqtn "$APP_SRC" "$TARGET"
xattr -cr "$TARGET" 2>/dev/null || true

echo "完成，正在打开 / Done, launching…"
open "$TARGET"
echo "已安装并打开：$TARGET"
echo "Installed and launched: $TARGET"
