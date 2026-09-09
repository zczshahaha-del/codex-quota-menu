# Codex 余量

一个只驻留在 macOS 菜单栏的小工具。菜单栏使用紧凑格式显示，例如 `77%·6d`；点击后可查看 Codex 各额度窗口及准确重置时间。

## 功能

- 菜单栏显示 Codex 主额度的剩余百分比和重置倒计时。
- 点击后显示主额度及其他模型额度窗口。
- 每 5 分钟自动刷新，也可以手动刷新。
- 复用本机 ChatGPT/Codex 登录，不读取、不保存 Token。
- 没有 Dock 图标；通过菜单中的“退出”关闭。

## 使用

1. 确认 ChatGPT/Codex 已安装并登录。
2. 双击 `Codex 余量.app`。
3. 如需调整位置，按住 `Command` 后拖动菜单栏项目。

首次本地构建后直接打开即可。应用使用临时签名，适合当前 Mac 自用，不是 App Store 发布包。

## 开发

要求 macOS 13 或更高版本，以及 Xcode Command Line Tools。

```bash
swift test
./scripts/build-app.sh /path/to/output
```

项目通过 Codex 官方 `app-server` 的 `account/rateLimits/read` 方法读取额度。应用启动一个本地 Codex 子进程，并按官方要求完成初始化握手。
