#!/usr/bin/env bash
# Codex 对话管家 · 一行命令安装 / one-line installer
#
#   curl -fsSL https://raw.githubusercontent.com/daYangjiao/codex-vault/main/scripts/quick-install.sh | bash
#
# 通过 curl 下载已编译好的 .app 压缩包（不会被打上 quarantine 隔离标记），解压装到「应用程序」后
# 自动打开，无需 Apple 开发者签名 / 公证，也无需 Xcode。
# Downloads a prebuilt .app zip via curl (no quarantine flag), installs into /Applications,
# and launches it — no Apple Developer signing / notarization and no Xcode required.
set -euo pipefail

REPO="daYangjiao/codex-vault"
APP_NAME="Codex 对话管家"
ASSET_URL="https://github.com/$REPO/releases/latest/download/Codex-Vault.app.zip"
TARGET="/Applications/$APP_NAME.app"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "仅支持 macOS / macOS only." >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

echo "下载安装包 / Downloading…"
curl -fL --progress-bar "$ASSET_URL" -o "$WORK_DIR/app.zip"

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
