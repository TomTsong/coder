# coder

手机遥控云端服务器，让 Claude Code（接 DeepSeek）在服务端写代码。

- 断线不丢会话（tmux + mosh / ttyd）
- 多会话并发 + 菜单式管理
- iOS / Android / 鸿蒙 三端可用

## 版本

| 目录 | 版本 | 适用场景 |
|---|---|---|
| [`single/`](single/) | 单用户版 | 个人自用，一台服务器自己连 |
| `multi/` | 多用户版 | 内部团队，员工入职建账号、离职删账号，各自隔离 |

## 快速导航

- 单用户版：见 [`single/README.md`](single/README.md) 或 [`single/远程AI编码环境搭建指南.md`](single/远程AI编码环境搭建指南.md)
- 多用户版：见 `multi/README.md`（开发中）

## 技术栈

- **tmux**：会话永驻，断线不丢
- **mosh**：UDP 抗断线连接（iOS/Android）
- **ttyd + Caddy**：网页终端 + 自动 HTTPS（鸿蒙/临时设备兜底）
- **Claude Code + DeepSeek**：大模型在服务端写代码
