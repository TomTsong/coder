# 远程 AI 编码环境

用手机遥控一台香港云服务器，让 Claude Code（接 DeepSeek）在服务端写代码。

- 断线不丢会话（tmux + mosh）
- 多会话并发 + 菜单式管理
- iOS / Android / 鸿蒙 三端可用（固定域名入口）

## 文件组成

| 文件 | 作用 | 运行位置 |
|---|---|---|
| `deploy.sh` | 一键部署（上传 + 初始化 + 配置 + 交互式输密码） | 本机 |
| `deploy.local.sh.example` | 本地部署配置模板（复制为 `deploy.local.sh` 后填真实 IP） | 本机 |
| `setup.sh` | 服务器初始化（tmux/mosh/ttyd/Caddy/Claude Code） | 服务器 |
| `ac` | AI 会话管理菜单（新建/继续/恢复历史/关闭/查看） | 服务器 |
| `远程AI编码环境搭建指南.md` | 完整说明文档 | 阅读 |

## 快速开始

```bash
# 1. 复制配置模板并填入真实服务器信息
cp deploy.local.sh.example deploy.local.sh
vim deploy.local.sh          # 填 SERVER_IP / SERVER_USER / SSH_PORT

# 2. 运行（交互式输入网页终端密码）
bash deploy.sh
```

> `deploy.local.sh` 含真实服务器 IP，已被 `.gitignore` 忽略，不会提交到公开仓库。

## 技术栈

- **tmux**：会话永驻，断线不丢
- **mosh**：UDP 抗断线连接（iOS/Android）
- **ttyd + Caddy**：网页终端 + 自动 HTTPS（鸿蒙/临时设备兜底）
- **Claude Code + DeepSeek**：大模型在服务端写代码

详见 [`远程AI编码环境搭建指南.md`](远程AI编码环境搭建指南.md)。
