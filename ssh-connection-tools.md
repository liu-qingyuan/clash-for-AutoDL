# SSH 连接保持工具安装指南

本文档介绍如何安装和使用 tmux 和 mosh 来防止 SSH 连接断开。

## tmux 安装与使用

### 什么是 tmux
tmux 是一个终端复用器，它允许在单个终端窗口中创建多个会话，并在网络断开后保持会话状态。

### 安装 tmux

#### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install tmux
```

#### CentOS/RHEL
```bash
sudo yum install tmux
# 或者在较新版本中
sudo dnf install tmux
```

#### macOS
```bash
brew install tmux
```

#### 编译安装（适用于其他系统）
```bash
# 下载源码
wget https://github.com/tmux/tmux/releases/download/3.3a/tmux-3.3a.tar.gz
tar -xzf tmux-3.3a.tar.gz
cd tmux-3.3a

# 安装依赖（Ubuntu/Debian）
sudo apt-get install build-essential libevent-dev libncurses-dev

# 配置并安装
./configure && make
sudo make install
```

### tmux 基本使用

#### 创建新会话
```bash
# 创建命名会话
tmux new -s mysession

# 创建默认名称的会话
tmux new
```

#### 分离会话
在 tmux 会话中按 `Ctrl + b` 然后按 `d`

#### 重新连接会话
```bash
# 列出所有会话
tmux ls

# 重新连接指定会话
tmux attach -t mysession
# 或简写
tmux a -t mysession
```

#### 常用快捷键
- `Ctrl + b` + `c`：创建新窗口
- `Ctrl + b` + `w`：列出所有窗口
- `Ctrl + b` + `n`：切换到下一个窗口
- `Ctrl + b` + `p`：切换到上一个窗口
- `Ctrl + b` + `0-9`：切换到指定编号的窗口
- `Ctrl + b` + `%`：水平分割窗口
- `Ctrl + b` + `"`：垂直分割窗口
- `Ctrl + b` + `x`：关闭当前面板

## mosh 安装与使用

### 什么是 mosh
mosh (Mobile Shell) 是一个替代 SSH 的远程终端工具，专门为不稳定的网络连接设计，支持无缝漫游和断线重连。

### 安装 mosh

#### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install mosh
```

#### CentOS/RHEL
```bash
sudo yum install mosh
# 或者在较新版本中
sudo dnf install mosh
```

#### macOS
```bash
brew install mosh
```

#### 编译安装（适用于其他系统）
```bash
# 安装依赖（Ubuntu/Debian）
sudo apt-get install build-essential libssl-dev libprotobuf-dev protobuf-compiler libutempter-dev

# 下载源码
wget https://mosh.org/mosh-1.4.0.tar.gz
tar -xzf mosh-1.4.0.tar.gz
cd mosh-1.4.0

# 配置并安装
./configure && make
sudo make install
```

### mosh 使用

#### 基本连接
```bash
# 使用默认设置连接
mosh user@hostname

# 指定端口
mosh --port=60001 user@hostname

# 使用 SSH 配置文件中的服务器设置
mosh server-name-from-ssh-config
```

#### 常用参数
```bash
# 指定端口范围
mosh --port=60000:60010 user@hostname

# 指定颜色支持
mosh --colors=256 user@hostname

# 禁用本地回显
mosh --no-local-echo user@hostname
```

### 防火墙配置
mosh 使用 UDP 端口 60000-61000，需要确保防火墙允许这些端口：

#### iptables
```bash
sudo iptables -I INPUT -p udp --dport 60000:61000 -j ACCEPT
```

#### ufw (Ubuntu)
```bash
sudo ufw allow 60000:61000/udp
```

#### firewalld (CentOS/RHEL)
```bash
sudo firewall-cmd --add-port=60000-61000/udp --permanent
sudo firewall-cmd --reload
```

## 组合使用建议

### 最佳实践
1. **长期运行任务**：使用 `tmux` + SSH 连接
2. **不稳定的网络环境**：使用 `mosh`
3. **移动设备连接**：优先使用 `mosh`
4. **服务器管理**：`mosh` + `tmux` 组合使用

### 组合使用示例
```bash
# 使用 mosh 连接服务器
mosh user@hostname

# 在 mosh 会话中启动 tmux
tmux new -s work

# 现在即使网络不稳定，连接也能自动恢复，并且 tmux 会话保持状态
```

## 故障排除

### tmux 常见问题
1. **无法连接到现有会话**：
   ```bash
   # 强制杀死会话
   tmux kill-session -t mysession
   ```

2. **显示问题**：
   ```bash
   # 设置正确的终端类型
   export TERM=screen-256color
   ```

### mosh 常见问题
1. **连接失败**：
   - 检查防火墙设置
   - 确认 UDP 端口 60000-61000 开放

2. **编码问题**：
   ```bash
   # 设置正确的编码
   export LANG=en_US.UTF-8
   ```

3. **性能问题**：
   ```bash
   # 减少预测延迟
   mosh --predict=experimental user@hostname
   ```

## 总结

- **tmux**：适合保持长期运行的会话，需要手动重连
- **mosh**：适合不稳定的网络环境，自动重连
- **组合使用**：最佳解决方案，既保持会话状态又能自动重连

选择合适的工具取决于你的具体使用场景和网络环境。