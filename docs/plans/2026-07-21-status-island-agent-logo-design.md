# 灵动岛 Agent 任务 Logo 设计

## 目标

当灵动岛展示 Code Agent 任务时，在任务标题前显示对应的 Claude Code、Codex 或 Cursor 小 Logo。普通任务的标题布局保持不变。

## 方案比较

1. 展示时通过 `TodoTask.id` 查询 `AgentRunStore`：无需修改持久化模型，provider 来源可靠，可复用现有图标解析器。采用此方案。
2. 将 provider 冗余写入 `TodoTask`：读取简单，但需要模型、持久化和迁移改动，超出本需求。
3. 在标题中拼接符号或文字：实现简单，但不是对应产品 Logo，也会污染任务标题和辅助功能文本。

## 展示范围

- 展开灵动岛：每条 Agent 任务的标题前显示 16pt Logo，Logo 与标题间距 6pt。
- 收起灵动岛：轮播到 Agent 任务时，在标题前显示小 Logo；刘海屏使用 11pt，非刘海屏使用 14pt。
- 普通任务不预留 Logo 空间，不改变标题对齐。

## 数据流与回退

仅当任务来源为 `codeAgent` 时，通过 `AgentRunStore.run(taskID:)` 获取 provider，再交给现有 `AgentProviderIconResolver`。解析器优先读取已安装应用图标，失败时使用项目内 `AgentIconClaudeCode`、`AgentIconCodex`、`AgentIconCursor` 资产。

如果历史 Agent 任务缺少 run 关联，或图标解析失败，则只显示原标题，不显示空白占位。Logo 隐藏于辅助功能树，现有任务标题继续作为完整朗读标签。

## 边界

- 不生成或修改视觉资产。
- 不修改任务模型、持久化格式、Agent 生命周期或排序。
- 不改变灵动岛尺寸、任务行高度、颜色、操作按钮和动画节奏。

## 验证

- 单元测试覆盖 Agent/普通任务 provider 解析及无关联回退。
- 保持既有图标兜底资产测试和灵动岛尺寸、布局、动画测试通过。
- 运行完整 macOS 客户端测试。
