# Codex Vault macOS MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a lightweight native macOS app that scans local Codex conversations and packages as a double-clickable app.

**Architecture:** Core parsing and diagnostics live in `CodexVaultCore` with tests and fixtures. The GUI lives in `CodexVaultApp` and consumes a single scan result model. Packaging is handled by a shell script that assembles a macOS `.app` bundle from the SwiftPM release binary.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI, AppKit, SQLite3, hdiutil.

---

### Task 1: Project Skeleton

**Files:**
- Create: `Package.swift`
- Create: `README.md`
- Create: `.gitignore`
- Create: `docs/codex-vault-macos-mvp.md`

- [ ] Create a SwiftPM package with `CodexVaultCore`, `CodexVaultApp`, and `CodexVaultCoreTests`.
- [ ] Add product docs and safety notes.
- [ ] Verify `swift package describe` succeeds.

### Task 2: Tested Core Scanner

**Files:**
- Create: `Sources/CodexVaultCore/*.swift`
- Create: `Tests/CodexVaultCoreTests/*.swift`
- Create: `Tests/CodexVaultCoreTests/Fixtures/**`

- [ ] Write tests for session parsing, SQLite merge, and provider mismatch diagnostics.
- [ ] Run tests and verify they fail before implementation.
- [ ] Implement session scanning, SQLite scanning, and conversation merging.
- [ ] Run `swift test`.

### Task 3: Native GUI

**Files:**
- Create: `Sources/CodexVaultApp/main.swift`

- [ ] Build a SwiftUI window with sidebar, conversation table, and detail panel.
- [ ] Add refresh and choose-folder actions.
- [ ] Show scan errors without crashing.
- [ ] Run `swift build`.

### Task 4: Packaging

**Files:**
- Create: `scripts/package-macos.sh`

- [ ] Build release binary.
- [ ] Assemble `dist/Codex Vault.app`.
- [ ] Add `Info.plist`.
- [ ] Ad-hoc sign the app if `codesign` is available.
- [ ] Create `dist/Codex-Vault.dmg`.
- [ ] Verify the `.app` launches.

### Task 5: Publish

**Files:**
- Modify: repository files as needed.

- [ ] Run `swift test`.
- [ ] Run `swift build -c release`.
- [ ] Run packaging script.
- [ ] Commit changes.
- [ ] Push to GitHub.
