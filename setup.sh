#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════
#  远程 AI 编码环境 · 一键初始化脚本
#  目标：Ubuntu 24.04（腾讯云轻量香港 4核8G）
#  装好：tmux + mosh + ttyd + Caddy(HTTPS)，并跑起 Claude Code
#  用法：以 root 或 sudo 用户登录服务器后执行  bash setup.sh
# ════════════════════════════════════════════════════════════════

# ────────────────────────────────────────────────────────────────
#  配置项（后期只需改这里）
# ────────────────────────────────────────────────────────────────
DOMAIN="code.thinkers.top"            # 固定入口域名（唯一，不用子域名）
SERVER_USER="ubuntu"                  # 服务器登录用户名（按实际改）
TTYD_PORT="7681"                      # ttyd 本地回环端口（内网，不用改）
TTYD_USER="admin"                     # 网页终端登录名（可改）
# TTYD_PASS 不在此写死，改由环境变量提供（部署时交互式输入）
TTYD_PASS="${TTYD_PASS:-}"            # 从环境变量读取；为空则脚本会强制要求提供
# ────────────────────────────────────────────────────────────────

# 密码校验：必须通过环境变量传入，否则中止，避免留空密码或写死在文件里
if [ -z "$TTYD_PASS" ]; then
  echo "✗ 未提供网页终端密码。请用 TTYD_PASS 环境变量传入："
  echo "    export TTYD_PASS='你的强密码' && bash setup.sh"
  exit 1
fi

set -euo pipefail

log() { echo -e "\n\033[1;32m==>\033[0m $*"; }

# 校验运行身份与系统
if [ "$(id -u)" -ne 0 ] && ! sudo -n true 2>/dev/null; then
  echo "需要 root 权限或免密 sudo。请用 sudo 运行：sudo bash setup.sh"
  exit 1
fi

SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO="sudo"

log "1/9 更新系统"
$SUDO apt-get update -y
$SUDO apt-get upgrade -y

log "2/9 安装 tmux + mosh + 基础工具"
$SUDO apt-get install -y tmux mosh curl git wget vim ca-certificates

log "3/9 确认 Claude Code 已安装（已装则跳过）"
if ! command -v claude >/dev/null 2>&1; then
  log "   下载安装 Claude Code CLI..."
  curl -fsSL https://claude.ai/install.sh | sh
else
  log "   已检测到 claude，跳过安装"
fi

log "4/9 mosh 防火墙放行（UDP 60000-60010 / SSH 22 / HTTP 80,443）"
if command -v ufw >/dev/null 2>&1; then
  $SUDO ufw allow 22/tcp       || true
  $SUDO ufw allow 80/tcp       || true
  $SUDO ufw allow 443/tcp      || true
  $SUDO ufw allow 60000:60010/udp || true
  log "   ufw 规则已加（若 ufw 未启用会忽略；腾讯云安全组需另放行 UDP）"
else
  log "   未检测到 ufw，请到腾讯云控制台安全组放行 60000-60010/UDP"
fi

log "5/9 写入基础 tmux 配置"
cat > ~/.tmux.conf <<'EOF'
set-option -g default-shell /bin/bash
set -g mouse on
set-option -g history-limit 100000
set -g status-bg colour236
set -g status-right '#(date +%H:%M)'
EOF

log "6/9 安装 ttyd（网页终端，供鸿蒙/临时设备）"
if ! command -v ttyd >/dev/null 2>&1; then
  $SUDO apt-get install -y build-essential cmake libjson-c-dev libwebsockets-dev zlib1g-dev libssl-dev
  rm -rf /tmp/ttyd-src
  git clone https://github.com/tsl0922/ttyd.git /tmp/ttyd-src
  cd /tmp/ttyd-src
  git submodule update --init
  mkdir -p build && cd build
  cmake .. && make -j"$(nproc)"
  $SUDO make install
  cd ~
else
  log "   已检测到 ttyd，跳过编译"
fi

log "7/9 让 ttyd 常驻（只监听本机回环，安全）"
$SUDO tee /etc/systemd/system/ttyd.service >/dev/null <<EOF
[Unit]
Description=ttyd web terminal
After=network.target

[Service]
ExecStart=/usr/local/bin/ttyd -p ${TTYD_PORT} -c ${TTYD_USER}:${TTYD_PASS} bash
Restart=always
User=${SERVER_USER}

[Install]
WantedBy=multi-user.target
EOF
$SUDO systemctl daemon-reload
$SUDO systemctl enable --now ttyd

log "8/9 安装 Caddy（自动 HTTPS 反向代理）"
$SUDO apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | $SUDO gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  | $SUDO tee /etc/apt/sources.list.d/caddy-stable.list
$SUDO apt-get update -y
$SUDO apt-get install -y caddy

log "9/9 Caddy 把域名反代到本机 ttyd"
$SUDO tee /etc/caddy/Caddyfile >/dev/null <<EOF
${DOMAIN} {
    reverse_proxy localhost:${TTYD_PORT}
}
EOF
$SUDO systemctl enable --now caddy
$SUDO systemctl reload caddy

log "完成 ✅"
cat <<EOF

────────────────────────────────────────────────
  🎉 初始化完成
────────────────────────────────────────────────
  网页终端入口   : https://${DOMAIN}
  登录凭证       : ${TTYD_USER} / （你设置的密码）

  iOS/Android   : 用 mosh + 服务器公网 IP（端口 22）连接
  鸿蒙/临时设备 : 浏览器打开上面的 HTTPS 地址

  ⚠️ 记得做两件事：
  1. 在 DNS 控制台把 ${DOMAIN} 的 A 记录指向本服务器公网 IP
  2. 在腾讯云「安全组」放行 60000-60010/UDP（mosh 必需）

  下一步：上传并配置会话管理脚本 ~/bin/ac，然后 tmux 里跑 claude
────────────────────────────────────────────────
EOF
