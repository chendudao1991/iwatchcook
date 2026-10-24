# 腕录 AI（WristNoteAI）

Apple Watch + iPhone 原生录音转文字 App。在当前 `iwatchcook` 仓库中根据随附 PRD 从零建立，
并非对已有 Swift 工程的修复。

## 当前功能

- Watch：实时／录后模式、麦克风授权、独立本地录音、时长、异常保存、本地录音列表。
- 同步：WatchConnectivity 文件队列、UUID 去重、手机持久化接收确认、断连后重试、删除 tombstone。
- iPhone：原音频播放、搜索、中文录后转写、40 秒分段检查点、失败重试、文字编辑、TXT／音频导出。
- 实时：16 kHz mono Int16 分片、iPhone Speech 识别、双端字幕、连接状态、失败降级、本地完整音频兜底。
- 隐私：默认设备本地识别；在线 Apple Speech 需用户明确开启并完成系统授权。

这些是**已实现的代码路径，不代表已经通过 Apple SDK 编译或真机验收**。
当前 Linux 环境的实际验证结果见 [开发记录](docs/DEVELOPMENT_LOG.md)。

## macOS 上生成和运行

需要 Xcode 15 或更新版本、iOS 17+、watchOS 10+ 和 XcodeGen 2.42+。

```bash
brew install xcodegen
cd /path/to/iwatchcook
xcodegen generate
open WristNoteAI.xcodeproj
```

1. 在 `project.yml` 中修改两端 Bundle ID（watch ID 必须以 phone ID 加 `.` 开头），并同步修改
   `WKCompanionAppBundleIdentifier`。配置 `DEVELOPMENT_TEAM` 为你的 Apple Developer Team，重新生成工程。
2. 运行 `WristNoteAI` scheme 到 iPhone，再运行 `WristNoteWatch` scheme 到配对 Watch。
3. 手机“识别设置”确认音频处理方式并申请语音识别授权。默认本地中文模型不可用时会明确失败，
   不会自动切换在线识别；可按需明确开启 Apple 在线识别。
4. 手表首次录音允许麦克风权限。先验证录后模式：关闭手机连接，录音，停止保存，再恢复连接同步。
5. 实时模式验证时保持 iPhone App 前台。无法实时通信时手表仍保留完整录音；最终全文在文件接收后生成。

模拟器构建和 XCTest（需要已安装 iOS/watchOS Simulator runtime）：

```bash
bash scripts/check_apple.sh
```

工程生成时 XcodeGen 会生成两端 `Info.plist`。这不是签名、真机配对或后台行为已验证的证据。
GitHub Actions 已配置 Linux 共享层测试和 macOS 构建／模拟器测试；须以实际运行结果为准。

## Linux 可执行检查

共享协议与分段逻辑仅依赖 Foundation，可直接用 Swift 5.9+／6.0.3 测试：

```bash
swift test --jobs 2
python3 -m venv /tmp/wristnote-checks
/tmp/wristnote-checks/bin/pip install -r scripts/check-requirements.txt
/tmp/wristnote-checks/bin/python scripts/check_project.py
```

当前云机器已额外安装 Swift 6.0.3：

```bash
WRISTNOTE_SWIFT_BIN=/workspace/toolchains/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swift \
  bash scripts/test_core.sh
```

Swift 共享层测试不包含 AVFoundation、Speech、WatchConnectivity 或 SwiftUI。
`check_project.py` 检查工程声明和 Swift 语法树；不替代 XcodeGen 或 Apple SDK 类型检查。

## 真实设备验收与限制

逐项执行 [验收清单](docs/ACCEPTANCE_CHECKLIST.md)，记录设备、系统版本、日志和复现步骤。
特别验证 5/30/60 分钟录音、熄屏、低电量、来电、磁盘不足、断连、重复传输、重启、识别拒绝和离线模型缺失。
所有未实测的验收项保持未勾选。

- Watch 保存 16 位 PCM CAF，48 kHz 单声道约 346 MB/小时，暂无压缩和自动空间清理。
- 实时字幕只保留最近 2,000 字；轮换、断连、拥塞可能造成实时文字缺失，完整录音录后转写提供最终全文。
- 40 秒分段有边界断词风险，暂无词级重叠去重；无声段报错时不会静默跳过。
- 后台／锁屏持续录音与实时字幕、崩溃后 CAF 恢复都必须在真机验证。
- 当前导出 TXT 和原音频；Word／PDF、暂停恢复、iCloud、摘要不属于已实现内容。
- 正式上架仍需图标、正式隐私政策 URL、App Store 隐私标签、签名与发布配置。

## 项目文档

- [PRD](docs/PRD.md)
- [验收清单](docs/ACCEPTANCE_CHECKLIST.md)
- [架构与恢复约定](docs/ARCHITECTURE.md)
- [开发与验证记录](docs/DEVELOPMENT_LOG.md)
- [原始开发任务文档](CODEX_PROMPT.md)

收到的 `CODEX_PROMPT.md` 是项目参考文档；其中对已有源码的描述不代表本次确实收到那些源码。
本次没有收到 `AGENTS.md`，也未发现已有文件。
