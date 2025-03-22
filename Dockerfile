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
    xvfb build-essential cmake \
    libgoogle-perftools-dev bc \
    apt-transport-https htop nano && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 创建用户
RUN useradd -m webui
WORKDIR /app

# 拷贝脚本与资源
COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh && chown -R webui:webui /app

# 使用 root 用户构建阶段，但运行时切换为 webui（延后 clone 时切换）
ENTRYPOINT ["/app/run.sh"]
