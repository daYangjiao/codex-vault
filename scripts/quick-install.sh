#!/usr/bin/env bash
# Codex 对话管家 · 一行命令安装 / one-line installer
#
#   curl -fsSL https://raw.githubusercontent.com/daYangjiao/codex-vault/main/scripts/quick-install.sh | bash
#
# 从源码构建并安装到「应用程序」，装完自动打开。
# 本地构建的程序没有 quarantine 隔离标记，可直接打开，无需 Apple 签名 / 公证。
# Builds from source, installs into /Applications, and launches it. Locally built
# binaries carry no quarantine flag, so the app opens cleanly — no Apple signing needed.
set -euo pipefail

REPO_URL="https://github.com/daYangjiao/codex-vault.git"
APP_NAME="Codex 对话管家"
TARGET="/Applications/$APP_NAME.app"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "仅支持 macOS / macOS only." >&2
  exit 1
fi

# 需要 Swift 工具链（Xcode 命令行工具）
if ! command -v swift >/dev/null 2>&1; then
  echo "需要先安装 Xcode 命令行工具 / Xcode Command Line Tools required." >&2
  echo "请运行 / run:  xcode-select --install" >&2
  echo "装好后再重新执行本命令 / then re-run this command." >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

echo "下载源码 / Cloning…"
git clone --depth 1 "$REPO_URL" "$WORK_DIR/src" >/dev/null 2>&1
cd "$WORK_DIR/src"

echo "构建中（首次约需 1-2 分钟）/ Building (1-2 min on first run)…"
./scripts/package-macos.sh >/dev/null

BUILT_APP="dist/$APP_NAME.app"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "构建失败：未生成应用 / build failed: app not produced." >&2
  exit 1
fi

echo "安装到「应用程序」/ Installing into /Applications…"
[[ -d "$TARGET" ]] && rm -rf "$TARGET"
ditto --noextattr --noqtn "$BUILT_APP" "$TARGET"
xattr -cr "$TARGET" 2>/dev/null || true

echo "完成，正在打开 / Done, launching…"
open "$TARGET"
echo "已安装并打开：$TARGET"
echo "Installed and launched: $TARGET"
