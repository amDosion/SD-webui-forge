#!/bin/bash

set -e
set -o pipefail

# 日志输出
LOG_FILE="/app/webui/launch.log"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "🚀 [0] 启动脚本 Stable Diffusion WebUI"
echo "=================================================="

# ---------------------------------------------------
# 系统环境自检
# ---------------------------------------------------
echo "🛠️  [0.5] 系统环境自检..."

# Python 检查
if command -v python3 &>/dev/null; then
  echo "✅ Python3 版本: $(python3 --version)"
else
  echo "❌ 未找到 Python3，脚本将无法运行！"
  exit 1
fi

# pip 检查
if command -v pip3 &>/dev/null; then
  echo "✅ pip3 版本: $(pip3 --version)"
else
  echo "❌ pip3 未安装！请在 Dockerfile 中添加 python3-pip"
  exit 1
fi

# CUDA & GPU 检查（使用 nvidia-smi 原生输出）
if command -v nvidia-smi &>/dev/null; then
  echo "✅ nvidia-smi 检测成功，GPU 信息如下："
  echo "--------------------------------------------------"
  nvidia-smi
  echo "--------------------------------------------------"
else
  echo "⚠️ 未检测到 nvidia-smi（可能无 GPU 或驱动未安装）"
fi

# 容器检测
if [ -f "/.dockerenv" ]; then
  echo "📦 正在容器中运行"
else
  echo "🖥️ 非容器环境"
fi

echo "👤 当前用户: $(whoami)"

if [ -w "/app/webui" ]; then
  echo "✅ /app/webui 可写"
else
  echo "❌ /app/webui 不可写，可能会导致运行失败"
  exit 1
fi

echo "✅ 系统环境自检通过"

# ---------------------------------------------------
# 环境变量设置
# ---------------------------------------------------
echo "🔧 [1] 解析 UI 与 ARGS 环境变量..."
UI="${UI:-forge}"
ARGS="${ARGS:---xformers --api --listen --enable-insecure-extension-access --theme dark}"
echo "🧠 UI=${UI}"
echo "🧠 ARGS=${ARGS}"

echo "🔧 [2] 解析下载开关环境变量..."
ENABLE_DOWNLOAD_ALL="${ENABLE_DOWNLOAD:-true}"
ENABLE_DOWNLOAD_MODELS="${ENABLE_DOWNLOAD_MODELS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_EXTS="${ENABLE_DOWNLOAD_EXTS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_CONTROLNET="${ENABLE_DOWNLOAD_CONTROLNET:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_VAE="${ENABLE_DOWNLOAD_VAE:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_TEXT_ENCODERS="${ENABLE_DOWNLOAD_TEXT_ENCODERS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_TRANSFORMERS="${ENABLE_DOWNLOAD_TRANSFORMERS:-$ENABLE_DOWNLOAD_ALL}"
echo "✅ DOWNLOAD_FLAGS: MODELS=$ENABLE_DOWNLOAD_MODELS, EXTS=$ENABLE_DOWNLOAD_EXTS"

export NO_TCMALLOC=1
export PIP_EXTRA_INDEX_URL="https://download.pytorch.org/whl/nightly/cu128"

# ---------------------------------------------------
# 设置 Git 源路径
# ---------------------------------------------------
echo "🔧 [3] 设置仓库路径与 Git 源..."
if [ "$UI" = "auto" ]; then
  TARGET_DIR="/app/webui/sd-webui"
  REPO="https://github.com/AUTOMATIC1111/stable-diffusion-webui.git"
elif [ "$UI" = "forge" ]; then
  TARGET_DIR="/app/webui/sd-webui-forge"
  REPO="https://github.com/amDosion/stable-diffusion-webui-forge-cuda128.git"
else
  echo "❌ Unknown UI: $UI"
  exit 1
fi
echo "📁 目标目录: $TARGET_DIR"
echo "🌐 GIT 源: $REPO"

# ---------------------------------------------------
# 克隆/更新仓库
# ---------------------------------------------------
if [ -d "$TARGET_DIR/.git" ]; then
  echo "🔁 仓库已存在，执行 git pull..."
  git -C "$TARGET_DIR" pull --ff-only || echo "⚠️ Git pull failed"
else
  echo "📥 Clone 仓库..."
  git clone "$REPO" "$TARGET_DIR"
  chmod +x "$TARGET_DIR/webui.sh"
fi

# ---------------------------------------------------
# requirements_versions.txt 修复
# ---------------------------------------------------
echo "🔧 [5] 补丁修正 requirements_versions.txt..."
REQ_FILE="$TARGET_DIR/requirements_versions.txt"
touch "$REQ_FILE"

# 添加或替换某个依赖版本
add_or_replace_requirement() {
  local package="$1"
  local version="$2"
  if grep -q "^$package==" "$REQ_FILE"; then
    echo "🔁 替换: $package==... → $package==$version"
    sed -i "s|^$package==.*|$package==$version|" "$REQ_FILE"
  else
    echo "➕ 追加: $package==$version"
    echo "$package==$version" >> "$REQ_FILE"
  fi
}

# 推荐依赖版本（将统一写入或替换）
add_or_replace_requirement "xformers" "0.0.29.post3"
add_or_replace_requirement "diffusers" "0.31.0"
add_or_replace_requirement "transformers" "4.46.1"
add_or_replace_requirement "torchdiffeq" "0.2.3"
add_or_replace_requirement "torchsde" "0.2.6"
add_or_replace_requirement "protobuf" "4.25.3"
add_or_replace_requirement "pydantic" "2.6.4"
add_or_replace_requirement "open-clip-torch" "2.24.0"
add_or_replace_requirement "GitPython" "3.1.41"

# 🧹 清理注释和空行，保持纯净格式
echo "🧹 清理注释内容..."
CLEANED_REQ_FILE="${REQ_FILE}.cleaned"
sed 's/#.*//' "$REQ_FILE" | sed '/^\s*$/d' > "$CLEANED_REQ_FILE"
mv "$CLEANED_REQ_FILE" "$REQ_FILE"

# ✅ 输出最终依赖列表
echo "📄 最终依赖列表如下："
cat "$REQ_FILE"

# 输出最终依赖列表
echo "📦 最终依赖列表如下："
grep -E '^(xformers|diffusers|transformers|torchdiffeq|torchsde|GitPython|protobuf|pydantic|open-clip-torch)=' "$REQ_FILE" | sort

# ---------------------------------------------------
# Python 虚拟环境
# ---------------------------------------------------
cd "$TARGET_DIR"
chmod -R 777 .

echo "🐍 [6] 虚拟环境检查..."
if [ ! -x "venv/bin/activate" ]; then
  echo "📦 创建 venv..."
  python3 -m venv venv
fi

# 激活虚拟环境
source venv/bin/activate

echo "📥 升级 pip..."
pip install --upgrade pip | tee -a "$LOG_FILE"

echo "📥 安装主依赖 requirements_versions.txt ..."
DEPENDENCIES_INFO_URL="https://raw.githubusercontent.com/amDosion/SD-webui-forge/main/dependencies_info.json"
DEPENDENCIES_INFO=$(curl -s "$DEPENDENCIES_INFO_URL")

while IFS= read -r line || [[ -n "$line" ]]; do
  # 清洗注释和空行
  line=$(echo "$line" | sed 's/#.*//' | xargs)
  [[ -z "$line" ]] && continue

  # 提取包名与版本
  if [[ "$line" == *"=="* ]]; then
    package_name=$(echo "$line" | cut -d'=' -f1)
    package_version=$(echo "$line" | cut -d'=' -f3)
  else
    package_name="$line"
    package_version="最新"
  fi

  # 获取描述信息
  description=$(echo "$DEPENDENCIES_INFO" | jq -r --arg pkg "$package_name" '.[$pkg].description // empty')

  echo "📦 安装 ${package_name}==${package_version}"
  [[ -n "$description" ]] && echo "📘 说明: $description" || echo "📘 说明: 无（未记录）"

  # ✅ 安装并美化成功信息输出
  pip install "${package_name}==${package_version}" --extra-index-url "$PIP_EXTRA_INDEX_URL" 2>&1 \
    | tee -a "$LOG_FILE" \
    | sed 's/^Successfully installed/✅ 成功安装/'
done < "$REQ_FILE"

echo "📥 安装额外依赖 numpy, scikit-image, gdown 等..."
pip install numpy==1.25.2 scikit-image==0.21.0 gdown insightface onnx onnxruntime \
  | tee -a "$LOG_FILE"

# 修复 torchvision 安装失败的问题
pip install --pre torchvision==0.22.0.dev20250326+cu128 --index-url "$PIP_EXTRA_INDEX_URL" | tee -a "$LOG_FILE"

# 安装 huggingface-cli 工具
pip install --upgrade "huggingface_hub[cli]" | tee -a "$LOG_FILE"

if [[ "$ENABLE_DOWNLOAD_TRANSFORMERS" == "true" ]]; then
  echo "📥 安装 transformers 相关组件（transformers, accelerate, diffusers）..."
  pip install transformers accelerate diffusers | tee -a "$LOG_FILE"
fi

# ---------------------------------------------------
# 安装 TensorFlow
# ---------------------------------------------------
echo "🔍 正在检测 CPU 支持情况..."

CPU_VENDOR=$(grep -m 1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
AVX2_SUPPORTED=$(grep -m 1 avx2 /proc/cpuinfo || true)

echo "🧠 检测到 CPU: ${CPU_VENDOR}"

if [[ -n "$AVX2_SUPPORTED" ]]; then
  echo "✅ 检测到 AVX2 指令集"

  echo "🔍 检测并安装 TensorFlow（GPU 优先）..."
  pip uninstall -y tensorflow tensorflow-cpu || true

  if command -v nvidia-smi &>/dev/null; then
    echo "🧠 检测到 GPU，尝试安装 TensorFlow GPU 版本（支持 Python 3.11）"
    pip install tensorflow==2.19.0 | tee -a "$LOG_FILE"

    # 输出详细的GPU信息
    echo "🔧 获取 GPU 详细信息..."
    nvidia-smi | tee -a "$LOG_FILE"
    
  else
    echo "🧠 未检测到 GPU，安装 tensorflow-cpu==2.19.0（兼容 Python 3.11）"
    pip install tensorflow-cpu==2.19.0 | tee -a "$LOG_FILE"
  fi

  echo "🧪 验证 TensorFlow 是否识别 GPU："
  python3 -c "import tensorflow as tf; gpus=tf.config.list_physical_devices('GPU'); 
    if gpus: 
        print('✅ 可用 GPU:', gpus); 
    else: 
        print('⚠️ 没有检测到可用的 GPU'); 
    exit(0)" || echo "⚠️ TensorFlow 未能识别 GPU，请确认驱动与 CUDA 库完整"

else
  echo "⚠️ 未检测到 AVX2 → fallback 到 tensorflow-cpu==2.19.0"
  pip install tensorflow-cpu==2.19.0
fi


deactivate

# ---------------------------------------------------
# 安装完成日志
# ---------------------------------------------------
echo "📦 venv 安装完成 ✅"

# ---------------------------------------------------
# 创建目录
# ---------------------------------------------------
echo "📁 [7] 初始化项目目录结构..."
mkdir -p extensions models models/ControlNet outputs

# ---------------------------------------------------
# 网络测试
# ---------------------------------------------------
echo "🌐 [8] 网络连通性测试..."
if curl -s --connect-timeout 3 https://www.google.com > /dev/null; then
  NET_OK=true
  echo "✅ 网络连通 (Google 可访问)"
else
  NET_OK=false
  echo "⚠️ 无法访问 Google，部分资源或插件可能无法下载"
fi

# ---------------------------------------------------
# 插件黑名单
# ---------------------------------------------------
SKIP_LIST=(
  "extensions/stable-diffusion-aws-extension"
  "extensions/sd_dreambooth_extension"
  "extensions/stable-diffusion-webui-aesthetic-image-scorer"
)

should_skip() {
  local dir="$1"
  for skip in "${SKIP_LIST[@]}"; do
    [[ "$dir" == "$skip" ]] && return 0
  done
  return 1
}

# ---------------------------------------------------
# 下载资源
# ---------------------------------------------------
echo "📦 [9] 加载资源资源列表..."
RESOURCE_PATH="/app/webui/resources.txt"
mkdir -p /app/webui

if [ ! -f "$RESOURCE_PATH" ]; then
  echo "📥 下载默认 resources.txt..."
  curl -fsSL -o "$RESOURCE_PATH" https://raw.githubusercontent.com/chuan1127/SD-webui-forge/main/resources.txt
else
  echo "✅ 使用本地 resources.txt"
fi

clone_or_update_repo() {
  local dir="$1"; local repo="$2"
  if [ -d "$dir/.git" ]; then
    echo "🔁 更新 $dir"
    git -C "$dir" pull --ff-only || echo "⚠️ Git update failed: $dir"
  elif [ ! -d "$dir" ]; then
    echo "📥 克隆 $repo → $dir"
    git clone --depth=1 "$repo" "$dir"
  fi
}

download_with_progress() {
  local output="$1"; local url="$2"
  if [ ! -f "$output" ]; then
    echo "⬇️ 下载: $output"
    mkdir -p "$(dirname "$output")"
    wget --show-progress -O "$output" "$url"
  else
    echo "✅ 已存在: $output"
  fi
}

while IFS=, read -r dir url; do
  [[ "$dir" =~ ^#.*$ || -z "$dir" ]] && continue
  if should_skip "$dir"; then
    echo "⛔ 跳过黑名单插件: $dir"
    continue
  fi
  case "$dir" in
    extensions/*)
      [[ "$ENABLE_DOWNLOAD_EXTS" == "true" ]] && clone_or_update_repo "$dir" "$url"
      ;;
    models/ControlNet/*)
      [[ "$ENABLE_DOWNLOAD_CONTROLNET" == "true" && "$NET_OK" == "true" ]] && download_with_progress "$dir" "$url"
      ;;
    models/VAE/*)
      [[ "$ENABLE_DOWNLOAD_VAE" == "true" && "$NET_OK" == "true" ]] && download_with_progress "$dir" "$url"
      ;;
    models/text_encoder/*)
      [[ "$ENABLE_DOWNLOAD_TEXT_ENCODERS" == "true" && "$NET_OK" == "true" ]] && download_with_progress "$dir" "$url"
      ;;
    models/*)
      [[ "$ENABLE_DOWNLOAD_MODELS" == "true" && "$NET_OK" == "true" ]] && download_with_progress "$dir" "$url"
      ;;
    *)
      echo "❓ 未识别资源类型: $dir"
      ;;
  esac
done < "$RESOURCE_PATH"

# ---------------------------------------------------
# 权限令牌
# ---------------------------------------------------
echo "🔐 [10] 权限登录检查..."
if [[ -n "$HUGGINGFACE_TOKEN" ]]; then
  echo "$HUGGINGFACE_TOKEN" | huggingface-cli login --token || echo "⚠️ HuggingFace 登录失败"
fi

if [[ -n "$CIVITAI_API_TOKEN" ]]; then
  echo "🔐 CIVITAI_API_TOKEN 读取成功，长度：${#CIVITAI_API_TOKEN}"
fi


# ---------------------------------------------------
# 🔥 启动最终服务（FIXED!）
# ---------------------------------------------------
echo "🚀 [11] 所有准备就绪，启动 webui.sh ..."

exec bash webui.sh -f $ARGS
