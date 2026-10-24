# 远程 AI 编码环境搭建指南

> 目标：用手机遥控一台香港云服务器，让 Claude Code（接 DeepSeek）在服务端写代码。
> 断线不丢会话、多会话并发、iOS / Android / 鸿蒙三端可用。

---

## 零、最终方案概览

```
                      香港云服务器（腾讯云轻量 4核8G，Ubuntu 24.04）
                       ┌─────────────────────────────────────────┐
  iOS/Android ── mosh ─┤  tmux 会话 1  ── Claude Code (DeepSeek)  │
  （Blink/Termius）     │  tmux 会话 2  ── Claude Code (DeepSeek)  │
                       │  tmux 会话 N  ── Claude Code (DeepSeek)  │
  鸿蒙(兜底) ── 浏览器──┤  ttyd 网页终端（HTTPS，Basic Auth）      │
  （打开域名）          └─────────────────────────────────────────┘
                      入口：一个固定域名  code.thinkers.top
```

**核心思路**：让「会话状态」和「网络连接」彻底解耦。
- 代码、Claude Code 进程、对话历史 → 全在服务器上（tmux 保存会话）
- 网络断 → 会话照跑，重新连接后 `tmux attach` 一秒接回

---

## 一、服务器端初始化（一次性）

**推荐用 `deploy.sh` 一键部署**（本机脚本已随目录提供，内含 `setup.sh`），无需手工复制粘贴。

### 部署流程（三步）

```bash
# 1. 生成本地配置并填入服务器信息（deploy.local.sh 已被 .gitignore 忽略，不提交）
cp deploy.local.sh.example deploy.local.sh
vim deploy.local.sh          # 填 SERVER_IP / SERVER_USER / SSH_PORT

# 2. 执行（会交互式提示输入网页终端密码，输入不回显、二次确认）
bash deploy.sh
```

`deploy.sh` 会自动完成：读取 `deploy.local.sh` → 上传 → 执行 `setup.sh` → 配置 `ac` → 清理临时文件。

> 服务器 IP、用户名、SSH 端口等私密信息放在 `deploy.local.sh`（不进 git），`deploy.sh` 本体不含任何真实 IP，可安全公开。

### 关于密码（不落盘设计）

- 网页终端密码 **不在任何脚本里写死**，也不进 git。
- 部署时**交互式输入**（不回显 + 二次确认 + 至少 8 位），经 SSH 环境变量一次性传给 `setup.sh`。
- 密码最终只存在于**服务器**的 `/etc/systemd/system/ttyd.service`（ttyd 启动所需）。
- 改密码：编辑服务器上该 service 文件里的 `-c 用户名:密码`，然后 `systemctl restart ttyd`。

### 如果你想手动在服务器上执行（不用 deploy.sh）

以 `root` 或 sudo 用户登录服务器：

```bash
# 上传 setup.sh 后执行；密码用环境变量传入
export TTYD_PASS='你的强密码'
bash setup.sh
```

> 两个手工步骤无论哪种方式都要做（脚本无法代办）：
> 1. DNS：给 `code.thinkers.top` 加 A 记录 → 服务器公网 IP（Caddy 会自动申请 HTTPS 证书）
> 2. 腾讯云安全组：放行 `60000-60010/UDP`（mosh 必需）

---

## 二、会话管理（菜单式 `ac` 命令）

新建 / 历史 / resume / 关闭，都通过菜单操作。脚本已随目录提供（`ac` 文件），`deploy.sh` 会自动配置到 `~/bin/ac`。

若手动配置：

```bash
mkdir -p ~/bin
cp ac ~/bin/ac && chmod +x ~/bin/ac
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### `ac` 的交互菜单

```
=======================================
   AI 编码会话管理
=======================================
   1. 新建会话（新 Claude 对话）
   2. 继续 / 进入某个会话
   3. 恢复历史会话（claude --resume）
   4. 关闭会话（退出 Claude）
   5. 查看所有会话
   0. 退出
---------------------------------------
```

### 会话管理逻辑（`ac` 脚本内部）

脚本文件 `ac` 实现了四个核心动作（对应菜单 1–4）：

| 菜单项 | 底层动作 | 对应你的需求 |
|---|---|---|
| 1 新建 | `tmux new -d -s 名字`，向其中发 `claude`（全新对话） | 新建会话 → 服务端建一个 Claude session |
| 2 继续 | `tmux attach -t 名字` | 进入运行中的会话 |
| 3 恢复历史 | 若 tmux 会话仍在 → attach；若已关 → 重建 tmux 并 `claude --resume`（列出历史供选择） | 选历史会话 → resume 进去 |
| 4 关闭 | 向会话发 `/quit`，再 `tmux kill-session` | 关闭会话 → 退出 Claude |

**关键区别**：`1 新建` 是"全新对话"；`3 恢复` 是"回到之前的对话"。Claude 对话历史由 Claude Code 自身持久化在服务器，独立于 tmux 存亡——所以关闭会话后仍可 resume 找回。

**现状说明**：`ac` 目前通过 `claude --resume` 交互式列出历史会话供手选（最稳、不依赖 Claude Code 未公开接口）。会话名 ↔ conversation ID 的自动映射（`~/.ac_sessions`）属可选增强，等你实测服务器上 Claude Code 版本后再按需补。

---

## 三、三端连接步骤

### iOS（Blink Shell，推荐）
1. App Store 装 **Blink Shell**
2. 添加 Host：地址填服务器公网 IP，端口 `22`
3. 连接方式选 **mosh**
4. 连上后：`tmux attach -t 会话名`（或 `ac`）

### Android（Termius / Shelly）
1. 装 **Termius**（免费版够）或 **Shelly**
2. Host 类型选 **Mosh**
3. 连上后：`tmux attach -t 会话名`

### 鸿蒙（纯血/旧版通吃）
1. 浏览器打开 `https://code.thinkers.top`
2. 输入网页终端的用户名/密码（Basic Auth）
3. 进入后：`ac` 或 `tmux attach -t 会话名`

---

## 四、日常操作清单

| 动作 | 命令 / 按键 |
|---|---|
| 离开会话（后台继续跑） | `Ctrl+B` 松开后按 `D` |
| 接回某个会话 | `tmux attach -t 会话名` |
| 打开管理菜单 | `ac` |
| 列出所有会话 | `tmux ls` |
| 退出 Claude（停 AI 进程） | `/quit` 或 `Ctrl+C` |
| 彻底关闭会话 | `ac` 选 4（停 claude + 关 tmux） |
| 恢复历史对话 | `claude --resume` 或 `ac` 选 3 |

**关键心智模型**
- 关 App / 断网 ≠ 退出会话（tmux 里的 Claude 照跑）
- `Ctrl+B D` 是"暂时离开"，不是"结束"
- Claude 的对话历史独立于 tmux 持久存在，删除 tmux 会话不影响 reseum

---

## 五、安全与运维备忘

1. **密码不落盘、不进 git**：网页终端密码部署时交互式输入，只存在于服务器 `/etc/systemd/system/ttyd.service` 的 `-c 用户名:密码` 这一行；改密码即编辑此处并 `systemctl restart ttyd`。
2. **网页终端务必强密码**：ttyd 的 `-c 用户名:密码` 即 Basic Auth，密码要够长。
3. **Caddy 已自动 HTTPS**：证书自动申请与续期，不需手动管。
4. **mosh 走 UDP 60000-60010**：防火墙已放行，云厂商安全组也要放行（腾讯云控制台 → 安全组）。
5. **改域名后期很轻**：DNS 改 A 记录 + `/etc/caddy/Caddyfile` 改一行 + `systemctl reload caddy`。
6. **升级到动态会话**：本方案用固定域名 + tmux 动态开/关会话，无需子域名/DNS 变更。若将来要多会话各自直达，可平滑升级到泛解析方案。
