# 使用 Codex App Server 读取额度

## 决定

使用官方 `codex app-server` JSON-RPC 接口中的 `account/rateLimits/read`，不抓取网页，也不直接读取本地认证文件。

## 原因

- 官方接口直接返回 `usedPercent`、`windowDurationMins` 和 `resetsAt`。
- 可以复用 Codex 当前登录状态。
- 支持多额度桶和额度变化通知。
- 避免保存或处理账户 Token。

## 代价

- 本机必须安装并登录 ChatGPT/Codex。
- Codex 可执行文件移动位置时，需要更新候选路径或设置 `CODEX_BINARY`。
