# Codex 余量

一个只驻留在 macOS 菜单栏的小工具。菜单栏使用紧凑格式显示，例如 `77%·6d`；点击后用玻璃卡片查看 Codex 主额度、准确重置时间及今日 token 用量。

## 功能

- 菜单栏显示 Codex 主额度的剩余百分比和重置倒计时。
- 点击后显示最常用的 Codex 主额度和「今日已用」token，列出输入、输出；不到 1 亿统一以万为单位，达到 1 亿以亿为单位，最多两位小数；悬停用量区可看准确数字及缓存输入。
- 今日用量按本地时间午夜起计算，统计本机 Codex 的所有聊天和已归档记录；输入包含缓存，输出包含推理用量，不重复相加。它不是账户跨设备或云端的总用量。
- macOS 26 使用原生 Liquid Glass，旧版本使用半透明系统材质。
- 每 1 分钟自动刷新；点击卡片右上角「⋯」可立即刷新或退出，也支持右键菜单。
- 刷新失败时安静保留上次额度，不显示警告或错误；连接或读取超过 20 秒会结束等待，可手动重试或等待下次自动刷新。
- 复用本机 ChatGPT/Codex 登录，不读取、不保存登录凭据；token 统计只读本地会话中的用量记录。
- 没有 Dock 图标。

## 使用

1. 确认 ChatGPT/Codex 已安装并登录。
2. 双击 `Codex 余量.app`。
3. 点击菜单栏额度打开卡片，再点击右上角「⋯」，可选择「立即刷新」或「退出」。
4. 如需调整位置，按住 `Command` 后拖动菜单栏项目。

首次本地构建后直接打开即可。应用使用临时签名，适合当前 Mac 自用，不是 App Store 发布包。

## 分享给朋友

运行 `build-dmg.sh` 后，将生成的 `Codex余量-版本号.dmg` 发给朋友。DMG 中包含应用、Applications 快捷入口和中文安装说明。当前测试版使用临时签名，朋友首次打开时需要在“系统设置 → 隐私与安全性”中选择“仍要打开”。要消除这一步，需要使用 Developer ID Application 证书签名并提交 Apple 公证。

## 开发

要求 macOS 13 或更高版本，以及 Xcode Command Line Tools。

```bash
swift test
./scripts/build-app.sh /path/to/output
./scripts/build-dmg.sh /path/to/output
```

`build-app.sh` 默认生成同时支持 Apple Silicon 与 Intel 的通用应用。设置 `CODE_SIGN_IDENTITY` 后可使用 Developer ID 正式签名；未设置时生成适合本地与朋友测试的临时签名版本。

项目通过 Codex 官方 `app-server` 的 `account/rateLimits/read` 方法读取额度。应用启动一个本地 Codex 子进程，并按官方要求完成初始化握手。

今日 token 统计读取 `CODEX_HOME`（默认 `~/.codex`）下的 `sessions` 和 `archived_sessions`，不上传会话记录。启动时在后台读取历史用量，之后每分钟只读取追加内容；点击「立即刷新」也会更新用量。没有可读记录时显示 `--`，读取失败时保留同日上次结果，不弹提示。
