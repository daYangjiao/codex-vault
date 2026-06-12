# Codex Vault macOS MVP Product Design

**Product name:** Codex Vault  
**Chinese name:** Codex 对话库  
**Platform:** macOS  
**Form factor:** Lightweight native SwiftUI app  
**Goal:** Let users view, diagnose, back up, restore, and migrate local Codex conversations across providers with a simple graphical interface.

## MVP Scope

Included in the first shippable build:

- Auto-detect the local Codex data directory.
- Scan local Codex session files.
- Read Codex `state_5.sqlite`.
- Show all conversations across providers.
- Filter conversations by provider, project path, and diagnostic status.
- Detect inconsistent provider metadata between session files and SQLite.
- Create local backups.
- Migrate selected conversations to another provider.
- Restore the latest local backup.

Deferred until after the first packaged build:

- Batch multi-select migration.
- Fine-grained backup picker.
- SQLite repair wizard.
- DMG signing and notarization.

## Safety Rule

Codex Vault must never write to a real `.codex` directory unless it has first created a backup and verified Codex is fully closed.
