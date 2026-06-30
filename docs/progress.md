# Progress

## 2026-06-30

- Updated the local checkout to `origin/main` commit `a9924f9978ed88349da78512ebdda8bdb383859f` (`release: v1.0 — install builds from source (no Release assets needed)`).
- Re-read all files under `docs/` before installation work.
- Confirmed the v1.0 `quick-install.sh` now clones the repository and builds from source instead of downloading a prebuilt release asset.
- Tested the clean v1.0 source on the installed macOS Command Line Tools: `swift run CodexVaultSmokeTests` passed, but `swift build -c release --product CodexVault` failed without a local `@MainActor` compatibility patch for `NSApp` menu access.
- Uninstalled the existing `/Applications/Codex 对话管家.app` application bundle.
- Cleared local build outputs and rebuilt from source as a first-install-style build.
- Applied a local build compatibility patch by marking `CodexVaultApplication` and `AppDelegate` as `@MainActor`.
- Ran `swift run CodexVaultSmokeTests`; it passed.
- Packaged and installed v1.0 using `scripts/package-macos.sh` and `scripts/install-macos.sh`.
- Verified `/Applications/Codex 对话管家.app` reports `CFBundleShortVersionString` `1.0.0`, `CFBundleVersion` `100`, `LSMinimumSystemVersion` `14.0`, and binary architectures `x86_64 arm64`.
- Verified the v1.0 app launched successfully from `/Applications/Codex 对话管家.app`.
- Updated the install approach for AI-friendly first installs: `scripts/quick-install.sh` now downloads `Codex-Vault.app.zip` from the latest GitHub Release instead of requiring source builds on the target Mac.
- Updated `scripts/package-macos.sh` to produce `dist/Codex-Vault.app.zip` and `dist/Codex-Vault.app.zip.sha256` alongside the existing DMG.
- Updated README installation docs to state that normal installation requires macOS 14+ only, not Xcode or Xcode Command Line Tools.
- Verified the generated `dist/Codex-Vault.app.zip` extracts to `Codex 对话管家.app`, reports version `1.0.0`, and contains binary architectures `x86_64 arm64`.
- Simulated the AI install path with `CODEX_VAULT_ASSET_URL=file://.../dist/Codex-Vault.app.zip ./scripts/quick-install.sh`; it installed and launched successfully.
- Created local commit `8492d0d` (`release: restore prebuilt installer asset flow`) with the AI-friendly install changes.
- Attempted `git push origin main`; it failed because the local environment has no GitHub CLI, no `GITHUB_TOKEN`/`GH_TOKEN`, and no HTTPS credentials available for `github.com`.
- Replaced the previous icon direction with a premium minimal generated icon: porcelain/glass rounded-square base, abstract chat-card migration mark, cyan accent, no vault/safe motif, and no green background.
- Regenerated `Assets/AppIcon/codex-vault-icon.png`, the full `CodexVault.iconset`, and `CodexVault.icns`.
- Confirmed local SSH authentication to GitHub works as account `xiaoYuan928`, but pushing to `daYangjiao/codex-vault` over SSH failed with `Permission denied`, so that account/key does not currently have write access to the repository.
