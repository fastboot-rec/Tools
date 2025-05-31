#!/bin/bash

set -e

echo "开始系统清理任务..."

# 获取当前正在运行的内核版本
current_kernel=$(uname -r)
echo "当前运行内核版本: $current_kernel"

# 需要保留的元包（用于确保系统能持续接收内核更新）
meta_kernels=("linux-image-cloud-amd64" "linux-headers-cloud-amd64" "linux-image-amd64" "linux-headers-amd64")

# 构建完整保留包名列表
keep_kernels=("${meta_kernels[@]}")
keep_kernels+=("linux-image-$current_kernel" "linux-headers-$current_kernel")

# 查找所有安装的内核相关包（排除非内核包）
installed_kernels=$(dpkg --list | grep -E 'linux-(image|headers)-[0-9]+' | awk '{print $2}')

# 找出准备清除的包（不在保留列表中）
kernels_to_remove=()
for pkg in $installed_kernels; do
    keep=0
    for keep_pkg in "${keep_kernels[@]}"; do
        if [[ "$pkg" == "$keep_pkg" ]]; then
            keep=1
            break
        fi
    done
    if [[ $keep -eq 0 ]]; then
        kernels_to_remove+=("$pkg")
    fi
done

# 删除前确认
if [ ${#kernels_to_remove[@]} -eq 0 ]; then
    echo "没有需要删除的旧内核。"
else
    echo ""
    echo "⚠️ 以下旧内核包将被删除："
    for k in "${kernels_to_remove[@]}"; do
        echo " - $k"
    done
    echo ""
    read -p "是否继续删除上述内核包？(y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        sudo apt purge -y "${kernels_to_remove[@]}"
    else
        echo "❌ 删除操作已取消。"
    fi
fi

# 自动清理无用包
echo "执行自动清理..."
sudo apt autoremove -y

# 清理 apt 缓存
echo "清理 APT 缓存..."
sudo apt clean
sudo apt autoclean

# 清理 systemd 日志（保留3天）
echo "清理 systemd 日志（保留最近3天）..."
sudo journalctl --vacuum-time=3d

# 清理 /tmp 目录
echo "清理 /tmp 目录..."
sudo rm -rf /tmp/*

echo "✅ 系统清理完成。当前内核和元包已保留。"
