FROM ubuntu:22.04

LABEL maintainer="xrsec"
LABEL mail="Jalapeno1868@outlook.com"
LABEL Github="https://github.com/Ran-Xing/wrt_release"
LABEL org.opencontainers.image.source="https://github.com/Ran-Xing/wrt_release"
LABEL org.opencontainers.image.title="Image-Builder"

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# 安装基础依赖
RUN rm -rf /etc/apt/sources.list.d/* /usr/share/dotnet /usr/local/lib/android /opt/ghc /etc/mysql /etc/php \
    && apt-get -y purge azure-cli* docker* ghc* zulu* hhvm* llvm* firefox* google* dotnet* aspnetcore* powershell* openjdk* adoptopenjdk* mysql* php* mongodb* moby* snap* || true \
    && apt-get update \
    && apt-get install -y \
    sudo \
    build-essential \
    gcc-11 g++-11 \
    libncurses5-dev \
    libncursesw5-dev \
    zlib1g-dev \
    gawk \
    git \
    wget \
    curl \
    gettext \
    libssl-dev \
    xsltproc \
    unzip \
    python3 \
    python3-distutils \
    qemu-utils \
    genisoimage \
    zstd \
    dos2unix \
    libfuse-dev \
    rsync \
    file \
    libc6-dev \
    binutils-dev \
    libelf-dev \
    && apt -y full-upgrade \
    && bash -c 'bash <(curl -sL https://build-scripts.immortalwrt.org/init_build_environment.sh)' \
    && apt-get -qq autoremove --purge -y \
    && apt-get -qq clean \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -u 1000 builder

# 设置时区
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 创建工作目录
WORKDIR /work

# 设置默认命令
CMD ["/bin/bash"]
