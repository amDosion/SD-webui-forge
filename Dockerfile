FROM pytorch/pytorch:2.6.0-cuda12.6-cudnn9-devel

# 设置时区
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 安装依赖
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

# 创建 webui 用户
RUN useradd -m webui

# 设置工作目录为 /app
WORKDIR /app

# 拷贝运行资源
COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh

# 切换权限给 webui 用户
RUN chown -R webui:webui /app

# 切换用户（WebUI 不允许 root）
USER webui
# ✅ 设置容器运行时工作目录
WORKDIR /app/webui

ENTRYPOINT ["/app/run.sh"]
