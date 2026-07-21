# Code Agent 品牌图标来源

更新时间：2026-07-14

这些图标只用于标识 TodoPilot 本机 Agent 任务的来源，不属于 TodoPilot 品牌，也不表示对应品牌对 TodoPilot 的认可或合作背书。运行时优先读取用户本机已安装应用的图标；下列 128×128 PNG 仅在对应桌面应用不可用时降级使用。

| 资源 | 官方参考 | 本次原始文件 | 原始 SHA-256 | 输出 SHA-256 |
| --- | --- | --- | --- | --- |
| `AgentIconClaudeCode.png` | [Anthropic Media Assets](https://www.anthropic.com/news) | 官方 Claude macOS 应用的 `electron.icns` | `7d0ffbc29b82d47ec63962f60d6dcb8c0659c62959a19d650191006e0d84cc27` | `f3889e0ac9a0010c7d13bba6798fc855e7997aba672b5fbb59fe1256387671b1` |
| `AgentIconCodex.png` | [OpenAI Design Guidelines](https://openai.com/brand/) | 官方 macOS 应用（bundle id `com.openai.codex`）的 `electron.icns` | `8ee5a24e1e32e33f976bc56943c2e8ad0a700449e6857741e543dc738648a2fb` | `979ea53ec0bb72bb53d9cca16b54386702eea2ac36be647f73d9160697cbacd3` |
| `AgentIconCursor.png` | [Cursor Brand Guidelines](https://cursor.com/en-US/brand) | 官方 Cursor macOS 应用的 `Cursor.icns` | `69257574472105aaae5f369dc141e85e54ea4a06da906133606a2080936cf83a` | `a2d83913831f1002df008fabc91cbfce181a61e79dc0d3237f96c52b813f57a0` |

转换命令只做格式转换和等比缩放：`sips -s format png -z 128 128`。没有裁切、染色、重绘、滤镜或 AI 生成；因此没有图像生成模型与 prompt 记录。

发布前需重新核对各品牌当时有效的使用规范。若品牌方要求停止或调整使用，应更新或移除对应降级资源；本机动态图标解析不记录或上传应用路径。
