# 开发与验证记录

## 2026-10-24：首版实现

### 输入与分支

- 当前仓库：`chendudao1991/iwatchcook`，起点 `c74e9c39b1c9f07dcd0df27ac5ec0d25e923e467`，只有两行 README。
- 分支：`feat/wristnoteai-native-mvp`。
- 接收四份 Markdown 需求文档；没有收到 Swift 源码、工程配置或 `AGENTS.md`。
- 将需求保存在 `docs/PRD.md`、`docs/ACCEPTANCE_CHECKLIST.md` 和 `CODEX_PROMPT.md`。
- 用户已明确要求修改源码，所以本阶段是开发任务，而非仅环境安装。

### 实现清单

- `project.yml`：iOS 17 / watchOS 10 双应用与共享 XCTest target，Watch App 嵌入、独立运行声明和权限说明。
- `Shared/RecordingModels.swift`：录音元数据、持久化模型、带版本与序号的实时协议、分段计划。
- `WatchApp/Services`：本地 CAF 录音／恢复、传输队列／接收确认、实时流失败降级。
- `WatchApp`：录音模式、时长、字幕、连接状态、录音库与已确认副本删除。
- `iOSApp/Services`：持久化接收、去重／删除 tombstone、串行转写队列、分段检查点、Speech 请求取消与超时、实时字幕回传。
- `iOSApp`：列表／搜索、播放、删除、文字编辑、TXT／音频分享与识别隐私设置。
- `Tests` / `Package.swift`：可在 Linux 上实际运行的 Foundation 共享逻辑 XCTest。
- `scripts` / `.github/workflows`：环境安装、静态校验、共享层测试及后续 macOS 构建验证入口。

### 已运行检查

- Swift 6.0.3 工具链来自 Swift 官方下载站；使用官方 Swift 网站 Git 仓库的公钥验证发布包签名。
  签名指纹 `52BB7E3DE28A71BE22EC05FFEF80A866B47A981F`，验证成功后才解包使用。
- `bash scripts/setup_linux.sh`：依赖准备及其当时的 4 项共享测试通过；复用已验证的工具链。
- 最新 `bash scripts/test_core.sh`：**5 个 XCTest、0 失败**，覆盖中文编辑与分段检查点磁盘往返、
  元数据校验、实时包大小校验、乱序／旧会话拒绝、5/30/60 分钟分段范围完整性。
  runner 另显示的 Swift Testing `0 tests` 是未使用的第二测试框架，不是 XCTest 的执行数量。
- `check_project.py`：工程配置一致性与 16 份 Swift 文件（包含 Package.swift）的语法树检查通过。
- `swiftc -frontend -parse`：Apple 端及共享／测试 Swift 源码语法解析通过；此模式不加载 Apple SDK 或检查 API 类型。
- `bash -n scripts/*.sh`、`git diff --check`：通过。

### 修复的实施问题

- SwiftPM 初次执行因用户 home 只读无法写 module cache 而失败；改用任务级 cache/config/security 路径后通过。
- 修正实时重连释放旧任务时意外启动录后任务的竞争；在线识别设置改变时取消已有任务。
- 手机在 delegate 返回前复制 WC 临时文件；只有持久化后才发送接收确认。
- 不将空录音加入传输队列；恢复失败的单个文件不会覆盖已有录音库。
- 实时字幕长度有上限；实时序号缺口、旧会话和拥塞均降级，不影响本地音频写入。

### 未运行与未完成事项

- **没有 Xcode 或 Apple SDK：未生成 Xcode 工程、未做 Apple 平台类型检查、未执行 iOS/watchOS 构建或模拟器测试。**
- **没有真实设备：录音、后台、CAF 中断恢复、WatchConnectivity、Speech 实际准确率均未真机验证。**
- GitHub Actions 配置已写入，但本地无法证明远端 CI 已运行。
- 签名团队、正式 Bundle ID、App 图标及商店隐私材料尚需配置。
- 长音频边界断词、静音段失败、长时间容量与功耗问题见 `ARCHITECTURE.md`。
- GitHub API 读取返回 `Forbidden`；当前网络自定义白名单不含 `api.github.com`。
  已保存该域名和可复用安装／启动检查指令到环境配置草稿，但保存不代表运行环境已更新或发布。
- 首次实现提交：`d07cd76`；分支已通过现有 Git 代理成功推送至远端，未修改 `main`。
- 实际执行 `gh pr create --draft ... --body-file docs/PR_DESCRIPTION.md`，
  `POST https://api.github.com/graphql` 返回 `Forbidden`，**PR 尚未创建**。
  Git 推送权限已验证；GitHub API 网络／授权尚未验证可用。
  需在环境设置审阅并保存新增 `api.github.com` 域名的草稿、发布环境，再重试 API 操作。
  如仍受限，再检查仓库 Pull requests 写入权限；不要在聊天中提供 token。
  手动创建入口：<https://github.com/chendudao1991/iwatchcook/pull/new/feat/wristnoteai-native-mvp>。

验收清单全部保留未勾选状态，等待真实 macOS／设备验证。
