#!/bin/bash

# ==============================================================================
# Script Name: change_locale.sh
# Description: Changes the system locale on Debian-based systems with presets.
#              (Memory-efficient version for low-resource systems)
# Author:      Gemini
# Date:        2025-08-12
# Usage:       sudo bash change_locale.sh
# Requires:    root privileges, standard Debian utilities (locale-gen, update-locale)
# ==============================================================================

# --- 配置 ---
# 预设语言环境代码及其描述
declare -A locales=(
    ["en_US.UTF-8"]="美式英语 (American English)"
    ["zh_TW.UTF-8"]="台湾繁体中文 (Traditional Chinese, Taiwan)"
    ["zh_CN.UTF-8"]="中国简体中文 (Simplified Chinese, China)"
)
locale_keys=("en_US.UTF-8" "zh_TW.UTF-8" "zh_CN.UTF-8")
LOCALE_GEN_FILE="/etc/locale.gen"
LOCALE_GEN_BACKUP="/etc/locale.gen.backup"

# --- 函数定义 ---

# 显示错误信息并退出
error_exit() {
    echo "错误: $1" >&2
    # 如果备份文件存在，则恢复
    if [ -f "$LOCALE_GEN_BACKUP" ]; then
        echo "正在从备份恢复 $LOCALE_GEN_FILE..."
        mv "$LOCALE_GEN_BACKUP" "$LOCALE_GEN_FILE"
    fi
    exit 1
}

# 检查是否以 root 权限运行
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error_exit "此脚本需要 root 权限运行。请使用 'sudo bash $0' 或切换到 root 用户执行。"
    fi
}

# 清理函数，用于退出时恢复备份
cleanup() {
    if [ -f "$LOCALE_GEN_BACKUP" ]; then
        echo "操作完成，正在恢复原始的 $LOCALE_GEN_FILE 文件..."
        mv "$LOCALE_GEN_BACKUP" "$LOCALE_GEN_FILE" || echo "警告: 恢复备份文件失败。"
    fi
}


# 生成并更新 locale (内存优化版)
set_locale() {
    local target_locale="$1"
    local description="${locales[$target_locale]}"

    echo "正在准备设置系统语言为: $description ($target_locale)..."
    
    # 设置 trap，确保脚本退出时（无论成功还是失败）都尝试恢复备份
    trap cleanup EXIT

    # 1. 备份 /etc/locale.gen 文件
    echo "正在备份 $LOCALE_GEN_FILE 到 $LOCALE_GEN_BACKUP..."
    cp "$LOCALE_GEN_FILE" "$LOCALE_GEN_BACKUP" || error_exit "创建备份文件失败。"

    # 2. 修改 /etc/locale.gen，仅保留目标 locale
    echo "正在修改 $LOCALE_GEN_FILE 以仅启用 $target_locale..."
    # 首先注释掉所有行
    sed -i 's/^/# /' "$LOCALE_GEN_FILE"
    # 然后找到目标 locale 并取消其注释
    # 如果目标 locale 不存在，则添加到文件末尾
    if grep -q "# ${target_locale}" "$LOCALE_GEN_FILE"; then
        sed -i -E "s/^#\s*(${target_locale}\s+UTF-8)/\1/" "$LOCALE_GEN_FILE" || error_exit "在 $LOCALE_GEN_FILE 中启用目标 locale 失败。"
    else
        echo "未在文件中找到 ${target_locale}，正在添加..."
        echo "${target_locale} UTF-8" >> "$LOCALE_GEN_FILE" || error_exit "向 $LOCALE_GEN_FILE 添加新 locale 失败。"
    fi
    
    # 3. 重新生成 locale 数据
    echo "正在运行 locale-gen (仅针对选定语言)..."
    if locale-gen; then
        echo "locale-gen 执行成功。"
    else
        error_exit "locale-gen 执行失败。请检查系统日志。"
    fi

    # 4. 更新系统默认 locale 设置
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
        # 检查 LANG 是否被正确设置
        local current_setting=$(grep -E "^LANG=" /etc/default/locale)
        if [[ "$current_setting" == "LANG=$expected_locale" ]]; then
            echo "检验成功: /etc/default/locale 文件中的 LANG 已正确设置为 $expected_locale。"
        else
            echo "检验警告: /etc/default/locale 文件中的 LANG 设置 ($current_setting) 与预期 ($expected_locale) 不符。请手动检查。"
        fi
    else
        echo "检验警告: 无法找到或读取 /etc/default/locale 文件。"
    fi

    echo -e "\n请注意：语言环境的更改通常需要您 **重新登录** 或 **重启系统** 才能完全生效。"
    echo "您可以通过在新终端中运行 'locale' 命令来检查当前会话的设置（可能需要重开终端）。"
}

# --- 主程序 ---

# 0. 权限检查
check_root

# 1. 显示菜单并获取用户选择
echo "请选择要设置的系统语言："
options=()
for key in "${locale_keys[@]}"; do
    options+=("${locales[$key]} (${key})")
done
options+=("退出脚本")

PS3="请输入选项编号: " # 设置 select 命令的提示符
select opt in "${options[@]}"; do
    # $REPLY 是用户输入的数字
    choice_index=$((REPLY - 1))

    if [[ "$REPLY" -ge 1 && "$REPLY" -le ${#locale_keys[@]} ]]; then
        selected_locale=${locale_keys[$choice_index]}
        echo "您选择了: ${locales[$selected_locale]} ($selected_locale)"
        break # 退出 select 循环
    elif [[ "$REPLY" == "$((${#options[@]}))" ]]; then
        echo "操作已取消，退出脚本。"
        exit 0
    else
        echo "无效选项 '$REPLY'，请重新输入。"
    fi
done

# 2. 设置选定的 locale
set_locale "$selected_locale"

# 3. 执行检验
verify_locale "$selected_locale"

exit 0
