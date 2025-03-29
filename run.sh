#!/bin/bash

# 确保脚本出错时立即退出
set -e
# 确保管道中的命令失败时也退出
set -o pipefail

# ==================================================
# 日志配置
# ==================================================
LOG_FILE="/app/webui/launch.log"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "🚀 [0] 启动脚本 - Stable Diffusion WebUI (CUDA 12.8 / PyTorch Nightly)"
echo "=================================================="
echo "⏳ 开始时间: $(date)"
echo "🔧 使用 PyTorch Nightly builds，可能存在不稳定风险。"

# ==================================================
# 系统环境自检
# ==================================================
echo "🛠️  [0.5] 系统环境自检..."
# ... (自检部分保持不变, 检查 Python 3.11, pip, nvidia-smi 等) ...
if command -v python3.11 &>/dev/null; then
  echo "✅ Python 版本: $(python3.11 --version)"
else
  echo "❌ 未找到 python3.11，Dockerfile 配置可能存在问题！"
  exit 1
fi
if python3.11 -m pip --version &>/dev/null; then
  echo "✅ pip for Python 3.11 版本: $(python3.11 -m pip --version)"
else
  echo "❌ 未找到 pip for Python 3.11！"
  exit 1
fi
if command -v nvidia-smi &>/dev/null; then
  echo "✅ nvidia-smi 检测成功 (应显示 CUDA Version >= 12.8)，GPU 信息如下："
  echo "---------------- Nvidia SMI Output Start -----------------"
  nvidia-smi
  echo "---------------- Nvidia SMI Output End -------------------"
else
  echo "⚠️ 未检测到 nvidia-smi 命令。可能原因：容器未加 --gpus all 启动，或 Nvidia 驱动未正确安装。"
fi
if [ -f "/.dockerenv" ]; then
  echo "📦 正在 Docker 容器中运行"
else
  echo "🖥️ 非 Docker 容器环境"
fi
echo "👤 当前用户: $(whoami) (应为 webui)"
if [ -w "/app/webui" ]; then
  echo "✅ /app/webui 目录可写"
else
  echo "❌ /app/webui 目录不可写，启动可能会失败！请检查 Dockerfile 中的权限设置。"
fi
echo "✅ 系统环境自检完成"

# ==================================================
# 环境变量设置
# ==================================================
echo "🔧 [1] 解析 UI 与 ARGS 环境变量..."
UI="${UI:-forge}"
ARGS="${ARGS:---xformers --api --listen --enable-insecure-extension-access --theme dark}"
echo "  - UI 类型 (UI): ${UI}"
echo "  - WebUI 启动参数 (ARGS): ${ARGS}"

echo "🔧 [2] 解析下载开关环境变量 (默认全部启用)..."
# ... (下载开关环境变量解析保持不变) ...
ENABLE_DOWNLOAD_ALL="${ENABLE_DOWNLOAD:-true}"
ENABLE_DOWNLOAD_MODELS="${ENABLE_DOWNLOAD_MODELS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_EXTS="${ENABLE_DOWNLOAD_EXTS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_CONTROLNET="${ENABLE_DOWNLOAD_CONTROLNET:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_VAE="${ENABLE_DOWNLOAD_VAE:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_TEXT_ENCODERS="${ENABLE_DOWNLOAD_TEXT_ENCODERS:-$ENABLE_DOWNLOAD_ALL}"
# ENABLE_DOWNLOAD_TRANSFORMERS is not directly used below, control happens via MODELS/EXTS flags
echo "  - 下载总开关 (ENABLE_DOWNLOAD): ${ENABLE_DOWNLOAD_ALL}"
echo "  - 下载 Models   (ENABLE_DOWNLOAD_MODELS): ${ENABLE_DOWNLOAD_MODELS}"
echo "  - 下载 Extensions(ENABLE_DOWNLOAD_EXTS): ${ENABLE_DOWNLOAD_EXTS}"
echo "  - 下载 ControlNet(ENABLE_DOWNLOAD_CONTROLNET): ${ENABLE_DOWNLOAD_CONTROLNET}"
echo "  - 下载 VAE       (ENABLE_DOWNLOAD_VAE): ${ENABLE_DOWNLOAD_VAE}"
echo "  - 下载 TextEncodr(ENABLE_DOWNLOAD_TEXT_ENCODERS): ${ENABLE_DOWNLOAD_TEXT_ENCODERS}"

export NO_TCMALLOC=1
# 设置 pip 的额外索引 URL (用于查找 PyTorch CUDA 12.8 Nightly 包)
export PIP_EXTRA_INDEX_URL="https://download.pytorch.org/whl/nightly/cu128"
echo "  - 禁用的 TCMalloc (NO_TCMALLOC): ${NO_TCMALLOC}"
echo "  - pip 额外索引 (PIP_EXTRA_INDEX_URL): ${PIP_EXTRA_INDEX_URL}"

# ==================================================
# 设置 Git 源路径
# ==================================================
echo "🔧 [3] 设置 WebUI 仓库路径与 Git 源 (通常为最新开发版/Preview)..."
TARGET_DIR=""
REPO=""
WEBUI_EXECUTABLE="webui.sh"

if [ "$UI" = "auto" ]; then
  TARGET_DIR="/app/webui/stable-diffusion-webui"
  REPO="https://github.com/AUTOMATIC1111/stable-diffusion-webui.git"
elif [ "$UI" = "forge" ]; then
  TARGET_DIR="/app/webui/sd-webui-forge"
  # 使用官方 Forge 仓库。如果需要特定 fork (如 amDosion 的)，请修改下面的 URL
  REPO="https://github.com/lllyasviel/stable-diffusion-webui-forge.git"
  # REPO="https://github.com/amDosion/stable-diffusion-webui-forge-cuda128.git" # 备选 Fork URL
elif [ "$UI" = "stable_diffusion_webui" ]; then # Alias for auto
  TARGET_DIR="/app/webui/stable-diffusion-webui"
  REPO="https://github.com/AUTOMATIC1111/stable-diffusion-webui.git"
else
  echo "❌ 未知的 UI 类型: $UI。请设置 UI 环境变量为 'auto' 或 'forge' 或 'stable_diffusion_webui'。"
  exit 1
fi
echo "  - 目标目录: $TARGET_DIR"
echo "  - Git 仓库源: $REPO (将克隆默认/主分支)"

# ==================================================
# 克隆/更新 WebUI 仓库
# ==================================================
echo "🔄 [4] 克隆或更新 WebUI 仓库..."
# ... (克隆/更新逻辑保持不变) ...
if [ -d "$TARGET_DIR/.git" ]; then
  echo "  - 仓库已存在于 $TARGET_DIR，尝试更新 (git pull)..."
  cd "$TARGET_DIR"
  git pull --ff-only || echo "⚠️ Git pull 失败，可能是本地有修改或网络问题。将继续使用当前版本。"
  cd /app/webui
else
  echo "  - 仓库不存在，开始克隆 $REPO 到 $TARGET_DIR..."
  git clone --depth=1 "$REPO" "$TARGET_DIR"
  if [ -f "$TARGET_DIR/$WEBUI_EXECUTABLE" ]; then
      chmod +x "$TARGET_DIR/$WEBUI_EXECUTABLE"
      echo "  - 已赋予 $TARGET_DIR/$WEBUI_EXECUTABLE 执行权限"
  else
      echo "⚠️ 未在 $TARGET_DIR 中找到预期的启动脚本 $WEBUI_EXECUTABLE"
  fi
fi
echo "✅ 仓库操作完成"

# 切换到 WebUI 目录进行后续操作
cd "$TARGET_DIR"

# ==================================================
# requirements_versions.txt 修复 (仅非 Forge UI)
# 注意：此步骤已移除硬编码的版本修改，依赖 requirements 文件和 --pre 标志
# ==================================================
if [ "$UI" != "forge" ]; then
    echo "🔧 [5] (非 Forge UI) 检查 requirements 文件..."
    REQ_FILE_CHECK="requirements_versions.txt"
    if [ ! -f "$REQ_FILE_CHECK" ]; then
        REQ_FILE_CHECK="requirements.txt"
    fi
    if [ -f "$REQ_FILE_CHECK" ]; then
        echo "  - 将使用 $REQ_FILE_CHECK 文件安装依赖。"
        # 可以选择性地清理文件 (如果需要)
        # echo "  - 清理 $REQ_FILE_CHECK 中的注释和空行..."
        # CLEANED_REQ_FILE="${REQ_FILE_CHECK}.cleaned"
        # sed 's/#.*//; s/[[:space:]]*$//; /^\s*$/d' "$REQ_FILE_CHECK" > "$CLEANED_REQ_FILE"
        # mv "$CLEANED_REQ_FILE" "$REQ_FILE_CHECK"
        # echo "  - 清理完成。"
    else
        echo "  - ⚠️ 未找到 $REQ_FILE_CHECK 或 requirements.txt。依赖安装可能不完整。"
    fi
else
    echo "⚙️ [5] (Forge UI) 跳过手动处理 requirements 文件的步骤 (由 Forge 自行处理)。"
fi

# ==================================================
# 权限设置 (警告：777 过于宽松)
# ==================================================
echo "⚠️ [5.5] 正在为 $TARGET_DIR 设置递归 777 权限。这在生产环境中不推荐！"
chmod -R 777 . || echo "⚠️ chmod 777 失败，后续步骤可能因权限问题失败。"

# ==================================================
# Python 虚拟环境设置与依赖安装
# ==================================================
VENV_DIR="venv"
echo "🐍 [6] 设置 Python 虚拟环境 ($VENV_DIR)..."
# ... (虚拟环境创建检查和激活逻辑保持不变) ...
if [ ! -x "$VENV_DIR/bin/activate" ]; then
  echo "  - 虚拟环境不存在或未正确创建，现在使用 python3.11 创建..."
  rm -rf "$VENV_DIR"
  python3.11 -m venv "$VENV_DIR"
  echo "  - 虚拟环境创建成功。"
else
  echo "  - 虚拟环境已存在。"
fi
echo "  - 激活虚拟环境..."
source "$VENV_DIR/bin/activate"
echo "  - 当前 Python: $(which python) (应在 venv 内)"
echo "  - 当前 pip: $(which pip) (应在 venv 内)"

echo "📥 [6.1] 升级 pip 到最新版本..."
pip install --upgrade pip | tee -a "$LOG_FILE"

echo "📥 [6.2] 安装 WebUI 核心依赖 (基于 UI 类型)..."
if [ "$UI" = "forge" ]; then
    echo "  - (Forge UI) 依赖安装将由 $WEBUI_EXECUTABLE 处理，此处跳过手动 pip install。"
else
    # Automatic1111 或其他非 Forge UI
    REQ_FILE_TO_INSTALL="requirements_versions.txt"
    if [ ! -f "$REQ_FILE_TO_INSTALL" ]; then
        REQ_FILE_TO_INSTALL="requirements.txt"
    fi

    if [ -f "$REQ_FILE_TO_INSTALL" ]; then
        echo "  - 使用 $REQ_FILE_TO_INSTALL 安装依赖 (允许预发布版本 --pre)..."
        sed -i 's/\r$//' "$REQ_FILE_TO_INSTALL" # 修复 Windows 换行符
        while IFS= read -r line || [[ -n "$line" ]]; do
            line=$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            [[ -z "$line" ]] && continue
            echo "    - 安装: ${line}"
            # 添加 --pre 允许安装预发布版本，这对于匹配 Nightly PyTorch 很重要
            # 使用 --no-cache-dir 减少空间占用
            pip install --pre "${line}" --no-cache-dir --extra-index-url "$PIP_EXTRA_INDEX_URL" 2>&1 \
                | tee -a "$LOG_FILE" \
                | sed 's/^Successfully installed/      ✅ 成功安装/' \
                | sed 's/^Requirement already satisfied/      ⏩ 需求已满足/'
            if [ ${PIPESTATUS[0]} -ne 0 ]; then
                echo "❌ 安装失败: ${line}"
            fi
        done < "$REQ_FILE_TO_INSTALL"
        echo "  - $REQ_FILE_TO_INSTALL 中的依赖处理完成。"
    else
        echo "⚠️ 未找到 $REQ_FILE_TO_INSTALL 或 requirements.txt，无法自动安装核心依赖。"
    fi
fi

# ==================================================
# TensorFlow 安装 (可选，在 venv 内)
# ==================================================
INSTALL_TENSORFLOW="${INSTALL_TENSORFLOW:-false}"
if [[ "$INSTALL_TENSORFLOW" == "true" ]]; then
    echo "🧠 [6.4] 按需安装 TensorFlow (版本需兼容 CUDA 12.8)..."
    # ... (TensorFlow 安装逻辑保持不变, 使用 v2.16.1) ...
    echo "  - 正在检测 CPU 支持情况..."
    CPU_VENDOR=$(grep -m 1 'vendor_id' /proc/cpuinfo | awk '{print $3}' || echo "未知")
    AVX2_SUPPORTED=$(grep -q avx2 /proc/cpuinfo && echo "true" || echo "false")
    echo "    - CPU Vendor: ${CPU_VENDOR}"
    echo "    - AVX2 支持: ${AVX2_SUPPORTED}"
    TF_VERSION="2.16.1" # 确认此版本 pip 包支持 CUDA 12.8 (通常支持)
    TF_CPU_VERSION="2.16.1"
    echo "    - 目标 TensorFlow 版本: ${TF_VERSION} (GPU) / ${TF_CPU_VERSION} (CPU)"

    if [[ "$AVX2_SUPPORTED" == "true" ]]; then
        echo "    - AVX2 支持，继续安装..."
        echo "    - 尝试卸载旧的 TensorFlow..."
        pip uninstall -y tensorflow tensorflow-cpu tensorflow-gpu tensorboard tf-nightly &>/dev/null || true
        TF_PACKAGE=""
        if command -v nvidia-smi &>/dev/null; then
            echo "    - 检测到 GPU，尝试安装 TensorFlow GPU 版本..."
            TF_PACKAGE="tensorflow==${TF_VERSION}"
        else
            echo "    - 未检测到 GPU，安装 TensorFlow CPU 版本..."
            TF_PACKAGE="tensorflow-cpu==${TF_CPU_VERSION}"
        fi
        echo "    - 安装: ${TF_PACKAGE}"
        pip install "${TF_PACKAGE}" --no-cache-dir | tee -a "$LOG_FILE"
        if [ ${PIPESTATUS[0]} -ne 0 ]; then
            echo "❌ TensorFlow 安装失败!"
        else
            echo "    - ✅ TensorFlow 安装完成。"
            echo "    - 🧪 验证 TensorFlow GPU 可用性 (如果安装了 GPU 版本)..."
            if [[ "$TF_PACKAGE" == *"tensorflow=="* ]]; then # 仅在安装 GPU 版本时验证
                python -c "import warnings; warnings.filterwarnings('ignore', category=FutureWarning); warnings.filterwarnings('ignore', category=UserWarning); import tensorflow as tf; gpus = tf.config.list_physical_devices('GPU'); print(f'TensorFlow Version: {tf.__version__}'); print(f'Num GPUs Available: {len(gpus)}'); print(f'Available GPUs: {gpus}'); assert len(gpus) > 0, 'No GPU detected by TensorFlow'"
                if [ $? -eq 0 ]; then
                    echo "    - ✅ TensorFlow 成功检测到 GPU！"
                else
                    echo "    - ⚠️ TensorFlow 未能检测到 GPU 或验证失败。请检查 CUDA/cuDNN 版本兼容性以及 Nvidia 驱动。"
                fi
            else
                 echo "    - (安装了 CPU 版本，跳过 GPU 验证)"
            fi
        fi
    else
        echo "    - ⚠️ 未检测到 AVX2 指令集，将安装 TensorFlow CPU 版本。"
        pip uninstall -y tensorflow tensorflow-cpu tensorflow-gpu tensorboard tf-nightly &>/dev/null || true
        TF_PACKAGE="tensorflow-cpu==${TF_CPU_VERSION}"
        echo "    - 安装: ${TF_PACKAGE}"
        pip install "${TF_PACKAGE}" --no-cache-dir | tee -a "$LOG_FILE"
        if [ ${PIPESTATUS[0]} -ne 0 ]; then
            echo "❌ TensorFlow CPU 安装失败!"
        else
            echo "    - ✅ TensorFlow CPU 安装完成。"
        fi
    fi
else
    echo "⏭️ [6.4] 跳过 TensorFlow 安装 (INSTALL_TENSORFLOW 未设置为 true)。"
fi

# ==================================================
# 创建 WebUI 相关目录
# ==================================================
echo "📁 [7] 确保 WebUI 主要目录存在..."
# ... (目录创建逻辑保持不变) ...
mkdir -p embeddings models/Stable-diffusion models/VAE models/Lora models/LyCORIS models/ControlNet outputs extensions || echo "⚠️ 创建部分目录失败，请检查权限。"
echo "  - 主要目录检查/创建完成。"

# ==================================================
# 网络测试
# ==================================================
echo "🌐 [8] 网络连通性测试 (访问 huggingface.co)..."
# ... (网络测试逻辑保持不变) ...
NET_OK=false
if curl -s --connect-timeout 5 https://huggingface.co > /dev/null; then
  NET_OK=true
  echo "  - ✅ 网络连通 (huggingface.co 可访问)"
else
  if curl -s --connect-timeout 5 https://github.com > /dev/null; then
      NET_OK=true
      echo "  - ⚠️ huggingface.co 无法访问，但 github.com 可访问。部分模型下载可能受影响。"
  else
      echo "  - ❌ 网络不通 (无法访问 huggingface.co 和 github.com)。资源下载和插件更新将失败！"
  fi
fi

# ==================================================
# 资源下载 (使用 resources.txt)
# ==================================================
echo "📦 [9] 处理资源下载 (基于 resources.txt 和下载开关)..."
# ... (资源下载逻辑，包括 clone_or_update_repo 和 download_with_progress 函数，以及处理循环，保持不变) ...
RESOURCE_PATH="/app/webui/resources.txt"
if [ ! -f "$RESOURCE_PATH" ]; then
  DEFAULT_RESOURCE_URL="https://raw.githubusercontent.com/chuan1127/SD-webui-forge/main/resources.txt" # 使用你的原始 URL
  echo "  - 未找到本地 resources.txt，尝试从 ${DEFAULT_RESOURCE_URL} 下载..."
  curl -fsSL -o "$RESOURCE_PATH" "$DEFAULT_RESOURCE_URL"
  if [ $? -eq 0 ]; then
      echo "  - ✅ 默认 resources.txt 下载成功。"
  else
      echo "  - ❌ 下载默认 resources.txt 失败。请手动创建 ${RESOURCE_PATH} 或检查网络。"
      touch "$RESOURCE_PATH"
      echo "  - 已创建空的 resources.txt 文件以继续，但不会下载任何资源。"
  fi
else
  echo "  - ✅ 使用本地已存在的 resources.txt: ${RESOURCE_PATH}"
fi

clone_or_update_repo() {
  local dir="$1" repo="$2"
  local dirname
  dirname=$(basename "$dir")
  if [ -d "$dir/.git" ]; then
    if [[ "$ENABLE_DOWNLOAD_EXTS" == "true" ]]; then
        echo "    - 🔄 更新扩展: $dirname"
        (cd "$dir" && git pull --ff-only) || echo "      ⚠️ Git pull 失败: $dirname"
    else
        echo "    - ⏭️ 跳过更新扩展 (ENABLE_DOWNLOAD_EXTS=false): $dirname"
    fi
  elif [ ! -d "$dir" ]; then
    if [[ "$ENABLE_DOWNLOAD_EXTS" == "true" ]]; then
        echo "    - 📥 克隆扩展: $repo -> $dirname"
        git clone --depth=1 "$repo" "$dir" || echo "      ❌ Git clone 失败: $dirname"
    else
        echo "    - ⏭️ 跳过克隆扩展 (ENABLE_DOWNLOAD_EXTS=false): $dirname"
    fi
  else
    echo "    - ✅ 目录已存在但非 Git 仓库: $dirname"
  fi
}

download_with_progress() {
  local output_path="$1" url="$2" type="$3" enabled_flag="$4"
  local filename
  filename=$(basename "$output_path")
  if [[ "$enabled_flag" != "true" ]]; then
      echo "    - ⏭️ 跳过下载 ${type} (下载开关 '$enabled_flag' 关闭): $filename"
      return
  fi
  if [[ "$NET_OK" != "true" ]]; then
      echo "    - ❌ 跳过下载 ${type} (网络不通): $filename"
      return
  fi
  if [ ! -f "$output_path" ]; then
    echo "    - ⬇️ 下载 ${type}: $filename"
    mkdir -p "$(dirname "$output_path")"
    wget --progress=bar:force:noscroll --prefer-dns=ipv4 --timeout=60 -O "$output_path" "$url" # Increased timeout to 60s
    if [ $? -ne 0 ]; then
        echo "      ❌ 下载失败: $filename from $url"
        rm -f "$output_path"
    else
        echo "      ✅ 下载完成: $filename"
    fi
  else
    echo "    - ✅ 文件已存在，跳过下载 ${type}: $filename"
  fi
}

SKIP_DIRS=(
  "extensions/stable-diffusion-aws-extension"
  "extensions/sd_dreambooth_extension"
)
should_skip() {
  local dir_to_check="$1"
  for skip_dir in "${SKIP_DIRS[@]}"; do
    if [[ "$dir_to_check" == "$skip_dir" ]]; then
      return 0 # 0 means skip
    fi
  done
  return 1 # 1 means do not skip
}

echo "  - 开始处理 resources.txt 中的条目..."
while IFS=, read -r target_path source_url || [[ -n "$target_path" ]]; do
  target_path=$(echo "$target_path" | xargs)
  source_url=$(echo "$source_url" | xargs)
  [[ "$target_path" =~ ^#.*$ || -z "$target_path" || -z "$source_url" ]] && continue
  if should_skip "$target_path"; then
    echo "    - ⛔ 跳过黑名单条目: $target_path"
    continue
  fi
  case "$target_path" in
    extensions/*)
      clone_or_update_repo "$target_path" "$source_url"
      ;;
    models/ControlNet/*)
      download_with_progress "$target_path" "$source_url" "ControlNet Model" "$ENABLE_DOWNLOAD_CONTROLNET"
      ;;
    models/VAE/*)
      download_with_progress "$target_path" "$source_url" "VAE Model" "$ENABLE_DOWNLOAD_VAE"
      ;;
    models/Lora/* | models/LyCORIS/* | models/LoCon/*)
      download_with_progress "$target_path" "$source_url" "LoRA/LyCORIS Model" "$ENABLE_DOWNLOAD_MODELS"
      ;;
    models/Stable-diffusion/*)
      download_with_progress "$target_path" "$source_url" "Stable Diffusion Checkpoint" "$ENABLE_DOWNLOAD_MODELS"
      ;;
    models/text_encoder/*)
      download_with_progress "$target_path" "$source_url" "Text Encoder" "$ENABLE_DOWNLOAD_TEXT_ENCODERS"
      ;;
    embeddings/*)
       download_with_progress "$target_path" "$source_url" "Embedding" "$ENABLE_DOWNLOAD_MODELS"
       ;;
    *)
      if [[ "$source_url" == *.git ]]; then
           echo "    - ❓ 处理未分类 Git 仓库: $target_path (假设为扩展)"
           clone_or_update_repo "$target_path" "$source_url"
      elif [[ "$source_url" == http* ]]; then
           echo "    - ❓ 处理未分类文件下载: $target_path (假设为模型)"
           download_with_progress "$target_path" "$source_url" "Unknown Model/File" "$ENABLE_DOWNLOAD_MODELS"
      else
           echo "    - ❓ 无法识别的资源类型或无效 URL: $target_path, $source_url"
      fi
      ;;
  esac
done < "$RESOURCE_PATH"
echo "✅ 资源下载处理完成。"

# ==================================================
# Token 处理
# ==================================================
echo "🔐 [10] 处理 API Tokens..."
# ... (Token 处理逻辑保持不变) ...
if [[ -n "$HUGGINGFACE_TOKEN" ]]; then
  echo "  - 检测到 HUGGINGFACE_TOKEN，尝试登录..."
  if command -v huggingface-cli &>/dev/null; then
      echo "$HUGGINGFACE_TOKEN" | huggingface-cli login --token --add-to-git-credential
      if [ $? -eq 0 ]; then
          echo "  - ✅ Hugging Face CLI 登录成功。"
      else
          echo "  - ⚠️ Hugging Face CLI 登录失败。请检查 Token 是否有效。"
      fi
  else
      echo "  - ⚠️ 未找到 huggingface-cli 命令，无法登录。请确保 huggingface_hub[cli] 已安装。"
  fi
else
  echo "  - ⏭️ 未设置 HUGGINGFACE_TOKEN，跳过 Hugging Face 登录。"
fi

if [[ -n "$CIVITAI_API_TOKEN" ]]; then
  echo "  - ✅ 检测到 CIVITAI_API_TOKEN (长度: ${#CIVITAI_API_TOKEN})。某些插件可能会使用此 Token。"
else
  echo "  - ⏭️ 未设置 CIVITAI_API_TOKEN。"
fi

# ==================================================
# 🔥 启动 WebUI
# ==================================================
echo "🚀 [11] 所有准备工作完成，开始启动 WebUI ($WEBUI_EXECUTABLE)..."
echo "  - UI Type: ${UI}"
echo "  - Arguments: -f ${ARGS}" # -f 通常用于 Forge，强制跳过它的内部安装步骤 (因为我们已完成)

cd "$TARGET_DIR" || { echo "❌ 无法切换到目录 $TARGET_DIR，启动失败！"; exit 1; }

echo "⏳ WebUI 启动时间: $(date)"
# 使用 exec 运行，确保在 venv 环境内
exec bash "$WEBUI_EXECUTABLE" -f $ARGS

# Script should not reach here if exec is successful
echo "❌ 启动 $WEBUI_EXECUTABLE 失败！"
exit 1
