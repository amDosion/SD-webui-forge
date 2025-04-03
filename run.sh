#!/bin/bash

# 确保脚本出错时立即退出
set -e
# 确保管道中的命令失败时也退出
set -o pipefail

# ==================================================
# 日志配置
# ==================================================
LOG_FILE="/app/webui/launch.log"
# 确保日志目录存在
mkdir -p "$(dirname "$LOG_FILE")"
# 将所有标准输出和错误输出重定向到文件和控制台
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "🚀 [0] 启动脚本 - Stable Diffusion WebUI (CUDA 12.8 / PyTorch Nightly)"
echo "=================================================="
echo "⏳ 开始时间: $(date)"
echo "🔧 使用 PyTorch Nightly (Preview) builds 构建，可能存在不稳定风险。"
echo "🔧 xformers 已在 Docker 构建时从源码编译 (目标架构: 8.9 for RTX 4090)。"

# ==================================================
# 🛠️  [0.5] 系统环境自检
# ==================================================
echo "🛠️  [0.5] 系统环境自检..."

# Python 检查 (应为 3.11)
if command -v python3.11 &>/dev/null; then
  echo "✅ Python 版本: $(python3.11 --version)"
else
  echo "❌ 未找到 python3.11，Dockerfile 配置可能存在问题！"
  exit 1
fi

# pip 检查 (通过 python -m pip 调用)
if python3.11 -m pip --version &>/dev/null; then
  echo "✅ pip for Python 3.11 版本: $(python3.11 -m pip --version)"
else
  echo "❌ 未找到 pip for Python 3.11！"
  exit 1
fi

# 检查是否安装 g++
if command -v g++ &>/dev/null; then
  echo "✅ g++ 已安装"
else
  echo "❌ 未找到 g++，请手动安装"
  exit 1
fi

# 检查是否安装 unzip
if command -v unzip &>/dev/null; then
  echo "✅ unzip 已安装"
else
  echo "❌ 未找到 unzip，安装失败"
  exit 1
fi

# 检查是否安装 zip
if command -v zip &>/dev/null; then
  echo "✅ zip 已安装"
else
  echo "❌ 未找到 zip，安装失败"
  exit 1
fi

# CUDA & GPU 检查 (nvidia-smi)
if command -v nvidia-smi &>/dev/null; then
  # 检查 nvidia-smi 输出中的 CUDA 版本
  # 注意：nvidia-smi 显示的 CUDA 版本是驱动支持的最高版本，可能高于运行时版本 (12.8)
  echo "✅ nvidia-smi 检测成功 (驱动应支持 CUDA >= 12.8)，GPU 信息如下："
  echo "---------------- Nvidia SMI Output Start -----------------"
  nvidia-smi
  echo "---------------- Nvidia SMI Output End -------------------"
else
  echo "⚠️ 未检测到 nvidia-smi 命令。可能原因：容器未加 --gpus all 启动，或 Nvidia 驱动未正确安装。"
  echo "⚠️ 无法验证 GPU 可用性，后续步骤可能失败。"
fi

# 容器检测
if [ -f "/.dockerenv" ]; then
  echo "📦 正在 Docker 容器中运行"
else
  echo "🖥️ 非 Docker 容器环境"
fi

# 用户检查 (应为 webui)
echo "👤 当前用户: $(whoami) (应为 webui)"

# 工作目录写入权限检查
if [ -w "/app/webui" ]; then
  echo "✅ /app/webui 目录可写"
else
  echo "❌ /app/webui 目录不可写，启动可能会失败！请检查 Dockerfile 中的权限设置。"
  # 允许继续，以便在具体步骤中捕获错误
fi
echo "✅ 系统环境自检完成"

# ==================================================
# 环境变量设置
# ==================================================
echo "🔧 [1] 解析 UI 与 ARGS 环境变量..."
# UI 类型，默认为 forge
UI="${UI:-forge}"
# 传递给 webui.sh 的参数，默认包含 --xformers
ARGS="${ARGS:---xformers --api --listen --enable-insecure-extension-access --theme dark}"
echo "  - UI 类型 (UI): ${UI}"
echo "  - WebUI 启动参数 (ARGS): ${ARGS}"

echo "🔧 [2] 解析下载开关环境变量 (默认全部启用)..."
# 解析全局下载开关
ENABLE_DOWNLOAD_ALL="${ENABLE_DOWNLOAD:-true}"

# 解析独立的模型和资源类别开关
ENABLE_DOWNLOAD_EXTS="${ENABLE_DOWNLOAD_EXTS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_MODEL_SD15="${ENABLE_DOWNLOAD_MODEL_SD15:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_MODEL_SDXL="${ENABLE_DOWNLOAD_MODEL_SDXL:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_MODEL_FLUX="${ENABLE_DOWNLOAD_MODEL_FLUX:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_VAE_FLUX="${ENABLE_DOWNLOAD_VAE_FLUX:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_TE_FLUX="${ENABLE_DOWNLOAD_TE_FLUX:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_CNET_SD15="${ENABLE_DOWNLOAD_CNET_SD15:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_CNET_SDXL="${ENABLE_DOWNLOAD_CNET_SDXL:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_CNET_FLUX="${ENABLE_DOWNLOAD_CNET_FLUX:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_VAE="${ENABLE_DOWNLOAD_VAE:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_LORAS="${ENABLE_DOWNLOAD_LORAS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_EMBEDDINGS="${ENABLE_DOWNLOAD_EMBEDDINGS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_UPSCALERS="${ENABLE_DOWNLOAD_UPSCALERS:-$ENABLE_DOWNLOAD_ALL}"

# 解析独立的镜像使用开关
USE_HF_MIRROR="${USE_HF_MIRROR:-false}" # 控制是否使用 hf-mirror.com
USE_GIT_MIRROR="${USE_GIT_MIRROR:-false}" # 控制是否使用 gitcode.net

echo "  - 下载总开关        (ENABLE_DOWNLOAD_ALL): ${ENABLE_DOWNLOAD_ALL}"
echo "  - 下载 Extensions   (ENABLE_DOWNLOAD_EXTS): ${ENABLE_DOWNLOAD_EXTS}"
echo "  - 下载 Checkpoint SD1.5 (ENABLE_DOWNLOAD_MODEL_SD15): ${ENABLE_DOWNLOAD_MODEL_SD15}"
echo "  - 下载 Checkpoint SDXL  (ENABLE_DOWNLOAD_MODEL_SDXL): ${ENABLE_DOWNLOAD_MODEL_SDXL}"
echo "  - 下载 Checkpoint FLUX (ENABLE_DOWNLOAD_MODEL_FLUX): ${ENABLE_DOWNLOAD_MODEL_FLUX}"
echo "  - 下载 VAE FLUX       (ENABLE_DOWNLOAD_VAE_FLUX): ${ENABLE_DOWNLOAD_VAE_FLUX}"
echo "  - 下载 TE FLUX        (ENABLE_DOWNLOAD_TE_FLUX): ${ENABLE_DOWNLOAD_TE_FLUX}"
echo "  - 下载 ControlNet SD1.5 (ENABLE_DOWNLOAD_CNET_SD15): ${ENABLE_DOWNLOAD_CNET_SD15}"
echo "  - 下载 ControlNet SDXL  (ENABLE_DOWNLOAD_CNET_SDXL): ${ENABLE_DOWNLOAD_CNET_SDXL}"
echo "  - 下载 ControlNet FLUX  (ENABLE_DOWNLOAD_CNET_FLUX): ${ENABLE_DOWNLOAD_CNET_FLUX}"
echo "  - 下载 通用 VAE     (ENABLE_DOWNLOAD_VAE): ${ENABLE_DOWNLOAD_VAE}"
echo "  - 下载 LoRAs/LyCORIS (ENABLE_DOWNLOAD_LORAS): ${ENABLE_DOWNLOAD_LORAS}"
echo "  - 下载 Embeddings   (ENABLE_DOWNLOAD_EMBEDDINGS): ${ENABLE_DOWNLOAD_EMBEDDINGS}"
echo "  - 下载 Upscalers    (ENABLE_DOWNLOAD_UPSCALERS): ${ENABLE_DOWNLOAD_UPSCALERS}"
echo "  - 是否使用 HF 镜像  (USE_HF_MIRROR): ${USE_HF_MIRROR}" # (hf-mirror.com)
echo "  - 是否使用 Git 镜像 (USE_GIT_MIRROR): ${USE_GIT_MIRROR}" # (gitcode.net)

# 预定义镜像地址 (如果需要可以从环境变量读取，但简单起见先硬编码)
HF_MIRROR_URL="https://hf-mirror.com"
GIT_MIRROR_URL="https://gitcode.net" # 使用 https

# TCMalloc 和 Pip 索引设置
export NO_TCMALLOC=1
export PIP_EXTRA_INDEX_URL="https://download.pytorch.org/whl/nightly/cu128"
echo "  - 禁用的 TCMalloc (NO_TCMALLOC): ${NO_TCMALLOC}"
echo "  - pip 额外索引 (PIP_EXTRA_INDEX_URL): ${PIP_EXTRA_INDEX_URL} (用于 PyTorch Nightly cu128)"

# ==================================================
# 设置 Git 源路径
# ==================================================
echo "🔧 [3] 设置 WebUI 仓库路径与 Git 源 (通常为最新开发版/Preview)..."
TARGET_DIR="" # 初始化
REPO=""       # 初始化
WEBUI_EXECUTABLE="webui.sh" # 默认启动脚本名称

# 根据 UI 环境变量设置目标目录和仓库 URL
if [ "$UI" = "auto" ]; then
  TARGET_DIR="/app/webui/stable-diffusion-webui"
  REPO="https://github.com/AUTOMATIC1111/stable-diffusion-webui.git"
elif [ "$UI" = "forge" ]; then
  TARGET_DIR="/app/webui/sd-webui-forge"
  # 使用官方 Forge 仓库
  REPO="https://github.com/amDosion/stable-diffusion-webui-forge-cuda128.git"

elif [ "$UI" = "stable_diffusion_webui" ]; then # auto 的别名
  TARGET_DIR="/app/webui/stable-diffusion-webui"
  REPO="https://github.com/AUTOMATIC1111/stable-diffusion-webui.git"
else
  echo "❌ 未知的 UI 类型: $UI。请设置 UI 环境变量为 'auto', 'forge' 或 'stable_diffusion_webui'。"
  exit 1
fi
echo "  - 目标目录: $TARGET_DIR"
echo "  - Git 仓库源: $REPO (将克隆默认/主分支)"

# ==================================================
# 克隆/更新 WebUI 仓库
# ==================================================
if [ -d "$TARGET_DIR/.git" ]; then
  echo "  - 仓库已存在于 $TARGET_DIR，尝试更新 (git pull)..."
  # 进入目录执行 git pull, --ff-only 避免合并冲突
  cd "$TARGET_DIR"
  git pull --ff-only || echo "⚠️ Git pull 失败，可能是本地有修改或网络问题。将继续使用当前版本。"
  # 操作完成后返回上层目录
  cd /app/webui
else
 echo "  - 仓库不存在，开始完整克隆 $REPO 到 $TARGET_DIR ..."
 # 使用完整克隆（非浅克隆），并初始化子模块（推荐）
 git clone --recursive "$REPO" "$TARGET_DIR"

 # 赋予启动脚本执行权限
 if [ -f "$TARGET_DIR/$WEBUI_EXECUTABLE" ]; then
    chmod +x "$TARGET_DIR/$WEBUI_EXECUTABLE"
    echo "  - 已赋予 $TARGET_DIR/$WEBUI_EXECUTABLE 执行权限"
 else
    echo "⚠️ 未在克隆的仓库 $TARGET_DIR 中找到预期的启动脚本 $WEBUI_EXECUTABLE"
    # 可以考虑是否添加 exit 1
 fi
fi
echo "✅ 仓库操作完成"

# 切换到 WebUI 目标目录进行后续操作
cd "$TARGET_DIR" || { echo "❌ 无法切换到 WebUI 目标目录 $TARGET_DIR"; exit 1; }

# ==================================================
# requirements 文件检查 (仅非 Forge UI)
# ==================================================
# 注意：Forge UI 默认通过 webui.sh 自动安装依赖，但当前配置已跳过其官方依赖处理步骤 (--skip-install 等参数已设置)。
# 因此此处不需要检查 requirements 文件的存在性。实际依赖的安装和版本控制将在后续步骤 (【6.2】) 中明确处理。
if [ "$UI" != "forge" ]; then
    echo "🔧 [5] (非 Forge UI) 检查 requirements_versions.txt 文件..."

    REQ_FILE_CHECK="requirements_versions.txt"
    if [ -f "$REQ_FILE_CHECK" ]; then
        echo "  - 将使用 $REQ_FILE_CHECK 文件安装依赖。"
    else
        echo "  - ⚠️ 未找到 $REQ_FILE_CHECK。依赖安装将被跳过，请确保该文件存在。"
    fi
else
    echo "⚙️ [5] (Forge UI) 已跳过官方依赖处理，手动安装将在后续步骤执行。"
fi

# ==================================================
# 权限设置 (警告)
# ==================================================
# 警告：赋予 777 权限可能带来安全风险。
# 仅在明确需要且了解后果时使用。更好的做法是精细控制权限。
echo "⚠️ [5.5] 正在为当前目录 ($TARGET_DIR) 设置递归 777 权限。这在生产环境中不推荐！"
chmod -R 777 . || echo "⚠️ chmod 777 失败，后续步骤可能因权限问题失败。"

# ==================================================
# Python 虚拟环境设置与依赖安装
# ==================================================
VENV_DIR="venv" # 定义虚拟环境目录名
echo "🐍 [6] 设置 Python 虚拟环境 ($VENV_DIR)..."

# 检查虚拟环境是否已正确创建
if [ ! -x "$VENV_DIR/bin/activate" ]; then
  echo "  - 虚拟环境不存在或未正确创建，现在使用 python3.11 创建..."
  # 移除可能存在的无效目录
  rm -rf "$VENV_DIR"
  # 使用明确的 Python 版本创建
  python3.11 -m venv "$VENV_DIR"
  echo "  - 虚拟环境创建成功。"
else
  echo "  - 虚拟环境已存在于 $VENV_DIR。"
fi

echo "  - 激活虚拟环境..."
# 激活虚拟环境
# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"

# 确认 venv 内的 Python 和 pip
echo "  - 当前 Python: $(which python) (应指向 $VENV_DIR/bin/python)"
echo "  - 当前 pip: $(which pip) (应指向 $VENV_DIR/bin/pip)"


echo "📥 [6.1] 升级 venv 内的 pip 到最新版本..."
pip install --upgrade pip | tee -a "$LOG_FILE" # 同时输出到控制台和日志

echo "🔧 [6.1.1] 安装 huggingface_hub CLI 工具..."
# 确保命令行登录功能可用
pip install --upgrade "huggingface_hub[cli]" | tee -a "$LOG_FILE"

# ==================================================
# 安装 WebUI 核心依赖 (基于 UI 类型)
# ==================================================
echo "📥 [6.2] 安装 WebUI 核心依赖 (基于 UI 类型)..."

# ==================================================
# 🔧 强制跳过 Forge UI 内部依赖检查（通过环境变量）
# ==================================================
export COMMANDLINE_ARGS="--skip-install --skip-prepare-environment --skip-python-version-check --skip-torch-cuda-test"
ARGS="$COMMANDLINE_ARGS $ARGS"
echo "  - 已设置 COMMANDLINE_ARGS: $COMMANDLINE_ARGS"

# ==================================================
# 根据 UI 类型决定依赖处理方式
# ==================================================
if [ "$UI" = "forge" ]; then
    echo "  - (Forge UI) 使用 run.sh 控制依赖安装流程"

    INSTALL_TORCH="${INSTALL_TORCH:-true}"
    if [[ "$INSTALL_TORCH" == "true" ]]; then
        TORCH_COMMAND="pip install --pre torch==2.8.0.dev20250326+cu128 torchvision==0.22.0.dev20250326+cu128 torchaudio==2.6.0.dev20250326+cu128 --extra-index-url https://download.pytorch.org/whl/nightly/cu128"
        echo "  - 安装 PyTorch Nightly: $TORCH_COMMAND"
        $TORCH_COMMAND && echo "    ✅ PyTorch 安装成功" || echo "    ❌ PyTorch 安装失败"
    else
        echo "  - ⏭️ 跳过 PyTorch 安装 (INSTALL_TORCH=false)"
    fi

    # 🔧 安装其他核心依赖（不降级，仅安装未存在的）
    REQ_FILE="requirements_versions.txt"
    if [ -f "$REQ_FILE" ]; then
        echo "  - 使用 $REQ_FILE 安装其他依赖（仅安装未存在模块，跳过 xformers）..."
        sed -i 's/\r$//' "$REQ_FILE"

        while IFS= read -r line || [[ -n "$line" ]]; do
            clean_line=$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            [[ -z "$clean_line" ]] && continue

            pkg_name=$(echo "$clean_line" | cut -d '=' -f1)

            if [[ "$pkg_name" == *xformers* ]]; then
                echo "    - ⏭️ 跳过 xformers（已从源码编译）"
                continue
            fi

            if pip show "$pkg_name" > /dev/null 2>&1; then
                echo "    - ⏩ 已存在: $pkg_name，跳过"
                continue
            fi

            echo "    - 安装: $clean_line"
            pip install --pre "$clean_line" --no-cache-dir --extra-index-url "$PIP_EXTRA_INDEX_URL" 2>&1 \
                | tee -a "$LOG_FILE" \
                | sed 's/^Successfully installed/      ✅ 成功安装/' \
                | sed 's/^Requirement already satisfied/      ⏩ 需求已满足/'

            if [ ${PIPESTATUS[0]} -ne 0 ]; then
                echo "❌ 安装失败: $clean_line"
            fi
        done < "$REQ_FILE"

        echo "  - 其他依赖处理完成。"
    else
        echo "⚠️ 未找到 $REQ_FILE，跳过依赖安装。"
    fi

else
    echo "  - (非 Forge UI) 全量安装 requirements_versions.txt 中依赖..."
    REQ_FILE="requirements_versions.txt"
    if [ -f "$REQ_FILE" ]; then
        sed -i 's/\r$//' "$REQ_FILE"

        while IFS= read -r line || [[ -n "$line" ]]; do
            clean_line=$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            [[ -z "$clean_line" ]] && continue

            echo "    - 安装: $clean_line"
            pip install --pre "$clean_line" --no-cache-dir --extra-index-url "$PIP_EXTRA_INDEX_URL" 2>&1 \
                | tee -a "$LOG_FILE" \
                | sed 's/^Successfully installed/      ✅ 成功安装/' \
                | sed 's/^Requirement already satisfied/      ⏩ 需求已满足/'

            if [ ${PIPESTATUS[0]} -ne 0 ]; then
                echo "❌ 安装失败: $clean_line"
            fi
        done < "$REQ_FILE"

        echo "  - requirements_versions.txt 中的依赖处理完成。"
    else
        echo "⚠️ 未找到 $REQ_FILE，跳过依赖安装。"
    fi
fi

# ==================================================
# 🔧 [6.3] Ninja + xformers 编译安装（适配 CUDA 12.8）
# ==================================================
INSTALL_XFORMERS="${INSTALL_XFORMERS:-true}"

TORCH_VER="2.8.0.dev20250326+cu128"
VISION_VER="0.22.0.dev20250326+cu128"
AUDIO_VER="2.6.0.dev20250326+cu128"
TORCH_COMMAND="pip install --pre torch==${TORCH_VER} torchvision==${VISION_VER} torchaudio==${AUDIO_VER} --extra-index-url https://download.pytorch.org/whl/nightly/cu128"

if [[ "$INSTALL_XFORMERS" == "true" ]]; then
  echo "⚙️ [6.3] 正在编译并安装 xformers（适配 CUDA 12.8）"
  echo "🐍 当前 Python 路径: $(which python)"

  # ✅ 检查 PyTorch 是否正确安装
  torch_ok=false
  vision_ok=false
  audio_ok=false

  torch_ver=$(pip show torch 2>/dev/null | awk '/^Version:/{print $2}')
  vision_ver=$(pip show torchvision 2>/dev/null | awk '/^Version:/{print $2}')
  audio_ver=$(pip show torchaudio 2>/dev/null | awk '/^Version:/{print $2}')

  [[ "$torch_ver" == "$TORCH_VER" ]] && torch_ok=true
  [[ "$vision_ver" == "$VISION_VER" ]] && vision_ok=true
  [[ "$audio_ver" == "$AUDIO_VER" ]] && audio_ok=true

  if [[ "$torch_ok" != "true" || "$vision_ok" != "true" || "$audio_ok" != "true" ]]; then
    echo "  - 未检测到指定版本 PyTorch，执行安装..."
    echo "    ➤ $TORCH_COMMAND"
    $TORCH_COMMAND && echo "    ✅ PyTorch 安装成功" || { echo "    ❌ PyTorch 安装失败"; exit 1; }
  else
    echo "    ✅ 已存在所需版本 torch/vision/audio，跳过安装"
  fi

  echo "📦 安装 Ninja 和 wheel..."
  pip install --upgrade pip wheel ninja setuptools cmake --no-cache-dir && echo "    ✅ 构建工具安装成功"

  export TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-8.9}"
  export MAX_JOBS=$(nproc)
  echo "  - 使用 CUDA 架构: $TORCH_CUDA_ARCH_LIST"
  echo "  - 并行编译线程数: $MAX_JOBS"

  XFORMERS_DIR="xformers-src"
  XFORMERS_REPO="https://github.com/facebookresearch/xformers.git"

  if [ ! -d "$XFORMERS_DIR/.git" ]; then
    echo "  - 克隆 xformers 仓库..."
    git clone --recursive "$XFORMERS_REPO" "$XFORMERS_DIR"
  else
    echo "  - 已存在 xformers 源码目录，执行 git pull..."
    cd "$XFORMERS_DIR"
    git pull --ff-only || echo "⚠️ 仓库更新失败，保留本地副本"
    cd ..
  fi

  echo "  - 初始化 Flash-Attention 子模块..."
  cd "$XFORMERS_DIR"
  git submodule update --init --recursive || {
    echo "❌ 子模块拉取失败，请检查网络或 .gitmodules 设置"
    echo "📁 当前目录: $(pwd)"
    exit 1
  }

  # ✅ 安装系统依赖（仅限 root）
  if [ "$(id -u)" -eq 0 ]; then
    echo "🔧 以 root 用户执行，尝试安装系统级构建依赖..."
    apt-get update && apt-get install -y build-essential g++ zip unzip
  else
    echo "⚠️ 当前非 root 用户，跳过 apt 安装系统构建依赖"
    echo "🔍 正在检测系统中是否已预装以下依赖项：build-essential, g++, zip, unzip"

    if command -v g++ >/dev/null 2>&1; then
      echo "    ✅ g++ 已安装: $(g++ --version | head -n 1)"
    else
      echo "    ❌ g++ 未安装！"
    fi

    if command -v zip >/dev/null 2>&1; then
      echo "    ✅ zip 已安装: $(zip -v | head -n 1)"
    else
      echo "    ❌ zip 未安装！"
    fi

    if command -v unzip >/dev/null 2>&1; then
      echo "    ✅ unzip 已安装: $(unzip -v | head -n 1)"
    else
      echo "    ❌ unzip 未安装！"
    fi

    echo "📌 如缺失上方任何构建依赖，请确保在 Dockerfile 中加入："
    echo "    apt-get install -y build-essential g++ zip unzip"
  fi  # ✅ 修复点：缺失的 fi

  echo "  - 安装 Python 构建依赖..."
  > requirements.txt  # 清空旧依赖
  pip install -r requirements.txt --no-cache-dir || echo "    ⚠️ 无 requirements.txt 或内容为空，跳过"

  echo "  - 开始构建 xformers（包含 C++ 扩展）..."
  export XFORMERS_FORCE_CUDA=1
  export XFORMERS_BUILD_CPP=1

  pip install -e . --no-build-isolation --verbose
  build_result=$?

  unset XFORMERS_FORCE_CUDA
  unset XFORMERS_BUILD_CPP

  if [ $build_result -ne 0 ]; then
    echo "    ❌ xformers 安装失败，尝试诊断错误..."
    echo "📌 当前 pip: $(pip --version)"
    echo "📌 setuptools: $(python -c 'import setuptools; print(setuptools.__version__)')"
    echo "📌 wheel: $(python -c 'import wheel; print(wheel.__version__)')"
    echo "📌 cmake: $(cmake --version | head -n 1)"
    echo "📦 pip 构建依赖列表（grep 关键词）:"
    python -m pip list | grep -E 'torch|wheel|setuptools|cmake|ninja'
    exit 1
  else
    echo "    ✅ xformers 编译并安装成功（含 C++ 扩展）"
  fi

  echo "🔍 验证 PyTorch 和 xformers 环境..."
  python -m torch.utils.collect_env | tee ../torch_env.txt

  echo "🧩 诊断 xformers C++ 扩展状态..."
  XFORMERS_INFO_FILE="../xformers_info.txt"
  if python -m xformers.info | tee "$XFORMERS_INFO_FILE"; then
    echo "    ✅ xformers.info 成功执行"
  else
    echo "    ⚠️ 无法运行 xformers.info，可能代表扩展未完整构建"
  fi

  if grep -q "unavailable" "$XFORMERS_INFO_FILE"; then
    echo "⚠️ 以下 xformers 模块未启用："
    grep "unavailable" "$XFORMERS_INFO_FILE" | sed 's/^/    - /'
    echo "📌 可能原因如下："
    echo "    • 缺少编译依赖（如 g++、zip、unzip）"
    echo "    • 缺失 Python 构建模块（如 wheel/setuptools）"
    echo "    • 编译路径未在虚拟环境中运行"
    echo "    • CUDA/PyTorch 构建参数不一致或环境变量丢失"
    echo "    • 子模块（如 Flash-Attention）未初始化"
  else
    echo "✅ 所有 xformers 扩展可用 ✅"
  fi

  echo "📁 xformers 源码目录: $(realpath "$XFORMERS_DIR")"
  echo "🐍 当前 Python: $(which python)"

  cd ..
  unset TORCH_CUDA_ARCH_LIST
  unset MAX_JOBS
else
  echo "⏭️ [6.3] 跳过 xformers 编译安装（INSTALL_XFORMERS=false）"
fi

# ==================================================
# 🧠 [6.4] TensorFlow 编译（支持 GPU 和 CUDA 12.8）
# ==================================================
INSTALL_TENSORFLOW="${INSTALL_TENSORFLOW:-true}"
if [[ "$INSTALL_TENSORFLOW" == "true" ]]; then
  echo "🧠 [6.4] 动态编译 TensorFlow (支持 CUDA 12.8)..."

  TF_INSTALLED_VERSION=$(python -c "import tensorflow as tf; print(tf.__version__)" 2>/dev/null || echo "not_installed")
  if [[ "$TF_INSTALLED_VERSION" == *"dev"* || "$TF_INSTALLED_VERSION" == *"nightly"* ]]; then
    echo "    ✅ 已安装 tf-nightly: $TF_INSTALLED_VERSION，跳过编译步骤。"
  else
    echo "    - 当前 TensorFlow 版本: $TF_INSTALLED_VERSION，准备从源码构建..."

    echo "    - 检查 CPU 是否支持 AVX2..."
    AVX2_SUPPORTED=$(grep -q avx2 /proc/cpuinfo && echo "true" || echo "false")
    if [[ "$AVX2_SUPPORTED" != "true" ]]; then
      echo "    ⚠️ 当前 CPU 不支持 AVX2，跳过 TensorFlow 编译"
    else
      TF_SRC_DIR="${TARGET_DIR:-/app/webui}/tensorflow-src"
      if [ ! -d "$TF_SRC_DIR/.git" ]; then
        echo "    - 克隆 TensorFlow 源码（默认 master 分支）到 $TF_SRC_DIR..."
        git clone https://github.com/tensorflow/tensorflow.git "$TF_SRC_DIR"
      else
        echo "    - 已存在 TensorFlow 源目录: $TF_SRC_DIR，跳过克隆"
      fi

      cd "$TF_SRC_DIR" || { echo "❌ 切换目录失败: $TF_SRC_DIR"; exit 1; }

      echo "    - 设置构建参数环境变量..."
      export PYTHON_BIN_PATH=$(which python)
      export PYTHON_LIB_PATH=$(python -c "import site; print(site.getsitepackages()[0])")
      export GCC_HOST_COMPILER_PATH=$(which gcc)
      export TF_NEED_CUDA=1
      export TF_CUDA_VERSION=12.8
      export TF_CUDNN_VERSION=8
      export TF_CUDA_COMPUTE_CAPABILITIES="8.9"
      export TF_CUDA_PATHS="/usr/local/cuda"
      export CC_OPT_FLAGS="-march=core-avx2"
      export TF_ENABLE_XLA=1
      export TF_NEED_CLANG=0
      export TF_CUDA_CLANG=0
      export TF_DOWNLOAD_CLANG=0
      export TF_NEED_ROCM=0
      export TF_NEED_TENSORRT=0
      export TF_SET_ANDROID_WORKSPACE=0

      # ➕ Hermetic 变量：使 configure 全自动完成
      export HERMETIC_CUDA_VERSION="${TF_CUDA_VERSION}"
      export HERMETIC_CUDNN_VERSION="${TF_CUDNN_VERSION}"
      export HERMETIC_CUDA_COMPUTE_CAPABILITIES="${TF_CUDA_COMPUTE_CAPABILITIES}"
      export LOCAL_CUDA_PATH="/usr/local/cuda"
      export LOCAL_CUDNN_PATH="/usr/local/cuda"
      export LOCAL_NCCL_PATH="/usr"

      echo "    - 配置 TensorFlow (CUDA 支持, 非交互模式)..."
      ./configure 2>&1 | tee ../tf_configure_log.txt || {
        echo "❌ ./configure 配置失败，请查看 ../tf_configure_log.txt"; exit 1;
      }

      echo "    - 使用 Bazel 构建 TensorFlow pip 包..."
      bazel build --config=opt --config=cuda //tensorflow/tools/pip_package:build_pip_package || {
        echo "❌ Bazel 编译失败"; exit 1;
      }

      echo "    - 生成 .whl pip 安装包..."
      ./bazel-bin/tensorflow/tools/pip_package/build_pip_package /tmp/tensorflow_pkg || {
        echo "❌ Pip 包生成失败"; exit 1;
      }

      echo "    - 安装 .whl 包..."
      pip install /tmp/tensorflow_pkg/tensorflow-*.whl || {
        echo "❌ TensorFlow 安装失败"; exit 1;
      }

      cd "${TARGET_DIR:-/app/webui}"
      echo "    ✅ TensorFlow 编译并安装成功"
    fi
  fi

  echo "    - 验证 TensorFlow 是否支持 GPU..."
  python -c "
import tensorflow as tf
gpus = tf.config.list_physical_devices('GPU')
print(f'Num GPUs Available: {len(gpus)}')
if gpus:
    print(f'✅ 检测到 GPU 数量: {len(gpus)}')
else:
    print('⚠️ 未检测到 GPU，将使用 CPU')
" || echo "⚠️ TensorFlow 启动时检测异常"
else
  echo "⏭️ [6.4] 跳过 TensorFlow 编译 (INSTALL_TENSORFLOW 未设置为 true)"
fi

# ==================================================
# [6.5] TensorFlow GPU 性能优化配置（XLA + 动态显存 + RTX 4090 增强）
# ==================================================
echo "⚡ [6.5] 配置 TensorFlow GPU 性能优化参数..."

cat > ./tf_gpu_opt.py <<EOF
import os
import tensorflow as tf

print("🔧 启用 XLA JIT 编译器...")
tf.config.optimizer.set_jit(True)
os.environ['TF_XLA_FLAGS'] = '--tf_xla_auto_jit=2'
os.environ['TF_ENABLE_AUTO_MIXED_PRECISION'] = '1'

print("🔧 启用动态显存分配...")
gpus = tf.config.list_physical_devices('GPU')
if gpus:
    try:
        for gpu in gpus:
            tf.config.experimental.set_memory_growth(gpu, True)
        print(f"✅ 成功为 {len(gpus)} 个 GPU 启用动态显存")
    except Exception as e:
        print(f"⚠️ 设置动态显存失败: {e}")
else:
    print("⚠️ 未检测到 GPU，跳过显存配置")

print("🔍 检测是否为 Ada Lovelace 系列显卡（如 RTX 4090）...")
from tensorflow.python.eager.context import context
if gpus:
    dev_details = tf.config.experimental.get_device_details(gpus[0])
    if 'compute_capability' in dev_details and dev_details['compute_capability'] >= (8,9):
        print("✅ 检测到 RTX 4090 或以上架构，可启用高级特性（如 FP8 支持）")
    else:
        print("ℹ️ 非 Ada 架构，略过高级特性提示")
EOF

echo "🚀 执行 tf_gpu_opt.py 配置检查..."
python ./tf_gpu_opt.py || echo "⚠️ TensorFlow 优化检查执行失败，请手动排查"

echo "✅ [6.5] TensorFlow GPU 优化配置完成"

# ==================================================
# [6.6] FP8 支持检测 + TensorFlow 性能探测（针对 RTX 4090）
# ==================================================
echo "🔍 [6.6] 开始检测 FP8 支持情况 + TensorFlow 执行性能..."

cat > ./tf_fp8_check.py <<EOF
import tensorflow as tf
import os

print("🧠 当前 TensorFlow 版本:", tf.__version__)
print("📦 CUDA 可用:", tf.config.list_physical_devices('GPU'))

gpus = tf.config.list_physical_devices('GPU')
if not gpus:
    print("❌ 未检测到 GPU，无法检查 FP8 支持")
    exit(0)

device_info = tf.config.experimental.get_device_details(gpus[0])
compute_capability = device_info.get("compute_capability", (0, 0))
print("🔧 GPU Compute Capability:", compute_capability)

if compute_capability >= (8, 9):
    print("✅ 当前为 Ada 架构 (如 RTX 4090)，理论支持 FP8 和 TensorFloat32")
    print("⚙️ 你可以尝试使用 FP8 模型库或微调工具")
else:
    print("ℹ️ 当前架构低于 Ada 系列，FP8 支持可能受限")

print("🚀 执行简单卷积性能探测...")
import time
import numpy as np

B, H, W, C = 8, 512, 512, 3
X = tf.constant(np.random.randn(B, H, W, C).astype("float32"))
conv = tf.keras.layers.Conv2D(64, 3, padding="same")

start = time.time()
Y = conv(X)
end = time.time()
print(f"✅ 卷积前向执行时间: {end - start:.4f} 秒")

if tf.config.optimizer.get_jit():
    print("✅ XLA 已启用")
else:
    print("⚠️ XLA 未启用，可尝试 tf.config.optimizer.set_jit(True)")
EOF

echo "🚀 执行 tf_fp8_check.py 检测脚本..."
python ./tf_fp8_check.py || echo "⚠️ [6.6] 检测脚本执行失败，请手动排查"

echo "✅ [6.6] FP8 支持与性能探测完成"


# ==================================================
# 创建 WebUI 相关目录
# ==================================================
echo "📁 [7] 确保 WebUI 主要工作目录存在..."
# 创建常用的子目录，如果不存在的话
mkdir -p embeddings models/Stable-diffusion models/VAE models/Lora models/LyCORIS models/ControlNet outputs extensions || echo "⚠️ 创建部分目录失败，请检查权限。"
echo "  - 主要目录检查/创建完成。"

# ==================================================
# 网络测试 (可选)
# ==================================================
echo "🌐 [8] 网络连通性测试 (尝试访问 huggingface.co)..."
NET_OK=false # 默认网络不通
# 使用 curl 测试连接，设置超时时间
if curl -fsS --connect-timeout 5 https://huggingface.co > /dev/null; then
  NET_OK=true
  echo "  - ✅ 网络连通 (huggingface.co 可访问)"
else
  # 如果 Hugging Face 不通，尝试 GitHub 作为备选检查
  if curl -fsS --connect-timeout 5 https://github.com > /dev/null; then
      NET_OK=true # 至少 Git 相关操作可能成功
      echo "  - ⚠️ huggingface.co 无法访问，但 github.com 可访问。部分模型下载可能受影响。"
  else
      echo "  - ❌ 网络不通 (无法访问 huggingface.co 和 github.com)。资源下载和插件更新将失败！"
  fi
fi

# ==================================================
# 资源下载 (使用 resources.txt)
# ==================================================
echo "📦 [9] 处理资源下载 (基于 /app/webui/resources.txt 和下载开关)..."
RESOURCE_PATH="/app/webui/resources.txt" # 定义资源列表文件路径

# 检查资源文件是否存在，如果不存在则尝试下载默认版本
if [ ! -f "$RESOURCE_PATH" ]; then
  # 指定默认资源文件的 URL
  DEFAULT_RESOURCE_URL="https://raw.githubusercontent.com/chuan1127/SD-webui-forge/main/resources.txt"
  echo "  - 未找到本地 resources.txt，尝试从 ${DEFAULT_RESOURCE_URL} 下载..."
  # 使用 curl 下载，确保失败时不输出错误页面 (-f)，静默 (-s)，跟随重定向 (-L)
  curl -fsSL -o "$RESOURCE_PATH" "$DEFAULT_RESOURCE_URL"
  if [ $? -eq 0 ]; then
      echo "  - ✅ 默认 resources.txt 下载成功。"
  else
      echo "  - ❌ 下载默认 resources.txt 失败。请手动将资源文件放在 ${RESOURCE_PATH} 或检查网络/URL。"
      # 创建一个空文件以避免后续读取错误，但不会下载任何内容
      touch "$RESOURCE_PATH"
      echo "  - 已创建空的 resources.txt 文件以继续，但不会下载任何资源。"
  fi
else
  echo "  - ✅ 使用本地已存在的 resources.txt: ${RESOURCE_PATH}"
fi

# 定义函数：克隆或更新 Git 仓库 (支持独立 Git 镜像开关)
clone_or_update_repo() {
    # $1: 目标目录, $2: 原始仓库 URL
    local dir="$1" repo_original="$2"
    local dirname
    local repo_url # URL to be used for cloning/pulling

    dirname=$(basename "$dir")

    # 检查是否启用了 Git 镜像以及是否是 GitHub URL
    if [[ "$USE_GIT_MIRROR" == "true" && "$repo_original" == "https://github.com/"* ]]; then
        local git_mirror_host
        git_mirror_host=$(echo "$GIT_MIRROR_URL" | sed 's|https://||; s|http://||; s|/.*||')
        repo_url=$(echo "$repo_original" | sed "s|github.com|$git_mirror_host|")
        echo "    - 使用镜像转换 (Git): $repo_original -> $repo_url"
    else
        repo_url="$repo_original"
    fi

    # 检查扩展下载开关
    if [[ "$ENABLE_DOWNLOAD_EXTS" != "true" ]]; then
        if [ -d "$dir" ]; then
            echo "    - ⏭️ 跳过更新扩展/仓库 (ENABLE_DOWNLOAD_EXTS=false): $dirname"
        else
            echo "    - ⏭️ 跳过克隆扩展/仓库 (ENABLE_DOWNLOAD_EXTS=false): $dirname"
        fi
        return
    fi

    # 尝试更新或克隆
    if [ -d "$dir/.git" ]; then
        echo "    - 🔄 更新扩展/仓库: $dirname (from $repo_url)"
        (cd "$dir" && git pull --ff-only) || echo "      ⚠️ Git pull 失败: $dirname (可能存在本地修改或网络问题)"
    elif [ ! -d "$dir" ]; then
        echo "    - 📥 克隆扩展/仓库: $repo_url -> $dirname (完整克隆)"
        git clone --recursive "$repo_url" "$dir" || echo "      ❌ Git clone 失败: $dirname (检查 URL: $repo_url 和网络)"
    else
        echo "    - ✅ 目录已存在但非 Git 仓库，跳过 Git 操作: $dirname"
    fi  # ✅ 这里是必须的
}

# 定义函数：下载文件 (支持独立 HF 镜像开关)
download_with_progress() {
    # $1: 输出路径, $2: 原始 URL, $3: 资源类型描述, $4: 对应的下载开关变量值
    local output_path="$1" url_original="$2" type="$3" enabled_flag="$4"
    local filename
    local download_url # URL to be used for downloading

    filename=$(basename "$output_path")

    # 检查下载开关
    if [[ "$enabled_flag" != "true" ]]; then
        echo "    - ⏭️ 跳过下载 ${type} (开关 '$enabled_flag' != 'true'): $filename"
        return
    fi
    # 检查网络
    if [[ "$NET_OK" != "true" ]]; then
        echo "    - ❌ 跳过下载 ${type} (网络不通): $filename"
        return
    fi

    # 检查是否启用了 HF 镜像以及是否是 Hugging Face URL
    # 使用步骤 [2] 中定义的 HF_MIRROR_URL
    if [[ "$USE_HF_MIRROR" == "true" && "$url_original" == "https://huggingface.co/"* ]]; then
        # 替换 huggingface.co 为镜像地址
        download_url=$(echo "$url_original" | sed "s|https://huggingface.co|$HF_MIRROR_URL|")
        echo "    - 使用镜像转换 (HF): $url_original -> $download_url"
    else
        # 使用原始 URL
        download_url="$url_original"
    fi

    # 检查文件是否已存在
    if [ ! -f "$output_path" ]; then
        echo "    - ⬇️ 下载 ${type}: $filename (from $download_url)"
        mkdir -p "$(dirname "$output_path")"
        # 执行下载
        wget --progress=bar:force:noscroll --timeout=120 -O "$output_path" "$download_url"
        # 检查结果
        if [ $? -ne 0 ]; then
            echo "      ❌ 下载失败: $filename from $download_url (检查 URL 或网络)"
            rm -f "$output_path"
        else
            echo "      ✅ 下载完成: $filename"
        fi
    else
        echo "    - ✅ 文件已存在，跳过下载 ${type}: $filename"
    fi
}

# 定义插件/目录黑名单 (示例)
SKIP_DIRS=(
  "extensions/stable-diffusion-aws-extension" # 示例：跳过 AWS 插件
  "extensions/sd_dreambooth_extension"     # 示例：跳过 Dreambooth (如果需要单独管理)
)
# 函数：检查目标路径是否应跳过
should_skip() {
  local dir_to_check="$1"
  for skip_dir in "${SKIP_DIRS[@]}"; do
    # 完全匹配路径
    if [[ "$dir_to_check" == "$skip_dir" ]]; then
      return 0 # 0 表示应该跳过 (Bash true)
    fi
  done
  return 1 # 1 表示不应该跳过 (Bash false)
}

echo "  - 开始处理 resources.txt 中的条目..."
# 逐行读取 resources.txt 文件 (逗号分隔: 目标路径,源URL)
while IFS=, read -r target_path source_url || [[ -n "$target_path" ]]; do
  # 清理路径和 URL 的前后空格
  target_path=$(echo "$target_path" | xargs)
  source_url=$(echo "$source_url" | xargs)

  # 跳过注释行 (# 开头) 或空行 (路径或 URL 为空)
  [[ "$target_path" =~ ^#.*$ || -z "$target_path" || -z "$source_url" ]] && continue

  # 检查是否在黑名单中
  if should_skip "$target_path"; then
    echo "    - ⛔ 跳过黑名单条目: $target_path"
    continue # 处理下一行
  fi


# 根据目标路径判断资源类型并调用相应下载函数及正确的独立开关
case "$target_path" in
    # 1. Extensions
    extensions/*)
        clone_or_update_repo "$target_path" "$source_url" # Uses ENABLE_DOWNLOAD_EXTS internally
        ;;

    # 2. Stable Diffusion Checkpoints
    models/Stable-diffusion/SD1.5/*)
        download_with_progress "$target_path" "$source_url" "SD 1.5 Checkpoint" "$ENABLE_DOWNLOAD_MODEL_SD15"
        ;;
    models/Stable-diffusion/XL/*)
        download_with_progress "$target_path" "$source_url" "SDXL Checkpoint" "$ENABLE_DOWNLOAD_MODEL_SDXL"
        ;;
    models/Stable-diffusion/flux/*)
        download_with_progress "$target_path" "$source_url" "FLUX Checkpoint" "$ENABLE_DOWNLOAD_MODEL_FLUX"
        ;;
    models/Stable-diffusion/*) # Fallback
        echo "    - ❓ 处理未分类 Stable Diffusion 模型: $target_path (默认使用 SD1.5 开关)"
        download_with_progress "$target_path" "$source_url" "SD 1.5 Checkpoint (Fallback)" "$ENABLE_DOWNLOAD_MODEL_SD15"
        ;;

    # 3. VAEs
    models/VAE/flux-*.safetensors) # FLUX Specific VAE
        download_with_progress "$target_path" "$source_url" "FLUX VAE" "$ENABLE_DOWNLOAD_VAE_FLUX" # Use specific FLUX VAE switch
        ;;
    models/VAE/*) # Other VAEs
        download_with_progress "$target_path" "$source_url" "VAE Model" "$ENABLE_DOWNLOAD_VAE"
        ;;

    # 4. Text Encoders (Currently FLUX specific)
    models/text_encoder/*)
        download_with_progress "$target_path" "$source_url" "Text Encoder (FLUX)" "$ENABLE_DOWNLOAD_TE_FLUX" # Use specific FLUX TE switch
        ;;

    # 5. ControlNet Models
    models/ControlNet/*)
        if [[ "$target_path" == *sdxl* || "$target_path" == *SDXL* ]]; then
            download_with_progress "$target_path" "$source_url" "ControlNet SDXL" "$ENABLE_DOWNLOAD_CNET_SDXL"
        elif [[ "$target_path" == *flux* || "$target_path" == *FLUX* ]]; then
            download_with_progress "$target_path" "$source_url" "ControlNet FLUX" "$ENABLE_DOWNLOAD_CNET_FLUX"
        # Use keywords sd15 or v11 as indicators for SD 1.5 ControlNets
        elif [[ "$target_path" == *sd15* || "$target_path" == *SD15* || "$target_path" == *v11p* || "$target_path" == *v11e* || "$target_path" == *v11f* ]]; then
             download_with_progress "$target_path" "$source_url" "ControlNet SD 1.5" "$ENABLE_DOWNLOAD_CNET_SD15"
        else
            echo "    - ❓ 处理未分类 ControlNet 模型: $target_path (默认使用 SD1.5 ControlNet 开关)"
            download_with_progress "$target_path" "$source_url" "ControlNet SD 1.5 (Fallback)" "$ENABLE_DOWNLOAD_CNET_SD15"
        fi
        ;;

    # 6. LoRA and related models
    models/Lora/* | models/LyCORIS/* | models/LoCon/*)
        download_with_progress "$target_path" "$source_url" "LoRA/LyCORIS" "$ENABLE_DOWNLOAD_LORAS"
        ;;

    # 7. Embeddings / Textual Inversion
    models/TextualInversion/* | embeddings/*)
       download_with_progress "$target_path" "$source_url" "Embedding/Textual Inversion" "$ENABLE_DOWNLOAD_EMBEDDINGS"
       ;;

    # 8. Upscalers
    models/Upscaler/* | models/ESRGAN/*)
       download_with_progress "$target_path" "$source_url" "Upscaler Model" "$ENABLE_DOWNLOAD_UPSCALERS"
       ;;

    # 9. Fallback for any other paths
    *)
        if [[ "$source_url" == *.git ]]; then
             echo "    - ❓ 处理未分类 Git 仓库: $target_path (默认使用 Extension 开关)"
             clone_or_update_repo "$target_path" "$source_url" # Uses ENABLE_DOWNLOAD_EXTS internally
        elif [[ "$source_url" == http* ]]; then
             echo "    - ❓ 处理未分类文件下载: $target_path (默认使用 SD1.5 Model 开关)"
             download_with_progress "$target_path" "$source_url" "Unknown Model/File" "$ENABLE_DOWNLOAD_MODEL_SD15"
        else
             echo "    - ❓ 无法识别的资源类型或无效 URL: target='$target_path', source='$source_url'"
        fi
        ;;
esac # End case
done < "$RESOURCE_PATH" # 从资源文件读取
echo "✅ 资源下载处理完成。"

# ==================================================
# Token 处理 (Hugging Face, Civitai)
# ==================================================
# 步骤号顺延为 [10]
echo "🔐 [10] 处理 API Tokens (如果已提供)..."

# 处理 Hugging Face Token (如果环境变量已设置)
if [[ -n "$HUGGINGFACE_TOKEN" ]]; then
  echo "  - 检测到 HUGGINGFACE_TOKEN，尝试使用 huggingface-cli 登录..."
  # 检查 huggingface-cli 命令是否存在 (应由 huggingface_hub[cli] 提供)
  if command -v huggingface-cli &>/dev/null; then
      # 正确用法：将 token 作为参数传递给 --token
      huggingface-cli login --token "$HUGGINGFACE_TOKEN" --add-to-git-credential
      # 检查命令执行是否成功
      if [ $? -eq 0 ]; then
          echo "  - ✅ Hugging Face CLI 登录成功。"
      else
          # 登录失败通常不会是致命错误，只记录警告
          echo "  - ⚠️ Hugging Face CLI 登录失败。请检查 Token 是否有效、是否过期或 huggingface-cli 是否工作正常。"
      fi
  else
      echo "  - ⚠️ 未找到 huggingface-cli 命令，无法登录。请确保依赖 'huggingface_hub[cli]' 已正确安装在 venv 中。"
  fi
else
  # 如果未提供 Token
  echo "  - ⏭️ 未设置 HUGGINGFACE_TOKEN 环境变量，跳过 Hugging Face 登录。"
fi

# 检查 Civitai API Token
if [[ -n "$CIVITAI_API_TOKEN" ]]; then
  echo "  - ✅ 检测到 CIVITAI_API_TOKEN (长度: ${#CIVITAI_API_TOKEN})。"
else
  echo "  - ⏭️ 未设置 CIVITAI_API_TOKEN 环境变量。"
fi

# ==================================================
# 🔥 启动 WebUI (使用 venv 内的 Python)
# ==================================================
echo "🚀 [11] 所有准备工作完成，开始启动 WebUI (直接执行 launch.py)..."
echo "  - UI Type: ${UI}"

# ⚙️ 打印关键环境依赖版本信息
echo "📋 [11.1] 当前 Python & 依赖版本:"
"$VENV_DIR/bin/python" -c "
import sys
print(f'🧠 Python 解释器: {sys.executable}')
print(f'🐍 Python 版本: {sys.version}')

try:
    import torch
    print(f'🔥 PyTorch: {torch.__version__} (CUDA: {torch.version.cuda})')
except Exception as e:
    print(f'🔥 PyTorch: 未安装或出错: {e}')

try:
    import xformers
    print(f'🧩 xFormers: {xformers.__version__}')
except Exception as e:
    print(f'🧩 xFormers: 未安装或出错: {e}')

try:
    import tensorflow as tf
    gpus = tf.config.list_physical_devices(\"GPU\")
    print(f'🧠 TensorFlow: {tf.__version__} (GPU 可见: {len(gpus)})')
except Exception as e:
    print(f'🧠 TensorFlow: 未安装或出错: {e}')
"

# 拼接参数
ALL_ARGS="$COMMANDLINE_ARGS $ARGS"
echo "  - 启动参数 (ALL_ARGS): $ALL_ARGS"

# 确保在 WebUI 的正确目录中
CURRENT_DIR=$(pwd)
if [[ "$CURRENT_DIR" != "$TARGET_DIR" ]]; then
    echo "⚠️ 当前目录 ($CURRENT_DIR) 不是预期的 WebUI 目录 ($TARGET_DIR)，尝试切换..."
    cd "$TARGET_DIR" || { echo "❌ 无法切换到目录 $TARGET_DIR，启动失败！"; exit 1; }
    echo "✅ 已切换到目录: $(pwd)"
fi

# 检查 launch.py 是否存在
if [ ! -f "launch.py" ]; then
    echo "❌ 错误: 未在当前目录 ($(pwd)) 中找到 launch.py 文件！"
    exit 1
fi

# 打印执行时间和执行命令
echo "⏳ WebUI 启动时间: $(date)"
echo "=================================================="
echo "🚀 执行命令:"
echo "$VENV_DIR/bin/python launch.py $ALL_ARGS"
echo "=================================================="

# 启动 WebUI，替换当前 shell
exec "$VENV_DIR/bin/python" launch.py $ALL_ARGS

# 如果 exec 成功执行，脚本不会执行到这里
echo "❌ 启动 launch.py 失败！请检查日志和执行权限。"
exit 1
