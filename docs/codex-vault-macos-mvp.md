# Codex 对话管家 macOS MVP

**产品名：** Codex 对话管家
**平台：** macOS
**形式：** 轻量原生 SwiftUI 应用
**定位：** Codex 聊天记录转换和基础管理工具。

## 核心目标

用户打开应用后，第一眼就能完成两件事：

- `API → 官方`
- `官方 → API`

会话内容不作为主功能展示。默认只读取列表和状态，避免用户本机会话很多时卡顿。

## 当前范围

- 自动识别本机 Codex 数据目录。
- 快速读取 `state_5.sqlite` 会话列表。
- 固定中文三栏界面，避免系统侧栏隐藏/显示导致顶部布局跳动。
- 按全部、API、官方、异常筛选会话。
- 支持选中会话转换。
- 支持全部 API 会话转官方。
- 支持全部官方会话转 API。
- 需要时同步校验 session JSONL 文件。
- 转换前自动备份。
- Codex 或 `codex app-server` 运行中拒绝写入。
- 恢复最近一次本地备份。

## 暂缓

- 完整聊天内容浏览。
- 多选表格批量转换。
- 备份历史选择器。
- SQLite 修复向导。
- 签名和 notarization。

## 安全规则

任何写入真实 `.codex` 数据前，必须先创建备份，并确认 Codex 已完全退出。`state_5.sqlite` 不是唯一事实来源，转换必须同步更新 session JSONL 的 `session_meta.model_provider`。
