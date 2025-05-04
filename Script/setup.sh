#!/bin/bash

# 检查是否为 root 用户
if [ "$(id -u)" != "0" ]; then
   echo "此脚本需要以 root 权限运行，请使用 sudo 执行！" 
   exit 1
fi

# 安装基础工具
apt update -y
apt install -y htop curl wget net-tools sudo git screen unzip dnsutils zsh zsh-syntax-highlighting zsh-autosuggestions apt-transport-https ca-certificates btop rsyslog

# 配置 Zsh 和 Powerlevel10k
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /root/powerlevel10k
echo 'source ~/powerlevel10k/powerlevel10k.zsh-theme' >> /root/.zshrc
echo 'autoload -Uz compinit\ncompinit' >> /root/.zshrc
chsh -s /bin/zsh

# 配置防火墙
apt install -y ufw
ufw allow 16789/tcp
yes | ufw enable

# 安装并配置 Fail2Ban
apt install -y fail2ban
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

# 写入自定义配置到 jail.local
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

# 重启服务
systemctl restart fail2ban

# 最终提示
echo -e "\n\033[32m[+] 脚本执行完成！请执行以下操作：\033[0m"
echo "1. 重新登录系统以使 Zsh 配置生效"
echo "2. 确认 SSH 端口已修改为 16789（若未修改请编辑 /etc/ssh/sshd_config）"
echo "3. 使用命令检查防火墙状态：ufw status"
