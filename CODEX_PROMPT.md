# 可直接交给 Codex 的开发任务

请在当前仓库中继续开发“腕录 AI”Apple Watch + iPhone 原生 App。先阅读 `AGENTS.md`、`README.md`、`docs/PRD.md`、`docs/ACCEPTANCE_CHECKLIST.md`。

第一目标不是添加新功能，而是把项目修复到可由 Xcode 打开、编译、运行，并实现稳定的 MVP。

按以下顺序工作：
1. 检查 `project.yml`，用 XcodeGen 生成 Xcode 工程，确保 iOS App 与 watchOS App target 正确嵌入和签名。
2. 检查所有 Swift 编译错误与 API 可用性。若没有 macOS/Xcode 环境，明确标注未能编译，不得声称已通过构建。
3. 优先完成 Apple Watch 独立录音：麦克风权限、开始/停止、文件关闭与本地保存、录音异常提示。
4. 完成 `WCSession.transferFile` 文件同步，并在 iPhone 上显示录音列表、播放原音频、删除和重新转写。
5. 完成录后中文转写：语音识别权限、长音频分段、失败状态、重试和文字编辑保存。
6. 完成实时模式：先确保 Watch 录音不受实时链路影响，再验证音频分片、iPhone Speech 缓冲请求和字幕回传。断连时要显示状态，不得把实时字幕成功作为录音成功的前提。
7. 检查并发安全、重复文件、传输重试、临时分段文件清理、App 重启后的状态恢复。
8. 补充测试、运行步骤、隐私说明和 App Store 所需权限说明。

技术限制：iPhone 侧可使用 Speech 框架；不要尝试在 watchOS target 中直接调用 `SFSpeechRecognizer`。不要把第三方 ASR 密钥放进客户端。实时链路、后台录音和长录音必须列出真实设备测试步骤。

最终请给出：改动文件清单、构建/测试结果、未解决风险，以及在 Xcode 中运行的具体步骤。
