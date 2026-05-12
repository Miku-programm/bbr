#!/bin/bash
# =============================================================
#  VPS3 - 一键无人值守安装脚本
#  顺序：SSH 配置 -> nyanpass 安装 -> BBR 优化
#  用法：sudo bash awsjp_c5n_2c_install.sh
# =============================================================
set -euo pipefail

# 避免未生成 en_US.UTF-8 时 bash/工具链反复输出 setlocale 警告。
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

LOG_FILE="/var/log/vps3-install.log"

ROOT_PASSWORD='>Qx$qpG>1.KF3TWHv>Z='

NYANPASS1_URL="https://ny.nypassline.top"
NYANPASS2_URL="https://nyp.pccwg.us"
NYANPASS_INSTALL_URL="https://dl.nyafw.com/download/nyanpass-install.sh"
NYANPASS_TIMEOUT=600
NYANPASS1_NAME="awshk1"
NYANPASS1_TOKEN="5a4e7912-9faa-4a71-9d42-cd76a0ed39ce"
NYANPASS2_NAME="awshk2"
NYANPASS2_TOKEN="185496e8-b7dc-442f-a7d7-76ad24680da2"

log() {
    mkdir -p "$(dirname "$LOG_FILE")"
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" | tee -a "$LOG_FILE"
}

need_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "请用 sudo/root 运行"
        exit 1
    fi
}

fix_locale() {
    if locale -a 2>/dev/null | grep -qi '^en_US\.utf8$'; then
        return 0
    fi

    if command -v locale-gen >/dev/null 2>&1; then
        log INFO "生成 en_US.UTF-8 locale..."
        sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen 2>/dev/null || true
        locale-gen en_US.UTF-8 >/dev/null 2>&1 || true
        update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 >/dev/null 2>&1 || true
    fi
}

install_deps() {
    local missing=()
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    command -v timeout >/dev/null 2>&1 || missing+=("coreutils")

    [[ ${#missing[@]} -eq 0 ]] && return 0

    log INFO "安装依赖：${missing[*]}"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}"
    elif command -v yum >/dev/null 2>&1; then
        yum install -y -q "${missing[@]}"
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y -q "${missing[@]}"
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache "${missing[@]}"
    else
        log ERROR "未找到支持的包管理器，请手动安装：${missing[*]}"
        exit 1
    fi
}

configure_bbr() {
    log INFO "配置 BBR + fq（AWS 日本 c5.large）..."

    if [[ -f /etc/sysctl.conf ]]; then
        cp /etc/sysctl.conf "/etc/sysctl.conf.bak.$(date +%s)" 2>/dev/null || true
    fi

    modprobe tcp_bbr 2>/dev/null || true

    cat > /etc/sysctl.conf <<'EOF'
fs.file-max = 6815744
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_ecn = 0
net.ipv4.tcp_frto = 0
net.ipv4.tcp_mtu_probing = 0
net.ipv4.tcp_rfc1337 = 0
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_adv_win_scale = 1
net.ipv4.tcp_moderate_rcvbuf = 1
net.core.rmem_max = 10000000
net.core.wmem_max = 10000000
net.ipv4.tcp_rmem = 4096 131072 10000000
net.ipv4.tcp_wmem = 4096 131072 10000000
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.ipv4.ip_forward = 1
net.ipv4.conf.all.route_localnet = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.default.forwarding = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

    sysctl -p >/dev/null 2>&1 || log WARN "sysctl -p 应用可能未完全成功"
    sysctl --system >/dev/null 2>&1 || true

    local cc qdisc
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown")
    log INFO "当前拥塞控制算法：$cc"
    log INFO "当前队列算法：$qdisc"
}

configure_ssh() {
    log INFO "配置 SSH root 登录和密码登录..."

    if echo "root:${ROOT_PASSWORD}" | chpasswd 2>/dev/null; then
        log INFO "root 密码设置完成"
    else
        log WARN "root 密码设置可能失败"
    fi

    local sshd_config="/etc/ssh/sshd_config"
    if [[ ! -f "$sshd_config" ]]; then
        log WARN "未找到 $sshd_config，跳过 SSH 配置"
        return 0
    fi

    cp "$sshd_config" "${sshd_config}.bak.$(date +%s)" 2>/dev/null || true
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' "$sshd_config" 2>/dev/null || true
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' "$sshd_config" 2>/dev/null || true
    rm -rf /etc/ssh/sshd_config.d 2>/dev/null || true

    if systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; then
        log INFO "SSH 服务重启完成"
    else
        log WARN "SSH 服务重启可能失败"
    fi
}

install_nyanpass() {
    local instance_num="$1"
    local service_name="$2"
    local install_args="$3"
    local install_cmd

    log INFO "无人值守安装 nyanpass 实例${instance_num}：${service_name}"
    install_cmd="printf '${service_name}\nn\ny\n' | timeout ${NYANPASS_TIMEOUT} bash <(curl -fLSs ${NYANPASS_INSTALL_URL}) rel_nodeclient \"${install_args}\""

    if eval "$install_cmd" 2>&1 | tee -a "$LOG_FILE"; then
        log INFO "nyanpass 实例${instance_num}安装完成：${service_name}"
    else
        log WARN "nyanpass 实例${instance_num}安装可能未完全成功：${service_name}"
    fi
}

install_nyanpass_all() {
    install_nyanpass 1 "$NYANPASS1_NAME" "-o -t ${NYANPASS1_TOKEN} -u ${NYANPASS1_URL}"
    install_nyanpass 2 "$NYANPASS2_NAME" "-o -t ${NYANPASS2_TOKEN} -u ${NYANPASS2_URL}"
}

install_all() {
    need_root
    log INFO "开始 VPS3 一键无人值守安装..."
    fix_locale
    configure_ssh
    install_deps
    install_nyanpass_all
    configure_bbr
    log INFO "全部安装完成"
}

case "${1:-}" in
    *) install_all ;;
esac
