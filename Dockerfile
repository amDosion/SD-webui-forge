FROM nvidia/cuda:12.6.3-cudnn-devel-ubuntu22.04

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
        python3 python3-pip python3-venv \
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
# 🚩 安装 PyTorch（匹配 CUDA 12.6）
# ====================================
RUN pip3 install --upgrade pip && \
    pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126

# ====================================
# 🚩 安装 TensorRT（CUDA 12.6 专用）— 拆分安装 + 检查是否重复安装 + 锁定版本
# ====================================
RUN CODENAME="ubuntu2204" && \
    echo "🔧 配置 NVIDIA CUDA 仓库 for CUDA 12.6..." && \
    rm -f /etc/apt/sources.list.d/cuda-ubuntu2204-x86_64.list && \
    mkdir -p /usr/share/keyrings && \
    curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/${CODENAME}/x86_64/cuda-archive-keyring.gpg \
        | gpg --batch --yes --dearmor -o /usr/share/keyrings/cuda-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cuda-archive-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/${CODENAME}/x86_64/ /" \
        > /etc/apt/sources.list.d/cuda.list && \
    apt-get update && \

    # 💡 需要安装的 TensorRT 运行时包（准确锁定版本 +cuda12.6）
    for pkg in \
      "libnvinfer8=8.6.1.6-1+cuda12.6" \
      "libnvinfer-plugin8=8.6.1.6-1+cuda12.6" \
      "libnvparsers8=8.6.1.6-1+cuda12.6" \
      "libnvonnxparsers8=8.6.1.6-1+cuda12.6" \
      "libnvinfer-bin=8.6.1.6-1+cuda12.6" \
      "python3-libnvinfer=8.6.1-1+cuda12.6"; \
    do \
        pkg_name=$(echo $pkg | cut -d= -f1); \
        if dpkg -s "$pkg_name" >/dev/null 2>&1; then \
            echo "✅ 已安装：$pkg_name，跳过"; \
        else \
            echo "📦 安装：$pkg"; \
            apt-get install -y --no-install-recommends "$pkg"; \
        fi; \
    done && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/*


# =============================
# 🚩 验证 CUDA 和 TensorRT 环境
# =============================
RUN echo "🔍 CUDA 编译器版本：" && nvcc --version && \
    echo "🔍 TensorRT 安装包：" && dpkg -l | grep -E "libnvinfer|libnvparsers" && \
    python3 -c "import torch; print('torch:', torch.__version__, '| CUDA:', torch.version.cuda)"

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
# 🚩 切换至非
