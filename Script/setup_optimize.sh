#!/bin/bash
#
# Debian 初始化配置脚本（个人使用版）
# 功能：基础工具安装、Zsh 配置、防火墙设置、Fail2Ban 安全防护
# 2026 个人优化版 - 加入 dist-upgrade + fastfetch

set -euo pipefail

#==========================================================
# 函数：交互式确认
#==========================================================
confirm() {
    local prompt="$1"
    local default=${2:-y}
    while true; do
        read -rp $'\e[33m'"$prompt [Y/n] "$'\e[0m' answer
        answer=${answer:-$default}
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) echo -e "\e[31m无效输入，请选择 Y/n\e[0m" ;;
        esac
    done
}

#==========================================================
# 步骤 0: 检查 root 权限
#==========================================================
if [ "$(id -u)" != "0" ]; then
   echo -e "\e[31m[!] 此脚本需要 root 权限，请使用 sudo 运行！\e[0m"
   exit 1
fi

#==========================================================
# 步骤 1: 系统检测 (仅 Debian)
#==========================================================
echo -e "\n\e[36m[+] 正在检测操作系统...\e[0m"

if [ ! -f /etc/os-release ]; then
    echo -e "\e[31m[!] 无法检测系统版本，/etc/os-release 不存在\e[0m"
    exit 1
fi

. /etc/os-release

if [[ "$ID" != "debian" ]]; then
    echo -e "\e[31m[!] 当前系统 ($ID) 不在支持范围，仅支持 Debian\e[0m"
    exit 1
fi

echo -e "\e[32m[√] 系统检测通过：$PRETTY_NAME\e[0m"

#==========================================================
# 步骤 2: 自动读取 SSH 端口
#==========================================================
echo -e "\n\e[36m[+] 正在读取 SSH 端口...\e[0m"

ssh_port=$(grep -iE "^Port\s+" /etc/ssh/sshd_config | awk '{print $2}' | head -n1)

if [ -z "$ssh_port" ]; then
    ssh_port=22
fi

echo -e "\e[32m[√] 检测到 SSH 端口: $ssh_port\e[0m"

#==========================================================
# 步骤 3: 系统更新 + 升级
#==========================================================
if confirm "[?] 是否执行系统更新和升级（dist-upgrade）？"; then
    echo -e "\n\e[36m[+] 正在更新软件源并升级系统...\e[0m"
    
    apt-get update -yq
    apt-get dist-upgrade -yq
    apt-get autoremove -yq
    apt-get autoclean -yq
    
    echo -e "\e[32m[√] 系统升级完成\e[0m"
fi

#==========================================================
# 步骤 4: 安装基础工具
#==========================================================
if confirm "[?] 是否安装常用工具和依赖包？"; then
    echo -e "\n\e[36m[+] 正在安装常用工具...\e[0m"

    # 先装核心工具（尽量少依赖）
    apt-get install -y --no-install-recommends \
        screen zsh \
        zsh-syntax-highlighting zsh-autosuggestions \
        rsyslog fail2ban ufw fastfetch htop curl wget git

    # 再装 iperf3（可选依赖较多）
    apt-get install -y iperf3

    echo -e "\e[32m[√] 基础工具安装完成\e[0m"
fi

#==========================================================
# 步骤 5: 配置 Zsh + Powerlevel10k
#==========================================================
if confirm "[?] 是否配置 Zsh 和 Powerlevel10k？"; then
    echo -e "\n\e[36m[+] 正在配置 Zsh...\e[0m"

    if [ ! -d "/root/powerlevel10k" ]; then
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /root/powerlevel10k
    fi

    # 避免重复添加
    grep -q "source.*powerlevel10k/powerlevel10k.zsh-theme" /root/.zshrc 2>/dev/null || \
        echo 'source ~/powerlevel10k/powerlevel10k.zsh-theme' >> /root/.zshrc

    grep -q "autoload -Uz compinit" /root/.zshrc 2>/dev/null || \
        echo -e 'autoload -Uz compinit\ncompinit' >> /root/.zshrc

    grep -q "\.p10k.zsh" /root/.zshrc 2>/dev/null || \
        echo '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh' >> /root/.zshrc

    grep -q "zsh-autosuggestions.zsh" /root/.zshrc 2>/dev/null || \
        echo 'source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh' >> /root/.zshrc

    grep -q "zsh-syntax-highlighting.zsh" /root/.zshrc 2>/dev/null || \
        echo 'source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' >> /root/.zshrc

    chsh -s /bin/zsh root

    echo -e "\e[32m[√] Zsh 配置完成，重新登录后生效\e[0m"
    echo "     建议第一次登录后运行：p10k configure"
fi

#==========================================================
# 步骤 6: 配置防火墙 UFW
#==========================================================
if confirm "[?] 是否配置并启用防火墙 (UFW)？"; then
    echo -e "\n\e[36m[+] 正在配置 UFW...\e[0m"

    # 默认策略
    ufw default deny incoming
    ufw default allow outgoing

    # 开放已知的 SSH 端口
    ufw allow "$ssh_port/tcp"

    # iperf3（可选）
    if confirm "[?] 开放 iperf3 端口 5201？"; then
        ufw allow 5201/tcp
    fi

    if confirm "[?] 现在启用防火墙？（默认Y）"; then
        ufw --force enable
        echo -e "\e[32m[√] 防火墙已启用，当前规则：\e[0m"
        ufw status numbered
    else
        echo -e "\e[33m[!] 防火墙已配置但暂未启用，可随时使用 'ufw enable' 开启\e[0m"
    fi
fi

#==========================================================
# 步骤 7: 配置 Fail2Ban (仅 SSH)
#==========================================================
if confirm "[?] 是否安装并配置 Fail2Ban（仅 SSH）？"; then
    echo -e "\n\e[36m[+] 正在配置 Fail2Ban...\e[0m"

    mkdir -p /etc/fail2ban/jail.d

    cat > /etc/fail2ban/jail.d/sshd-only.local << EOF
[sshd]
enabled   = true
port      = $ssh_port
filter    = sshd
backend   = systemd
logpath   = /var/log/auth.log

bantime   = 72h
findtime  = 20m
maxretry  = 5

banaction = nftables-multiport
EOF

    systemctl enable --now fail2ban

    echo -e "\e[32m[√] Fail2Ban 已启用\e[0m"
    fail2ban-client status sshd || echo -e "\e[33m(如果没看到 jail 信息，可能是日志还没产生，稍后重试)\e[0m"
fi

#==========================================================
# 完成提示
#==========================================================
echo -e "\n\e[32m✅ 所有初始化操作已完成！\e[0m"
echo "当前状态概览："
echo "  • SSH 端口          : $ssh_port"
echo "  • 系统已升级        : $(if [ -n "${dist_upgrade_done:-}" ]; then echo 是; else echo 跳过; fi)"
echo "  • 防火墙开放端口    : $ssh_port $(if ufw status | grep -q 5201; then echo ", 5201"; fi)"
echo "  • Fail2Ban          : 已配置 sshd jail"
echo "  • 推荐操作          : 重新登录使用 Zsh + Powerlevel10k"
echo "                        第一次登录建议运行：  p10k configure"
echo ""
echo -e "\e[33m提示：如果 fail2ban 监控没效果，请确认 /var/log/auth.log 有新登录记录\e[0m"