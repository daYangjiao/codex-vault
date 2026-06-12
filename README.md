# Codex Vault

Codex Vault is a lightweight macOS conversation manager for local Codex Desktop history.

It scans local Codex session files and `state_5.sqlite`, then shows conversations across provider groups such as `openai` and `custom`. The first build is intentionally read-first: it focuses on visibility and diagnostics before enabling destructive migration flows.

## Current Features

- Native macOS SwiftUI app.
- Auto-detects `~/.codex`.
- Opens with a fast SQLite-only conversation list.
- Shows provider, project path, update time, and diagnostics status.
- Runs deeper session-file sync only when requested.
- Detects provider mismatches between session JSONL metadata and SQLite after sync.
- Creates local backups.
- Migrates the selected conversation to another provider after Codex is closed.
- Restores the latest Codex Vault backup.
- Includes tested core scanning and migration logic.
- Ships as a manually assembled `.app` bundle and `.dmg`.

## Build

```bash
swift test
swift build -c release
./scripts/package-macos.sh
```

The app bundle is written to:

```text
dist/Codex Vault.app
```

The DMG is written to:

```text
dist/Codex-Vault.dmg
```

## Safety

Codex Vault reads:

```text
~/.codex/sessions
~/.codex/archived_sessions
~/.codex/state_5.sqlite
```

Before provider migration or restore, Codex Vault checks for running Codex processes and refuses to write while Codex or `codex app-server` is active. Migration creates an automatic backup before changing `model_provider`.

Backups are stored under:

```text
~/Library/Application Support/Codex Vault/Backups
```
