#!/usr/bin/env bash
#
# ImageBuilder Quick Build Script
# Uses an existing ImageBuilder archive and the repo's deconfig files to
# generate a firmware artifact set without a full source build.

set -e

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

    log_info "从配置文件读取包列表: $(basename "$config_file")"

    while IFS= read -r line; do
        local pkg=""
        local state=""

        if [[ "$line" =~ ^#\ CONFIG_PACKAGE_([A-Za-z0-9_+.-]+)\ is\ not\ set$ ]]; then
            pkg="${BASH_REMATCH[1]}"
            state="n"
        elif [[ "$line" =~ ^CONFIG_PACKAGE_([A-Za-z0-9_+.-]+)[[:space:]]*=[[:space:]]*([ymn]).*$ ]]; then
            pkg="${BASH_REMATCH[1]}"
            state="${BASH_REMATCH[2]}"
        else
            continue
        fi

        # ImageBuilder only understands actual package names, not menuconfig feature toggles.
        if [[ "$pkg" =~ [A-Z] ]]; then
            ((count_skipped++))
            continue
        fi

        pkg=$(echo "$pkg" | tr -d ' ')
        pkg="${pkg//_/-}"

        if [ -z "$pkg" ]; then
            ((count_skipped++))
            continue
        fi

        if [[ "$state" == "n" ]]; then
            packages="$packages -$pkg"
            ((count_remove++))
        else
            packages="$packages $pkg"
            ((count_install++))
        fi
    done < "$config_file"

    log_info "解析完成: 安装 $count_install 个包, 移除 $count_remove 个包, 跳过 $count_skipped 个"

    echo "$packages"
}

MODEL=$1
IMAGEBUILDER_URL=$2

BASE_PATH=$(cd "$(dirname "$0")" && pwd)
CORE_PATH="$BASE_PATH/wrt_core"
WORK_DIR="$BASE_PATH/imagebuilder_work"
FIRMWARE_DIR="$BASE_PATH/firmware"

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

if [ -n "$EXTRA_PACKAGES" ]; then
    log_info "额外安装的包: $EXTRA_PACKAGES"
fi
if [ -n "$REMOVE_PACKAGES" ]; then
    log_info "额外移除的包: $REMOVE_PACKAGES"
fi

mkdir -p "$WORK_DIR"
rm -rf "$FIRMWARE_DIR"
mkdir -p "$FIRMWARE_DIR"
cd "$WORK_DIR"

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

builder_dir=$(find . -maxdepth 1 -type d -name "*imagebuilder*" | head -n 1)
if [ -z "$builder_dir" ]; then
    log_error "未找到 ImageBuilder 目录"
    exit 1
fi

cd "$builder_dir"
log_info "进入目录: $(pwd)"

log_info "确定设备 Profile..."
case "$MODEL" in
    *aliyun_ap8220*)
        PROFILE="aliyun_ap8220"
        ;;
    *cmcc_rax3000m*)
        PROFILE="cmcc_rax3000m"
        ;;
    *gemtek_w1701k*)
        PROFILE="gemtek_w1701k"
        ;;
    *jdcloud_ax6000*)
        PROFILE="jdcloud_re-cp-03"
        ;;
    *jdcloud_ipq60xx*)
        PROFILE="jdcloud_ax1800-pro"
        ;;
    *link_nn6000v2*)
        PROFILE="link_nn6000-v2"
        ;;
    *linksys_mx4*)
        PROFILE="linksys_mx4200"
        ;;
    *qihoo_360v6*)
        PROFILE="qihoo_360v6"
        ;;
    *redmi_ax5*)
        PROFILE="redmi_ax5"
        ;;
    *redmi_ax6000*)
        PROFILE="xiaomi_redmi-router-ax6000"
        ;;
    *redmi_ax6*)
        PROFILE="redmi_ax6"
        ;;
    *x64*)
        PROFILE="generic"
        ;;
    *zn_m2*)
        PROFILE="zn_m2"
        ;;
    *)
        log_warn "未识别的设备型号，尝试列出可用 profiles..."
        make info 2>/dev/null || true
        log_error "请在脚本中添加 $MODEL 的 profile 映射"
        exit 1
        ;;
esac

log_info "使用 Profile: $PROFILE"
log_info "准备包列表..."

CONFIG_FILE="$CORE_PATH/deconfig/${MODEL}.config"
if [ -f "$CONFIG_FILE" ]; then
    PACKAGES=$(parse_packages_from_config "$CONFIG_FILE")
else
    log_warn "配置文件不存在: $CONFIG_FILE"
    log_warn "使用空的包列表"
    PACKAGES=""
fi

if [ -n "$EXTRA_PACKAGES" ]; then
    log_info "添加额外的包: $EXTRA_PACKAGES"
    PACKAGES="$PACKAGES $EXTRA_PACKAGES"
fi

if [ -n "$REMOVE_PACKAGES" ]; then
    log_info "额外移除的包: $REMOVE_PACKAGES"
    for pkg in $REMOVE_PACKAGES; do
        PACKAGES="$PACKAGES -$pkg"
    done
fi

PACKAGES=$(echo "$PACKAGES" | xargs)
log_info "最终包列表: $PACKAGES"

FILES_DIR="$BASE_PATH/files"
if [ -d "$FILES_DIR" ]; then
    log_info "使用自定义文件: $FILES_DIR"
    FILES_OPT="FILES=$FILES_DIR"
else
    FILES_OPT=""
fi

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
log_info "收集固件文件..."

bin_dir=$(find . -type d -name "bin" | head -n 1)
if [ -z "$bin_dir" ]; then
    log_error "未找到固件输出目录"
    exit 1
fi

find "$bin_dir" -type f \
    \( -name "*.bin" -o -name "*.img" -o -name "*.img.gz" \
    -o -name "*.manifest" -o -name "sha256sums" \) \
    -exec cp -v {} "$FIRMWARE_DIR/" \;

if [ -f "$bin_dir/targets/"*"/"*"/*.manifest" ]; then
    cp "$bin_dir/targets/"*"/"*"/*.manifest" "$FIRMWARE_DIR/packages.txt"
fi

log_info "=========================================="
log_info "固件文件已保存到: $FIRMWARE_DIR"
log_info "=========================================="

ls -lh "$FIRMWARE_DIR"
