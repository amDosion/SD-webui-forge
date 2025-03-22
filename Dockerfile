FROM pytorch/pytorch:2.6.0-cuda12.6-cudnn9-devel

# 设置时区
ENV TZ=Europe/Minsk
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

# 创建用户
RUN useradd -m webui
WORKDIR /app

# 拷贝启动脚本和资源文件
COPY run.sh /app/run.sh
COPY resources.txt /app/resources.txt
RUN chmod +x /app/run.sh && chown -R webui:webui /app

USER webui
ENTRYPOINT ["/app/run.sh"]
