#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$DIST_DIR/staging"
APP_NAME="Codex Vault"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
STAGED_APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE="$ROOT_DIR/.build/release/CodexVault"
DMG_PATH="$DIST_DIR/Codex-Vault.dmg"

cd "$ROOT_DIR"

swift build -c release --product CodexVault

rm -rf "$APP_BUNDLE" "$DMG_PATH" "$STAGING_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE" "$MACOS_DIR/CodexVault"
chmod +x "$MACOS_DIR/CodexVault"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Codex Vault</string>
  <key>CFBundleExecutable</key>
  <string>CodexVault</string>
  <key>CFBundleIdentifier</key>
  <string>com.dayangjiao.codexvault</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Codex Vault</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 Codex Vault contributors.</string>
</dict>
</plist>
PLIST

cat > "$RESOURCES_DIR/README.txt" <<'TEXT'
Codex Vault is a read-only local Codex conversation manager.

This build scans ~/.codex session files and state_5.sqlite, then shows conversations across provider groups.
TEXT

if command -v xattr >/dev/null 2>&1; then
  xattr -c "$APP_BUNDLE" || true
  xattr -cr "$APP_BUNDLE"
fi

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_BUNDLE"
  if command -v xattr >/dev/null 2>&1; then
    xattr -c "$APP_BUNDLE" || true
  fi
  codesign --force --deep --sign - "$APP_BUNDLE"
fi

mkdir -p "$STAGING_DIR"
ditto "$APP_BUNDLE" "$STAGED_APP_BUNDLE"

hdiutil create \
  -volname "Codex Vault" \
  -srcfolder "$STAGED_APP_BUNDLE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$STAGING_DIR"

if command -v xattr >/dev/null 2>&1; then
  xattr -c "$APP_BUNDLE" || true
  xattr -cr "$APP_BUNDLE"
fi
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_BUNDLE"
fi

shasum -a 256 "$DMG_PATH" > "$DIST_DIR/Codex-Vault.dmg.sha256"

echo "$APP_BUNDLE"
echo "$DMG_PATH"
