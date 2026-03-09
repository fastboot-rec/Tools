#!/usr/bin/env bash
set -euo pipefail

echo "=== VPS 磁盘清理脚本（针对低空间优化） ==="
echo "目标：保留当前 + 最新 2 个内核，其余全部清理"
echo "当前时间: $(date)"
echo ""

# 1. 显示当前状态
current_kernel=$(uname -r)
echo "当前运行内核: $current_kernel"

# 显示 /boot 空间使用情况
df -h /boot 2>/dev/null || df -h /  # 如果 /boot 是独立分区就显示它，否则显示根分区

# 列出所有已安装的内核（按版本排序）
echo -e "\n已安装的内核列表（按版本排序）："
dpkg -l 'linux-image-[0-9]*' 2>/dev/null | awk '/^ii/ {print $2}' | sort -V || echo "无匹配内核包"

# 找出所有 linux-image-* 包
mapfile -t all_images < <(dpkg -l 'linux-image-[0-9]*' 2>/dev/null | awk '/^ii/ {print $2}' | sort -V)

if [ ${#all_images[@]} -le 2 ]; then
    echo -e "\n只有 ${#all_images[@]} 个内核，无需清理内核。"
else
    # 保留：最新 2 个（数组最后两个）
    keep=("${all_images[-2]}" "${all_images[-1]}")

    # 如果当前内核不在最新两个里（极少见，但防止意外），强制加入
    current_pkg="linux-image-$current_kernel"
    if ! [[ " ${keep[*]} " =~ " $current_pkg " ]]; then
        keep+=("$current_pkg")
        echo "警告：当前内核不在最新两个中，已强制保留"
    fi

    # 收集要删除的包（image + headers + modules + modules-extra）
    to_remove=()
    for pkg in "${all_images[@]}"; do
        if ! [[ " ${keep[*]} " =~ " $pkg " ]]; then
            to_remove+=("$pkg")
            base=${pkg#linux-image-}
            [[ -n "$base" ]] && {
                to_remove+=("linux-headers-$base")
                to_remove+=("linux-modules-${base:-}")
                to_remove+=("linux-modules-extra-${base:-}")
            }
        fi
    done

    # 去重 + 只保留真的已安装的
    to_remove=($(printf '%s\n' "${to_remove[@]}" | sort -u | xargs -r dpkg-query -W -f='${Status} ${Package}\n' 2>/dev/null | awk '$1~/ii/ {print $2}'))

    if [ ${#to_remove[@]} -eq 0 ]; then
        echo -e "\n没有可删除的旧内核。"
    else
        echo -e "\n⚠️  将删除以下包（保留最新 2 个内核）："
        printf '  - %s\n' "${to_remove[@]}"
        echo ""
        echo "预计释放空间：每个内核约 150–400MB（视版本而定）"
        read -p "确认删除？(y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            sudo apt purge -y "${to_remove[@]}"
            sudo update-grub
            echo "内核清理完成，已更新 grub。"
        else
            echo "已取消内核清理。"
        fi
    fi
fi

# 2. 通用清理（无论是否删内核都执行）
echo -e "\n=== 通用清理 ==="
echo "自动移除无用依赖..."
sudo apt autoremove -y --purge

echo "清理 apt 缓存..."
sudo apt autoclean
sudo apt clean

echo "清理 systemd 日志（保留 7 天 + 限制 50MB）..."
sudo journalctl --vacuum-time=7d --vacuum-size=50M

echo "清理 /tmp ..."
sudo systemd-tmpfiles --clean  # 比 rm -rf 更安全

# 3. 最终状态
echo -e "\n=== 清理后状态 ==="
df -h /boot 2>/dev/null || df -h /
free -h

echo -e "\n清理完成！建议：定期运行此脚本（比如每月一次 cron）。"
echo "如果 /boot 还是满，考虑："
echo "1. 升级到更大存储的 VPS 方案"
echo "2. 启用 unattended-upgrades 并配置自动清理旧内核"
echo "   sudo apt install unattended-upgrades"
echo "   然后编辑 /etc/apt/apt.conf.d/50unattended-upgrades"