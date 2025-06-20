#!/bin/bash

# 定义颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# wget 命令检查
if wget --help | grep -q 'show-progress'; then
    WGET_CMD="wget -q --show-progress"
else
    WGET_CMD="wget -q"
fi

set +m  # 关闭监视模式，不再报告后台作业状态
Status=0  # 脚本运行状态，默认为0，表示成功

#==============================================================
# 设置环境变量
#==============================================================

# 文件路径变量
Server_Dir="$( cd "$( dirname "$(readlink -f "${BASH_SOURCE[0]}")" )" && pwd )"
Conf_Dir="$Server_Dir/conf"
Log_Dir="$Server_Dir/logs"
SUBCONVERTER_DIR="$Server_Dir/subconverter"

# 注入配置文件里面的变量
source $Server_Dir/.env

# 第三方库版本变量
CLASH_VERSION="1.18"
YQ_VERSION="v4.44.3"
SUBCONVERTER_VERSION="v0.9.0"

# 第三方库和配置文件保存路径
YQ_BINARY="$Server_Dir/bin/yq"
log_file="logs/clash.log"
SUBCONVERTER_TAR="subconverter.tar.gz"
Config_File="$Conf_Dir/config.yaml"

# URL变量
URL=${CLASH_URL:?Error: CLASH_URL variable is not set or empty}
# Clash 密钥
Secret=${CLASH_SECRET:-$(openssl rand -hex 32)}

# 下载重试次数
MAX_RETRIES=3
# 下载重试延迟
RETRY_DELAY=5

# Clash 配置
TEMPLATE_FILE="$Conf_Dir/template.yaml"
MERGED_FILE="$Conf_Dir/merged.yaml"

# Subconverter 配置
SUBCONVERTER_URL="http://127.0.0.1:25500/sub"

# GitHub镜像站点列表（按优先级排序）
# 修改镜像站点列表，将 ghfast.top 放在前面
GITHUB_MIRRORS=(
    "ghfast.top/https://github.com"    # GitHub 加速代理
    "github.com"                       # 原站
    "kkgithub.com"
    "gitclone.com"
    "github.hscsec.cn"
    "git.homegu.com"
    "github.ur1.fun"
)

# 提示信息
Text1="Clash订阅地址可访问！"
Text2="Clash订阅地址不可访问！"
Text3="原始配置文件下载成功！"
Text4="原始配置文件下载失败，请检查订阅地址是否正确！"
Text5="服务启动成功！"
Text6="服务启动失败！"

# CPU架构选项
CpuArch_checks=("x86_64" "amd64" "aarch64" "arm64" "armv7")

#==============================================================
# 自定义函数
#==============================================================

# 编码URL
urlencode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * )               printf -v o '%%%02x' "'$c"
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

# 检查YAML文件格式是否正确
check_yaml() {
    local file="$1"
    
    # 检查文件是否为空
    if [ ! -s "$file" ]; then
        echo "错误：文件为空"
        return 1
    fi

    # 检查文件是否包含冒号
    if ! grep -q ':' "$file"; then
        echo "错误：文件不包含冒号，可能不是有效的YAML"
        return 1
    fi

    # 文件非空且包含冒号，视为可能是有效的YAML
    return 0
}

# 通用GitHub文件下载函数（支持镜像站点）
download_github_file() {
    local github_path="$1"      # GitHub路径，如 /Kuingsmile/clash-core/releases/download/v1.18.7/clash-linux-amd64-v1.18.7.gz
    local output_file="$2"      # 输出文件路径
    local description="$3"      # 下载描述
    
    echo -e "${YELLOW}正在下载 $description...${NC}"
    
    # 遍历所有镜像站点
    for mirror in "${GITHUB_MIRRORS[@]}"; do
        local download_url="https://${mirror}${github_path}"
        
        echo "尝试从 $mirror 下载..."
        echo "下载地址: $download_url"
        
        # 尝试下载，最多重试3次
        for attempt in $(seq 1 3); do
            if [ $attempt -gt 1 ]; then
                echo "第 $attempt 次重试..."
            fi
            
            if $WGET_CMD \
                --progress=bar:force:noscroll \
                --retry-connrefused --waitretry=1 --read-timeout=20 --timeout=15 -t 1 \
                -O "$output_file" \
                "$download_url"; then
                
                # 验证下载的文件是否有效（非空且大于1KB）
                if [ -f "$output_file" ] && [ $(stat -c%s "$output_file" 2>/dev/null || echo 0) -gt 1024 ]; then
                    echo -e "${GREEN}✓ 从 $mirror 下载 $description 成功！${NC}"
                    return 0
                else
                    echo -e "${RED}✗ 下载的文件无效，删除并重试...${NC}"
                    rm -f "$output_file"
                fi
            fi
            
            if [ $attempt -lt 3 ]; then
                echo "等待 ${RETRY_DELAY}s 后重试..."
                sleep $RETRY_DELAY
            fi
        done
        
        echo -e "${RED}✗ 从 $mirror 下载失败${NC}"
    done
    
    echo -e "${RED}✗ 所有镜像站点都下载失败: $description${NC}"
    return 1
}

# 下载clash二进制文件
download_clash() {
    local arch=$1
    local github_path="/Kuingsmile/clash-core/releases/download/${CLASH_VERSION}/clash-linux-${arch}-v${CLASH_VERSION}.0.gz"
    local temp_file="/tmp/clash-${arch}.gz"
    local target_file="$Server_Dir/bin/clash-linux-${arch}"
    
    echo -e "${YELLOW}开始下载 Clash for ${arch}...${NC}"
    
    if download_github_file "$github_path" "$temp_file" "Clash for ${arch}"; then
        echo "正在解压 Clash 二进制文件..."
        if gzip -d -c "$temp_file" > "$target_file"; then
            chmod +x "$target_file"
            rm -f "$temp_file"
            echo -e "${GREEN}✓ Clash binary for ${arch} 已准备就绪${NC}"
            return 0
        else
            echo -e "${RED}✗ 解压下载文件失败${NC}"
            rm -f "$temp_file"
        fi
    fi
    
    echo -e "${RED}✗ 无法下载 Clash for ${arch}${NC}"
    return 1
}

# 检查并安装 yq
install_yq() {
    echo -e "${YELLOW}正在安装 yq...${NC}"
    local github_path="/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"
    
    if download_github_file "$github_path" "$YQ_BINARY" "yq"; then
        chmod +x "$YQ_BINARY"
        echo -e "${GREEN}✓ yq 安装成功${NC}"
        return 0
    fi
    
    echo -e "${RED}✗ yq 安装失败${NC}"
    return 1
}

# 安装subconverter
install_subconverter() {
    echo -e "${YELLOW}正在安装 subconverter...${NC}"
    local github_path="/tindy2013/subconverter/releases/download/${SUBCONVERTER_VERSION}/subconverter_linux64.tar.gz"
    local temp_file="/tmp/subconverter.tar.gz"
    
    if download_github_file "$github_path" "$temp_file" "subconverter"; then
        echo "正在解压 subconverter..."
        
        # 捕获tar的输出和退出状态
        tar_output=$(tar -xzf "$temp_file" -C "$Server_Dir" 2>&1)
        tar_status=$?

        if [ $tar_status -eq 0 ]; then
            echo -e "${GREEN}✓ subconverter 安装完成${NC}"
            rm -f "$temp_file"
            return 0
        else
            echo -e "${RED}✗ 解压失败。错误信息:${NC}"
            echo "$tar_output"
            rm -f "$temp_file"
        fi
    fi
    
    echo -e "${RED}✗ subconverter 安装失败，请检查网络连接或手动安装${NC}"
    echo "正在退出..."
    sleep 10
    exit 1
}

# 自定义action函数，实现通用action功能
success() {
    echo -en "\033[60G[${GREEN}  OK  ${NC}]\r"
    return 0
}

failure() {
    local rc=$?
    echo -en "\033[60G[${RED}FAILED${NC}]\r"
    [ -x /bin/plymouth ] && /bin/plymouth --details
    return $rc
}

action() {
    local STRING rc

    STRING=$1
    echo -n "$STRING "
    shift
    "$@" && success $"$STRING" || failure $"$STRING"
    rc=$?
    echo
    return $rc
}

# 判断命令是否正常执行的函数
if_success() {
    local ReturnStatus=${3:-0}  # 如果 \$3 未设置或为空，默认 0
    if [ "$ReturnStatus" -eq 0 ]; then
        action "$1" /bin/true
        Status=0  # 脚本运行状态设置为0，表示成功
    else
        action "$2" /bin/false
        Status=1  # 脚本运行状态设置为1，表示失败
    fi
}

#==============================================================
# 鲁棒性检测
#==============================================================
# 清除变量
unset http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY

# 从 .bashrc 中删除函数和相关行
functions_to_remove=("proxy_on" "proxy_off" "shutdown_system")
for func in "${functions_to_remove[@]}"; do
  sed -i -E "/^function[[:space:]]+${func}[[:space:]]*()/,/^}$/d" ~/.bashrc
done

# 删除相关行
sed -i '/^# 开启系统代理/d; /^# 关闭系统代理/d; /^# 关闭系统函数/d; /^# 检查clash进程是否正常启动/d; /proxy_on/d; /^#.*proxy_on/d' ~/.bashrc
sed -i '/^$/N;/^\n$/D' ~/.bashrc

# 确保logs,conf,bin目录存在
[[ ! -d "$Log_Dir" ]] && mkdir -p $Log_Dir
[[ ! -d "$Conf_Dir" ]] && mkdir -p $Conf_Dir
[[ ! -d "$Server_Dir/bin" ]] && mkdir -p $Server_Dir/bin

# 删除可能存在的转换文件和合并文件
[[ -f "$Conf_Dir/config.yaml.converted" ]] && rm -f "$Conf_Dir/config.yaml.converted"
[[ -f "$Conf_Dir/merged.yaml" ]] && rm -f "$Conf_Dir/merged.yaml"
[[ -f "$Log_Dir/clash.log" ]] && rm -f "$Log_Dir/clash.log"

# 检测并安装subconverter
if [ ! -f "$SUBCONVERTER_DIR/subconverter" ]; then
    install_subconverter
fi

# 检测并安装yq
if [ ! -f "$YQ_BINARY" ]; then
    install_yq
fi

# 设置subconverter参数
SUBCONVERTER_PARAMS="target=clash&url=$(urlencode "${URL}")"
# 检测clash进程是否存在，存在则要先杀掉，不存在就正常执行
pids=$(pgrep -f "clash-linux")
if [ -n "$pids" ]; then
    kill $pids &>/dev/null
fi

#==============================================================
# 配置文件检查与下载
#==============================================================
# 检测config是否下载，没有就下载，有就不下载
if [ -f "$Config_File" ]; then
    echo "配置文件已存在，无需下载。"
else
    echo -e '\n正在检测订阅地址...'
    if curl -o /dev/null -L -k -sS --retry 5 -m 10 --connect-timeout 10 -w "%{http_code}" "$URL" | grep -E '^[23][0-9]{2}$' &>/dev/null; then
        echo "Clash订阅地址可访问！"
        
        echo -e '\n正在下载Clash配置文件...'
        if curl -L -k -sS --retry 5 -m 30 -o "$Config_File" "$URL"; then
            echo "配置文件下载成功！"
        else
            echo "使用curl下载失败，尝试使用wget进行下..."
            if $WGET_CMD -O "$Config_File" "$URL"; then
                echo "使用wget下载成功！"
            else
                echo "配置文件下载失败，请检查订阅地址是否正确！"
                exit 1
            fi
        fi
    else
        echo "Clash订阅地址不可访问！请检查URL或网络连接。"
        exit 1
    fi
fi

#==============================================================
# 配置文件格式验证与转换
#==============================================================
if check_yaml "$Config_File"; then
    echo "配置文件格式正确，无需转换。"
else
    echo "检测到配置文件格式不正确，尝试使用subconverter进行转换..."

    # 启动subconverter
    nohup "$Server_Dir/subconverter/subconverter" > /dev/null 2>&1 &
    SUBCONVERTER_PID=$!
    sleep 2  # 给subconverter一些启动时间

    # 使用subconverter转换配置
    SUBCONVERTER_URL="http://127.0.0.1:25500/sub"
    if curl -s -o "${Config_File}.converted" "${SUBCONVERTER_URL}?${SUBCONVERTER_PARAMS}"; then
        if check_yaml "${Config_File}.converted"; then
            echo "Subconverter转换成功，文件现在是有效的YAML格式。"
            mv "${Config_File}.converted" "$Config_File"
        else
            echo "Subconverter转换失败，无法生成有效的YAML文件。"
            rm "${Config_File}.converted"
            exit 1
        fi
    else
        echo "Subconverter转换过程中发生错误。"
        exit 1
    fi

    # 关闭subconverter进程
    kill $SUBCONVERTER_PID
fi

# 合并配置文件
$YQ_BINARY -n "load(\"$Config_File\") * load(\"$TEMPLATE_FILE\")" > $MERGED_FILE
mv $MERGED_FILE $Config_File

# CPU 配置检测
#==============================================================
# 检测CPU配置，设置CPU相关变量
# 获取CPU架构
if /bin/arch &>/dev/null; then
    CpuArch=`/bin/arch`
elif /usr/bin/arch &>/dev/null; then
    CpuArch=`/usr/bin/arch`
elif /bin/uname -m &>/dev/null; then
    CpuArch=`/bin/uname -m`
else
    echo -e "${RED}\n[ERROR] Failed to obtain CPU architecture！${NC}"
fi

# Check if we obtained CPU architecture, and Status is still 0
if [[ $Status -eq 0 ]]; then
  if [[ -z "$CpuArch" ]] ; then
        echo "Failed to obtain CPU architecture"
        Status=1  # 脚本运行状态设置为1，表示失败
  fi
fi 

#==============================================================
# Clash 二进制文件检查与下载
#==============================================================
# 根据CPU变量，检测是否下载bin，没有就下载，有就不下载
if [[ $Status -eq 0 ]]; then
    ## 启动Clash服务
    echo -e '\n正在启动Clash服务...'
    Text5="服务启动成功！"
    Text6="服务启动失败！"
    if [[ $CpuArch =~ "x86_64" || $CpuArch =~ "amd64"  ]]; then
        clash_bin="$Server_Dir/bin/clash-linux-amd64"
        [[ ! -f "$clash_bin" ]] && download_clash "amd64"
        nohup "$clash_bin" -d "$Conf_Dir" > "$Log_Dir/clash.log" 2>&1 </dev/null &
        disown
        ReturnStatus=$?
        if_success $Text5 $Text6 $ReturnStatus
    elif [[ $CpuArch =~ "aarch64" ||  $CpuArch =~ "arm64" ]]; then
        clash_bin="$Server_Dir/bin/clash-linux-arm64"
        [[ ! -f "$clash_bin" ]] && download_clash "arm64"
        nohup "$clash_bin" -d "$Conf_Dir" > "$Log_Dir/clash.log" 2>&1 </dev/null &
        disown
        ReturnStatus=$?
        if_success $Text5 $Text6 $ReturnStatus
    elif [[ $CpuArch =~ "armv7" ]]; then
        clash_bin="$Server_Dir/bin/clash-linux-armv7"
        [[ ! -f "$clash_bin" ]] && download_clash "armv7"
        nohup "$clash_bin" -d "$Conf_Dir" > "$Log_Dir/clash.log" 2>&1 </dev/null &
        disown
        ReturnStatus=$?
        if_success $Text5 $Text6 $ReturnStatus
    else
        echo -e "${RED}\n[ERROR] Unsupported CPU Architecture！${NC}"
        exit 1
    fi
fi

if [[ $Status -eq 0 ]]; then
    # Output Dashboard access address and Secret
    echo ''
    echo -e "Clash 控制面板访问地址: http://<your_ip>:6006/ui"
    echo ''
fi

#==============================================================
# 自定义命令注入
#==============================================================
CLASH_PORT=$($YQ_BINARY eval '.port' $Config_File)

if [[ $Status -eq 0 ]]; then
    # 定义要添加的函数内容
    cat << EOF > /tmp/clash_functions_template
# 开启系统代理
function proxy_on() {
    local is_quiet=\${1:-false}
    
    export http_proxy=http://127.0.0.1:$CLASH_PORT
    export https_proxy=http://127.0.0.1:$CLASH_PORT
    export no_proxy=127.0.0.1,localhost
    export HTTP_PROXY=http://127.0.0.1:$CLASH_PORT
    export HTTPS_PROXY=http://127.0.0.1:$CLASH_PORT
    export NO_PROXY=127.0.0.1,localhost
    
    if [ #is_quiet != "true" ]; then
        echo -e "${GREEN}[√] 已开启代理${NC}"
    fi
}

# 关闭系统代理
function proxy_off() {
    local is_quiet=\${1:-false}
    
    unset http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY

    if [ #is_quiet != "true" ]; then
        echo -e "${RED}[×] 已关闭代理${NC}"
    fi
}

# 关闭系统函数
function shutdown_system() {
    echo "准备执行系统关闭脚本..."
    $Server_Dir/shutdown.sh
}
EOF

    # 使用 envsubst 替换变量
    if command -v envsubst &> /dev/null; then
        envsubst < /tmp/clash_functions_template > /tmp/clash_functions
    else
        # 纯bash实现变量替换，不依赖envsubst
        eval "cat << EOF
$(cat /tmp/clash_functions_template)
EOF" > /tmp/clash_functions
    fi

    # 在临时函数文件中将 #is_quiet 替换为 $is_quiet
    sed -i 's/#is_quiet/$is_quiet/g' /tmp/clash_functions

    # 将函数追加到 .bashrc
    cat /tmp/clash_functions >> ~/.bashrc
    echo "已添加代理函数到 .bashrc。"

    rm /tmp/clash_functions_template
    rm /tmp/clash_functions

    echo -e "请执行以下命令启动系统代理: proxy_on"
    echo -e "若要临时关闭系统代理，请执行: proxy_off"
    echo -e "若需要彻底删除，请调用: shutdown_system"

    # 询问用户是否要自动添加 proxy_on 命令
    read -p "是否要在 .bashrc 中自动添加 proxy_on 命令？(y/n): " auto_proxy
    if [[ $auto_proxy == "y" || $auto_proxy == "Y" ]]; then
        echo "proxy_on" >> ~/.bashrc
        echo "已在 .bashrc 中添加自动执行 proxy_on 命令。"
        auto_proxy_enabled=true
    else
        echo ""
        echo "未添加自动执行 proxy_on 命令，您可以手动执行该命令来启用代理。"
        auto_proxy_enabled=false
    fi

    # 重新加载 .bashrc
    source ~/.bashrc
fi

# 如果是第一次运行或用户拒绝自动添加，此变量可能未设置
if [ -z "${auto_proxy_enabled+x}" ]; then
    auto_proxy_enabled=false
fi

# 添加 curl 测试
echo "正在测试网络连接..."

# 如果不是自动设置代理，则手动开启代理
is_quiet_mode=true
if [ "$auto_proxy_enabled" = false ]; then
    # 直接定义并使用proxy_on函数，而不是依赖于已加载的函数
    export http_proxy=http://127.0.0.1:$CLASH_PORT
    export https_proxy=http://127.0.0.1:$CLASH_PORT
    export no_proxy=127.0.0.1,localhost
    export HTTP_PROXY=http://127.0.0.1:$CLASH_PORT
    export HTTPS_PROXY=http://127.0.0.1:$CLASH_PORT
    export NO_PROXY=127.0.0.1,localhost
    echo -e "${GREEN}[√] 已临时开启代理进行测试${NC}"
fi

if curl -s -o /dev/null -w "%{http_code}" google.com | grep -qE '^[0-9]+$'; then
    echo -e "${GREEN}网络连接测试成功。${NC}"
else
    echo -e "${RED}网络连接测试失败。请检查您的网络和 Clash 配置。${NC}"
fi

# 如果不是自动设置代理，则手动关闭代理
if [ "$auto_proxy_enabled" = false ]; then
    # 直接清除代理变量，而不是依赖于已加载的函数
    unset http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY
    echo -e "${RED}[×] 已关闭临时测试代理${NC}"
fi

#==============================================================
# 恢复监视模式
set -m