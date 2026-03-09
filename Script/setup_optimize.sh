#!/bin/bash
#
# Debian 初始化配置脚本
# 功能：基础工具安装、Zsh 配置、防火墙设置、Fail2Ban 安全防护、BBR 网络优化
# 2026 修正版
# 由 ChatGPT 驱动

set -euo pipefail

#==========================================================
# 函数：交互式确认
#==========================================================
confirm() {
    local prompt="$1"
    local default=${2:-y}
    while true; do
        read -rp "$prompt [Y/n] " answer
        answer=${answer:-$default}
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) echo "无效输入，请选择 Y/n" ;;
        esac
    done
}

#==========================================================
# 步骤 1: 系统检测 (仅 Debian)
#==========================================================
echo -e "\n[+] 正在检测操作系统..."

if [ ! -f /etc/os-release ]; then
    echo "[!] 无法检测系统版本，/etc/os-release 不存在"
    exit 1
fi

. /etc/os-release

if [[ "$ID" != "debian" ]]; then
    echo "[!] 当前系统 ($ID) 不在支持范围，仅支持 Debian"
    exit 1
fi

echo "[√] 系统检测通过：$PRETTY_NAME"


#==========================================================
# 步骤 2: 检查 root 权限
#==========================================================
if [ "$(id -u)" != "0" ]; then
   echo "[!] 此脚本需要 root 权限，请使用 sudo 运行！"
   exit 1
fi

#==========================================================
# 步骤 3: 获取 SSH 端口
#==========================================================
while true; do
    read -rp "[?] 请输入 SSH 端口号 (默认 16789): " ssh_port
    ssh_port=${ssh_port:-16789}
    if [[ $ssh_port =~ ^[0-9]+$ ]] && [ $ssh_port -gt 0 ] && [ $ssh_port -le 65535 ]; then
        break
    else
        echo "[!] 端口号必须是 1-65535 之间的数字"
    fi
done
echo "[√] SSH 端口将设置为: $ssh_port"


#==========================================================
# 步骤 4: 安装基础工具
#==========================================================
if confirm "[?] 是否安装系统工具和依赖包？"; then
    echo -e "\n[+] 正在更新软件源并安装常用工具..."
    apt-get update -yq
    apt-get install -yq --no-install-recommends \
        git screen zsh \
        zsh-syntax-highlighting zsh-autosuggestions \
        rsyslog iperf3 ufw fail2ban
    echo "[√] 基础工具安装完成"
fi

#==========================================================
# 步骤 5: 配置 Zsh + Powerlevel10k
#==========================================================
if confirm "[?] 是否配置 Zsh 和 Powerlevel10k？"; then
    echo -e "\n[+] 正在配置 Zsh..."
    if [ ! -d "/root/powerlevel10k" ]; then
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /root/powerlevel10k
    fi
    grep -q "powerlevel10k" /root/.zshrc || echo 'source ~/powerlevel10k/powerlevel10k.zsh-theme' >> /root/.zshrc
    grep -q "compinit" /root/.zshrc || echo -e 'autoload -Uz compinit\ncompinit' >> /root/.zshrc
    grep -q ".p10k.zsh" /root/.zshrc || echo '[[ -r ~/.p10k.zsh ]] && source ~/.p10k.zsh' >> /root/.zshrc
    grep -q "zsh-autosuggestions" /root/.zshrc || echo 'source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh' >> /root/.zshrc
    grep -q "zsh-syntax-highlighting" /root/.zshrc || echo 'source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' >> /root/.zshrc
    chsh -s /bin/zsh
    echo "[√] Zsh 配置完成，重新登录后生效"
fi

#==========================================================
# 步骤 6: 配置防火墙 UFW
#==========================================================
if confirm "[?] 是否配置防火墙 (UFW)？"; then

    echo -e "\n[+] 正在配置防火墙..."

    # 开放 SSH 端口
    ufw allow "$ssh_port/tcp"

    # iperf3
    ufw allow 5201/tcp

    if confirm "[?] 是否启用防火墙？(默认Y)"; then
        ufw --force enable

        echo -e "[√] 防火墙已启用，当前规则："
        ufw status numbered
    fi
fi


#==========================================================
# 步骤 7: 配置 Fail2Ban (仅 SSH)
#==========================================================
if confirm "[?] 是否安装并配置 Fail2Ban？"; then

    echo -e "\n[+] 正在配置 Fail2Ban..."

    mkdir -p /etc/fail2ban/jail.d

    cat > /etc/fail2ban/jail.d/sshd-only.local << EOF
[sshd]

enabled   = true
port      = $ssh_port
filter    = sshd
backend   = systemd

bantime   = 1d
findtime  = 15m
maxretry  = 5

banaction = nftables-multiport
EOF

    systemctl enable --now fail2ban

    echo "[√] Fail2Ban 已启用"
    fail2ban-client status sshd
fi


#==========================================================
# 步骤 8: 配置网络优化 (BBR/FQ)
#==========================================================
if confirm "[?] 是否应用网络优化参数？"; then
    echo -e "\n[+] 正在检测并启用 BBR/FQ..."

    # 尝试加载内核模块（若已内置则会直接成功）
    modprobe tcp_bbr 2>/dev/null || true
    modprobe sch_fq 2>/dev/null || true

    # 检查支持情况
    cc_list=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo "")
    fq_loaded=$(lsmod | grep -q sch_fq && echo yes || echo no)
    bbr_loaded=$(lsmod | grep -q bbr && echo yes || echo no)

    if [[ "$cc_list" == *bbr* || "$bbr_loaded" == "yes" ]]; then
        echo "[√] BBR 拥塞控制已可用"
    else
        echo "[!] 内核未检测到 bbr 拥塞控制，可能内核过旧 (<4.9)"
        uname -r
        exit 1
    fi

    if [[ "$fq_loaded" == "yes" ]]; then
        echo "[√] FQ 调度器已可用"
    else
        echo "[!] 未检测到 FQ 调度器，可能内核配置未启用 sch_fq"
    fi

    # 写入配置文件（不会覆盖原有 sysctl.conf，而是单独文件）
    cat > /etc/sysctl.d/99-bbr.conf << EOF
# 启用 TCP BBR 拥塞控制 + FQ 调度器
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

    # 应用配置
    sysctl --system

    echo "[√] 已启用 BBR/FQ"
    echo "当前拥塞算法: $(sysctl -n net.ipv4.tcp_congestion_control)"
fi

#==========================================================
# 最终提示
#==========================================================
echo -e "\n✅ 所有初始化操作已完成！"
echo "⚠️ 请确认："
echo "1. SSH 服务端口实际运行情况"
echo "2. 防火墙已允许端口: $ssh_port, 5201"
echo "3. Fail2Ban 已启用保护 (sshd)"
echo "4. BBR 拥塞控制生效状态请通过 'sysctl net.ipv4.tcp_congestion_control' 验证"
echo "5. 建议重新登录以使用 Zsh + Powerlevel10k"
