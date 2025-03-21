FROM pytorch/pytorch:2.6.0-cuda12.6-cudnn9-devel

# 设置时区
ENV TZ=Europe/Minsk
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 安装系统依赖（你提供的已整合并优化）
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    wget git git-lfs curl procps \
    python3 python3-pip python3-venv \
    libgl1 libgl1-mesa-glx libglvnd0 \
    libglib2.0-0 libsm6 libxrender1 libxext6 \
    xvfb build-essential cmake \
    libgoogle-perftools-dev bc \
    apt-transport-https htop nano \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 创建非 root 用户
RUN useradd -m webui
WORKDIR /app

# 拷贝运行脚本和资源列表
COPY run.sh /app/run.sh
COPY resources.txt /app/resources.txt

# 使用非 root 用户执行（WebUI 禁止 root 启动）
USER webui

# 启动脚本作为容器入口
ENTRYPOINT ["/app/run.sh"]
