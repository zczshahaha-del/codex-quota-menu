# Issue 1：在菜单栏显示 Codex 剩余额度

## 为什么做

Codex 额度需要随时可见，减少反复打开设置或执行命令的操作。

## 本次范围

- 建立 macOS 菜单栏应用。
- 通过 Codex App Server 读取额度。
- 显示 `77%·6d` 风格的紧凑状态。
- 提供详情、自动刷新、手动刷新和退出。
- 完成单元测试、真实接口验证和本机应用构建。

## 不做

- 开机启动、自动更新、App Store 发布和其他平台。

## 完成条件

- [x] `swift test` 通过：3 个测试，0 个失败。
- [x] Release 构建成功并完成临时代码签名。
- [x] 打包后的 `.app` 已启动，菜单栏显示真实数据 `76%·6d`。
- [x] 点击后能显示 Codex 与 GPT-5.3-Codex-Spark 的额度窗口。
- [x] 实际界面检查确认没有新增 Dock 图标。
- [x] 应用只调用 Codex App Server，不读取或保存认证文件。

## 检查环境

- macOS 26.6.2（Apple Silicon）
- Swift 6.3.3
- Codex CLI 0.153.4
