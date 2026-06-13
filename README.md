# Codex 对话管家

一个轻量的 macOS 图形化工具，用来管理和转换本机 Codex 聊天记录。

核心目标很简单：把 Codex 会话在 `API` 和 `官方` 之间一键转换。应用默认只读取会话列表，不展开完整聊天内容，避免会话很多时卡顿。

## 当前功能

- 原生 macOS SwiftUI 应用，可直接双击打开。
- 自动识别本机 Codex 记录目录。
- 启动时快速读取会话列表。
- 中文固定三栏界面，不使用会跳动的系统侧栏。
- 按全部、API、官方、异常会话筛选。
- 区分桌面会话和 CLI 会话。
- 按项目目录分组显示标题和相对时间。
- 支持单击勾选多条会话后批量转换。
- 未勾选时默认转换当前范围内的全部可转换会话。
- 勾选后自动转换已勾选的 1 条、2 条或更多会话。
- 勾选后可批量删除；点开详情后可删除单条会话。
- 需要时可检查本机记录。
- 转换前自动创建本地备份。
- 删除前自动创建本地备份，并从本机列表和记录中移除。
- Codex 正在运行时拒绝写入，避免影响进行中的任务。
- 可恢复最近一次备份。

## 构建

```bash
swift run CodexVaultSmokeTests
swift build -c release --product CodexVault
./scripts/package-macos.sh
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

## 安全规则

执行转换、删除或恢复前，会检查 Codex 是否完全退出，并建议先结束正在运行的任务。转换后重新打开 Codex，列表才会刷新。

图片多的会话不会展开或重写完整聊天内容，迁移时会尽量保持原始内容不变。

备份目录：

```text
~/Library/Application Support/Codex Vault/Backups
```
