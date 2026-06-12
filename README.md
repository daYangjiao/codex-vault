# Codex 对话管家

一个轻量的 macOS 图形化工具，用来管理和转换本机 Codex 聊天记录。

核心目标很简单：把 Codex 会话在 `API/custom` 和 `官方/openai` 之间一键转换。应用默认只读取 `state_5.sqlite` 里的会话列表，不展开完整聊天内容，避免会话很多时卡顿。

## 当前功能

- 原生 macOS SwiftUI 应用，可直接双击打开。
- 自动识别 `~/.codex`。
- 启动时快速读取 SQLite 会话列表。
- 中文固定三栏界面，不使用会跳动的系统侧栏。
- 按全部、API、官方、异常会话筛选。
- 支持选中会话 `API → 官方`、`官方 → API`。
- 支持全部 API 会话转官方、全部官方会话转 API。
- 需要时可同步校验 session JSONL 文件。
- 转换前自动创建本地备份。
- Codex 或 `codex app-server` 正在运行时拒绝写入，避免被运行中的 Codex 覆盖。
- 可恢复最近一次备份。

## 构建

```bash
swift run CodexVaultSmokeTests
swift build -c release --product CodexVault
./scripts/package-macos.sh
```

应用包输出到：

```text
dist/Codex 对话管家.app
```

DMG 输出到：

```text
dist/Codex-Vault.dmg
```

## 安全规则

应用会读取：

```text
~/.codex/sessions
~/.codex/archived_sessions
~/.codex/state_5.sqlite
```

执行转换或恢复前，会检查 Codex 是否完全退出。转换会同时更新 session JSONL 的 `session_meta.model_provider` 和 SQLite 里的 provider 字段，并在写入前自动备份。

备份目录：

```text
~/Library/Application Support/Codex Vault/Backups
```
