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
echo "🔧 使用 PyTorch Nightly (Preview) builds 构建。"
echo "🔧 xformers 已在 Docker 构建时从源码编译 (目标架构: 8.9 for RTX 4090)。"
echo "🔧 TensorFlow Nightly 已在 Docker 构建时安装。"

# ==================================================
# 系统环境自检
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

# CUDA & GPU 检查 (nvidia-smi)
if command -v nvidia-smi &>/dev/null; then
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
# 解析各类资源的下载开关
ENABLE_DOWNLOAD_ALL="${ENABLE_DOWNLOAD:-true}"
ENABLE_DOWNLOAD_MODELS="${ENABLE_DOWNLOAD_MODELS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_EXTS="${ENABLE_DOWNLOAD_EXTS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_CONTROLNET="${ENABLE_DOWNLOAD_CONTROLNET:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_VAE="${ENABLE_DOWNLOAD_VAE:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_TEXT_ENCODERS="${ENABLE_DOWNLOAD_TEXT_ENCODERS:-$ENABLE_DOWNLOAD_ALL}"
echo "  - 下载总开关 (ENABLE_DOWNLOAD): ${ENABLE_DOWNLOAD_ALL}"
echo "  - 下载 Models   (ENABLE_DOWNLOAD_MODELS): ${ENABLE_DOWNLOAD_MODELS}"
echo "  - 下载 Extensions(ENABLE_DOWNLOAD_EXTS): ${ENABLE_DOWNLOAD_EXTS}"
echo "  - 下载 ControlNet(ENABLE_DOWNLOAD_CONTROLNET): ${ENABLE_DOWNLOAD_CONTROLNET}"
echo "  - 下载 VAE       (ENABLE_DOWNLOAD_VAE): ${ENABLE_DOWNLOAD_VAE}"
echo "  - 下载 TextEncodr(ENABLE_DOWNLOAD_TEXT_ENCODERS): ${ENABLE_DOWNLOAD_TEXT_ENCODERS}"

# TCMalloc 和 Pip 索引设置
export NO_TCMALLOC=1
export PIP_EXTRA_INDEX_URL="https://download.pytorch.org/whl/nightly/cu128"
echo "  - 禁用的 TCMalloc (NO_TCMALLOC): ${NO_TCMALLOC}"
echo "  - pip 额外索引 (PIP_EXTRA_INDEX_URL): ${PIP_EXTRA_INDEX_URL} (用于 PyTorch Nightly cu128)"

# ==================================================
# 设置 Git 源路径
# ==================================================
echo "🔧 [3] 设置 WebUI 仓库路径与 Git 源 (通常为最新开发版/Preview)..."
TARGET_DIR=""
REPO=""
WEBUI_EXECUTABLE="webui.sh"

# 根据 UI 环境变量设置目标目录和仓库 URL
if [ "$UI" = "auto" ]; then
  TARGET_DIR="/app/webui/stable-diffusion-webui"
  REPO="https://github.com/AUTOMATIC1111/stable-diffusion-webui.git"
elif [ "$UI" = "forge" ]; then
  TARGET_DIR="/app/webui/sd-webui-forge"
  REPO="https://github.com/lllyasviel/stable-diffusion-webui-forge.git"
elif [ "$UI" = "stable_diffusion_webui" ]; then
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
echo "🔄 [4] 克隆或更新 WebUI 仓库..."
if [ -d "$TARGET_DIR/.git" ]; then
  echo "  - 仓库已存在于 $TARGET_DIR，尝试更新 (git pull)..."
  cd "$TARGET_DIR"
  git pull --ff-only || echo "⚠️ Git pull 失败，可能是本地有修改或网络问题。将继续使用当前版本。"
  cd /app/webui
else
  echo "  - 仓库不存在，开始克隆 $REPO 到 $TARGET_DIR (浅克隆)..."
  git clone --depth=1 "$REPO" "$TARGET_DIR"
  if [ -f "$TARGET_DIR/$WEBUI_EXECUTABLE" ]; then
      chmod +x "$TARGET_DIR/$WEBUI_EXECUTABLE"
      echo "  - 已赋予 $TARGET_DIR/$WEBUI_EXECUTABLE 执行权限"
  else
      echo "⚠️ 未在克隆的仓库 $TARGET_DIR 中找到预期的启动脚本 $WEBUI_EXECUTABLE"
  fi
fi
echo "✅ 仓库操作完成"

# 切换到 WebUI 目标目录
cd "$TARGET_DIR" || { echo "❌ 无法切换到 WebUI 目标目录 $TARGET_DIR"; exit 1; }

# ==================================================
# requirements 文件检查 (仅非 Forge UI)
# ==================================================
if [ "$UI" != "forge" ]; then
    echo "🔧 [5] (非 Forge UI) 检查 requirements 文件..."
    REQ_FILE_CHECK="requirements_versions.txt"
    if [ ! -f "$REQ_FILE_CHECK" ]; then
        REQ_FILE_CHECK="requirements.txt"
    fi
    if [ -f "$REQ_FILE_CHECK" ]; then
        echo "  - 将使用 $REQ_FILE_CHECK 文件安装依赖。"
    else
        echo "  - ⚠️ 未找到 $REQ_FILE_CHECK 或 requirements.txt。依赖安装可能不完整。"
    fi
else
    echo "⚙️ [5] (Forge UI) 跳过手动处理 requirements 文件的步骤 (由 Forge $WEBUI_EXECUTABLE 自行处理)。"
fi

# ==================================================
# 权限设置 (警告)
# ==================================================
echo "⚠️ [5.5] 正在为当前目录 ($TARGET_DIR) 设置递归 777 权限。这在生产环境中不推荐！"
chmod -R 777 . || echo "⚠️ chmod 777 失败，后续步骤可能因权限问题失败。"

# ==================================================
# Python 虚拟环境设置与依赖安装
# ==================================================
VENV_DIR="venv"
echo "🐍 [6] 设置 Python 虚拟环境 ($VENV_DIR)..."

if [ ! -x "$VENV_DIR/bin/activate" ]; then
  echo "  - 虚拟环境不存在或未正确创建，现在使用 python3.11 创建..."
  rm -rf "$VENV_DIR"
  python3.11 -m venv "$VENV_DIR"
  echo "  - 虚拟环境创建成功。"
else
  echo "  - 虚拟环境已存在于 $VENV_DIR。"
fi

echo "  - 激活虚拟环境..."
source "$VENV_DIR/bin/activate"

echo "  - 当前 Python: $(which python) (应指向 $VENV_DIR/bin/python)"
echo "  - 当前 pip: $(which pip) (应指向 $VENV_DIR/bin/pip)"

echo "📥 [6.1] 升级 venv 内的 pip 到最新版本..."
pip install --upgrade pip | tee -a "$LOG_FILE"

# ==================================================
# 安装 WebUI 核心依赖 (基于 UI 类型)
# ==================================================
echo "📥 [6.2] 安装 WebUI 核心依赖 (基于 UI 类型)..."

if [ "$UI" = "forge" ]; then
    echo "  - (Forge UI) 依赖安装将由 $WEBUI_EXECUTABLE 处理，此处跳过手动 pip install。"
    echo "  - Forge 通常会处理 xformers 等关键依赖的安装或检查。"
else
    # Automatic1111 或其他非 Forge UI
    REQ_FILE_TO_INSTALL="requirements_versions.txt"
    if [ ! -f "$REQ_FILE_TO_INSTALL" ]; then
        REQ_FILE_TO_INSTALL="requirements.txt"
    fi

    if [ -f "$REQ_FILE_TO_INSTALL" ]; then
        echo "  - 使用 $REQ_FILE_TO_INSTALL 安装依赖 (允许预发布版本 --pre)..."
        echo "  - (注意: xformers 和 TensorFlow Nightly 预计已在 Dockerfile 中安装)"
        sed -i 's/\r$//' "$REQ_FILE_TO_INSTALL"
        while IFS= read -r line || [[ -n "$line" ]]; do
            line=$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            [[ -z "$line" ]] && continue
            echo "    - 安装: ${line}"
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
        echo "⚠️ 未找到 $REQ_FILE_TO_INSTALL 或 requirements.txt，无法自动安装核心依赖。请检查 WebUI 仓库内容。"
    fi
fi

# 注意：TensorFlow 安装步骤 [6.4] 已移除

# ==================================================
# 创建 WebUI 相关目录
# ==================================================
# 步骤号顺延
echo "📁 [7] 确保 WebUI 主要工作目录存在..."
mkdir -p embeddings models/Stable-diffusion models/VAE models/Lora models/LyCORIS models/ControlNet outputs extensions || echo "⚠️ 创建部分目录失败，请检查权限。"
echo "  - 主要目录检查/创建完成。"

# ==================================================
# 网络测试 (可选)
# ==================================================
# 步骤号顺延
echo "🌐 [8] 网络连通性测试 (尝试访问 huggingface.co)..."
NET_OK=false
if curl -fsS --connect-timeout 5 https://huggingface.co > /dev/null; then
  NET_OK=true
  echo "  - ✅ 网络连通 (huggingface.co 可访问)"
else
  if curl -fsS --connect-timeout 5 https://github.com > /dev/null; then
      NET_OK=true
      echo "  - ⚠️ huggingface.co 无法访问，但 github.com 可访问。部分模型下载可能受影响。"
  else
      echo "  - ❌ 网络不通 (无法访问 huggingface.co 和 github.com)。资源下载和插件更新将失败！"
  fi
fi

# ==================================================
# 资源下载 (使用 resources.txt)
# ==================================================
# 步骤号顺延
echo "📦 [9] 处理资源下载 (基于 /app/webui/resources.txt 和下载开关)..."
RESOURCE_PATH="/app/webui/resources.txt"

if [ ! -f "$RESOURCE_PATH" ]; then
  DEFAULT_RESOURCE_URL="https://raw.githubusercontent.com/chuan1127/SD-webui-forge/main/resources.txt"
  echo "  - 未找到本地 resources.txt，尝试从 ${DEFAULT_RESOURCE_URL} 下载..."
  curl -fsSL -o "$RESOURCE_PATH" "$DEFAULT_RESOURCE_URL"
  if [ $? -eq 0 ]; then
      echo "  - ✅ 默认 resources.txt 下载成功。"
  else
      echo "  - ❌ 下载默认 resources.txt 失败。请手动将资源文件放在 ${RESOURCE_PATH} 或检查网络/URL。"
      touch "$RESOURCE_PATH"
      echo "  - 已创建空的 resources.txt 文件以继续，但不会下载任何资源。"
  fi
else
  echo "  - ✅ 使用本地已存在的 resources.txt: ${RESOURCE_PATH}"
fi

# 定义函数：克隆或更新 Git 仓库
clone_or_update_repo() {
  local dir="$1" repo="$2"
  local dirname
  dirname=$(basename "$dir")
  if [ -d "$dir/.git" ]; then
    if [[ "$ENABLE_DOWNLOAD_EXTS" == "true" ]]; then
        echo "    - 🔄 更新扩展/仓库: $dirname"
        (cd "$dir" && git pull --ff-only) || echo "      ⚠️ Git pull 失败: $dirname (可能存在本地修改或网络问题)"
    else
        echo "    - ⏭️ 跳过更新扩展/仓库 (ENABLE_DOWNLOAD_EXTS=false): $dirname"
    fi
  elif [ ! -d "$dir" ]; then
    if [[ "$ENABLE_DOWNLOAD_EXTS" == "true" ]]; then
        echo "    - 📥 克隆扩展/仓库: $repo -> $dirname (浅克隆)"
        git clone --depth=1 "$repo" "$dir" || echo "      ❌ Git clone 失败: $dirname (检查 URL 和网络)"
    else
        echo "    - ⏭️ 跳过克隆扩展/仓库 (ENABLE_DOWNLOAD_EXTS=false): $dirname"
    fi
  else
    echo "    - ✅ 目录已存在但非 Git 仓库，跳过 Git 操作: $dirname"
  fi
}

# 定义函数：下载文件
download_with_progress() {
  local output_path="$1" url="$2" type="$3" enabled_flag="$4"
  local filename
  filename=$(basename "$output_path")
  if [[ "$enabled_flag" != "true" ]]; then
      echo "    - ⏭️ 跳过下载 ${type} (开关 '$enabled_flag' 关闭): $filename"
      return
  fi
  if [[ "$NET_OK" != "true" ]]; then
      echo "    - ❌ 跳过下载 ${type} (网络不通): $filename"
      return
  fi
  if [ ! -f "$output_path" ]; then
    echo "    - ⬇️ 下载 ${type}: $filename"
    mkdir -p "$(dirname "$output_path")"
    wget --progress=bar:force:noscroll --timeout=120 -O "$output_path" "$url"
    if [ $? -ne 0 ]; then
        echo "      ❌ 下载失败: $filename from $url (检查 URL 或网络)"
        rm -f "$output_path"
    else
        echo "      ✅ 下载完成: $filename"
    fi
  else
    echo "    - ✅ 文件已存在，跳过下载 ${type}: $filename"
  fi
}

# 定义插件/目录黑名单
SKIP_DIRS=(
  "extensions/stable-diffusion-aws-extension"
  "extensions/sd_dreambooth_extension"
)
# 函数：检查目标路径是否应跳过
should_skip() {
  local dir_to_check="$1"
  for skip_dir in "${SKIP_DIRS[@]}"; do
    if [[ "$dir_to_check" == "$skip_dir" ]]; then
      return 0
    fi
  done
  return 1
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
    models/TextualInversion/* | embeddings/*)
       download_with_progress "$target_path" "$source_url" "Embedding/Textual Inversion" "$ENABLE_DOWNLOAD_MODELS"
       ;;
    models/Upscaler/* | models/ESRGAN/*)
       download_with_progress "$target_path" "$source_url" "Upscaler Model" "$ENABLE_DOWNLOAD_MODELS"
       ;;
    *)
      if [[ "$source_url" == *.git ]]; then
           echo "    - ❓ 处理未分类 Git 仓库: $target_path (假设为扩展)"
           clone_or_update_repo "$target_path" "$source_url" # 使用 EXTS 开关
      elif [[ "$source_url" == http* ]]; then
           echo "    - ❓ 处理未分类文件下载: $target_path (假设为模型)"
           download_with_progress "$target_path" "$source_url" "Unknown Model/File" "$ENABLE_DOWNLOAD_MODELS" # 使用 MODELS 开关
      else
           echo "    - ❓ 无法识别的资源类型或无效 URL: target='$target_path', source='$source_url'"
      fi
      ;;
  esac
done < "$RESOURCE_PATH"
echo "✅ 资源下载处理完成。"

# ==================================================
# Token 处理 (Hugging Face, Civitai)
# ==================================================
# 步骤号顺延
echo "🔐 [10] 处理 API Tokens (如果已提供)..."
if [[ -n "$HUGGINGFACE_TOKEN" ]]; then
  echo "  - 检测到 HUGGINGFACE_TOKEN，尝试使用 huggingface-cli 登录..."
  if command -v huggingface-cli &>/dev/null; then
      echo "$HUGGINGFACE_TOKEN" | huggingface-cli login --token --add-to-git-credential
      if [ $? -eq 0 ]; then
          echo "  - ✅ Hugging Face CLI 登录成功。"
      else
          echo "  - ⚠️ Hugging Face CLI 登录失败。"
      fi
  else
      echo "  - ⚠️ 未找到 huggingface-cli 命令，无法登录。"
  fi
else
  echo "  - ⏭️ 未设置 HUGGINGFACE_TOKEN 环境变量，跳过 Hugging Face 登录。"
fi

if [[ -n "$CIVITAI_API_TOKEN" ]]; then
  echo "  - ✅ 检测到 CIVITAI_API_TOKEN (长度: ${#CIVITAI_API_TOKEN})。"
else
  echo "  - ⏭️ 未设置 CIVITAI_API_TOKEN 环境变量。"
fi

# ==================================================
# 🔥 启动 WebUI
# ==================================================
# 步骤号顺延
echo "🚀 [11] 所有准备工作完成，开始启动 WebUI ($WEBUI_EXECUTABLE)..."
echo "  - UI Type: ${UI}"
echo "  - Arguments: -f ${ARGS}"

CURRENT_DIR=$(pwd)
if [[ "$CURRENT_DIR" != "$TARGET_DIR" ]]; then
     echo "⚠️ 当前目录 ($CURRENT_DIR) 不是预期的 WebUI 目录 ($TARGET_DIR)，尝试切换..."
     cd "$TARGET_DIR" || { echo "❌ 无法切换到目录 $TARGET_DIR，启动失败！"; exit 1; }
     echo "✅ 已切换到目录: $(pwd)"
fi

echo "⏳ WebUI 启动时间: $(date)"
echo "🚀 Executing: bash $WEBUI_EXECUTABLE -f $ARGS"

exec bash "$WEBUI_EXECUTABLE" -f $ARGS

echo "❌ 启动 $WEBUI_EXECUTABLE 失败！请检查脚本是否存在、是否有执行权限以及之前的日志输出。"
exit 1
