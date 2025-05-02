#!/bin/bash
set -e

# 检查是否以 root 身份运行
if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 权限运行此脚本，例如: sudo $0"
    exit 1
fi

# 配置参数
REPO="heiher/hev-socks5-tunnel"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/tun2socks"
SERVICE_FILE="/etc/systemd/system/tun2socks.service"
BINARY_PATH="$INSTALL_DIR/tun2socks"

# 显示用法信息
usage() {
    echo "用法: $0 [-i | -u]"
    echo "选项:"
    echo "  -i  安装 tun2socks"
    echo "  -u  完全卸载 tun2socks"
    exit 1
}

# 安装函数
install_tun2socks() {
    echo "正在安装 tun2socks..."

    # 获取最新版本下载链接
    DOWNLOAD_URL=$(curl -s https://api.github.com/repos/$REPO/releases/latest | grep "browser_download_url" | grep "linux-x86_64" | cut -d '"' -f 4)
    if [ -z "$DOWNLOAD_URL" ]; then
        echo "错误：无法获取下载链接"
        exit 1
    fi

    # 下载二进制文件
    echo "正在下载最新二进制文件：$DOWNLOAD_URL"
    curl -L -o "$BINARY_PATH" "$DOWNLOAD_URL"
    chmod +x "$BINARY_PATH"

    # 创建配置目录和文件
    echo "创建配置文件..."
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/config.yaml" <<'EOF'
tunnel:
  name: tun0
  mtu: 8500
  multi-queue: true
  ipv4: 198.18.0.1

socks5:
  port: 40000
  address: '2a14:67c0:100::af'
  udp: 'udp'
  username: 'alice'
  password: 'alicefofo123..@'
  mark: 438
EOF

    # 创建 systemd 服务（已修复版本）
    echo "配置 systemd 服务..."
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Tun2Socks Tunnel Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$BINARY_PATH $CONFIG_DIR/config.yaml
CapabilityBoundingSet=CAP_NET_ADMIN
AmbientCapabilities=CAP_NET_ADMIN

ExecStartPost=/bin/sh -c 'sleep 2 && /sbin/ip -6 rule add fwmark 438 lookup main pref 10'
ExecStartPost=/bin/sh -c 'sleep 2 && /sbin/ip route add default dev tun0 table 20'
ExecStartPost=/bin/sh -c 'sleep 2 && /sbin/ip rule add lookup 20 pref 20'

ExecStop=/sbin/ip -6 rule del fwmark 438 lookup main pref 10
ExecStop=/sbin/ip route del default dev tun0 table 20
ExecStop=/sbin/ip rule del lookup 20 pref 20

Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    # 重载 systemd 并启用服务
    systemctl daemon-reload
    systemctl enable tun2socks.service
    systemctl start tun2socks.service

    echo "安装完成！使用 'systemctl status tun2socks.service' 查看服务状态"
}

# 卸载函数
uninstall_tun2socks() {
    echo "开始卸载 tun2socks..."

    # 停止服务并清理路由规则
    if systemctl is-active --quiet tun2socks.service; then
        echo "停止服务..."
        systemctl stop tun2socks.service
    fi

    # 强制清理可能残留的路由规则
    echo "清理网络规则..."
    /sbin/ip -6 rule del fwmark 438 lookup main pref 10 >/dev/null 2>&1 || true
    /sbin/ip route del default dev tun0 table 20 >/dev/null 2>&1 || true
    /sbin/ip rule del lookup 20 pref 20 >/dev/null 2>&1 || true

    # 禁用并删除服务
    if systemctl is-enabled --quiet tun2socks.service; then
        echo "禁用服务..."
        systemctl disable tun2socks.service
    fi
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload

    # 删除相关文件
    echo "删除程序文件..."
    rm -f "$BINARY_PATH"
    rm -rf "$CONFIG_DIR"

    echo "卸载完成！所有相关文件和服务已清理"
}

# 参数处理
if [ $# -ne 1 ]; then
    usage
fi

case "$1" in
    -i) install_tun2socks ;;
    -u) uninstall_tun2socks ;;
    *)  echo "错误：无效参数 '$1'"
        usage
        ;;
esac

exit 0
