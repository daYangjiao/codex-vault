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

## 安装（一行终端命令）

> 需要 macOS 14 及以上。

打开「终端」，粘贴运行这一行：

```bash
curl -fsSL https://raw.githubusercontent.com/daYangjiao/codex-vault/main/scripts/quick-install.sh | bash
```

它会自动下载并安装「Codex 对话管家」，装好后会自动打开（安装到 `/Applications/Codex 对话管家.app`）。之后随时在**启动台 / 应用程序**里点开即可，不用再敲命令。

> **由 AI / 自动化代理安装？** 只需运行上面这一条 `curl` 命令即可完成安装，**不要**克隆仓库、**不要**从源码构建、**不要**运行 `swift run`。装好的应用名为 `Codex 对话管家.app`。

<details>
<summary>不想用管道命令？手动安装（仍是预编译，无需编译）</summary>

逐条运行下面命令，效果和上面那行一致（下载预编译好的应用并装入「应用程序」）：

```bash
curl -fL https://github.com/daYangjiao/codex-vault/releases/latest/download/Codex-Vault.app.zip -o /tmp/codex-vault.zip
rm -rf /tmp/codex-vault-app && ditto -x -k /tmp/codex-vault.zip /tmp/codex-vault-app
rm -rf "/Applications/Codex 对话管家.app"
ditto --noextattr --noqtn "/tmp/codex-vault-app/Codex 对话管家.app" "/Applications/Codex 对话管家.app"
open "/Applications/Codex 对话管家.app"
```

</details>

<details>
<summary>仅开发者：从源码构建（普通安装无需此步）</summary>

仅当你要改代码或调试时才需要。需要 Xcode 命令行工具（`xcode-select --install`）：

```bash
git clone https://github.com/daYangjiao/codex-vault.git
cd codex-vault

swift run CodexVaultSmokeTests          # 自检：验证扫描与迁移核心逻辑
swift run CodexVault                     # 前台运行一个开发版（不会安装到「应用程序」）

# 或打包并安装到「应用程序」
./scripts/package-macos.sh
./scripts/install-macos.sh
```

</details>

## 安全规则

- 执行转换、删除或恢复前，会检查 Codex 是否完全退出，并建议先结束正在运行的任务。
- 转换后需重新打开 Codex，会话列表才会刷新。
- 图片多的会话不会展开或重写完整聊天内容，迁移时尽量保持原始内容不变。
- 所有写操作前都会先创建本地备份。

备份目录：

```text
~/Library/Application Support/Codex Vault/Backups
```

## 常见问题与修复

**安装命令卡住或下载失败（`curl: (xx)` / 连不上 github）**
多半是网络访问 GitHub 不稳。挂上代理后重试，或换个网络。脚本只是下载 + 解压，重跑一次没有副作用。

**提示「已损坏，无法打开，应该移到废纸篓」**
这是 macOS 的安全提示。在终端执行下面这条命令，然后重新打开应用：
```bash
xattr -cr "/Applications/Codex 对话管家.app"
```

**提示「无法验证开发者 / 来自身份不明的开发者」**
打开「系统设置 → 隐私与安全性」，往下找到被拦的提示，点「仍要打开」；或对着应用图标右键选「打开」。

**应用打不开 / 闪退**
应用支持 Apple 芯片和 Intel 芯片的 Mac，但需要 macOS 14 及以上。系统版本过低时请先升级 macOS。

**应用里看不到任何会话 / 提示找不到 Codex 记录**
说明没找到 `~/.codex` 目录。请先确认本机装过并至少打开运行过一次 Codex；如果你的记录目录在别处，用左上角「选择文件夹」手动指定。

**转换/删除按钮点了没反应，提示 Codex 正在运行**
迁移会写入本机记录，必须先**完全退出 Codex**（包括菜单栏图标），并结束 VS Code 里 Codex 面板拉起的后台进程，再操作。

**转换成功了，但 Codex 里还是看不到那些会话**
Codex 按「来源」分桶显示。转换后需**重新打开 Codex**，并切到目标来源（API 或官方），列表才会刷新出来。

**装错地方 / 想卸载**
直接把「应用程序」里的「Codex 对话管家.app」拖到废纸篓即可。备份仍保留在 `~/Library/Application Support/Codex Vault/Backups`，可手动删除。

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

## Install (one Terminal command)

> Requires macOS 14+.

Open Terminal and paste this single line:

```bash
curl -fsSL https://raw.githubusercontent.com/daYangjiao/codex-vault/main/scripts/quick-install.sh | bash
```

It downloads and installs **Codex 对话管家**, then opens it automatically (installed to `/Applications/Codex 对话管家.app`). After that, open it any time from **Launchpad / Applications** — no command needed again.

> **Installing via an AI / automated agent?** Just run the single `curl` command above. **Do not** clone the repo, **do not** build from source, **do not** run `swift run`. The installed app is named `Codex 对话管家.app`.

<details>
<summary>Prefer not to pipe into bash? Manual install (still prebuilt, no compiling)</summary>

Run these line by line — same result as the one-liner (downloads the prebuilt app and installs it into /Applications):

```bash
curl -fL https://github.com/daYangjiao/codex-vault/releases/latest/download/Codex-Vault.app.zip -o /tmp/codex-vault.zip
rm -rf /tmp/codex-vault-app && ditto -x -k /tmp/codex-vault.zip /tmp/codex-vault-app
rm -rf "/Applications/Codex 对话管家.app"
ditto --noextattr --noqtn "/tmp/codex-vault-app/Codex 对话管家.app" "/Applications/Codex 对话管家.app"
open "/Applications/Codex 对话管家.app"
```

</details>

<details>
<summary>Developers only: build from source (not needed for normal install)</summary>

Only needed if you want to modify or debug the code. Requires the Xcode Command Line Tools (`xcode-select --install`):

```bash
git clone https://github.com/daYangjiao/codex-vault.git
cd codex-vault

swift run CodexVaultSmokeTests          # self-check: scanning + migration core logic
swift run CodexVault                     # runs a dev build in the foreground (does NOT install to /Applications)

# or package and install into /Applications
./scripts/package-macos.sh
./scripts/install-macos.sh
```

</details>

## Safety rules

- Before migrating, deleting, or restoring, it checks that Codex has fully quit and recommends ending any running tasks first.
- Reopen Codex after a migration for the list to refresh.
- Image-heavy conversations are not expanded or rewritten; original content is preserved as-is during migration.
- A local backup is created before every write.

Backups directory:

```text
~/Library/Application Support/Codex Vault/Backups
```

## Troubleshooting

**Install command hangs or download fails (`curl: (xx)` / can't reach github)**
Usually unstable access to GitHub. Retry behind a proxy or on a different network. The script only downloads + extracts, so re-running it is safe.

**"App is damaged and can't be opened. You should move it to the Trash."**
A macOS security prompt. Run this command in Terminal, then open the app again:
```bash
xattr -cr "/Applications/Codex 对话管家.app"
```

**"Cannot verify developer / unidentified developer"**
Open **System Settings → Privacy & Security**, scroll to the blocked-app prompt, and click **Open Anyway** — or right-click the app icon and choose **Open**.

**App won't launch / crashes**
It runs on both Apple Silicon and Intel Macs but requires macOS 14+. Upgrade macOS if yours is older.

**No conversations shown / "Codex directory not found"**
It couldn't locate `~/.codex`. Make sure Codex is installed and has been launched at least once. If your data lives elsewhere, use **Choose Folder** (top-left) to point at it.

**Migrate/Delete does nothing — "Codex is running"**
Migration writes to the local store, so you must **fully quit Codex** (including the menu-bar icon) and end any background process spawned by the Codex panel in VS Code, then retry.

**Migration succeeded, but the conversations still aren't visible in Codex**
Codex groups history by source. After migrating, **reopen Codex** and switch to the target source (API or Official) for the list to refresh.

**Installed in the wrong place / want to uninstall**
Drag **Codex 对话管家.app** from /Applications to the Trash. Backups remain in `~/Library/Application Support/Codex Vault/Backups` and can be deleted manually.
