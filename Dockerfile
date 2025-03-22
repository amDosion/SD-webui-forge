FROM pytorch/pytorch:2.6.0-cuda12.6-cudnn9-devel

# 设置时区
ENV TZ=Europe/Minsk
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
    apt-transport-https htop nano \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 创建用户和必要目录
RUN useradd -m webui && mkdir -p /home/webui && chown -R webui:webui /home/webui

# 工作目录
WORKDIR /app

# 拷贝脚本和资源文件
COPY run.sh /app/run.sh
COPY resources.txt /app/resources.txt
# 权限设置
RUN chmod +x /app/run.sh && chown -R webui:webui /app

# 切换非 root 用户执行
USER webui

# 入口脚本
ENTRYPOINT ["/app/run.sh"]
