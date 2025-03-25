FROM pytorch/pytorch:2.6.0-cuda12.6-cudnn9-devel

# ========================
# 时区配置（上海时区）
# ========================
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# ========================
# 添加 NVIDIA 仓库 & 安装 CUDA Toolkit + TensorRT
# ========================
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget curl gnupg2 lsb-release software-properties-common && \
    echo "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64 /" > /etc/apt/sources.list.d/cuda.list && \
    echo "deb https://developer.download.nvidia.com/compute/machine-learning/repos/ubuntu2204/x86_64 /" > /etc/apt/sources.list.d/nvidia-ml.list && \
    curl -s https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/7fa2af80.pub | apt-key add - && \
    apt-get update && apt-get install -y --no-install-recommends \
    cuda-toolkit-12-6 \
    libcudnn8=8.9.6.*-1+cuda12.6 \
    libcudnn8-dev=8.9.6.*-1+cuda12.6 \
    libnvinfer8=8.6.1.*-1+cuda12.6 \
    libnvinfer-plugin8=8.6.1.*-1+cuda12.6 \
    libnvparsers8=8.6.1.*-1+cuda12.6 \
    libnvonnxparsers8=8.6.1.*-1+cuda12.6 \
    libnvinfer-dev=8.6.1.*-1+cuda12.6 \
    libnvinfer-plugin-dev=8.6.1.*-1+cuda12.6 \
    libcublas-12-0 \
    libcublas-dev-12-0 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ========================
# 安装通用系统依赖
# ========================
RUN apt-get update && apt-get install -y --no-install-recommends \
    git git-lfs procps nano htop bc cmake \
    libgl1 libgl1-mesa-glx libglvnd0 libglib2.0-0 \
    libsm6 libxrender1 libxext6 xvfb build-essential \
    libgoogle-perftools-dev bsdmainutils && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ========================
# 检查 CUDA 版本
# ========================
RUN echo "✅ nvcc 版本：" && nvcc --version || echo "❌ nvcc 未安装"

# ========================
# 创建非 root 用户
# ========================
RUN useradd -m webui

# ========================
# 设置运行目录 & 权限
# ========================
WORKDIR /app
COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh
RUN mkdir -p /app/webui && chown -R webui:webui /app/webui

# ========================
# 切换到非 root 用户
# ========================
USER webui
WORKDIR /app/webui

# ========================
# 自检功能
# ========================
RUN echo "✅ Docker 环境检查开始..." && \
    python3 --version && \
    pip3 --version && \
    python3 -m venv --help > /dev/null && \
    echo "✅ Python, pip, venv 正常" || echo "⚠️ Python 环境不完整"

# ========================
# 容器入口
# ========================
ENTRYPOINT ["/app/run.sh"]
