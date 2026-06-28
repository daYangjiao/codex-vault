# Codex 对话管家 · Codex Vault

> 🌏 **中文** ｜ [English](#codex-vault-english)

一个轻量的 macOS 图形化工具，用来管理和转换本机 Codex 聊天记录。

核心目标很简单：把 Codex 会话在 **API** 和 **官方** 之间一键转换。应用默认只读取会话列表，不展开完整聊天内容，避免会话很多时卡顿。

## 它解决什么问题

Codex 桌面端会按「模型来源」把历史会话分桶显示——切到 API 就只看得到 API 的会话，切回官方就只看得到官方的。来回切换时，历史像「丢了」一样找不到。Codex 对话管家把这些会话在两个桶之间安全迁移，让你换了来源也能找回自己的对话。

## 当前功能

- 原生 macOS SwiftUI 应用，可直接双击打开。
- 自动识别本机 Codex 记录目录（`~/.codex`）。
- 启动时快速读取会话列表（只读列表，不加载完整正文）。
- 中文固定三栏界面，不使用会跳动的系统侧栏。
- 按「全部 / API / 官方 / 异常会话」筛选。
- 区分桌面会话和 CLI 会话。
- 按项目目录分组，显示标题和相对时间。
- 单击勾选多条会话后批量转换。
- 未勾选时，默认转换当前筛选范围内全部可转换的会话。
- 勾选后只转换已勾选的会话（1 条、2 条或更多）。
- 勾选后可批量删除；点开详情后可删除单条会话。
- 转换前自动创建本地备份。
- 删除前自动创建本地备份，并从本机列表和记录中移除。
- Codex 正在运行时拒绝写入，避免影响进行中的任务。
- 可一键恢复最近一次备份。

## 安装与构建

> 需要 macOS 14 及以上，并已安装 Xcode 命令行工具（`xcode-select --install`）。
> 目前通过源码构建分发，暂未提供已签名/公证的安装包。

```bash
git clone https://github.com/daYangjiao/codex-vault.git
cd codex-vault

# 1) 自检（验证扫描与迁移核心逻辑）
swift run CodexVaultSmokeTests

# 2) 构建 Release 版可执行文件
swift build -c release --product CodexVault

# 3) 打包成 .app 和 .dmg
./scripts/package-macos.sh

# 4) 安装到「应用程序」目录
./scripts/install-macos.sh
```

应用包输出到：

```text
dist/Codex 对话管家.app
```

DMG 输出到：

```text
dist/Codex-Vault.dmg
```

由于应用使用临时（ad-hoc）签名、未做公证，首次打开若被 Gatekeeper 拦截，可在「系统设置 → 隐私与安全性」中点「仍要打开」，或对 `.app` 执行 `xattr -cr`。`install-macos.sh` 在本机构建安装时已自动处理这一步。

## 安全规则

- 执行转换、删除或恢复前，会检查 Codex 是否完全退出，并建议先结束正在运行的任务。
- 转换后需重新打开 Codex，会话列表才会刷新。
- 图片多的会话不会展开或重写完整聊天内容，迁移时尽量保持原始内容不变。
- 所有写操作前都会先创建本地备份。

备份目录：

```text
~/Library/Application Support/Codex Vault/Backups
```

---

# Codex Vault (English)

> 🌏 [中文](#codex-对话管家--codex-vault) ｜ **English**

A lightweight macOS GUI tool for managing and migrating your local Codex chat history.

The goal is simple: move Codex conversations between the **API** and **Official** buckets with one click. By default the app only reads the conversation list — it never expands the full chat body, so it stays fast even with a large history.

## What it solves

Codex Desktop groups your history by model source: switch to an API provider and you only see API conversations; switch back to Official and you only see Official ones. Conversations feel "lost" whenever you switch. Codex Vault safely migrates conversations between the two buckets so your history follows you across sources.

## Features

- Native macOS SwiftUI app — double-click to launch.
- Auto-detects the local Codex directory (`~/.codex`).
- Fast list scan on launch (list only, no full message bodies).
- Fixed three-pane Chinese UI — no jittery system sidebar.
- Filter by All / API / Official / Problem conversations.
- Distinguishes desktop sessions from CLI sessions.
- Groups by project directory, with titles and relative timestamps.
- Click to select multiple conversations and migrate in bulk.
- With nothing selected, migrates every eligible conversation in the current filter.
- With items selected, migrates only those (1, 2, or many).
- Bulk-delete selected conversations; delete a single one from its detail view.
- Creates a local backup before every migration.
- Creates a local backup before every deletion, then removes it from the list and store.
- Refuses to write while Codex is running, protecting in-progress tasks.
- Restore the most recent backup with one click.

## Install & Build

> Requires macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`).
> Currently distributed as source — there is no signed/notarized installer yet.

```bash
git clone https://github.com/daYangjiao/codex-vault.git
cd codex-vault

# 1) Self-check (verifies scanning and migration core logic)
swift run CodexVaultSmokeTests

# 2) Build the release executable
swift build -c release --product CodexVault

# 3) Package into .app and .dmg
./scripts/package-macos.sh

# 4) Install into /Applications
./scripts/install-macos.sh
```

The app bundle is written to `dist/Codex 对话管家.app`; the DMG to `dist/Codex-Vault.dmg`.

The app is ad-hoc signed and not notarized. If Gatekeeper blocks the first launch, allow it under **System Settings → Privacy & Security → Open Anyway**, or run `xattr -cr` on the `.app`. The `install-macos.sh` script handles this automatically for local builds.

## Safety rules

- Before migrating, deleting, or restoring, it checks that Codex has fully quit and recommends ending any running tasks first.
- Reopen Codex after a migration for the list to refresh.
- Image-heavy conversations are not expanded or rewritten; original content is preserved as-is during migration.
- A local backup is created before every write.

Backups directory:

```text
~/Library/Application Support/Codex Vault/Backups
```
