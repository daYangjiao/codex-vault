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
UNIVERSAL_BIN="$WORK_DIR/CodexVault-universal"
ICON_FILE="$ROOT_DIR/Assets/AppIcon/CodexVault.icns"
DMG_PATH="$DIST_DIR/Codex-Vault.dmg"
TEMP_DMG_PATH="$WORK_DIR/Codex-Vault.dmg"
ZIP_PATH="$DIST_DIR/Codex-Vault.app.zip"
TEMP_ZIP_PATH="$WORK_DIR/Codex-Vault.app.zip"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cd "$ROOT_DIR"

# 构建通用二进制（Apple 芯片 + Intel），让两类 Mac 都能直接运行。
# Build a universal binary (Apple Silicon + Intel) so both Mac types run it directly.
# 分别编两个架构再用 lipo 合并，这样不依赖完整 Xcode（CommandLineTools 即可）。
# Build each arch separately and merge with lipo — no full Xcode required (CommandLineTools is enough).
swift build -c release --arch arm64 --product CodexVault
ARM_BIN="$ROOT_DIR/.build/arm64-apple-macosx/release/CodexVault"

if swift build -c release --arch x86_64 --product CodexVault 2>/dev/null; then
  X86_BIN="$ROOT_DIR/.build/x86_64-apple-macosx/release/CodexVault"
  lipo -create -output "$UNIVERSAL_BIN" "$ARM_BIN" "$X86_BIN"
else
  echo "warning: x86_64 slice failed to build; shipping arm64-only (Apple Silicon)." >&2
  cp "$ARM_BIN" "$UNIVERSAL_BIN"
fi
echo "binary archs: $(lipo -archs "$UNIVERSAL_BIN")"

rm -rf "$APP_BUNDLE" "$DMG_PATH" "$ZIP_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$UNIVERSAL_BIN" "$MACOS_DIR/CodexVault"
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
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>100</string>
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
ditto -c -k --keepParent "$BUILD_APP_BUNDLE" "$TEMP_ZIP_PATH"
cp "$TEMP_DMG_PATH" "$DMG_PATH"
cp "$TEMP_ZIP_PATH" "$ZIP_PATH"
shasum -a 256 "$DMG_PATH" > "$DIST_DIR/Codex-Vault.dmg.sha256"
shasum -a 256 "$ZIP_PATH" > "$DIST_DIR/Codex-Vault.app.zip.sha256"

echo "$APP_BUNDLE"
echo "$ZIP_PATH"
echo "$DMG_PATH"
