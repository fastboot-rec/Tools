#!/bin/bash

# 检查 root 权限
if [ "$(id -u)" != "0" ]; then
   echo -e "\033[31m[!] 此脚本需要以 root 权限运行，请使用 sudo 执行！\033[0m" 
   exit 1
fi

# 安装基础工具
echo -e "\n\033[36m[+] 正在更新源并安装基础工具...\033[0m"
apt update -y
apt install -y htop curl wget net-tools sudo git screen unzip dnsutils zsh \
zsh-syntax-highlighting zsh-autosuggestions apt-transport-https ca-certificates \
btop rsyslog
echo -e "\033[32m[√] 基础工具安装完成\033[0m"

# 配置 Zsh
echo -e "\n\033[36m[+] 正在配置 Zsh 和 Powerlevel10k...\033[0m"
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /root/powerlevel10k
echo 'source ~/powerlevel10k/powerlevel10k.zsh-theme' >> /root/.zshrc
echo -e 'autoload -Uz compinit\ncompinit' >> /root/.zshrc
chsh -s /bin/zsh
echo -e "\033[32m[√] Zsh 配置完成，重新登录后生效\033[0m"

# 配置防火墙
echo -e "\n\033[36m[+] 正在配置防火墙...\033[0m"
apt install -y ufw
ufw allow 16789/tcp
yes | ufw enable
echo -e "\033[32m[√] 防火墙已启用，当前规则：\033[0m"
ufw status numbered

# 配置 Fail2Ban
echo -e "\n\033[36m[+] 正在安装 Fail2Ban...\033[0m"
apt install -y fail2ban
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

echo -e "\n\033[36m[+] 写入自定义防护规则...\033[0m"
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
port = 16789
maxretry = 3
findtime = 30m
bantime = 30d
banaction = ufw
action = %(action_mwl)s
logpath = /var/log/auth.log
EOF

systemctl restart fail2ban
echo -e "\033[32m[√] Fail2Ban 配置完成，当前防护状态：\033[0m"
fail2ban-client status

# 网络优化配置
echo -e "\n\033[36m[+] 正在应用网络优化参数...\033[0m"
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

echo -e "\033[32m[√] 网络参数已更新，生效结果：\033[0m"
sysctl -p

# 最终提示
echo -e "\n\033[42m\033[37m============== 所有配置已完成 ==============\033[0m"
echo -e "\033[32m请执行以下后续操作：\033[0m"
echo "1. 重新登录系统以使 Zsh 配置生效"
echo "2. 编辑 SSH 配置文件 (/etc/ssh/sshd_config) 确认端口已改为 16789"
echo "3. 常用检查命令："
echo "   ufw status verbose         # 查看防火墙状态"
echo "   fail2ban-client status sshd # 查看SSH防护状态"
echo "   sysctl net.ipv4.tcp_congestion_control  # 检查BBR状态"
echo -e "\n\033[33m* 注意：ICMP响应已全局禁用，如需恢复请修改 /etc/sysctl.conf\033[0m"
