# ChatGPT 更新后无法读取额度

0.3.3 及更早版本只检查应用包内的 `Contents/Resources/codex`。新版 ChatGPT 将程序移至 `Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex`，从 Finder 启动的菜单栏应用也可能没有可用的 CLI `PATH`，因此提示找不到 Codex。

在新路径启动 `app-server --stdio`，完成初始化并调用 `account/rateLimits/read` 成功时，说明登录和接口正常，应检查程序定位，而不是重新登录。

0.3.4 已支持新路径，并保留旧版及 CLI 安装位置的回退。以后若应用包结构再次变化，可先确认实际可执行文件位置，再通过 `CODEX_BINARY` 指定路径启动，最后补充定位逻辑及回归测试。

相关记录：[Issue #3](https://github.com/zczshahaha-del/codex-quota-menu/issues/3)。
