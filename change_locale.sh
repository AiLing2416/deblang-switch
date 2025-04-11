#!/bin/bash

# ==============================================================================
# Script Name: change_locale.sh
# Description: Changes the system locale on Debian-based systems with presets.
# Author:      AI Assistant
# Date:        2025-04-07
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

# --- 函数定义 ---

# 显示错误信息并退出
error_exit() {
    echo "错误: $1" >&2
    exit 1
}

# 检查是否以 root 权限运行
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error_exit "此脚本需要 root 权限运行。请使用 'sudo bash $0' 或切换到 root 用户执行。"
    fi
}

# 生成并更新 locale
set_locale() {
    local target_locale="$1"
    local description="${locales[$target_locale]}"

    echo "正在准备设置系统语言为: $description ($target_locale)..."

    # 1. 确保目标 locale 在 /etc/locale.gen 文件中存在且未被注释
    echo "检查 /etc/locale.gen 文件..."
    # 检查是否存在对应的行，忽略前导空格和注释符
    if ! grep -q "^\s*${target_locale}\s\+UTF-8" /etc/locale.gen; then
        echo "警告: ${target_locale} 在 /etc/locale.gen 中未配置或被注释。正在尝试添加/启用..."
        # 如果存在注释行，则取消注释
        if grep -q "^\s*#\s*${target_locale}\s\+UTF-8" /etc/locale.gen; then
            echo "找到已注释的行，正在取消注释..."
            sed -i -E "s/^\s*#\s*(${target_locale}\s+UTF-8)/\1/" /etc/locale.gen || error_exit "修改 /etc/locale.gen 失败。"
        else
            # 如果完全不存在，则添加新行
            echo "未找到相关行，正在添加新行..."
            echo "${target_locale} UTF-8" >> /etc/locale.gen || error_exit "向 /etc/locale.gen 添加行失败。"
        fi
    else
         # 如果存在且未注释，检查是否真的未注释
         if grep -q "^\s*#\s*${target_locale}\s\+UTF-8" /etc/locale.gen; then
            echo "找到已注释的行，正在取消注释..."
            sed -i -E "s/^\s*#\s*(${target_locale}\s+UTF-8)/\1/" /etc/locale.gen || error_exit "修改 /etc/locale.gen 失败。"
         else
            echo "${target_locale} 已在 /etc/locale.gen 中启用。"
         fi
    fi

    # 2. 重新生成 locale 数据
    echo "正在运行 locale-gen..."
    if locale-gen "$target_locale"; then
        echo "locale-gen 执行成功。"
    else
        # 如果指定locale生成失败，尝试生成所有
        echo "警告：指定 locale 生成失败，尝试生成所有已启用的 locales..."
        if locale-gen; then
            echo "locale-gen (全部) 执行成功。"
        else
           error_exit "locale-gen 执行失败。请检查 /etc/locale.gen 文件配置和系统日志。"
        fi
    fi

    # 3. 更新系统默认 locale 设置
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
