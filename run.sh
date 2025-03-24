#!/bin/bash

set -e
set -o pipefail

# 日志输出
LOG_FILE="/app/webui/launch.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "🚀 [0] 启动脚本 Stable Diffusion WebUI"
echo "=================================================="

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
export PIP_EXTRA_INDEX_URL="https://download.pytorch.org/whl/cu126"

# ---------------------------------------------------
# 仓库路径配置
# ---------------------------------------------------
echo "🔧 [3] 设置仓库路径与 Git 源..."
if [ "$UI" = "auto" ]; then
  TARGET_DIR="/app/webui/sd-webui"
  REPO="https://github.com/AUTOMATIC1111/stable-diffusion-webui.git"
elif [ "$UI" = "forge" ]; then
  TARGET_DIR="/app/webui/sd-webui-forge"
  REPO="https://github.com/amDosion/stable-diffusion-webui-forge-cuda126.git"
else
  echo "❌ Unknown UI: $UI"
  exit 1
fi
echo "📁 目标目录: $TARGET_DIR"
echo "🌐 GIT 源: $REPO"

# ---------------------------------------------------
# 克隆仓库或拉取更新
# ---------------------------------------------------
if [ -d "$TARGET_DIR/.git" ]; then
  echo "🔁 [4] 仓库已存在，执行 git pull..."
  git -C "$TARGET_DIR" pull --ff-only || echo "⚠️ Git pull failed"
else
  echo "📥 [4] Clone 仓库..."
  git clone "$REPO" "$TARGET_DIR"
  chmod +x "$TARGET_DIR/webui.sh"
fi

# ---------------------------------------------------
# 依赖修复 patch：requirements_versions.txt
# ---------------------------------------------------
echo "🔧 [5] 补丁修正 requirements_versions.txt..."

REQ_FILE="$TARGET_DIR/requirements_versions.txt"
touch "$REQ_FILE"

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

add_or_replace_requirement "torch" "2.6.0"
add_or_replace_requirement "xformers" "0.0.29.post2"
add_or_replace_requirement "diffusers" "0.31.0"
add_or_replace_requirement "transformers" "4.46.1"
add_or_replace_requirement "torchdiffeq" "0.2.3"
add_or_replace_requirement "torchsde" "0.2.6"

echo "📦 完整依赖列表如下："
grep -E '^(torch|xformers|diffusers|transformers|torchdiffeq|torchsde)=' "$REQ_FILE"

# ---------------------------------------------------
# Python 虚拟环境
# ---------------------------------------------------
cd "$TARGET_DIR"
chmod -R 777 .

echo "🐍 [6] 虚拟环境检查..."
if [ ! -x "venv/bin/activate" ]; then
  echo "📦 创建 venv..."
  python3 -m venv venv
  source venv/bin/activate
  pip install --upgrade pip

  echo "📥 安装主依赖..."
  pip install -r requirements_versions.txt --extra-index-url "$PIP_EXTRA_INDEX_URL"

  echo "📥 安装额外依赖..."
  pip install numpy==1.25.2 scikit-image==0.21.0 gdown insightface onnx onnxruntime

  if [[ "$ENABLE_DOWNLOAD_TRANSFORMERS" == "true" ]]; then
    pip install transformers accelerate diffusers
  fi

  if grep -q avx2 /proc/cpuinfo; then
    echo "✅ 检测到 AVX2，安装 tensorflow-cpu-avx2..."
    pip uninstall -y tensorflow tensorflow-cpu || true
    pip install tensorflow-cpu-avx2==2.11.0
  else
    echo "⚠️ 无 AVX2，使用 fallback: tensorflow-cpu"
    pip install tensorflow-cpu==2.11.0
  fi

  deactivate
else
  echo "✅ venv 已存在，跳过安装"
fi

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
# 启动
# ---------------------------------------------------
echo "🚀 [11] 所有准备就绪，启动 webui.sh ..."
exec bash webui.sh -f $ARGS |& tee /app/webui/launch.log
