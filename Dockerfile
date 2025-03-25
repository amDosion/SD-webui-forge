FROM pytorch/pytorch:2.6.0-cuda12.6-cudnn9-devel

# ========================
# 时区配置（上海）
# ========================
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# ========================
# 系统依赖 + CUDA 常用库
# ========================
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    wget git git-lfs curl procps \
    libgl1 libgl1-mesa-glx libglvnd0 \
    libglib2.0-0 libsm6 libxrender1 libxext6 \
    xvfb build-essential cmake bc \
    libgoogle-perftools-dev \
    apt-transport-https htop nano bsdmainutils \
    # TensorFlow + PyTorch CUDA 依赖库
    cuda-compiler-12-6 \
    libcublas-12-6 libcublas-dev-12-6 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ========================
# 安装 TensorRT（匹配 CUDA 12.6）
# ========================
RUN apt-get update && apt-get install -y --no-install-recommends \
    libnvinfer8=8.6.1-1+cuda12.0 \
    libnvinfer-plugin8=8.6.1-1+cuda12.0 \
    libnvparsers8=8.6.1-1+cuda12.0 \
    libnvonnxparsers8=8.6.1-1+cuda12.0 \
    libnvinfer-bin=8.6.1-1+cuda12.0 \
    python3-libnvinfer=8.6.1-1+cuda12.0 \
    python3-libnvinfer-dev=8.6.1-1+cuda12.0 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ========================
# CUDA 编译器版本检查
# ========================
RUN echo "🔍 CUDA 编译器版本：" && nvcc --version

# ========================
# 创建非 root 用户 webui
# ========================
RUN useradd -m webui

# ========================
# 设置工作目录 & 权限
# ========================
WORKDIR /app
COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh && \
    mkdir -p /app/webui && chown -R webui:webui /app/webui

# ========================
# 切换为非 root 用户运行
# ========================
USER webui
WORKDIR /app/webui

# ========================
# 简单容器环境自检
# ========================
RUN echo "✅ Docker 环境检查开始..." && \
    python3 --version && \
    pip3 --version && \
    python3 -m venv --help > /dev/null && \
    echo "✅ Python, pip, venv 正常" || echo "⚠️ Python 环境不完整"

# ========================
# 容器启动脚本入口
# ========================
ENTRYPOINT ["/app/run.sh"]
