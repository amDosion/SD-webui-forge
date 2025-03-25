FROM pytorch/pytorch:2.6.0-cuda12.6-cudnn9-devel

# ===============================
# 🚩 时区设置（上海）
# ===============================
ENV TZ=Asia/Shanghai
RUN echo "🔧 正在设置时区为 $TZ..." && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    echo "✅ 时区已成功设置：$(date)"

# ====================================
# 🚩 系统依赖安装 + CUDA 开发库安装
# ============================================
RUN echo -e "🔧 开始更新软件包及安装系统基础依赖...\n" && \
    apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
        wget git git-lfs curl procps \
        libgl1 libgl1-mesa-glx libglvnd0 \
        libglib2.0-0 libsm6 libxrender1 libxext6 \
        xvfb build-essential cmake bc \
        libgoogle-perftools-dev \
        apt-transport-https htop nano bsdmainutils \
        lsb-release software-properties-common && \
    echo -e "✅ 基础系统依赖安装完成\n" && \
    echo -e "🔧 正在安装 CUDA 12.6工具链和TensorFlow、PyTorch相关CUDA库依赖...\n" && \
    apt-get install -y --no-install-recommends \
        cuda-compiler-12-6 \
        libcublas-12-6 libcublas-dev-12-6 && \
    echo -e "✅ CUDA工具链及相关数学库安装完成\n" && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ====================================
# 🚩 TensorRT 安装（匹配 CUDA 12.6）
# ====================================
# 第一步：配置 NVIDIA CUDA 仓库
RUN echo -e "🔧 配置 NVIDIA CUDA 仓库...\n" && \
    CODENAME="ubuntu2204" && \
    # 删除基础镜像中可能预置的重复 CUDA 源配置
    rm -f /etc/apt/sources.list.d/cuda-ubuntu2204-x86_64.list && \
    mkdir -p /usr/share/keyrings && \
    echo -e "📥 正在下载 CUDA 仓库密钥...\n" && \
    curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/${CODENAME}/x86_64/cuda-archive-keyring.gpg \
         | gpg --batch --yes --dearmor -o /usr/share/keyrings/cuda-archive-keyring.gpg && \
    echo -e "📜 添加 CUDA 仓库源到 /etc/apt/sources.list.d/cuda.list ...\n" && \
    echo "deb [signed-by=/usr/share/keyrings/cuda-archive-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/${CODENAME}/x86_64/ /" \
         > /etc/apt/sources.list.d/cuda.list && \
    echo -e "✅ NVIDIA 仓库配置完成\n"

# 第二步：安装 TensorRT（适配 CUDA 12.6）
# 为避免版本匹配问题，建议移除版本约束，安装仓库中最新可用的 TensorRT 相关包
RUN echo -e "🔧 正在安装 TensorRT（适配 CUDA 12.6）...\n" && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        libnvinfer8 \
        libnvinfer-plugin8 \
        libnvparsers8 \
        libnvonnxparsers8 \
        libnvinfer-bin \
        python3-libnvinfer && \
    echo -e "✅ TensorRT 安装完成\n" && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# =============================
# 🚩 验证CUDA和TensorRT
# =============================
RUN echo "🔍 验证CUDA编译器..." && nvcc --version && \
    echo "🔍 检查TensorRT版本..." && dpkg -l | grep -E "libnvinfer|libnvparsers" && \
    echo "✅ 环境验证通过"

# =============================
# 🚩 创建非 root 用户 webui
# =============================
RUN echo "🔧 正在创建非 root 用户 webui..." && \
    useradd -m webui && \
    echo "✅ 用户 webui 创建完成"

# ===================================
# 🚩 设置工作目录，复制脚本并授权
# ===================================
WORKDIR /app
COPY run.sh /app/run.sh
RUN echo "🔧 正在创建工作目录并设置权限..." && \
    chmod +x /app/run.sh && \
    mkdir -p /app/webui && chown -R webui:webui /app/webui && \
    echo "✅ 工作目录设置完成"

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
