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

## 空闲性能修复（2026-10-13）

- 现象：1.0.2（3）不操作仍有持续 CPU 开销，用户观察到完全退出后整机响应恢复。多次 sample 捕获灵动岛 SwiftUI 布局、动画及列表计算；应用 footprint 约 80 MB，暂未确认内存泄漏。
- 方案：保留灵动岛、轮播和螺旋桨动画，付费构建同步既有 tracking area、任务快照缓存及合成层帧动画；补齐隐藏/遮挡/卸载动画的暂停、恢复和资源释放。Today List 不可见时仅停止界面时钟更新，后台到期状态检查、日历刷新和提醒调度继续。
- 范围：两份客户端对应显示组件、窗口可见性监听、回归测试和脱敏空闲测量工具。数据模型、接口、权限、任务确认边界、订阅权益、日志内容不变；全量任务持久化隐患不纳入这次空闲修复。
- 执行顺序：先记录旧版空闲基线；同步及补齐生命周期；运行客户端测试和 Release 构建；保留原线上配置并更新本机实际应用；验证动画/交互及连续空闲资源趋势。临时报告和备份置于仓库外，不提交或发布线上版本。
- 验证入口：`scripts/measure-idle-performance.swift --pid <pid> --duration <seconds> --interval <seconds> --output <path or ->`，记录 CPU、RSS/footprint、线程、FD、窗口数量和 CoreGraphics 报告的窗口内存；不采集窗口标题或正文。实际验证结果见下文。

### 验证基线与结果

- 代码基线：Free `9d4af23`、paid `6fda85c` 加本次未提交补丁；系统 macOS 26.5.2、Xcode 26.6。正式运行目标由 1.0.2（3）更新为现有源码声明的 1.0.3（4），保持原三项线上配置并核对应用及 helper 的 ad hoc 签名；原应用已在仓库外备份。
- `xcodegen generate`（两份客户端）：通过；工程新增可见性监听和回归测试引用。
- `xcodebuild test -scheme TodoPilot -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`（两份客户端，分别指定仓库外 derivedData/resultBundle）：最终 Free 236 项、paid 280 项全部通过（`/tmp/todopilot-idle-free-final.xcresult`、`/tmp/todopilot-idle-paid-final-runloop.xcresult`）。新增真实窗口测试先复现 orderOut 后动画仍循环，再验证 KVO 修复；600 次逻辑轮播验证 2200 条任务缓存只重算一次，不能等同于实际运行 30 分钟。
- 自动关闭回归用真实主运行循环自然播放至关闭，在明确的 Cocoa 自动释放池边界后严格核对弱引用和具体 CG 窗口 ID；异步 XCTest 外层池会额外保留框架临时引用，先前失败不能直接当作生产泄漏。30 次真实显示/关闭的回归保留窗口基线与过期动作断言。测试同时修正已有表单测试的窗口所有权：Swift 管理的 parent/sheet 设为不在 close 时自动释放，避免其延迟系统动画污染后续异步测试；原 beginSheet/endSheet/close 断言保留。
- `xcodebuild build -configuration Release -scheme TodoPilot -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`（paid）：最终通过，日志 `/tmp/todopilot-idle-paid-final-release.log`；原有 OCR/Calendar SDK 弃用和空格警告未纳入本次修复。
- 已使用本机新应用确认主窗口可正常关闭且灵动岛继续显示；动画显示/隐藏/卸载与恢复由实际 NSWindow 回归测试验证。新 sample 不再捕获旧螺旋桨 Timeline body 或 hover 轮询。Screen Recording/OCR 权限、多屏/刘海/全屏/投屏未进行完整实机验收，本次未改变相关权限或捕获逻辑；几何、提醒和减少动态效果策略的既有测试通过。
- 空闲旧版采样命令：`/tmp/todopilot-measure-idle-performance --pid 3328 --duration 60 --interval 5 --output /tmp/todopilot-idle-old-build3-baseline.jsonl`。13 个样本零错误，CPU 平均 14.406%，窗口 16、FD 23 稳定。
- 新版连续采样命令：`/tmp/todopilot-measure-idle-performance --pid 70011 --duration 1200 --interval 5 --output /tmp/todopilot-idle-new-build4-20min.jsonl`。实际 1200.023 秒、241 个样本零错误，CPU 平均 0.852%、中位数 0.203%；前 13 分钟平均 0.192%。后半段外部 Agent 完成事件触发飞行提醒，最高 CPU 18.389%，不能把整个区间等同于纯空闲。footprint 70.73→73.99 MB（峰值 93.55 MB），FD 12 不变；总窗口 15→16、可见窗口最终仍为 1。确认额外记录属于隐藏的飞行面板，故继续补齐提醒关闭/计时生命周期；这是中间构建的发现，不作为最终补丁验收。
- 飞行生命周期补充：控制器同步撤销 Timer，避免延后的 onAppear 或旧 tick 重新启动/关闭新面板；计时按实际单调时钟推进，主线程掉帧不再延长提醒寿命。独立 NSApp.run 实验证实自动关闭后 AppKit 临时窗口引用可能停留在等待事件的外层自动释放池；关闭真实旧面板后发送一次无窗口/键鼠/任务数据关联的内部 `applicationDefined` 事件唤醒自身事件循环。独立完整 `NSApp.run` 对最终生产代码验证：主线程停顿 2 秒后仍约 6.308 秒自动关闭，弱引用释放、CG 窗口 0→0；30 次手动显示/关闭弱引用失败 0、窗口 0→0、过期动作 0。不能把 panel=nil 单独当作资源已释放的证据。
- CPU 的 100% 表示一个逻辑核心；工具已校准 Mach ticks 换算并与 top 同 PID 验证。CoreGraphics 窗口内存指标只代表该 API 报告的数值，不能代表 WindowServer/GPU 的全部占用。
- 未提交、未发布官网安装包，未改后端/数据库/接口契约。

### 最终实际安装版采样

- 实际路径 `/Users/neurobin/software/TodoPilot/TodoPilot.app`；版本 1.0.3（4）、PID 90154。安装二进制与最终 Release 暂存包匹配，SHA256 `da699b95141011e37cb8bd0ed931a2c4ab69ac1ade143bb8a8f4b851f978e165`；原三项配置逐项比较一致、app/helper 签名严格验证通过。最终运行中演示飞行和主窗口关闭均已检查，灵动岛继续显示；采样前 CG 列表没有飞行面板。
- 命令：`/tmp/todopilot-measure-idle-performance --pid 90154 --duration 1200 --interval 5 --output /tmp/todopilot-idle-final-20min.jsonl`。2026-10-13 18:32:11（北京时间）开始，关闭主窗口、保留灵动岛，期间不主动操作 TodoPilot；实际 1200.013 秒、241 个样本、零错误。CPU 平均 0.368%、中位数 0.091%、最高 12.001%；末尾 0.717%。footprint 70.86→84.49 MB、峰值 87.87 MB；RSS 98.62→129.14 MB、峰值 136.69 MB。总窗口 3→15：205 秒时一次性新增 12 条约 30–33 像素高的辅助窗口记录，之后未继续增加；可见窗口全程为 1。FD 全程 12。
- 本次不改历史任务全表持久化或历史归档策略：采样已定位常驻界面/提醒资源，任务变更时主线程全表保存仍是数据量增长后的性能隐患，需要独立测量保存耗时再处理，不能宣称所有运行场景都已消除卡顿。

### 改动文件与作用

以下客户端路径在 `app/` 与 `tmp/app-paid-1.0.1/` 对应目录同步；付费版灵动岛布局和付费能力继续保留。

| 文件 | 作用 |
| --- | --- |
| `TodoPilot/Services/Reminder/ReminderScheduler.swift` | 合成层帧动画、可见性暂停/恢复、飞行生命周期撤销、真实时长、窗口卸载回收 |
| `TodoPilot/Features/Island/StatusIslandWindowController.swift` | 付费版同步 tracking area 和任务快照缓存，两版处理系统时间回拨及减少动态效果 |
| `TodoPilot/Features/TodayList/TodayListView.swift` | 不可见时暂停界面时钟重绘，保留到期状态检查和日历刷新 |
| `TodoPilot/Core/UI/WindowRefreshVisibilityReader.swift` | 新增事件驱动的窗口可见性监听及观察者释放 |
| `TodoPilotTests/ReminderSchedulerTests.swift` | 缓存、动画、提醒取消/计时/窗口释放及已有窗口所有权回归 |
| `TodoPilotTests/WindowRefreshVisibilityTests.swift` | 新增真实窗口显示、隐藏、恢复及卸载监听回归 |
| `TodoPilot.xcodeproj/project.pbxproj` | 引用新增源文件/测试文件，原构建配置保留 |

`app/scripts/measure-idle-performance.swift` 为复用测量工具；本文件维护方案与验证摘要。临时测量 JSONL、日志、独立实验脚本和安装备份均置于仓库外，不纳入交付版本。

### 最终资源趋势和限制

- 约 200 秒的 CPU/内存变化与已捕获的外部 `agent_event_processed` 同时发生；约 625–640 秒另有短暂 CPU 峰值，尚未关联到具体调用栈，不将其归因为已确认的某个定时任务。CPU 随后回落。
- 1195 秒再次发生 Agent 事件，footprint 从约 78 MB 跳升至约 88 MB，终点约 84.5 MB；因此本次存在内存增长，不能写成“内存始终稳定”或“已排除内存泄漏”。无事件期间表现为平台值，尚未得到持续无界增长的证据。
- 20 分钟结束后外部 Agent 完成事件触发两次真实飞行提醒（北京时间 18:52:38、18:52:46）；自动结束后再次读取 CG 列表，总窗口仍为 15、可见 1，未有飞行面板记录。没有通过关闭提醒功能规避资源检查。
- 20 分钟实机采样与 30 次生命周期压力回归证实已定位的持续刷新/资源回收路径改善；用户原始数小时后的整机卡顿尚未完全验证。睡眠唤醒、多屏/刘海/全屏/投屏及捕获权限仍需完整实机覆盖；历史累积后的全表保存隐患保持已知限制。

| 最终采样区间 | CPU 平均 | CPU 中位数 | footprint 首→末（MB） | 末尾总窗口/可见窗口 |
| --- | ---: | ---: | ---: | ---: |
| 0–5 分钟 | 0.223% | 0.152% | 70.86→76.17 | 15/1 |
| 5–10 分钟 | 0.066% | 0.066% | 76.17→76.17 | 15/1 |
| 10–15 分钟 | 0.842% | 0.081% | 76.17→77.91 | 15/1 |
| 15–20 分钟 | 0.339% | 0.155% | 77.96→84.49 | 15/1 |

- 收尾实际提醒活动验证：`--pid 90154 --duration 60 --interval 2 --output /tmp/todopilot-idle-final-post-reminders.jsonl`，31 样本零错误。窗口 15→16→15（展示时可见 2，结束后 1），FD 全程 12；footprint 84.21→80.94 MB、峰值 98.16 MB，提醒后回落。该区间仍有外部 Agent 活动和真实飞行动画，CPU 平均 5.139%、中位数 0.729%、最高 25.066%，不得与纯静置 CPU 混为一谈或隐藏此开销。
- 收口检查：最终两版 `git diff --check` 通过；Release 安装配置/签名/二进制一致；应用保持运行，主窗口关闭、灵动岛及真实提醒可用。未提交或对外发布。


## 历史持久化与两小时空闲验证（2026-10-14）

### 本轮约束、设计与实施计划

用户要求退出原安装版、启动当前源码最新版，至少两小时空闲监测，并继续优化阶段性内存增长与历史任务保存；所有业务功能、UI/UX、灵动岛和动画保持原行为。

- 已核对代码基线仍为 Free `9d4af23`、paid `6fda85c` 加前次未提交性能补丁。原 PID 90154 正常退出；当前源码 fresh Release 已构建/安装/启动为 PID 32446，版本 1.0.3（4），原三项配置和签名/二进制匹配均核对。仓库外保存安装包及一致性的只读 SQLite 备份（仅聚合计数：2192 task/source、2118 Agent、21 capture）；不在文档保存真实正文或标识。
- 已复现旧实现写放大：真实 SQLite 合成数据，2200 条历史单条改动中位约 63ms、10000 条约 300ms；同值保存同级开销。旧删除重建每次约 4N 次行操作。真实数据库未用于性能写入试验。
- 选择同步增量更新：保持完整快照接口、schema、确认入库边界、历史数量与任务业务方法。每次 fetch 两表建立临时映射，复用记录并仅更新不同字段；完整快照缺失才物理删除，软删除/完成/归档仍保存。保留重复 ID 修复、来源 quote 双写/清空、导入幂等、paid cloudID。临时对象在明确 autoreleasepool 边界释放，不添加长期对象/快照缓存、不全局 reset 共享 context。
- 仍有 O(N) 读取比较；若其成本后续证明仍高再单独评估缓存或后台队列。本次不改 TaskStore 协议为异步、不合并或丢弃业务事件、不裁剪历史、不改任何 UI 文件。
- fetch/commit 失败回滚；成功后才推进初始化/迁移标志。保存聚合计量只含耗时/数量/结果，异常只含标准 domain/code，不含任务正文、OCR、UUID、截图路径或密钥，不新增外部遥测。
- 顺序：①旧/增量合成 SQLite 基准及重开校验；②已有测试文件补齐真实 SQLite 单条变更、同值、来源/quote/cloudID、删除恢复/clear、重复/来源修复、失败重试及共享数据不受影响；③两版完整测试、paid Release；④安装并重启最终补丁；⑤最终 PID 累计清醒至少 7200 秒，每5秒测 CPU/RSS/footprint/线程/FD/窗口，伴随双 Mach 时钟识别睡眠与校时；⑥分段趋势与实际保存计量/事件关联后收口。不能用短基准或前期构建时长替代最终两小时实机验证。
- 系统背景指标记录 WindowServer、swap/pressure 前后值，仅作为整机背景对照，不全部归因 TodoPilot。监测只临时阻止自动系统睡眠，屏幕可熄灭，主动睡眠会分段并延长清醒时长；不修改用户系统持久设置。


### 本轮实现、基准与最终监测入口

- 两版只修改 `CoreDataLocalStore.swift` 的存储实现及既有测试。模型定义逐字核对未改，业务/UI/资源/提醒等 99 个文件本轮哈希未改；TaskStore 的方法、同步完整快照协议和后台业务继续。仅窗口测试夹具改为后台可见的真实 NSPanel，并统一弱引用/CG 记录的有界释放等待，全部遮挡/显示/隐藏/恢复/卸载及窗口释放断言保留。
- 严格同模型 paid 基准：旧代码来自 `e2ef57e`，存储文件 SHA256 与当前 paid 基线 `6fda85c` 完全相同；旧/新使用同一 paid TaskStore/TodoTask（合成任务一半含非空 cloudID）。每项串行5次取中位，2200 单状态保存 63.874→19.950ms、同值 61.773→20.121ms；10000 单状态 293.535→99.693ms、同值 301.067→100.496ms。单标题改动任务/来源表物理写总计 8800/40000→1 次任务 UPDATE，同值不提交；4组独立进程真实 SQLite 全字段重开全部通过。仍为 O(N) 读取比较，没有使用长期缓存。
- `xcodebuild test -project TodoPilot.xcodeproj -scheme TodoPilot -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`（分别指定仓库外 derivedData/resultBundle）：paid 289、Free 244 全部通过。新增真实 SQLite 回归 free8项/paid9项及纯 CLI XCTest均通过。目标重载/来源清空/cloudID、历史软删除恢复/clear、重复孤儿/缺失来源、失败回滚/标志/重试、共享Agent/capture不夹带未提交数据已覆盖。
- `xcodebuild build -scheme TodoPilot -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`（paid）通过；不复述已有构建配置中的敏感值，完成日志已脱敏。
- 最终安装路径仍为 `/Users/neurobin/software/TodoPilot/TodoPilot.app`，1.0.3（4）；原三项配置一致、app/helper 严格签名验证及暂存/安装二进制一致。最终 SHA256 `9a7922ac0531db7184e0cec5f2249eec14d2934e100580a9612edb09fd648c54`，PID 39624。再次退出/安装前只读备份聚合计数 2192 task/source、2118 Agent、21 capture，历史未裁剪。
- 10:57:40 的首段监测约18分钟后，用户确认期间手动打开主窗口或点击提醒；该段保留为活动样本，不计入严格两小时。关闭主窗口后于北京时间2026-10-14 11:16:31重新开始：`caffeinate -i /tmp/todopilot-measure-idle-performance --pid 39624 --duration 7200 --interval 5 --output /tmp/todopilot-long-idle-20261014/strict-idle-2hour/final-2hour.jsonl`。伴随 clock-monitor 记录 awake/continuous/wall 三种时间及聚合输入空闲，日志仅采集该 PID 的固定聚合计量/既有脱敏事件。其他应用可正常使用，后台 Agent 事件和真实飞行提醒继续，因此这是 TodoPilot 无主动 UI 操作的正常后台场景，不等同于整台电脑无人输入或关闭业务后的纯静置。满两小时后再更新结论；不能把当前运行中计时写成已完成。
- 前期 `pre-incremental.jsonl` 在会话中断时仅留下45秒部分样本，不用于证明10分钟或最终两小时。后台监测监督进程与采集独立运行，应用退出/PID复用/指标错误会记录失败。
- 短时运行/退出对照：WindowServer 后5个样本 CPU 中位 53.6%→57.1%，未出现随 TodoPilot 退出下降；此对照并不能证明全部整机卡顿归因或排除系统背景。初始及构建阶段整机 swap 约30–33GB、32GB RAM，属于全机数据，不当作客户端专属泄漏。


### 两小时清醒监测的结果与限制

- 最终 PID 39624 的严格阶段：北京时间2026-10-14 11:16:31→14:01:18。采集器按清醒时钟完成7200秒目标，1441个样本、零指标错误、目标未退出，监督进程正常完成。首末样本清醒跨度7199.960秒（首样本存在约40ms启动偏移）；伴随时钟覆盖全部样本且累计7203.031秒清醒，实际首末样本墙钟9883.847秒。检测到5段系统挂起，合计2683.900秒（约44分44秒），已排除并延长监测；没有将睡眠时间当作有效空闲时长，也没有用前一段用户主动操作样本凑时长。不能写成连续两小时无睡眠。
- 全程 CPU 平均/按清醒间隔加权平均0.683%、中位0.233%、最高21.943%，前一小时均值约0.858%、后一小时约0.509%。短峰值包含正常后台业务和真实动画，不以关闭功能消除。没有持续攀升的 CPU 趋势。
- footprint 97.257→108.562MB，净增11.305MB，范围94.897–125.748MB；RSS 157.368→126.042MB，范围76.235–162.234MB。单位为十进制MB；vmmap/leaks的M为二进制MiB。内存存在阶段增长和回落，不能说内存不变、已排除泄漏或整机卡顿完全解决。无明显活动的60–85分钟附近约100–101MB平台；后段睡眠/唤醒及新增事件后约106–109MB，仍有待归因的增量。
- 总窗口16→15，范围7–17；可见窗口1→1，范围1–2（真实提醒展示）；CoreGraphics报告窗口内存37888→35520字节，范围16576–40256。约89分钟附近辅助窗口记录减少，随后恢复，未持续累积。该指标不代表整个WindowServer/GPU内存。FD 12→12，只有一个样本短暂为13；线程11→8，范围7–18。没有窗口、FD或线程累积增长的证据。
- 正常后台保留：日志采集到43次Agent处理、19次提醒批次；41次真实任务保存全部成功，中位33.862ms、最高44.665ms，每次最多2行变更；总任务计量2204→2225。未重新出现任务/来源全表删除重建。两个列表读取比较仍为O(N)，后续极大历史量仍有成本。
- 收尾只读SQLite统计2226 task/source、2151 Agent、21 capture；任务重复ID、孤儿来源和缺失来源均为0。较安装前增加34项任务/33项Agent，属于仍在运行的业务；没有删历史或用空库代替用户数据。
- `vmmap -summary 39624` 通过。初始vmmap在严格阶段及手动主窗口活动之前，属于冷启动参考（footprint69.9MiB），不能用它与收尾103.5MiB直接算严格两小时增量。收尾CoreAnimation约5.55MiB dirty、SQLite page cache1.125MiB，初始/末尾SQLite cache大小一致；malloc实际分配42.1→72.0MiB含前期暖机和活动，尚无分配栈证据能把增加归因到某一业务组件。
- `leaks --noContent --nostacks 39624` 两次（14:01:37、14:04:13）均报告662个对象、24448字节；退出码1表示发现可疑泄漏，不是检查通过。根类型包括3个NSXPCConnection循环、365个小NSArray根和7个无类型根；后一次数量/字节未增加。源码未直接创建NSXPCConnection，仍不能据此确定框架责任或排除客户端触发的生命周期问题；没有打开分配栈记录，无法归因具体调用点。这24KB不能解释11.3MB增量，检查也不排除仍可达对象的异常保留。未通过修改权限、吞掉报告或删除UI来伪造无泄漏。
- 全机收尾WindowServer后5次CPU中位58.2%、内存约1605MB；swap used29462.00→30779.94MiB（约28.77→30.06GiB），memory_pressure全机free36%→37%。全机交换空间和WindowServer仍有较高占用，不能全部归因于TodoPilot，也不能由客户端低CPU推断整机所有卡顿已消失。
- 最终实际PID/路径、版本1.0.3（4）、SHA256、三项原配置、app/helper严格签名再次核对；业务/UI/资源等99个文件本轮哈希仍相同，模型定义逐字未变，两版`git diff --check`通过。应用继续运行，监测工具结束；未提交、未发布外部安装包。

| 清醒区间（分钟） | CPU平均 | CPU中位 | footprint平均（MB） | footprint首→末（MB） | 末尾总窗口 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 0–15 | 1.197% | 0.236% | 98.51 | 97.26→98.11 | 16 |
| 15–30 | 0.911% | 0.230% | 100.60 | 100.75→102.02 | 15 |
| 30–45 | 1.102% | 0.251% | 102.54 | 102.02→103.11 | 15 |
| 45–60 | 0.222% | 0.228% | 102.06 | 103.11→100.94 | 15 |
| 60–75 | 0.235% | 0.232% | 100.38 | 100.94→100.55 | 15 |
| 75–90 | 0.356% | 0.238% | 100.90 | 100.55→103.92 | 8 |
| 90–105 | 0.838% | 0.228% | 106.49 | 103.88→108.10 | 15 |
| 105–120 | 0.606% | 0.228% | 107.13 | 108.10→108.56 | 15 |

### 本轮改动文件及验证入口

以下源码/测试文件在`app/`与`tmp/app-paid-1.0.1/`两版对应路径同步：

| 文件 | 目的 |
| --- | --- |
| `TodoPilot/Core/Storage/CoreDataLocalStore.swift` | 增量任务/来源写入、完整字段比较、临时对象释放、失败回滚和脱敏聚合计量；模型和同步协议保留 |
| `TodoPilotTests/TaskStoreTests.swift` | 真实SQLite、记录身份与字段、来源/quote/cloudID、历史状态、故障重试、共享Agent/capture回归 |
| `TodoPilotTests/WindowRefreshVisibilityTests.swift` | 测试夹具使用真实后台可见NSPanel，保留所有可见性断言；生产UI未变 |
| `TodoPilotTests/ReminderSchedulerTests.swift` | 弱引用及CG窗口释放使用同一有界等待，保留窗口/过期动作断言；生产提醒未变 |

本文件复用既有性能主题维护结果；本轮未新增其他交付文档、SQL或版本目录。

- 两版完整测试分别244/289通过；结果包`/tmp/todopilot-long-idle-20261014/free-final-verified.xcresult`、`paid-final-verified.xcresult`。paid Release构建通过，日志`final-release.log`；具体xcodebuild命令见上节。
- 可复现监测命令见上节。原始JSONL、双时钟和聚合事件在`/tmp/todopilot-long-idle-20261014/strict-idle-2hour/`；`analysis-final.json`包含24个五分钟清醒分段，`final-verification-summary.json`和严格同模型基准`persistence-bench/strict-paid-comparison.json`均在父临时目录。临时产物可能随系统清理，关键摘要保留于本文件；数据备份权限受限且未入Git。
- 保留所有业务功能、布局、动画、提醒、历史及权限。多屏/刘海与非刘海/全屏/投屏/捕获权限完整UI实机验收未重新覆盖；本轮相关生产文件未改、已有策略/几何/生命周期测试通过。阶段性内存增长具体来源尚未完全定位；后续需要同设置的更长测量及带分配栈的独立复现实验，不能把本次两小时结果写成任意时长无泄漏保证。


### 重新打包及后端资源替换（2026-10-14）

- 最初指令是“如果没有问题就重新打包，替换后端代码resource下的包”；先完成候选包和验证，再由用户明确接受已知内存风险，授权只替换后端源码resource、不部署。已替换新版ZIP及latest.json；阶段性内存增量继续作为后续定位项，不宣称已彻底解决。业务功能和UI/UX继续保持本轮已验证的源码行为。
- 复用当前目标1.0.3（4），paid源代码fresh Release通用构建：`xcodebuild -configuration Release -destination generic/platform=macOS build CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO ARCHS='arm64 x86_64' MARKETING_VERSION=1.0.3 CURRENT_PROJECT_VERSION=4`，三项配置从已验证安装版私下读取，日志脱敏。未修改UI/业务源码，99个关键文件哈希继续一致。候选三项配置与实机相同；旧资源包的网站字段为空，API及验证材料与实机相同。Intel完成编译/二进制架构检查，未进行Intel实机验证。
- 候选`/tmp/todopilot-repackage-20261014-0rg_5i64/TodoPilot-1.0.3-build4-macOS.zip`，6290619字节，SHA256 `9ebe74e650a0d9ad5dbf8adfee9cfe19c3d90e06a57b39c84b7b3fdb0ee16aa9`；配套`latest.json`同步版本、build、时间、字节数和SHA。App/helper均为arm64+x86_64、原entitlements的ad hoc签名；ZIP CRC、解压正文及可执行权限、解压后严格签名均通过。沿用原资源发布形态，未公证，未上传/部署。
- 新包首次验证发现既有`DownloadControllerHttpTest`写死6204610字节，候选包触发3项失败；修改该测试夹具从真实classpath归档获取期望大小，保留GET/HEAD/Range/attachment/no-store/ZIP前缀/不触发HEAD统计的断言，并增加完整GET正文SHA256一致性。没有降低断言或修改服务端生产逻辑。
- `mvn -q -pl business -am -Dtest=PublishedClientReleaseTest,PublishedReleaseServiceTest,DownloadControllerHttpTest -Dsurefire.failIfNoSpecifiedTests=false test`：原源码资源8项通过。候选临时置于Git忽略的`business/target/classes/static/downloads`，`mvn ... surefire:test`同一组8项全部通过、零失败/错误/跳过，随后恢复target资源。候选manifest/归档哈希、下载GET/HEAD/断点续传均实际验证；测试未连接真实数据库。
- 用户授权后，替换`TodoPilotBackend/business/src/main/resources/static/downloads/{TodoPilot-1.0.3-build4-macOS.zip,latest.json}`，按已验证候选同步ZIP大小6290619及SHA256；未改其他历史归档、后端生产代码或客户端源码。原资源备份和完整日志在仓库外临时目录，不纳入Git；新版资源仅作本地提交，未推送、未部署。运行中的后端按文件名缓存归档，同名替换需要后续重新打jar/重启后端才能对外生效；本次未执行该发布步骤。

- 资源实际替换后的收口验证：再次执行上述`mvn ... test`，8项全部通过、零失败/错误/跳过；源码resource与Maven实际测试classpath中的ZIP逐字一致，manifest字节数/SHA256与候选包一致，两份客户端99个关键业务/UI文件及paid存储文件哈希未变，后端及客户端文档`git diff --check`通过。只替换本地资源，未部署；后续内存归因尚未完成。
