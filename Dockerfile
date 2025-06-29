FROM ubuntu:22.04

LABEL maintainer="xrsec"
LABEL mail="Jalapeno1868@outlook.com"
LABEL Github="https://github.com/XRSec/wrt_release"
LABEL org.opencontainers.image.source="https://github.com/XRSec/wrt_release"
LABEL org.opencontainers.image.title="Image-Builder"

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# 安装基础依赖
RUN apt-get update && apt-get install -y \
    build-essential \
    libncurses5-dev \
    libncursesw5-dev \
    zlib1g-dev \
    gawk \
    git \
    gettext \
    libssl-dev \
    xsltproc \
    wget \
    unzip \
    python3 \
    qemu-utils \
    genisoimage \
    zstd \
    dos2unix \
    libfuse-dev \
    && apt -y full-upgrade \
    && bash -c 'bash <(curl -sL https://build-scripts.immortalwrt.org/init_build_environment.sh)' \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 设置时区
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 创建工作目录
WORKDIR /work

# 设置默认命令
CMD ["/bin/bash"]