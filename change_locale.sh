#!/bin/bash

# ==============================================================================
# Script Name: change_locale.sh
# Description: Changes the system locale on Debian-based systems with presets.
#              (Memory-efficient version with auto swap for low-resource systems)
# Author:      Gemini
# Date:        2025-08-12
# Usage:       sudo bash change_locale.sh
# Requires:    root privileges, standard Debian utilities (locale-gen, update-locale)
# ==============================================================================

# --- 配置 ---
declare -A locales=(
    ["en_US.UTF-8"]="美式英语 (American English)"
    ["zh_TW.UTF-8"]="台湾繁体中文 (Traditional Chinese, Taiwan)"
    ["zh_CN.UTF-8"]="中国简体中文 (Simplified Chinese, China)"
)
locale_keys=("en_US.UTF-8" "zh_TW.UTF-8" "zh_CN.UTF-8")
LOCALE_GEN_FILE="/etc/locale.gen"
LOCALE_GEN_BACKUP="/etc/locale.gen.backup"
SWAP_FILE="/tmp/swapfile_temp"
SWAP_ACTIVE=false

# --- 函数定义 ---

# 显示错误信息并退出
error_exit() {
    echo "错误: $1" >&2
    # cleanup 函数会由 trap 调用，这里只需退出
    exit 1
}

# 检查是否以 root 权限运行
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error_exit "此脚本需要 root 权限运行。请使用 'sudo bash $0' 或切换到 root 用户执行。"
    fi
}

# 移除临时交换文件
remove_swap() {
    if [ "$SWAP_ACTIVE" = true ]; then
        echo "正在停用并移除临时交换文件..."
        swapoff "$SWAP_FILE" >/dev/null 2>&1
        rm -f "$SWAP_FILE"
        SWAP_ACTIVE=false
    fi
}

# 恢复 /etc/locale.gen 的备份
restore_locale_gen() {
    if [ -f "$LOCALE_GEN_BACKUP" ]; then
        echo "正在从备份恢复 $LOCALE_GEN_FILE..."
        mv "$LOCALE_GEN_BACKUP" "$LOCALE_GEN_FILE"
    fi
}

# 清理函数，用于脚本退出时执行
cleanup() {
    echo "正在执行清理操作..."
    remove_swap
    restore_locale_gen
}

# 生成并更新 locale (内存优化 + 自动Swap)
set_locale() {
    local target_locale="$1"
    local description="${locales[$target_locale]}"

    echo "正在准备设置系统语言为: $description ($target_locale)..."
    
    # 设置 trap，确保脚本退出时（无论成功还是失败）都执行清理
    trap cleanup EXIT

    # 1. 创建并启用临时交换文件
    echo "检测到低内存环境，正在创建 1GB 临时交换文件以确保操作成功..."
    fallocate -l 1G "$SWAP_FILE" || error_exit "创建交换文件失败。请确保磁盘空间充足。"
    chmod 600 "$SWAP_FILE" || error_exit "设置交换文件权限失败。"
    mkswap "$SWAP_FILE" >/dev/null 2>&1 || error_exit "格式化交换文件失败。"
    swapon "$SWAP_FILE" || error_exit "启用交换文件失败。"
    SWAP_ACTIVE=true
    echo "临时交换文件已启用。"

    # 2. 备份 /etc/locale.gen 文件
    echo "正在备份 $LOCALE_GEN_FILE 到 $LOCALE_GEN_BACKUP..."
    cp "$LOCALE_GEN_FILE" "$LOCALE_GEN_BACKUP" || error_exit "创建备份文件失败。"

    # 3. 修改 /etc/locale.gen，仅保留目标 locale
    echo "正在修改 $LOCALE_GEN_FILE 以仅启用 $target_locale..."
    # 检查目标 locale 是否存在，如果不存在，则先添加
    if ! grep -q "${target_locale}" "$LOCALE_GEN_FILE"; then
        echo "未在文件中找到 ${target_locale}，正在添加..."
        echo "${target_locale} UTF-8" >> "$LOCALE_GEN_FILE" || error_exit "向 $LOCALE_GEN_FILE 添加新 locale 失败。"
    fi
    # 仅取消目标 locale 的注释，其他所有行都注释掉
    sed -i -E "s/^([^#])/# \1/g; s/^#\s*(${target_locale}\s+UTF-8)/\1/" "$LOCALE_GEN_FILE" || error_exit "修改 $LOCALE_GEN_FILE 失败。"

    # 4. 重新生成 locale 数据
    echo "正在运行 locale-gen (已启用交换空间)..."
    if locale-gen; then
        echo "locale-gen 执行成功。"
    else
        error_exit "locale-gen 执行失败。请检查系统日志。"
    fi

    # 5. 更新系统默认 locale 设置
    echo "正在运行 update-locale 将 LANG 设置为 $target_locale..."
    if update-locale LANG="$target_locale"; then
        echo "update-locale 执行成功。"
    else
        error_exit "update-locale 执行失败。"
    fi

    echo "系统默认语言已成功设置为 $description ($target_locale)。"
}

# 执行简易检验
verify_locale() {
    local expected_locale="$1"
    echo -e "\n--- 简易检验 ---"
    echo "检查系统默认 locale 配置文件 (/etc/default/locale)..."

    if [ -f /etc/default/locale ]; then
        echo "文件内容:"
        cat /etc/default/locale
        echo "------------------"
        local current_setting
        current_setting=$(grep -E "^LANG=" /etc/default/locale)
        if [[ "$current_setting" == "LANG=$expected_locale" ]]; then
            echo "检验成功: /etc/default/locale 文件中的 LANG 已正确设置为 $expected_locale。"
        else
            echo "检验警告: /etc/default/locale 文件中的 LANG 设置 ($current_setting) 与预期 ($expected_locale) 不符。请手动检查。"
        fi
    else
        echo "检验警告: 无法找到或读取 /etc/default/locale 文件。"
    fi

    echo -e "\n请注意：语言环境的更改通常需要您 **重新登录** 或 **重启系统** 才能完全生效。"
}

# --- 主程序 ---
check_root

echo "请选择要设置的系统语言："
options=()
for key in "${locale_keys[@]}"; do
    options+=("${locales[$key]} (${key})")
done
options+=("退出脚本")

PS3="请输入选项编号: "
select opt in "${options[@]}"; do
    choice_index=$((REPLY - 1))

    if [[ "$REPLY" -ge 1 && "$REPLY" -le ${#locale_keys[@]} ]]; then
        selected_locale=${locale_keys[$choice_index]}
        echo "您选择了: ${locales[$selected_locale]} ($selected_locale)"
        break
    elif [[ "$REPLY" == "$((${#options[@]}))" ]]; then
        echo "操作已取消，退出脚本。"
        exit 0
    else
        echo "无效选项 '$REPLY'，请重新输入。"
    fi
done

set_locale "$selected_locale"
verify_locale "$selected_locale"

exit 0
