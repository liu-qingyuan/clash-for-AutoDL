#!/bin/bash

# SSH连接保持工具一键安装脚本
# 支持 tmux 和 mosh 的安装、卸载和重装
# 适用于 Ubuntu/Debian 系统

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要root权限运行"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 检查系统类型
check_system() {
    if [[ ! -f /etc/os-release ]]; then
        print_error "无法检测系统类型"
        exit 1
    fi

    source /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        print_warning "此脚本主要支持 Ubuntu/Debian 系统"
        print_info "当前系统: $PRETTY_NAME"
        read -p "是否继续安装? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# 更新包管理器缓存
update_package_cache() {
    print_info "更新包管理器缓存..."
    if apt-get update; then
        print_success "包管理器缓存更新成功"
    else
        print_error "包管理器缓存更新失败"
        exit 1
    fi
}

# 安装单个工具
install_tool() {
    local tool=$1
    print_info "正在安装 $tool..."

    if apt-get install -y $tool; then
        print_success "$tool 安装成功"
        return 0
    else
        print_error "$tool 安装失败"
        return 1
    fi
}

# 卸载单个工具
uninstall_tool() {
    local tool=$1
    print_info "正在卸载 $tool..."

    if apt-get remove --purge -y $tool; then
        print_success "$tool 卸载成功"
        apt-get autoremove -y > /dev/null 2>&1
        return 0
    else
        print_error "$tool 卸载失败"
        return 1
    fi
}

# 检查工具是否已安装
check_tool() {
    local tool=$1
    if command -v $tool &> /dev/null; then
        return 0  # 已安装
    else
        return 1  # 未安装
    fi
}

# 配置 tmux
configure_tmux() {
    if check_tool tmux; then
        local tmux_conf="$HOME/.tmux.conf"
        local current_user=${SUDO_USER:-$USER}
        local user_home=$(getent passwd "$current_user" | cut -d: -f6)

        print_info "配置 tmux 支持鼠标滚动和友好操作..."

        # 创建 tmux 配置文件
        cat > "$user_home/.tmux.conf" << 'EOF'
# ~/.tmux.conf - tmux 配置文件

# 启用鼠标支持
setw -g mouse on

# 设置默认终端模式为 256 色
set -g default-terminal "screen-256color"

# 设置窗口和面板索引从 1 开始（更符合人类习惯）
set -g base-index 1
setw -g pane-base-index 1

# 重新加载配置文件的快捷键 (prefix + r)
bind r source-file ~/.tmux.conf \; display "配置文件已重新加载!"

# 启用活动窗口高亮
setw -g window-status-current-style fg=white,bg=red,bright

# 设置面板边框颜色
set -g pane-border-style fg=green,bg=black
set -g pane-active-border-style fg=white,bg=yellow

# 设置状态栏颜色
set -g status-style fg=white,bg=blue

# 设置状态栏内容
set -g status-left-length 40
set -g status-left "#[fg=green]Session: #S #[fg=yellow]#I #[fg=cyan]#P"
set -g status-right "#[fg=cyan]%d %b %R"

# 启用窗口活动提醒
setw -g monitor-activity on
set -g visual-activity on

# 设置历史记录大小
set -g history-limit 10000

# 启用自动重命名窗口
setw -g automatic-rename on

# 设置复制模式更容易使用
setw -g mode-keys vi

# 分割窗口的快捷键（更直观）
bind | split-window -h
bind - split-window -v

# 在面板之间移动的快捷键
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# 调整面板大小的快捷键
bind -r H resize-pane -L 5
bind -r J resize-pane -D 5
bind -r K resize-pane -U 5
bind -r L resize-pane -R 5

# 鼠标滚动配置
# - 滚轮向上：进入复制模式并向上滚动
# - 滚轮向下：向下滚动或退出复制模式
# - 点击选择面板
bind -n WheelUpPane if-shell -F -t = "#{mouse_any_flag}" "send-keys -M" "if -Ft= '#{pane_in_mode}' 'send-keys -M' 'select-pane -t=; copy-mode -e; send-keys -M'"
bind -n WheelDownPane select-pane -t= \; send-keys -M

# 启用触摸板支持
set -g mouse-utf8 on

EOF

        # 设置正确的文件所有者
        chown "$current_user:$current_user" "$user_home/.tmux.conf"

        print_success "tmux 配置完成！"
        print_info "配置说明："
        print_info "  - 现在可以使用鼠标滚轮滚动查看历史命令"
        print_info "  - 使用 | 键水平分割窗口"
        print_info "  - 使用 - 键垂直分割窗口"
        print_info "  - 使用 Ctrl+b 然后鼠标点击选择面板"
        print_info "  - 使用 Ctrl+b+r 重新加载配置"

    else
        print_warning "tmux 未安装，跳过配置..."
    fi
}

# 安装工具
install_tools() {
    local tools=("tmux" "mosh")
    local failed_tools=()

    update_package_cache

    for tool in "${tools[@]}"; do
        if check_tool $tool; then
            print_warning "$tool 已经安装，跳过..."
        else
            if ! install_tool $tool; then
                failed_tools+=($tool)
            fi
        fi
    done

    if [[ ${#failed_tools[@]} -eq 0 ]]; then
        print_success "所有工具安装完成！"
        show_versions
        configure_tmux  # 安装完成后自动配置 tmux
    else
        print_error "以下工具安装失败: ${failed_tools[*]}"
        exit 1
    fi
}

# 卸载工具
uninstall_tools() {
    local tools=("tmux" "mosh")
    local failed_tools=()

    for tool in "${tools[@]}"; do
        if check_tool $tool; then
            if ! uninstall_tool $tool; then
                failed_tools+=($tool)
            fi
        else
            print_warning "$tool 未安装，跳过..."
        fi
    done

    # 清理 tmux 配置文件
    cleanup_tmux_config

    if [[ ${#failed_tools[@]} -eq 0 ]]; then
        print_success "所有工具卸载完成！"
    else
        print_error "以下工具卸载失败: ${failed_tools[*]}"
        exit 1
    fi
}

# 清理 tmux 配置文件
cleanup_tmux_config() {
    local current_user=${SUDO_USER:-$USER}
    local user_home=$(getent passwd "$current_user" | cut -d: -f6)
    local tmux_conf="$user_home/.tmux.conf"

    if [[ -f "$tmux_conf" ]]; then
        print_info "删除 tmux 配置文件..."
        rm -f "$tmux_conf"
        print_success "tmux 配置文件已删除"
    fi
}

# 重装工具
reinstall_tools() {
    print_info "开始重装工具..."
    uninstall_tools
    print_info "等待2秒后开始重新安装..."
    sleep 2
    install_tools
}

# 显示版本信息
show_versions() {
    print_info "工具版本信息:"

    if check_tool tmux; then
        echo "  tmux: $(tmux -V)"
    fi

    if check_tool mosh; then
        echo "  mosh: $(mosh --version | head -n 1)"
    fi
}

# 显示状态
show_status() {
    print_info "工具安装状态:"

    if check_tool tmux; then
        echo "  tmux: 已安装 ($(tmux -V))"
    else
        echo "  tmux: 未安装"
    fi

    if check_tool mosh; then
        echo "  mosh: 已安装 ($(mosh --version | head -n 1))"
    else
        echo "  mosh: 未安装"
    fi
}

# 显示使用帮助
show_usage() {
    echo "SSH连接保持工具安装脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  install     安装 tmux 和 mosh（包含配置 tmux 支持鼠标滚动）"
    echo "  uninstall   卸载 tmux 和 mosh（清理配置文件）"
    echo "  reinstall   重装 tmux 和 mosh"
    echo "  config      仅配置 tmux（支持鼠标滚动）"
    echo "  status      显示安装状态"
    echo "  help        显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 install    # 安装工具并配置"
    echo "  $0 config     # 仅配置 tmux"
    echo "  $0 status     # 查看状态"
    echo "  $0 reinstall  # 重装工具"
    echo ""
    echo "tmux 配置特性："
    echo "  - 支持鼠标滚轮滚动查看历史命令"
    echo "  - 支持鼠标点击选择面板"
    echo "  - 友好的快捷键：| 水平分割，- 垂直分割"
    echo "  - 256 色彩支持和美观的状态栏"
}

# 主函数
main() {
    local action=${1:-"install"}

    print_info "SSH连接保持工具安装脚本启动"

    case $action in
        "install")
            check_root
            check_system
            install_tools
            ;;
        "uninstall")
            check_root
            uninstall_tools
            ;;
        "reinstall")
            check_root
            check_system
            reinstall_tools
            ;;
        "config")
            configure_tmux
            ;;
        "status")
            show_status
            ;;
        "help"|"-h"|"--help")
            show_usage
            ;;
        *)
            print_error "未知选项: $action"
            echo ""
            show_usage
            exit 1
            ;;
    esac

    print_success "脚本执行完成！"
}

# 运行主函数
main "$@"