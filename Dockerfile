FROM pytorch/pytorch:2.6.0-cuda12.6-cudnn9-devel

# ========================
# 时区配置（上海时区）
# ========================
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# ========================
# 安装系统依赖（根据基础镜像精简）
# ========================
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    wget git git-lfs curl procps \
    libgl1 libgl1-mesa-glx libglvnd0 \
    libglib2.0-0 libsm6 libxrender1 libxext6 \
    xvfb build-essential cmake bc \
    libgoogle-perftools-dev \
    apt-transport-https htop nano \
    bsdmainutils && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

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
