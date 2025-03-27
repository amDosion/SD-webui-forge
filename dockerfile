FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu22.04

# ===============================
# 🚩 设置时区（上海）
# ===============================
ENV TZ=Asia/Shanghai
RUN echo "🔧 设置时区为 ${TZ}..." && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    echo "✅ 时区设置成功：${TZ}"

# ====================================
# 🚩 系统依赖 + Python 环境 + 构建工具（分拆安装 + 跳过重复）
# ====================================
RUN echo "🔧 更新系统并安装基本依赖..." && \
    apt-get update && apt-get upgrade -y && \
    echo "✅ 系统更新完成" && \
    # 安装Python 3.11及相关依赖
    echo "📦 安装 Python 3.11 及相关依赖..." && \
    apt-get install -y python3.11 python3.11-pip python3.11-venv python3.11-dev && \
    echo "✅ Python 3.11 安装成功" && \
    # 设置 Python 3.11 为默认版本
    echo "🔧 设置 Python 3.11 为默认版本..." && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 && \
    update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 1 && \
    echo "✅ Python 3.11 设置为默认版本" && \
    # 安装其他系统依赖
    packages="\
        wget git git-lfs curl procps \
        libgl1 libgl1-mesa-glx libglvnd0 \
        libglib2.0-0 libsm6 libxrender1 libxext6 \
        xvfb build-essential cmake bc \
        libgoogle-perftools-dev \
        libgtk2.0-dev libgtk-3-dev libjpeg-dev libpng-dev libtiff-dev \
        libopenblas-base libopenmpi-dev \
        apt-transport-https htop nano bsdmainutils \
        lsb-release software-properties-common"; \
    for pkg in $packages; do \
        if dpkg -s "$pkg" >/dev/null 2>&1; then \
            echo "✅ 已安装：$pkg，跳过"; \
        else \
            echo "📦 安装：$pkg"; \
            apt-get install -y --no-install-recommends "$pkg"; \
        fi; \
    done && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    echo "✅ 系统依赖安装完成"

# ====================================
# 🚩 安装 PyTorch Nightly torch-tensorrt版本（包含 CUDA 12.8） 
# ====================================
RUN echo "🔧 安装 PyTorch 和 Torch-TensorRT..." && \
    pip3 install --pre \
    torch==2.8.0.dev20250326+cu128 \
    torchvision==0.22.0.dev20250326+cu128 \
    torchaudio==2.6.0.dev20250326+cu128 \
    torch-tensorrt==2.7.0.dev20250325+cu128 \
    --extra-index-url https://download.pytorch.org/whl/nightly/cu128 \
    --no-cache-dir && \
    echo "✅ PyTorch 和 Torch-TensorRT 安装成功"

# ====================================
# 🚩 安装其他 Python 依赖（如 insightface）
# ====================================
RUN echo "🔧 安装其他 Python 依赖..." && \
    pip3 install numpy scipy opencv-python scikit-learn Pillow insightface && \
    echo "✅ 其他依赖安装完成"

# ================================
# 🚩 创建非 root 用户 webui
# ================================
RUN echo "🔧 创建用户 webui..." && \
    useradd -m webui && \
    echo "✅ 用户 webui 创建成功"

# ===================================
# 🚩 设置工作目录，复制脚本并授权
# ===================================
WORKDIR /app
COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh && \
    mkdir -p /app/webui && chown -R webui:webui /app/webui && \
    echo "✅ 复制并授权 run.sh 成功"

# ================================
# 🚩 切换至非 root 用户 webui
# ================================
USER webui
WORKDIR /app/webui
RUN echo "✅ 已成功切换至用户：$(whoami)" && \
    echo "✅ 当前工作目录为：$(pwd)"

# ================================
# 🚩 环境基础自检（Python与Pip）
# ================================
RUN echo "🔎 Python 环境自检开始..." && \
    python3 --version && \
    pip3 --version && \
    python3 -m venv --help > /dev/null && \
    echo "✅ Python、pip 和 venv 已正确安装并通过检查" || \
    echo "⚠️ Python 环境完整性出现问题，请排查！"

# ================================
# 🚩 设置容器启动入口
# ================================
ENTRYPOINT ["/app/run.sh"]

# ====================================
# 以下部分被注释掉，移除不必要的 CUDA 安装
# ====================================
# RUN CODENAME="ubuntu2204" && \
#     echo "🔧 添加 NVIDIA CUDA 仓库..." && \
#     rm -f /etc/apt/sources.list.d/cuda-ubuntu2204-x86_64.list && \
#     mkdir -p /usr/share/keyrings && \
#     curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/${CODENAME}/x86_64/cuda-archive-keyring.gpg \
#          | gpg --batch --yes --dearmor -o /usr/share/keyrings/cuda-archive-keyring.gpg && \
#     echo "deb [signed-by=/usr/share/keyrings/cuda-archive-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/${CODENAME}/x86_64/ /" \
#          > /etc/apt/sources.list.d/cuda.list && \
#     apt-get update && \
#     for pkg in \
#         libnvinfer8 \
#         libnvinfer-plugin8 \
#         libnvparsers8 \
#         libnvonnxparsers8 \
#         libnvinfer-bin \
#         python3-libnvinfer; do \
#         if dpkg -s "$pkg" >/dev/null 2>&1; then \
#             echo "✅ 已安装：$pkg，跳过"; \
#         else \
#             echo "📦 安装：$pkg"; \
#             apt-get install -y --no-install-recommends "$pkg"; \
#         fi; \
#     done && \
#     apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/*
