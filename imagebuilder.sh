#!/usr/bin/env bash
#
# ImageBuilder Quick Build Script
# 用于快速使用 imagebuilder 构建固件并添加额外插件
#
# ============================================================
# 使用说明
# ============================================================
#
# GitHub Actions 使用：
#   1. 进入 Actions -> "ImageBuilder Quick Build"
#   2. 点击 "Run workflow"
#   3. 填写参数：
#      - Device Model: jdcloud_ipq60xx_immwrt
#      - ImageBuilder URL: https://github.com/你的用户名/wrt_release/releases/download/xxx/imagebuilder.tar.zst
#   4. 等待 5-10 分钟，从 Artifacts 下载固件
#
# 本地使用：
#   export EXTRA_PACKAGES="luci-app-extra1 luci-app-extra2"
#   export REMOVE_PACKAGES="package-to-remove1 package-to-remove2"
#   ./imagebuilder.sh jdcloud_ipq60xx_immwrt \
#       "https://github.com/xxx/releases/download/xxx/imagebuilder.tar.zst"
#
# 自定义配置：
#   - 脚本会自动从 deconfig/$MODEL.config 读取包列表
#   - 通过环境变量 EXTRA_PACKAGES 和 REMOVE_PACKAGES 添加/移除包
#   - 创建 files/ 目录放置自定义文件（可选）
#   - 添加新的设备 profile 映射
#
# ============================================================
#

set -e

# 定义颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

error_handler() {
    log_error "Error at line: ${BASH_LINENO[0]}, command: '${BASH_COMMAND}'"
    exit 1
}
trap 'error_handler' ERR

# ============================================================
# 函数：从 .config 文件解析包列表
# ============================================================
#
# 注意：ImageBuilder 不需要配置 feeds
# 只要完整编译时 update.sh 已添加 qmodem feed（第 88-93 行已配置）
# 生成的 ImageBuilder 就包含编译好的 qmodem 包，可直接使用
# ============================================================

parse_packages_from_config() {
    local config_file=$1
    local packages=""
    local count_install=0
    local count_remove=0
    local count_skipped=0
    
    if [ ! -f "$config_file" ]; then
        log_warn "配置文件不存在: $config_file"
        return 1
    fi
    
    log_info "从配置文件读取包列表: $(basename $config_file)"
    
    # 只解析 CONFIG_PACKAGE_ 开头的行
    # =y 或 =m 表示安装，=n 表示移除
    while IFS= read -r line; do
        # 跳过注释和空行
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        
        # 只处理 CONFIG_PACKAGE_ 开头的行
        # 改进的正则：处理等号周围空格、行尾注释
        if [[ "$line" =~ ^CONFIG_PACKAGE_([^=]+)[[:space:]]*=[[:space:]]*([ymn]).*$ ]]; then
            local pkg="${BASH_REMATCH[1]}"
            local state="${BASH_REMATCH[2]}"
            
            # 去除包名中的空格（如果有）
            pkg=$(echo "$pkg" | tr -d ' ')
            
            # 将下划线替换为连字符（OpenWrt 包名规则）
            pkg="${pkg//_/-}"
            
            # 跳过空包名
            if [ -z "$pkg" ]; then
                ((count_skipped++))
                continue
            fi
            
            # y 或 m 表示安装，n 表示移除（添加 - 前缀）
            if [[ "$state" == "n" ]]; then
                packages="$packages -$pkg"
                ((count_remove++))
            else
                packages="$packages $pkg"
                ((count_install++))
            fi
        fi
    done < "$config_file"
    
    log_info "解析完成: 安装 $count_install 个包, 移除 $count_remove 个包, 跳过 $count_skipped 个"
    
    echo "$packages"
}

# ============================================================

MODEL=$1
IMAGEBUILDER_URL=$2

BASE_PATH=$(cd $(dirname $0) && pwd)
WORK_DIR="$BASE_PATH/imagebuilder_work"
FIRMWARE_DIR="$BASE_PATH/firmware"

# 检查参数
if [ -z "$MODEL" ] || [ -z "$IMAGEBUILDER_URL" ]; then
    log_error "用法: $0 <model> <imagebuilder_url>"
    log_error "提示: 使用环境变量 EXTRA_PACKAGES 和 REMOVE_PACKAGES 指定额外的包"
    exit 1
fi

log_info "=========================================="
log_info "ImageBuilder 快速构建"
log_info "=========================================="
log_info "设备型号: $MODEL"
log_info "ImageBuilder URL: $IMAGEBUILDER_URL"

# 从环境变量读取额外的包
if [ -n "$EXTRA_PACKAGES" ]; then
    log_info "额外安装的包: $EXTRA_PACKAGES"
fi
if [ -n "$REMOVE_PACKAGES" ]; then
    log_info "额外移除的包: $REMOVE_PACKAGES"
fi

# 创建工作目录
mkdir -p "$WORK_DIR"
rm -rf "$FIRMWARE_DIR"
mkdir -p "$FIRMWARE_DIR"
cd "$WORK_DIR"

# 下载并解压 ImageBuilder
log_info "下载 ImageBuilder..."
filename=$(basename "$IMAGEBUILDER_URL")

if [ -f "$filename" ]; then
    log_warn "文件已存在，跳过下载"
else
    wget -q --show-progress "$IMAGEBUILDER_URL" -O "$filename" || {
        log_error "下载失败"
        exit 1
    }
fi

log_info "解压 ImageBuilder..."
tar -xf "$filename"

# 查找解压后的目录
builder_dir=$(find . -maxdepth 1 -type d -name "*imagebuilder*" | head -n 1)
if [ -z "$builder_dir" ]; then
    log_error "未找到 ImageBuilder 目录"
    exit 1
fi

cd "$builder_dir"
log_info "进入目录: $(pwd)"

# 根据型号确定 PROFILE
log_info "确定设备 Profile..."
case "$MODEL" in
    *jdcloud_ipq60xx*)
        PROFILE="jdcloud_ax1800-pro"
        ;;
    *jdcloud_ax6000*)
        PROFILE="jdcloud_ax6000"
        ;;
    *redmi_ax6*)
        PROFILE="redmi_ax6"
        ;;
    *redmi_ax5*)
        PROFILE="redmi_ax5"
        ;;
    *cmcc_rax3000m*)
        PROFILE="cmcc_rax3000m"
        ;;
    *qihoo_360v6*)
        PROFILE="qihoo_360v6"
        ;;
    *linksys_mx4*)
        PROFILE="linksys_mx4200"
        ;;
    *x64*)
        PROFILE="generic"
        ;;
    *)
        log_warn "未识别的设备型号，尝试列出可用 profiles..."
        make info 2>/dev/null || true
        log_error "请在脚本中添加 $MODEL 的 profile 映射"
        exit 1
        ;;
esac

log_info "使用 Profile: $PROFILE"

# 准备包列表
log_info "准备包列表..."

# 从配置文件读取包列表
CONFIG_FILE="$BASE_PATH/deconfig/${MODEL}.config"
if [ -f "$CONFIG_FILE" ]; then
    PACKAGES=$(parse_packages_from_config "$CONFIG_FILE")
else
    log_warn "配置文件不存在: $CONFIG_FILE"
    log_warn "使用空的包列表"
    PACKAGES=""
fi

# 添加环境变量指定的额外包
if [ -n "$EXTRA_PACKAGES" ]; then
    log_info "添加额外的包: $EXTRA_PACKAGES"
    PACKAGES="$PACKAGES $EXTRA_PACKAGES"
fi

# 添加环境变量指定的额外移除包
if [ -n "$REMOVE_PACKAGES" ]; then
    log_info "额外移除的包: $REMOVE_PACKAGES"
    # 为每个包添加 - 前缀
    for pkg in $REMOVE_PACKAGES; do
        PACKAGES="$PACKAGES -$pkg"
    done
fi

# 去除多余空格
PACKAGES=$(echo "$PACKAGES" | xargs)

log_info "最终包列表: $PACKAGES"

# 创建自定义文件目录（可选）
FILES_DIR="$BASE_PATH/files"
if [ -d "$FILES_DIR" ]; then
    log_info "使用自定义文件: $FILES_DIR"
    FILES_OPT="FILES=$FILES_DIR"
else
    FILES_OPT=""
fi

# 构建固件
log_info "开始构建固件..."
log_info "=========================================="

if ! make image \
    PROFILE="$PROFILE" \
    PACKAGES="$PACKAGES" \
    $FILES_OPT; then
    log_error "构建失败"
    exit 1
fi

log_info "=========================================="
log_info "构建成功！"

# 收集固件文件
log_info "收集固件文件..."

bin_dir=$(find . -type d -name "bin" | head -n 1)
if [ -z "$bin_dir" ]; then
    log_error "未找到固件输出目录"
    exit 1
fi

# 复制所有固件相关文件
find "$bin_dir" -type f \
    \( -name "*.bin" -o -name "*.img" -o -name "*.img.gz" \
    -o -name "*.manifest" -o -name "sha256sums" \) \
    -exec cp -v {} "$FIRMWARE_DIR/" \;

# 生成包列表
if [ -f "$bin_dir/targets/"*"/"*"/*.manifest" ]; then
    cp "$bin_dir/targets/"*"/"*"/*.manifest" "$FIRMWARE_DIR/packages.txt"
fi

log_info "=========================================="
log_info "固件文件已保存到: $FIRMWARE_DIR"
log_info "=========================================="

ls -lh "$FIRMWARE_DIR"

log_info ""
log_info "✅ 构建完成！"
log_info ""
