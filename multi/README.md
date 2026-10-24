# 多用户版

面向**内部团队**的远程 AI 编码平台：员工入职建账号、离职删账号，各自环境隔离，共用域名登录。

## 架构

```
浏览器 ── coder.thinkers.top ── Caddy(HTTPS)
                                  │
                                  ▼
                            门卫服务 coder-gateway(:8080)
                            ├─ 未登录 → 登录页
                            ├─ POST /login → 校验 users.db(bcrypt)
                            └─ 已登录 → 反代到用户专属 ttyd(:7001~)
                                           │
                              ┌────────────┼────────────┐
                              ▼            ▼            ▼
                         ttyd:alice    ttyd:bob     ttyd:carol
                         tmux -L alice tmux -L bob ...

隔离（软隔离，适配内部可信员工）：
  - 会话：每用户独立 tmux socket，互不可见
  - 文件：每用户独立 HOME /srv/coder/<用户>/
  - 凭证：独立 .claude 历史与 API Key
```

## 文件组成

| 文件 | 作用 |
|---|---|
| `install.sh` | 服务器一键初始化（门卫+ttyd+Caddy） |
| `coder-admin` | 用户管理命令（add/del/list/passwd/purge） |
| `_users.py` | 用户表 JSON 操作助手（被 coder-admin 调用） |
| `coder-gateway/` | 门卫服务源码（Go） |
| `多用户版使用指南.md` | 运维文档（云服务器部署） |
| `家庭自建方案.md` | 家用电脑 + Cloudflare Tunnel 部署 |

## 快速开始

> 两种部署方式：**云服务器**（默认，用 Caddy + DNS A 记录）或 **家庭自建**（废旧电脑 + Cloudflare Tunnel，无需固定 IP）。

### 云服务器部署

```bash
# 1. 初始化（root）
bash install.sh

# 2. DNS 把 coder.thinkers.top 的 A 记录指向服务器

# 3. 建第一个员工账号
coder-admin add alice   # 返回随机初始密码，告知本人
```

### 家庭自建部署（Cloudflare Tunnel）

```bash
# 1. 初始化时跳过 Caddy（Tunnel 处理 HTTPS）
SKIP_CADDY=1 bash install.sh

# 2. 域名托管到 Cloudflare（NS 迁移），详见 家庭自建方案.md
# 3. 搭 Cloudflare Tunnel，让 code.thinkers.top 指向 http://localhost:8080
```

详见 [`家庭自建方案.md`](家庭自建方案.md)。

## 用户生命周期

| 阶段 | 命令 | 效果 |
|---|---|---|
| 入职 | `coder-admin add alice` | 建隔离环境 + 随机初始密码 |
| 日常 | `coder-admin list` | 查看在职/禁用 |
| 改密 | `coder-admin passwd alice` | 重置密码 |
| 离职 | `coder-admin del alice` | 立即禁用 + 归档，7 天后清理 |
| 清理 | `coder-admin purge` | 删超过 7 天的归档（配 cron 自动跑） |

## 安全边界（软隔离）

- 密码 bcrypt 哈希存储，绝不明文
- 门卫校验后方可进入各自 ttyd，未登录/禁用一律拦截
- tmux socket 分离，用户间会话不可见
- **适用前提**：内部可信员工。若面向不信任的外部用户，需升级为容器级硬隔离。

详见 [`多用户版使用指南.md`](多用户版使用指南.md)。
