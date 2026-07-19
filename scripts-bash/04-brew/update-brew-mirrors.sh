#!/bin/bash
# ============================================================
# 文件名: switch_brew_mirror.sh
# 功能: 将 Homebrew 镜像源从清华切换至中科大（USTC）
# 特性: 
#   - 同时支持 Bash 和 Zsh 配置文件
#   - 直接修改 Homebrew 本地 Git 仓库的远程地址
#   - 检测并提示清除 Git 全局重定向规则
#   - 所有逻辑以函数模块划分，易于维护
#   - 自动编号的步骤进度显示
# 版本: 2.1 (带步骤序号)
# ============================================================

set -euo pipefail

# ------------------------------------------------------------
# 模块1: 全局常量与配置定义
# ------------------------------------------------------------

# 定义主流程中的步骤总数（与 main 中的 log_step 调用数量保持一致）
readonly TOTAL_STEPS=6

# 需要处理的 Shell 配置文件列表
declare -a CONFIG_FILES=(
    "$HOME/.bash_profile"
    "$HOME/.zshrc"
    "$HOME/.profile"
)

# 中科大镜像地址（仅保留有效的 3 个）
readonly USTC_BREW_REPO="https://mirrors.ustc.edu.cn/brew.git"
readonly USTC_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"
readonly USTC_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"

# 用于写入配置文件的环境变量块
get_env_block() {
    cat << 'EOF'
# Homebrew 中科大镜像源（由 switch_brew_mirror.sh 写入）
export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.ustc.edu.cn/brew.git"
export HOMEBREW_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"
export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"
EOF
}

# ------------------------------------------------------------
# 模块2: 工具函数（日志输出）
# ------------------------------------------------------------

# 全局计数器，在 main 中初始化为 0
_STEP_NUM=0

log_info() {
    echo "[INFO] $*"
}

log_success() {
    echo "[SUCCESS] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_step() {
    # 自动递增计数器
    _STEP_NUM=$((_STEP_NUM + 1))
    echo ""
    echo ">>> [STEP ${_STEP_NUM}/${TOTAL_STEPS}] $*"
}

log_warn() {
    echo "[WARN] $*" >&2
}

# ------------------------------------------------------------
# 模块3: 环境变量清理
# ------------------------------------------------------------

clean_brew_env_vars() {
    log_step "清空当前终端中所有 Homebrew 相关环境变量（包括旧的清华源）"
    unset HOMEBREW_BREW_GIT_REMOTE
    unset HOMEBREW_CORE_GIT_REMOTE
    unset HOMEBREW_CASK_GIT_REMOTE
    unset HOMEBREW_BOTTLE_DOMAIN
    unset HOMEBREW_API_DOMAIN
    log_info "当前终端环境变量已清理"
}

# ------------------------------------------------------------
# 模块4: 配置文件处理（备份、清理、写入）
# ------------------------------------------------------------

process_single_config() {
    local file="$1"
    local timestamp
    timestamp=$(date +%Y%m%d%H%M%S)

    if [ ! -f "$file" ]; then
        touch "$file"
        log_info "创建新配置文件: $file"
    else
        cp "$file" "${file}.bak.${timestamp}"
        log_info "已备份: ${file}.bak.${timestamp}"
    fi

    # 删除所有已有的 HOMEBREW_ 环境变量行（兼容 macOS BSD sed）
    sed -i '' '/^[[:space:]]*export[[:space:]]\+HOMEBREW_/d' "$file"
    sed -i '' '/^[[:space:]]*HOMEBREW_/d' "$file"

    get_env_block >> "$file"
    log_info "已写入配置: $file"
}

setup_all_configs() {
    log_step "同时处理 Bash (bash_profile) 和 Zsh (zshrc) 配置文件"
    for file in "${CONFIG_FILES[@]}"; do
        process_single_config "$file"
    done
}

# ------------------------------------------------------------
# 模块5: 直接修改 Homebrew 本地 Git 仓库的远程地址
# ------------------------------------------------------------

reset_single_git_remote() {
    local repo_path="$1"
    local remote_url="$2"
    local repo_name="$3"

    if [ -d "$repo_path" ]; then
        local current_url
        current_url=$(git -C "$repo_path" remote get-url origin 2>/dev/null || echo "")
        if [ "$current_url" != "$remote_url" ]; then
            git -C "$repo_path" remote set-url origin "$remote_url"
            log_success "已将 $repo_name 的 remote 从 '$current_url' 修改为 '$remote_url'"
        else
            log_info "$repo_name 的 remote 已经是 '$remote_url'，无需修改"
        fi
    else
        log_info "$repo_name 本地仓库不存在，跳过"
    fi
}

reset_brew_git_remotes() {
    log_step "直接修改 Homebrew 本地 Git 仓库的远程地址（绕过环境变量干扰）"

    local brew_repo
    brew_repo=$(brew --repo 2>/dev/null) || {
        log_error "无法获取 Homebrew 仓库路径，请确认 Homebrew 已正确安装"
        exit 1
    }
    reset_single_git_remote "$brew_repo" "$USTC_BREW_REPO" "brew.git"

    local core_repo
    core_repo=$(brew --repo homebrew/core 2>/dev/null || echo "")
    if [ -n "$core_repo" ] && [ -d "$core_repo" ]; then
        reset_single_git_remote "$core_repo" "https://mirrors.ustc.edu.cn/homebrew-core.git" "homebrew-core.git"
        log_warn "homebrew-core 的 Git 仓库已弃用，建议执行 'brew untap homebrew/core' 以切换到 API 模式"
    else
        log_info "homebrew-core 本地仓库不存在（API 模式），跳过"
    fi

    local cask_repo
    cask_repo=$(brew --repo homebrew/cask 2>/dev/null || echo "")
    if [ -n "$cask_repo" ] && [ -d "$cask_repo" ]; then
        reset_single_git_remote "$cask_repo" "https://mirrors.ustc.edu.cn/homebrew-cask.git" "homebrew-cask.git"
        log_warn "homebrew-cask 的 Git 仓库已弃用，建议执行 'brew untap homebrew/cask' 以切换到 API 模式"
    else
        log_info "homebrew-cask 本地仓库不存在，跳过"
    fi
}

# ------------------------------------------------------------
# 模块6: 检测并提示清理 Git 全局重定向规则
# ------------------------------------------------------------

check_git_global_redirect() {
    log_step "检查 Git 全局配置中是否存在强制重定向到清华的规则"

    local gitconfig="$HOME/.gitconfig"
    if [ ! -f "$gitconfig" ]; then
        log_info "未找到 ~/.gitconfig，跳过检查"
        return 0
    fi

    local redirect_lines
    redirect_lines=$(grep -E -i 'insteadOf.*(tuna|tsinghua)' "$gitconfig" 2>/dev/null || true)

    if [ -n "$redirect_lines" ]; then
        log_warn "发现 Git 全局重定向规则，可能将 GitHub 请求强制转向清华源："
        echo "--------------------------------------------------"
        echo "$redirect_lines"
        echo "--------------------------------------------------"
        log_warn "这些规则会干扰 brew update，建议您手动编辑 ~/.gitconfig 并删除或注释相关行。"
        log_warn "您也可以执行以下命令查看并编辑："
        echo "  git config --global --edit"
    else
        log_info "未发现指向清华的 Git 全局重定向规则"
    fi
}

# ------------------------------------------------------------
# 模块7: 当前终端环境重载
# ------------------------------------------------------------

reload_current_shell_env() {
    log_step "将新配置加载到当前 Bash 终端"

    if [ -f "$HOME/.bash_profile" ]; then
        # shellcheck source=/dev/null
        source "$HOME/.bash_profile"
        log_success "已加载 ~/.bash_profile"
    elif [ -f "$HOME/.profile" ]; then
        # shellcheck source=/dev/null
        source "$HOME/.profile"
        log_success "已加载 ~/.profile"
    else
        log_error "未找到可加载的配置文件，请重启终端或手动执行 source ~/.bash_profile"
        return 1
    fi

    log_info "当前 HOMEBREW_BOTTLE_DOMAIN = ${HOMEBREW_BOTTLE_DOMAIN:-未设置}"
}

# ------------------------------------------------------------
# 模块8: 验证与更新
# ------------------------------------------------------------

run_brew_update() {
    log_step "执行 brew update 验证新镜像速度"
    brew update --verbose
    local update_exit_code=$?
    if [ $update_exit_code -eq 0 ]; then
        log_success "brew update 执行成功，镜像切换生效"
    else
        log_error "brew update 失败，请检查网络或手动运行 brew update"
        return $update_exit_code
    fi
}

# ------------------------------------------------------------
# 模块9: 最终验证信息展示
# ------------------------------------------------------------

show_final_summary() {
    echo ""
    echo "=========================================="
    log_success "Homebrew 镜像切换至中科大完成！"
    echo ""
    echo "验证命令: brew config | grep -E 'BOTTLE|API|REMOTE'"
    echo "预期输出: 所有地址指向 mirrors.ustc.edu.cn"
    echo ""
    echo "重要提示:"
    echo " - 当前 Bash 终端已生效"
    echo " - 新打开的 Zsh 终端将自动读取 ~/.zshrc"
    echo " - 新打开的 Bash 登录终端将自动读取 ~/.bash_profile"
    echo " - 如果 brew update 仍然缓慢，请检查 ~/.gitconfig 中的 insteadOf 规则"
    echo "=========================================="
}

# ------------------------------------------------------------
# 模块10: 主入口函数（串联所有模块）
# ------------------------------------------------------------

main() {
    # 重置步骤计数器
    _STEP_NUM=0

    log_info "开始执行 Homebrew 镜像切换脚本（中科大源）"

    # 前置检查: 确认 Homebrew 已安装
    if ! command -v brew &> /dev/null; then
        log_error "未检测到 Homebrew，请先安装 Homebrew。"
        exit 1
    fi

    # 按顺序执行各个模块
    clean_brew_env_vars
    setup_all_configs
    reset_brew_git_remotes
    check_git_global_redirect
    reload_current_shell_env
    run_brew_update
    show_final_summary

    log_success "脚本执行完毕。"
}

# ------------------------------------------------------------
# 执行入口
# ------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
