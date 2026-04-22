#!/usr/bin/env bash
# =============================================================
#  BBR + TCP 优化脚本（无人值守）
#  适用: Amazon EC2 C6IN / 2C4G / Singapore 及同类实例
# =============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERR]${NC}   $*"; exit 1; }

# ── 权限检查 ──────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "请以 root 身份运行 (sudo $0)"

# ── 内核版本检查 (BBR 需要 4.9+) ──────────────────────────────
KERNEL_VER=$(uname -r | awk -F'[.-]' '{print $1*10000 + $2*100 + $3}')
[[ $KERNEL_VER -lt 40900 ]] && error "内核版本 $(uname -r) 过旧，BBR 需要 4.9+"

# ── 加载 BBR 模块 ─────────────────────────────────────────────
if ! modinfo tcp_bbr &>/dev/null; then
    modprobe tcp_bbr 2>/dev/null || error "无法加载 tcp_bbr 模块，请检查内核是否支持"
fi
echo "tcp_bbr" > /etc/modules-load.d/tcp_bbr.conf

# ── 备份旧配置 ────────────────────────────────────────────────
[[ -f /etc/sysctl.conf ]] && cp /etc/sysctl.conf "/etc/sysctl.conf.bak.$(date +%Y%m%d_%H%M%S)"

# ── 写入参数 ──────────────────────────────────────────────────
cat > /etc/sysctl.conf << EOF
fs.file-max = 6815744
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_ecn=0
net.ipv4.tcp_frto=0
net.ipv4.tcp_mtu_probing=0
net.ipv4.tcp_rfc1337=0
net.ipv4.tcp_sack=1
net.ipv4.tcp_fack=1
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_adv_win_scale=1
net.ipv4.tcp_moderate_rcvbuf=1
net.core.rmem_max=10000000
net.core.wmem_max=10000000
net.ipv4.tcp_rmem=4096 190054 10000000
net.ipv4.tcp_wmem=4096 190054 10000000
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192
net.ipv4.ip_forward=1
net.ipv4.conf.all.route_localnet=1
net.ipv4.conf.all.forwarding=1
net.ipv4.conf.default.forwarding=1
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

# ── 生效 ──────────────────────────────────────────────────────
sysctl -p &>/dev/null
sysctl --system &>/dev/null

# ── 验证 ──────────────────────────────────────────────────────
CC=$(sysctl -n net.ipv4.tcp_congestion_control)
QD=$(sysctl -n net.core.default_qdisc)

echo ""
echo "============================="
[[ "$CC" == "bbr" ]] && info "拥塞控制: ${GREEN}bbr${NC} ✓" || warn "拥塞控制: ${RED}${CC}${NC} ✗"
[[ "$QD" == "fq"  ]] && info "队列调度: ${GREEN}fq${NC}  ✓"  || warn "队列调度: ${RED}${QD}${NC}  ✗"
echo "============================="
echo ""

[[ "$CC" == "bbr" && "$QD" == "fq" ]] \
    && info "BBR 启用成功，无需重启。" \
    || error "参数未生效，请检查系统日志。"
