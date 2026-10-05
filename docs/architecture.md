# 项目结构

应用使用 AppKit `NSStatusItem` 提供菜单栏入口，并用透明、无边框 `NSPanel` 承载 SwiftUI 额度卡片，最低支持 macOS 13。这样可以避免系统弹窗与玻璃卡片形成双层背景。

## 数据流程

1. 应用定位本机 ChatGPT/Codex 内置的 `codex` 可执行文件。
   优先使用 `CODEX_BINARY`；随后检查应用包内的 `Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex` 和旧版 `Contents/Resources/codex`，最后检查常见 CLI 安装位置与 `PATH`。
2. 启动 `codex app-server --stdio` 子进程。
3. 通过逐行 JSON-RPC 完成 `initialize` 与 `initialized` 握手。
4. 调用 `account/rateLimits/read`。
5. 解析 `rateLimitsByLimitId`，以 `codex` 桶作为菜单栏主数字。
6. 收到 `account/rateLimits/updated` 通知或到达一分钟刷新周期时重新读取。

每次连接使用独立标识，旧连接的回调不影响新连接。初始化与额度请求均设 20 秒超时；初始化失败或超时会清理子进程，下一次手动或自动刷新重新连接。同一时间只保留一个额度请求，重复刷新合并到当前请求，响应需匹配当前请求 ID。

菜单栏和卡片统一选择 `primary`，缺失时回退到 `secondary`。读取失败或断开连接后保留上次结果，但增加过期警告和错误说明；重试期间保留警告，成功读取后才清除。

应用不直接读取 `~/.codex` 中的凭据文件。身份验证由 Codex 子进程使用现有登录状态完成。
