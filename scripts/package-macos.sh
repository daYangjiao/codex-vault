#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="Codex 对话管家"
WORK_DIR="$(mktemp -d /tmp/codex-vault-package.XXXXXX)"
STAGING_DIR="$WORK_DIR/staging"
BUILD_APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$BUILD_APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE="$ROOT_DIR/.build/release/CodexVault"
ICON_FILE="$ROOT_DIR/Assets/AppIcon/CodexVault.icns"
DMG_PATH="$DIST_DIR/Codex-Vault.dmg"
TEMP_DMG_PATH="$WORK_DIR/Codex-Vault.dmg"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cd "$ROOT_DIR"

swift build -c release --product CodexVault

rm -rf "$APP_BUNDLE" "$DMG_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE" "$MACOS_DIR/CodexVault"
chmod +x "$MACOS_DIR/CodexVault"
if [[ -f "$ICON_FILE" ]]; then
  cp "$ICON_FILE" "$RESOURCES_DIR/CodexVault.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh-CN</string>
  <key>CFBundleDisplayName</key>
  <string>Codex 对话管家</string>
  <key>CFBundleExecutable</key>
  <string>CodexVault</string>
  <key>CFBundleIconFile</key>
  <string>CodexVault</string>
  <key>CFBundleIdentifier</key>
  <string>com.dayangjiao.codexvault</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Codex 对话管家</string>
  <key>CFBundleSpokenName</key>
  <string>Codex 对话管家</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.5</string>
  <key>CFBundleVersion</key>
  <string>6</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <false/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 Codex 对话管家 contributors.</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

cat > "$RESOURCES_DIR/README.txt" <<'TEXT'
Codex 对话管家是一个本机 Codex 聊天记录转换工具。

它默认只读取会话列表，不展开完整聊天内容。转换前请先退出 Codex，并结束正在运行的任务。
TEXT

if command -v xattr >/dev/null 2>&1; then
  xattr -c "$BUILD_APP_BUNDLE" || true
  xattr -cr "$BUILD_APP_BUNDLE"
fi
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$BUILD_APP_BUNDLE"
fi

hdiutil create \
  -volname "Codex 对话管家" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "$TEMP_DMG_PATH"

if command -v xattr >/dev/null 2>&1; then
  xattr -c "$BUILD_APP_BUNDLE" || true
  xattr -cr "$BUILD_APP_BUNDLE"
fi

ditto --noextattr --noqtn "$BUILD_APP_BUNDLE" "$APP_BUNDLE"
cp "$TEMP_DMG_PATH" "$DMG_PATH"
shasum -a 256 "$DMG_PATH" > "$DIST_DIR/Codex-Vault.dmg.sha256"

echo "$APP_BUNDLE"
echo "$DMG_PATH"
