#!/bin/bash

echo "🚀 Starting Stable Diffusion WebUI..."

# 🔧 变量设置
UI="${UI:-forge}"
ARGS="${ARGS:---xformers --api --listen --enable-insecure-extension-access --theme dark}"

# 🌐 下载控制（支持细分）
ENABLE_DOWNLOAD_ALL="${ENABLE_DOWNLOAD:-true}"
ENABLE_DOWNLOAD_EXTS="${ENABLE_DOWNLOAD_EXTS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_MODELS="${ENABLE_DOWNLOAD_MODELS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_CONTROLNET="${ENABLE_DOWNLOAD_CONTROLNET:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_VAE="${ENABLE_DOWNLOAD_VAE:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_TEXT_ENCODERS="${ENABLE_DOWNLOAD_TEXT_ENCODERS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_TRANSFORMERS="${ENABLE_DOWNLOAD_TRANSFORMERS:-$ENABLE_DOWNLOAD_ALL}"

export NO_TCMALLOC=1

# ✅ WebUI 路径设置
if [ "$UI" = "auto" ]; then
  TARGET_DIR="/home/webui/sd-webui"
  REPO="https://github.com/AUTOMATIC1111/stable-diffusion-webui.git"
elif [ "$UI" = "forge" ]; then
  TARGET_DIR="/home/webui/sd-webui-forge"
  REPO="https://github.com/lllyasviel/stable-diffusion-webui-forge.git"
else
  echo "❌ Unknown UI: $UI"
  exit 1
fi

# ✅ 克隆或更新主项目
if [ -d "$TARGET_DIR/.git" ]; then
  echo "🔁 Updating Git repo: $TARGET_DIR"
  git -C "$TARGET_DIR" pull --ff-only || echo "⚠️ Git update failed"
elif [ ! -d "$TARGET_DIR" ] || [ -z "$(ls -A "$TARGET_DIR")" ]; then
  echo "📥 Cloning $UI WebUI..."
  git clone "$REPO" "$TARGET_DIR"
  chmod +x "$TARGET_DIR/webui.sh"
else
  echo "⚠️ $TARGET_DIR exists but not a Git repo. Skipping update."
fi

cd "$TARGET_DIR" || exit 1
chmod -R 777 .

# ✅ Python 虚拟环境
if [ ! -d "venv" ]; then
  echo "🐍 Creating Python venv..."
  python3 -m venv venv
  source venv/bin/activate

  pip install --upgrade pip
  pip install numpy==1.25.2 scikit-image==0.21.0 gdown xformers insightface onnx onnxruntime

  if [[ "$ENABLE_DOWNLOAD_TRANSFORMERS" == "true" ]]; then
    pip install transformers accelerate diffusers
  fi

  if grep -q avx2 /proc/cpuinfo; then
    echo "✅ AVX2 supported → Installing tensorflow-cpu-avx2"
    pip uninstall -y tensorflow tensorflow-cpu || true
    pip install --no-cache-dir tensorflow-cpu-avx2==2.11.0
  else
    echo "⚠️ AVX2 not found → Installing fallback tensorflow-cpu"
    pip install --no-cache-dir tensorflow-cpu==2.11.0
  fi

  deactivate
else
  echo "✅ Python venv already exists"
fi

# ✅ 创建必要目录
mkdir -p extensions \
  models/Stable-diffusion/SD1.5 \
  models/Stable-diffusion/flux \
  models/Stable-diffusion/XL \
  models/ControlNet \
  models/VAE \
  models/text_encoder \
  outputs

# ✅ 下载函数
clone_or_update_repo() {
  local dir="$1"; local repo="$2"
  if [ -d "$dir/.git" ]; then
    echo "🔄 Updating: $dir"
    git -C "$dir" pull --ff-only || echo "⚠️ Failed to update $dir"
  elif [ -d "$dir" ]; then
    echo "✅ $dir exists (non-git), skipping"
  else
    echo "📥 Cloning: $repo → $dir"
    git clone --depth=1 "$repo" "$dir"
  fi
}

download_with_progress() {
  local output="$1"; local url="$2"
  if [ ! -f "$output" ]; then
    echo "⬇️  Downloading: $output"
    mkdir -p "$(dirname "$output")"
    wget --progress=bar:force:noscroll -O "$output" "$url"
  else
    echo "✅ Already exists: $output"
  fi
}

# ✅ 网络检查
if curl -s --connect-timeout 3 https://www.google.com > /dev/null; then
  echo "🌐 Google is reachable"
  NET_OK=true
else
  echo "⚠️ Google unreachable → skipping downloads"
  NET_OK=false
fi

# ✅ 黑名单插件
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

# ✅ 拉取 remote resources.txt
RESOURCE_URL="https://raw.githubusercontent.com/chuan1127/SD-webui-forge/main/resources.txt"
RESOURCE_FILE="$TARGET_DIR/resources.txt"

echo "📥 Downloading resources.txt from: $RESOURCE_URL"
curl -fsSL "$RESOURCE_URL" -o "$RESOURCE_FILE" || echo "⚠️ Failed to download resources.txt"

# ✅ 处理资源
if [ -f "$RESOURCE_FILE" ]; then
  echo "📚 Processing resources.txt..."

  while IFS=, read -r dir url; do
    [[ "$dir" =~ ^#.*$ || -z "$dir" ]] && continue
    if should_skip "$dir"; then
      echo "⛔ Skipping incompatible: $dir"
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
      models/Stable-diffusion/*)
        [[ "$ENABLE_DOWNLOAD_MODELS" == "true" && "$NET_OK" == "true" ]] && download_with_progress "$dir" "$url"
        ;;
      *)
        echo "❓ Unknown resource type: $dir"
        ;;
    esac
  done < "$RESOURCE_FILE"
else
  echo "⚠️ No resources.txt found after attempted download"
fi

# ✅ HuggingFace 登录
if [[ -n "$HUGGINGFACE_TOKEN" ]]; then
  echo "$HUGGINGFACE_TOKEN" | huggingface-cli login --token || echo "⚠️ HuggingFace login failed"
else
  echo "ℹ️ No HUGGINGFACE_TOKEN provided"
fi

# ✅ CIVITAI Token 提示
if [[ -n "$CIVITAI_API_TOKEN" ]]; then
  echo "🔐 CIVITAI_API_TOKEN detected (length: ${#CIVITAI_API_TOKEN})"
else
  echo "ℹ️ No CIVITAI_API_TOKEN provided"
fi

# ✅ 启动 WebUI
echo "🚀 Launching WebUI with args: $ARGS"
exec bash webui.sh -f $ARGS
