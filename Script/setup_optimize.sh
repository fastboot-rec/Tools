#!/bin/bash

# 确认函数
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

# 检查 root 权限
if [ "$(id -u)" != "0" ]; then
   echo "[!] 此脚本需要以 root 权限运行，请使用 sudo 执行！" 
   exit 1
fi

# 获取 SSH 端口
while true; do
    read -rp "[?] 请输入 SSH 端口号 (默认 16789): " ssh_port
    ssh_port=${ssh_port:-16789}
    
    if [[ $ssh_port =~ ^[0-9]+$ ]] && [ $ssh_port -gt 0 ] && [ $ssh_port -le 65535 ]; then
        break
    else
        echo "[!] 端口号必须是 1-65535 之间的数字"
    fi
done

# 安装基础工具
if confirm "[?] 是否安装系统工具和依赖包？"; then
    echo -e "\n[+] 正在更新源并安装基础工具..."
    apt update -y
    apt install -y htop curl wget net-tools sudo git screen unzip dnsutils zsh \
    zsh-syntax-highlighting zsh-autosuggestions apt-transport-https ca-certificates \
    btop rsyslog
    echo "[√] 基础工具安装完成"
fi

# 配置 Zsh
if confirm "[?] 是否配置 Zsh 和 Powerlevel10k？"; then
    echo -e "\n[+] 正在配置 Zsh..."
    if [ ! -d "/root/powerlevel10k" ]; then
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /root/powerlevel10k
    fi
    grep -q "powerlevel10k" /root/.zshrc || echo 'source ~/powerlevel10k/powerlevel10k.zsh-theme' >> /root/.zshrc
    grep -q "compinit" /root/.zshrc || echo -e 'autoload -Uz compinit\ncompinit' >> /root/.zshrc
    chsh -s /bin/zsh
    echo "[√] Zsh 配置完成，重新登录后生效"
fi

# 配置防火墙
if confirm "[?] 是否配置防火墙 (UFW)？"; then
    echo -e "\n[+] 正在配置防火墙..."
    apt install -y ufw
    ufw allow "$ssh_port/tcp"
    
    if confirm "[?] 是否启用防火墙？(默认Y)"; then
        yes | ufw enable
        echo -e "[√] 防火墙已启用，当前规则："
        ufw status numbered
    fi
fi

# 配置 Fail2Ban
if confirm "[?] 是否安装配置 Fail2Ban？"; then
    echo -e "\n[+] 正在安装 Fail2Ban..."
    apt install -y fail2ban
    
    echo -e "\n[+] 写入自定义防护规则..."
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 600
findtime = 300
maxretry = 5
banaction = iptables-allports
action = %(action_mwl)s

[sshd]
ignoreip = 127.0.0.1/8
enabled = true
filter = sshd
port = $ssh_port
maxretry = 3
findtime = 30m
bantime = 30d
banaction = ufw
action = %(action_mwl)s
logpath = /var/log/auth.log
EOF

    systemctl restart fail2ban
    echo -e "[√] Fail2Ban 配置完成，当前防护状态："
    fail2ban-client status
fi

# 网络优化配置
if confirm "[?] 是否应用网络优化参数？(将覆盖现有配置)"; then
    echo -e "\n[+] 正在应用网络优化参数..."
    cp /etc/sysctl.conf /etc/sysctl.conf.bak 2>/dev/null
    echo "[!] 原配置已备份为 /etc/sysctl.conf.bak"
    
    cat > /etc/sysctl.conf << EOF
# 基础转发
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1

# TCP优化
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_sack = 1
net.core.somaxconn = 8192
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30

# 安全加固
net.ipv4.icmp_echo_ignore_all = 1
net.ipv6.icmp.echo_ignore_all = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.rp_filter = 1

# 系统资源
vm.swappiness = 10
fs.file-max = 2097152
vm.overcommit_memory = 1

# BBR配置
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

    echo -e "[√] 网络参数已更新，生效结果："
    sysctl -p
fi

# 最终提示
echo -e "\n════════════ 所有配置已完成 ════════════"
echo -e "请执行以下后续操作："
echo -e "1. 当前 SSH 端口：${ssh_port}，请确认已修改 /etc/ssh/sshd_config"
echo -e "2. 常用检查命令："
echo -e "   ufw status verbose         # 查看防火墙状态"
echo -e "   fail2ban-client status sshd # 查看SSH防护状态"
echo -e "   sysctl net.ipv4.tcp_congestion_control"
echo -e "\n* 注意：ICMP响应已全局禁用，如需恢复请修改 /etc/sysctl.conf"
