#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════
#  multi/install.sh：多用户版一键初始化
#
#  装好：Go 门卫服务 + ttyd + tmux + Caddy(HTTPS)
#  用法：以 root 执行  bash install.sh
# ════════════════════════════════════════════════════════════════

# ── 配置项 ──────────────────────────────────────────────────────
GATEWAY_DOMAIN="coder.thinkers.top"   # 共用域名入口
RUN_USER="coder"                       # 运行服务的基础系统用户
BASE_DIR="/srv/coder"                  # 用户数据根
GATEWAY_ADDR=":8080"                   # 门卫监听
SKIP_CADDY="${SKIP_CADDY:-0}"          # 1=跳过 Caddy（家庭自建 + CF Tunnel 时用）
# ────────────────────────────────────────────────────────────────

set -euo pipefail
SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"
log() { echo -e "\n\033[1;32m==>\033[0m $*"; }

log "1/8 安装基础依赖"
$SUDO apt-get update -y
$SUDO apt-get install -y tmux curl git ca-certificates build-essential \
  cmake libjson-c-dev libwebsockets-dev zlib1g-dev libssl-dev \
  apache2-utils python3 golang-go

log "2/8 检查 Claude Code"
command -v claude >/dev/null 2>&1 || curl -fsSL https://claude.ai/install.sh | sh

log "3/8 安装 ttyd（网页终端）"
if ! command -v ttyd >/dev/null 2>&1; then
  rm -rf /tmp/ttyd-src
  git clone https://github.com/tsl0922/ttyd.git /tmp/ttyd-src
  cd /tmp/ttyd-src
  git submodule update --init
  mkdir -p build && cd build
  cmake .. && make -j"$(nproc)" && $SUDO make install
  cd ~
fi

log "4/8 建运行用户与数据目录"
id -u "$RUN_USER" >/dev/null 2>&1 || $SUDO useradd -m "$RUN_USER"
$SUDO mkdir -p "$BASE_DIR/archive"
$SUDO chown -R "$RUN_USER:$RUN_USER" "$BASE_DIR"
[ -f "$BASE_DIR/users.db" ] || $SUDO -u "$RUN_USER" bash -c "echo '{\"users\":[]}' > '$BASE_DIR/users.db'"

log "5/8 编译门卫服务 coder-gateway"
cd "$(dirname "$0")/coder-gateway"
go mod tidy
go build -o /tmp/coder-gateway .
$SUDO install -m 755 /tmp/coder-gateway /usr/local/bin/coder-gateway

log "6/8 门卫服务 systemd 常驻"
$SUDO tee /etc/systemd/system/coder-gateway.service >/dev/null <<EOF
[Unit]
Description=coder gateway
After=network.target

[Service]
Environment=GATEWAY_ADDR=${GATEWAY_ADDR}
Environment=USERS_FILE=${BASE_DIR}/users.db
ExecStart=/usr/local/bin/coder-gateway
Restart=always
User=${RUN_USER}

[Install]
WantedBy=multi-user.target
EOF
$SUDO systemctl daemon-reload
$SUDO systemctl enable --now coder-gateway

if [ "$SKIP_CADDY" = "1" ]; then
  log "7/8 跳过 Caddy（家庭自建 + Cloudflare Tunnel，由 Tunnel 处理 HTTPS）"
  log "8/8 跳过 Caddy 反代"
else
  log "7/8 安装 Caddy（自动 HTTPS）"
  $SUDO apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | $SUDO gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | $SUDO tee /etc/apt/sources.list.d/caddy-stable.list
  $SUDO apt-get update -y && $SUDO apt-get install -y caddy

  log "8/8 Caddy 反向代理到门卫"
  $SUDO tee /etc/caddy/Caddyfile >/dev/null <<EOF
${GATEWAY_DOMAIN} {
    reverse_proxy localhost:${GATEWAY_ADDR#:}
}
EOF
  $SUDO systemctl enable --now caddy
  $SUDO systemctl reload caddy
fi

log "安装用户管理命令 coder-admin（含 _users.py 助手）"
$SUDO install -m 755 "$(dirname "$0")/coder-admin" /usr/local/bin/coder-admin
$SUDO install -m 755 "$(dirname "$0")/_users.py" /usr/local/bin/_users.py

cat <<EOF

────────────────────────────────────────────────
  ✅ 多用户版初始化完成
────────────────────────────────────────────────
  入口：https://${GATEWAY_DOMAIN}

  接下来（管理员）：
    coder-admin add alice    # 员工入职，返回初始密码
    coder-admin list         # 查看用户
    coder-admin del alice    # 离职：禁用 + 归档

EOF
if [ "$SKIP_CADDY" = "1" ]; then
  cat <<EOF
  ⚠️ 本次跳过了 Caddy。家庭自建请继续配 Cloudflare Tunnel：
    见 multi/家庭自建方案.md → 第五节（搭 CF Tunnel）
    Tunnel 目标设为 http://localhost:${GATEWAY_ADDR#:}

EOF
else
  cat <<EOF
  记得在 DNS 把 ${GATEWAY_DOMAIN} 的 A 记录指到本服务器。

EOF
fi
cat <<EOF
  建议配置归档清理定时任务：crontab 里加
    0 3 * * *  coder-admin purge
────────────────────────────────────────────────
EOF
