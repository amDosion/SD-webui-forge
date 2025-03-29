# Dockerfile
# 使用包含 CUDA 12.8.1 和 cuDNN 的 NVIDIA 官方镜像作为基础
# 目标是构建一个支持 PyTorch Nightly preview 版本的环境
FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu22.04

# ===============================
# 🚩 设置时区（上海）
# ===============================
# 设置环境变量 TZ 为上海时区
ENV TZ=Asia/Shanghai
# 通过创建软链接和写入 /etc/timezone 文件来应用时区设置
RUN echo "🔧 设置时区为 ${TZ}..." && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    echo "✅ 时区设置成功：${TZ}"

# ====================================
# 🚩 系统依赖 + Python 3.11 环境 + 构建工具
# ====================================
# 更新包列表，升级已安装包，并安装所需依赖
# - 安装 Python 3.11 及其开发和虚拟环境工具
# - 使用 get-pip.py 安装最新版 pip for Python 3.11
# - 设置 python3 命令指向 python3.11
# - 安装其他编译、图形、系统管理等基础依赖
# - 在同一层清理 apt 缓存以减小镜像体积
RUN echo "🔧 更新系统并安装基本依赖 (包括 Python 3.11 for Nightly builds)..." && \
    apt-get update && \
    apt-get upgrade -y && \
    # 安装 Python 3.11 相关包
    apt-get install -y --no-install-recommends \
        python3.11 \
        python3.11-venv \
        python3.11-dev \
        wget git git-lfs curl procps bc \
        libgl1 libgl1-mesa-glx libglvnd0 \
        libglib2.0-0 libsm6 libxrender1 libxext6 \
        xvfb build-essential cmake \
        libgoogle-perftools-dev \
        libgtk2.0-dev libgtk-3-dev libjpeg-dev libpng-dev libtiff-dev \
        libopenblas-base libopenmpi-dev \
        apt-transport-https htop nano bsdmainutils \
        lsb-release software-properties-common && \
    echo "✅ Python 3.11 及系统依赖安装初步完成" && \
    # 使用 get-pip.py 安装 pip for Python 3.11
    echo "📦 安装 pip for Python 3.11..." && \
    curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
    python3.11 get-pip.py && \
    rm get-pip.py && \
    echo "✅ pip for Python 3.11 安装成功" && \
    # 设置 Python 3.11 为默认的 python3
    echo "🔧 设置 Python 3.11 为默认 python3 版本..." && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 && \
    echo "✅ Python 3.11 设置为默认 python3 版本" && \
    # 清理 apt 缓存
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    echo "✅ 系统依赖安装和清理完成"

# ====================================
# 🚩 安装 PyTorch Nightly (含 torch-tensorrt) (匹配 CUDA 12.8)
# ====================================
# 安装特定日期的 PyTorch Nightly (Preview) 版本及相关组件
# 这些版本针对 CUDA 12.8 编译 (--extra-index-url .../cu128)
# 使用 --pre 标记安装预发布版本
# 使用 --no-cache-dir 避免缓存，减小镜像体积
RUN echo "🔧 安装 PyTorch Nightly Preview 和 Torch-TensorRT (CUDA 12.8)..." && \
    python3.11 -m pip install --upgrade pip && \
    python3.11 -m pip install --pre \
    torch==2.8.0.dev20250326+cu128 \
    torchvision==0.22.0.dev20250326+cu128 \
    torchaudio==2.6.0.dev20250326+cu128 \
    torch-tensorrt==2.7.0.dev20250325+cu128 \
    --extra-index-url https://download.pytorch.org/whl/nightly/cu128 \
    --no-cache-dir && \
    echo "✅ PyTorch Nightly Preview 和 Torch-TensorRT 安装成功"

# ====================================
# 🚩 安装其他 Python 依赖 (如 insightface)
# ====================================
# 使用 python3.11 -m pip 安装其他需要的 Python 库
# 这些库将安装其与当前环境兼容的最新（稳定版优先）版本
RUN echo "🔧 安装其他 Python 依赖 (如 insightface)..." && \
    python3.11 -m pip install --no-cache-dir \
        numpy \
        scipy \
        opencv-python \
        scikit-learn \
        Pillow \
        insightface && \
    echo "✅ 其他 Python 依赖安装完成"

# ================================
# 🚩 创建非 root 用户 webui
# ================================
# 创建一个名为 webui 的用户，并为其创建家目录
RUN echo "🔧 创建用户 webui..." && \
    useradd -m webui && \
    echo "✅ 用户 webui 创建成功"

# ===================================
# 🚩 设置工作目录，复制脚本并授权
# ===================================
WORKDIR /app
COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh && \
    mkdir -p /app/webui && chown -R webui:webui /app/webui && \
    echo "✅ 复制并授权 run.sh 成功，并设置 /app/webui 目录权限"

# ================================
# 🚩 切换至非 root 用户 webui
# ================================
USER webui
WORKDIR /app/webui
RUN echo "✅ 已成功切换至用户：$(whoami)" && \
    echo "✅ 当前工作目录为：$(pwd)"

# ================================
# 🚩 环境基础自检（Python与Pip）
# ================================
RUN echo "🔎 Python 环境自检开始..." && \
    python3 --version && # 应显示 Python 3.11.x
    python3 -m pip --version && # 检查关联的 pip
    python3 -m venv --help > /dev/null && \
    echo "✅ Python、pip 和 venv 已正确安装并通过检查 (应为 Python 3.11)" || \
    (echo "⚠️ Python 环境完整性出现问题，请排查！" && exit 1)

# ====================================
# 🚩 [注释掉] TensorRT 的 apt 安装部分
# ====================================
# 通过 pip 安装的 torch-tensorrt 通常已足够
# RUN echo "🔧 [注释] TensorRT 系统级安装 (apt)..."
# ... (apt install commands commented out) ...

# ================================
# 🚩 设置容器启动入口
# ================================
ENTRYPOINT ["/app/run.sh"]
