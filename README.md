# Codex 余量

一个只驻留在 macOS 菜单栏的小工具。菜单栏使用紧凑格式显示，例如 `77%·6d`；点击后用玻璃卡片查看 Codex 主额度及准确重置时间。

## 功能

- 菜单栏显示 Codex 主额度的剩余百分比和重置倒计时。
- 点击后只显示最常用的 Codex 主额度，不展示其他模型和次要信息。
- macOS 26 使用原生 Liquid Glass，旧版本使用半透明系统材质。
- 每 5 分钟自动刷新；右键卡片可立即刷新或退出。
- 复用本机 ChatGPT/Codex 登录，不读取、不保存 Token。
- 没有 Dock 图标。

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
