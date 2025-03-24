FROM pytorch/pytorch:2.6.0-cuda12.6-cudnn9-devel

# 设置时区
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 安装系统依赖
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    wget git git-lfs curl procps \
    python3 python3-pip python3-venv \
    libgl1 libgl1-mesa-glx libglvnd0 \
    libglib2.0-0 libsm6 libxrender1 libxext6 \
    xvfb build-essential cmake bc \
    libgoogle-perftools-dev \
    apt-transport-https htop nano && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 创建非 root 用户
RUN useradd -m webui

# 设置工作目录
WORKDIR /app

# 拷贝运行脚本
COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh

# ✅ 核心关键：创建 webui 目录并赋权
RUN mkdir -p /app/webui && chown -R webui:webui /app/webui

# 切换为非 root 用户运行容器
USER webui

# 设置容器启动目录
WORKDIR /app/webui

# 容器入口
ENTRYPOINT ["/app/run.sh"]
