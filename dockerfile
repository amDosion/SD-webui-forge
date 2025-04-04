# ================================================================
# 📦 0.1 基础镜像：CUDA 12.8.1 + cuDNN + Ubuntu 22.04
# ================================================================
FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu22.04

# ================================================================
# 🕒 1.1 设置系统时区（上海）
# ================================================================
ENV TZ=Asia/Shanghai
RUN echo "🔧 [1.1] 设置系统时区为 ${TZ}..." && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    echo "✅ [1.1] 时区设置完成"

# ================================================================
# 🧱 2.1 安装 Python 3.11 + 系统依赖 + jq
# ================================================================
RUN echo "🔧 [2.1] 安装 Python 3.11 及基础系统依赖..." && \
    apt-get update && apt-get upgrade -y && \
    apt-get install -y jq && \
    apt-get install -y --no-install-recommends \
        python3.11 python3.11-venv python3.11-dev \
        wget git git-lfs curl procps bc \
        libgl1 libgl1-mesa-glx libglvnd0 \
        libglib2.0-0 libsm6 libxrender1 libxext6 \
        xvfb build-essential cmake \
        libgoogle-perftools-dev \
        libgtk2.0-dev libgtk-3-dev libjpeg-dev libpng-dev libtiff-dev \
        libopenblas-base libopenmpi-dev \
        apt-transport-https htop nano bsdmainutils \
        lsb-release software-properties-common && \
    echo "✅ [2.1] 系统依赖安装完成" && \
    curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
    python3.11 get-pip.py && \
    rm get-pip.py && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    echo "✅ [2.1] Python 3.11 设置完成"

# ================================================================
# 🧱 2.2 安装构建工具 pip/wheel/setuptools/cmake/ninja
# ================================================================
RUN echo "🔧 [2.2] 安装 Python 构建工具..." && \
    python3.11 -m pip install --upgrade pip setuptools wheel cmake ninja --no-cache-dir && \
    echo "✅ [2.2] 构建工具安装完成"

# ================================================================
# 🧱 2.3 安装 xformers 所需 C++ 系统构建依赖
# ================================================================
RUN echo "🔧 [2.3] 安装 xformers C++ 构建依赖..." && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential g++ cmake ninja-build zip unzip git curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    echo "✅ [2.3] xformers 构建依赖安装完成"

# ✅ GCC 12.4.0 编译安装（不依赖 PPA，适配 GitHub Actions / CI）
RUN echo "🔧 安装 GCC 12.4.0..." && \
    apt-get update && \
    apt-get install -y build-essential wget libgmp-dev libmpfr-dev libmpc-dev flex bison && \
    cd /tmp && \
    wget https://ftp.gnu.org/gnu/gcc/gcc-12.4.0/gcc-12.4.0.tar.xz && \
    tar -xf gcc-12.4.0.tar.xz && cd gcc-12.4.0 && \
    ./contrib/download_prerequisites && \
    mkdir build && cd build && \
    ../configure --disable-multilib --enable-languages=c,c++ --prefix=/opt/gcc-12.4 && \
    make -j"$(nproc)" && make install && \
    ln -sf /opt/gcc-12.4/bin/gcc /usr/local/bin/gcc && \
    ln -sf /opt/gcc-12.4/bin/g++ /usr/local/bin/g++ && \
    echo "✅ GCC 12.4 安装完成"

# ================================================================
# 🧱 2.5 安装 TensorFlow 源码编译所需系统依赖（不启用 clang，但需避免 configure 报错）
# ================================================================
RUN echo "🔧 [2.5] 安装 TensorFlow 构建依赖..." && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    zlib1g-dev libcurl4-openssl-dev libssl-dev liblzma-dev \
    libtool autoconf automake python-is-python3 clang && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    echo "✅ [2.5] TensorFlow 编译依赖安装完成"

# ================================================================
# 🧱 3.1 安装 PyTorch Nightly (with CUDA 12.8)
# ================================================================
RUN echo "🔧 [3.1] 安装 PyTorch Nightly + Torch-TensorRT (CUDA 12.8)..." && \
    python3.11 -m pip install --upgrade pip && \
    python3.11 -m pip install --pre \
        torch==2.8.0.dev20250326+cu128 \
        torchvision==0.22.0.dev20250326+cu128 \
        torchaudio==2.6.0.dev20250326+cu128 \
        torch-tensorrt==2.7.0.dev20250326+cu128 \
        --extra-index-url https://download.pytorch.org/whl/nightly/cu128 \
        --no-cache-dir && \
    echo "✅ [3.1] PyTorch 安装完成"

# ================================================================
# 🧱 3.2 安装 Python 推理依赖（如 insightface）
# ================================================================
RUN echo "🔧 [3.2] 安装额外 Python 包..." && \
    python3.11 -m pip install --no-cache-dir \
        numpy scipy opencv-python scikit-learn Pillow insightface && \
    echo "✅ [3.2] 其他依赖安装完成"

# ================================================================
# 🧱 3.3 安装 Bazelisk（用于构建 TensorFlow）
# ================================================================
RUN echo "🔧 [3.3] 安装 Bazelisk（自动管理 Bazel）..." && \
    mkdir -p /usr/local/bin && \
    curl -fsSL https://github.com/bazelbuild/bazelisk/releases/download/v1.11.0/bazelisk-linux-amd64 \
    -o /usr/local/bin/bazelisk && \
    chmod +x /usr/local/bin/bazelisk && \
    ln -sf /usr/local/bin/bazelisk /usr/local/bin/bazel && \
    echo "✅ [3.3] Bazelisk 安装完成"

# ================================================================
# 👤 4.1 创建非 root 用户 webui
# ================================================================
RUN echo "🔧 [4.1] 创建非 root 用户 webui..." && \
    useradd -m webui && \
    echo "✅ [4.1] 用户 webui 创建完成"

# ================================================================
# 📂 5.1 设置工作目录并授权脚本
# ================================================================
WORKDIR /app
COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh && \
    mkdir -p /app/webui && chown -R webui:webui /app/webui && \
    echo "✅ [5.1] 脚本授权完成"

# ================================================================
# 👤 5.2 切换至 webui 用户并设置工作目录
# ================================================================
USER webui
WORKDIR /app/webui
RUN echo "✅ [5.2] 当前用户: $(whoami)" && \
    echo "✅ [5.2] 当前工作目录: $(pwd)"

# ================================================================
# 🔎 6.1 环境基础自检
# ================================================================
RUN echo "🔎 [6.1] 开始环境基础自检..." && \
    python3 --version && \
    python3 -m pip --version && \
    python3 -m venv --help > /dev/null && \
    echo "✅ [6.1] Python、pip 和 venv 已正常工作" || \
    (echo "❌ [6.1] Python 环境异常，请检查！" && exit 1)

# ================================================================
# 🚀 7.1 设置容器启动入口
# ================================================================
ENTRYPOINT ["/app/run.sh"]
