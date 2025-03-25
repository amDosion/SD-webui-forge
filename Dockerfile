FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu22.04

# ===============================
# 🚩 时区设置（上海）
# ===============================
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# ====================================
# 🚩 系统依赖 + Python 环境 + 常用库
# ====================================
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv \
    wget git git-lfs curl procps \
    libgl1 libgl1-mesa-glx libglvnd0 \
    libglib2.0-0 libsm6 libxrender1 libxext6 \
    xvfb build-essential cmake bc \
    libgoogle-perftools-dev \
    libgtk2.0-dev libgtk-3-dev libjpeg-dev libpng-dev libtiff-dev \
    libopenblas-base libopenmpi-dev \
    apt-transport-https htop nano bsdmainutils \
    lsb-release software-properties-common && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ====================================
# 🚩 安装 PyTorch（兼容 CUDA 12.8 的版本）
# ====================================
RUN pip3 install --upgrade pip && \
    pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128

# ====================================
# 🚩 安装 TensorRT（匹配 CUDA 12.8）
# ====================================
RUN CODENAME="ubuntu2204" && \
    rm -f /etc/apt/sources.list.d/cuda-ubuntu2204-x86_64.list && \
    mkdir -p /usr/share/keyrings && \
    curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/${CODENAME}/x86_64/cuda-archive-keyring.gpg \
        | gpg --batch --yes --dearmor -o /usr/share/keyrings/cuda-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cuda-archive-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/${CODENAME}/x86_64/ /" \
        > /etc/apt/sources.list.d/cuda.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        libnvinfer8 libnvinfer-plugin8 \
        libnvparsers8 libnvonnxparsers8 \
        libnvinfer-bin python3-libnvinfer && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/*

# =============================
# 🚩 验证 CUDA 和 TensorRT
# =============================
RUN echo "🔍 CUDA 编译器版本：" && nvcc --version && \
    echo "🔍 TensorRT 安装包：" && dpkg -l | grep -E "libnvinfer|libnvparsers" && \
    echo "✅ 环境验证通过"

# =============================
# 🚩 创建非 root 用户 webui
# =============================
RUN useradd -m webui

# ===================================
# 🚩 设置工作目录，复制脚本并授权
# ===================================
WORKDIR /app
COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh && \
    mkdir -p /app/webui && chown -R webui:webui /app/webui

# =============================
# 🚩 切换至非 root 用户 webui
# =============================
USER webui
WORKDIR /app/webui
RUN echo "✅ 已成功切换至用户：$(whoami)" && \
    echo "✅ 当前工作目录为：$(pwd)"

# =============================
# 🚩 环境基础自检（Python与Pip）
# =============================
RUN echo "🔎 Python 环境自检开始..." && \
    python3 --version && \
    pip3 --version && \
    python3 -m venv --help > /dev/null && \
    echo "✅ Python、pip 和 venv 已正确安装并通过检查" || \
    echo "⚠️ Python 环境完整性出现问题，请排查！"

# =============================
# 🚩 设置容器启动入口
# =============================
ENTRYPOINT ["/app/run.sh"]
