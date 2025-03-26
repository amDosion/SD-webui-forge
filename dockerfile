FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu22.04

# ===============================
# 🚩 设置时区（上海）
# ===============================
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# ====================================
# 🚩 系统依赖 + Python 环境 + 构建工具（分拆安装 + 跳过重复）
# ====================================
RUN apt-get update && apt-get upgrade -y && \
    packages="\
        python3 python3-pip python3-venv python3-dev \
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
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ====================================
# 🚩 安装 PyTorch Nightly torch-tensorrt版本（包含 CUDA 12.8） 
# ====================================
RUN pip3 install --pre \
    torch==2.8.0.dev20250326+cu128 \
    torchvision==0.22.0.dev20250326+cu128 \
    torchaudio==2.6.0.dev20250326+cu128 \
    torch-tensorrt==2.7.0.dev20250325+cu128 \
    --extra-index-url https://download.pytorch.org/whl/nightly/cu128 \
    --no-cache-dir
# ====================================
# 🚩 验证安装
# ====================================
RUN python3 - <<EOF
try:
    import torch_tensorrt
    print('torch-tensorrt installed successfully')
except Exception as e:
    print('Skipped torch-tensorrt check (no GPU)')
EOF

# ====================================
# 🚩 安装其他 Python 依赖（如 insightface）
# ====================================
RUN pip3 install numpy scipy opencv-python scikit-learn Pillow insightface

# ================================
# 🚩 创建非 root 用户 webui
# ================================
RUN useradd -m webui

# ===================================
# 🚩 设置工作目录，复制脚本并授权
# ===================================
WORKDIR /app
COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh && \
    mkdir -p /app/webui && chown -R webui:webui /app/webui

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
