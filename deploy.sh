#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════
#  deploy.sh：从本机（你的 Mac）一键部署到香港服务器
#  做什么：上传 setup.sh / ac → 远程执行初始化 → 装会话管理脚本
#  用法：  bash deploy.sh
# ════════════════════════════════════════════════════════════════

# ────────────────────────────────────────────────────────────────
#  配置项（本地：只改这里）
# ────────────────────────────────────────────────────────────────
SERVER_IP="你的服务器公网IP"           # 例如 1.2.3.4
SERVER_USER="ubuntu"                  # 例如 ubuntu 或 root
SSH_PORT="22"                         # SSH 端口
# ────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${SERVER_USER}@${SERVER_IP}"

log() { echo -e "\n\033[1;34m➜\033[0m $*"; }

# ── 交互式输入密码（不落盘、不进 git）──────────────────────────
read_password() {
  local p1 p2
  while true; do
    printf "请输入网页终端密码（至少 8 位，输入不回显）："
    read -r -s p1; echo
    printf "再次输入确认："
    read -r -s p2; echo
    [ "$p1" = "$p2" ] || { echo "✗ 两次输入不一致，请重试"; continue; }
    [ "${#p1}" -ge 8 ] || { echo "✗ 密码太短（至少 8 位）"; continue; }
    TTYD_PASS="$p1"
    return 0
  done
}

# 校验配置
if [ "$SERVER_IP" = "你的服务器公网IP" ]; then
  echo "✗ 请先编辑 deploy.sh 顶部的 SERVER_IP（填入真实 IP）"
  exit 1
fi

if [ ! -f "$SCRIPT_DIR/setup.sh" ] || [ ! -f "$SCRIPT_DIR/ac" ]; then
  echo "✗ 缺少 setup.sh 或 ac，请与 deploy.sh 放在同一目录"
  exit 1
fi

log "0/4 输入网页终端密码（不会写进任何文件）"
read_password

log "1/4 上传脚本到服务器"
scp -P "$SSH_PORT" "$SCRIPT_DIR/setup.sh" "$SCRIPT_DIR/ac" "${TARGET}:~/"

log "2/4 远程执行初始化（密码经环境变量传入，不落盘）"
ssh -p "$SSH_PORT" -t "$TARGET" "TTYD_PASS='${TTYD_PASS}' bash ~/setup.sh"

log "3/4 配置会话管理脚本 ac"
ssh -p "$SSH_PORT" -t "$TARGET" bash -s <<'REMOTE'
set -euo pipefail
mkdir -p ~/bin
mv -f ~/ac ~/bin/ac
chmod +x ~/bin/ac
grep -q 'export PATH="$HOME/bin:$PATH"' ~/.bashrc 2>/dev/null \
  || echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
echo "✓ ac 已就位：~/bin/ac（重新登录生效，或 source ~/.bashrc）"
REMOTE

log "4/4 清理上传的临时文件（setup.sh 已用完）"
ssh -p "$SSH_PORT" "$TARGET" "rm -f ~/setup.sh"

cat <<EOF

────────────────────────────────────────────────
  ✅ 部署完成
────────────────────────────────────────────────
  服务器已装好：tmux + mosh + ttyd + Caddy + Claude Code

  记得再手动做两件事（脚本无法代办）：
  1. DNS：给 code.thinkers.top 加 A 记录 → ${SERVER_IP}
  2. 安全组：放行 60000-60010/UDP（mosh 必需）

  网页终端登录：admin / （你刚才输入的密码）

  连接试用：
    ssh -p ${SSH_PORT} ${TARGET}
    然后输入  ac  （弹出会话管理菜单）
────────────────────────────────────────────────
EOF
