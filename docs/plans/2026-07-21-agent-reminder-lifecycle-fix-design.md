# Code Agent 提醒生命周期修复设计

## 背景

TodoPilot 当前把每次 Code Agent 用户请求建模为一个 turn/run。正常情况下，`UserPromptSubmit` 创建运行中任务，匹配该 turn 的 `Stop` 将任务置为终态并发送飞机提醒。

现有启动恢复逻辑会在 TodoPilot 每次启动时，把所有仍在运行的 run 立即标记为 `LOST` 并提醒。只要 TodoPilot 在 Agent 工作期间重启，就会产生错误提醒。Codex 同一会话的新 turn 还会把旧 turn 标记为取消并提醒，容易在用户已经继续工作时产生无意义警告。

## 方案选择

### 方案 A：保留 turn 级提醒，修正恢复和替代行为（采用）

- 匹配当前 turn 的真实 `Stop` 才产生完成提醒。
- TodoPilot 启动时保留 active run，不推断 Agent 已失联。
- 同一 Codex 会话的新 turn 替代旧 turn 时，旧 turn 收口为取消，但不进入提醒队列。
- 只有现有 24 小时无事件超时等明确失联路径才产生 `LOST` 警告提醒。

优点是遵循官方 Hook 能提供的可靠边界，改动小，并保留现有“一次请求完成就提醒”的产品闭环。

### 方案 B：整个会话关闭后才提醒

Codex 当前只提供并安装 `UserPromptSubmit / Stop`，没有可靠的 `SessionEnd` 事件。无法准确判断用户是否还会在同一线程继续提问，因此不采用。

### 方案 C：Stop 后等待一段空闲时间再提醒

可以减少连续 turn 间的提醒，但本质是时间启发式，会延迟正常提醒且仍可能误判，因此不采用。

## 状态流转

1. `UserPromptSubmit`：创建 running run 和 doing 任务。
2. 匹配 turn 的 `Stop`：run -> `COMPLETED`，任务 -> done，进入提醒队列。
3. 同会话新 turn 替代旧 turn：旧 run -> `CANCELLED`，旧任务 -> done，提醒状态 -> none；新 run 正常 running。
4. TodoPilot 重启：保留 active run 和 doing 任务；只恢复已经存在的 pending terminal 提醒。
5. active run 连续 24 小时没有事件：run -> `LOST`，任务 -> done，进入警告提醒队列。

## 影响边界

- 只修改 `app/` 的本地 Agent 状态协调与测试。
- 不修改 Hook 配置、传输 schema、隐私字段、任务正文和截图处理。
- 不改变飞机 UI、动画、声音、2 秒聚合、保守静默和提醒持久化。
- 不改变 Claude Code、Cursor 的官方终态事件映射。

## 验证

- 回归测试：启动恢复后 run 仍为 running、任务仍为 doing、队列为空。
- 回归测试：恢复后的 run 收到匹配 `Stop` 后仍正常完成并提醒。
- 回归测试：同一 Codex 会话新 turn 替代旧 turn 时旧任务收口但队列为空。
- 保持测试：正常 `Stop` 仍只提醒一次；24 小时超时仍产生 `LOST` 警告提醒。
- 运行完整 `xcodebuild test` 和 `xcodebuild build`。
