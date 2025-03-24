#!/bin/bash

echo "🚀 Starting Stable Diffusion WebUI..."

UI="${UI:-forge}"
ARGS="${ARGS:---xformers --api --listen --enable-insecure-extension-access --theme dark}"

# 🌐 下载控制细分
ENABLE_DOWNLOAD_ALL="${ENABLE_DOWNLOAD:-true}"
ENABLE_DOWNLOAD_MODELS="${ENABLE_DOWNLOAD_MODELS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_EXTS="${ENABLE_DOWNLOAD_EXTS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_CONTROLNET="${ENABLE_DOWNLOAD_CONTROLNET:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_VAE="${ENABLE_DOWNLOAD_VAE:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_TEXT_ENCODERS="${ENABLE_DOWNLOAD_TEXT_ENCODERS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_TRANSFORMERS="${ENABLE_DOWNLOAD_TRANSFORMERS:-$ENABLE_DOWNLOAD_ALL}"

export NO_TCMALLOC=1

# ✅ WebUI clone 设置
if [ "$UI" = "auto" ]; then
  TARGET_DIR="/app/webui/sd-webui"
  REPO="https://github.com/AUTOMATIC1111/stable-diffusion-webui.git"
elif [ "$UI" = "forge" ]; then
  TARGET_DIR="/app/webui/sd-webui-forge"
  REPO="https://github.com/lllyasviel/stable-diffusion-webui-forge.git"
else
  echo "❌ Unknown UI: $UI"
  exit 1
fi

# ✅ 克隆或更新主项目
if [ -d "$TARGET_DIR/.git" ]; then
  echo "🔁 Updating repo..."
  git -C "$TARGET_DIR" pull --ff-only
elif [ ! -d "$TARGET_DIR" ]; then
  echo "📥 Cloning WebUI → $TARGET_DIR"
  git clone "$REPO" "$TARGET_DIR"
  chmod +x "$TARGET_DIR/webui.sh"

  echo "🔧 Patching requirements_versions.txt for PyTorch 2.6.0 compatibility..."
  REQ_FILE="$TARGET_DIR/requirements_versions.txt"
  touch "$REQ_FILE"

  sed -i '/^torch/d' "$REQ_FILE"
  echo "torch==2.6.0" >> "$REQ_FILE"

  sed -i '/^xformers/d' "$REQ_FILE"
  echo "xformers==0.0.25" >> "$REQ_FILE"

  sed -i '/^diffusers/d' "$REQ_FILE"
  echo "diffusers==0.31.0" >> "$REQ_FILE"

  sed -i '/^transformers/d' "$REQ_FILE"
  echo "transformers==4.46.1" >> "$REQ_FILE"

  echo "✅ Patched dependencies:"
  grep -E 'torch|xformers|diffusers|transformers' "$REQ_FILE"
fi

cd "$TARGET_DIR" || exit 1
chmod -R 777 .

# ✅ Python venv
if [ ! -d "venv" ]; then
  echo "🐍 Creating venv..."
  python3 -m venv venv
  source venv/bin/activate
  pip install --upgrade pip
  pip install numpy==1.25.2 scikit-image==0.21.0 gdown insightface onnx onnxruntime

  if [[ "$ENABLE_DOWNLOAD_TRANSFORMERS" == "true" ]]; then
    pip install transformers accelerate diffusers
  fi

  if grep -q avx2 /proc/cpuinfo; then
    echo "✅ AVX2 supported → installing tensorflow-cpu-avx2"
    pip uninstall -y tensorflow tensorflow-cpu || true
    pip install tensorflow-cpu-avx2==2.11.0
  else
    echo "⚠️ No AVX2 → fallback to tensorflow-cpu"
    pip install tensorflow-cpu==2.11.0
  fi

  deactivate
else
  echo "✅ venv already exists"
fi

# ✅ 创建目录
mkdir -p extensions models models/ControlNet outputs

# ✅ 网络检测
if curl -s --connect-timeout 3 https://www.google.com > /dev/null; then
  NET_OK=true
  echo "🌐 Internet OK"
else
  NET_OK=false
  echo "⚠️ Cannot reach Google"
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

# ✅ 资源文件处理
RESOURCE_PATH="/app/webui/resources.txt"
mkdir -p /app/webui

if [ ! -f "$RESOURCE_PATH" ]; then
  echo "📥 Downloading default resources.txt..."
  curl -fsSL -o "$RESOURCE_PATH" https://raw.githubusercontent.com/chuan1127/SD-webui-forge/main/resources.txt
else
  echo "✅ Using existing or mapped resources.txt"
fi

# ✅ 下载函数
clone_or_update_repo() {
  local dir="$1"; local repo="$2"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" pull --ff-only || echo "⚠️ Failed to update $dir"
  elif [ ! -d "$dir" ]; then
    echo "📥 Cloning $repo → $dir"
    git clone --depth=1 "$repo" "$dir"
  fi
}

download_with_progress() {
  local output="$1"; local url="$2"
  if [ ! -f "$output" ]; then
    echo "⬇️  Downloading $output"
    mkdir -p "$(dirname "$output")"
    wget --show-progress -O "$output" "$url"
  else
    echo "✅ Already exists: $output"
  fi
}

# ✅ 下载资源
while IFS=, read -r dir url; do
  [[ "$dir" =~ ^#.*$ || -z "$dir" ]] && continue

  if should_skip "$dir"; then
    echo "⛔ Skipping blacklisted plugin: $dir"
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
      echo "❓ Unknown resource type: $dir"
      ;;
  esac
done < "$RESOURCE_PATH"

# ✅ HuggingFace 登录
if [[ -n "$HUGGINGFACE_TOKEN" ]]; then
  echo "$HUGGINGFACE_TOKEN" | huggingface-cli login --token || echo "⚠️ HuggingFace login failed"
fi

# ✅ CIVITAI token 显示
if [[ -n "$CIVITAI_API_TOKEN" ]]; then
  echo "🔐 CIVITAI_API_TOKEN: length ${#CIVITAI_API_TOKEN}"
fi

# ✅ 启动 WebUI（以非 root 身份）
echo "🚀 WebUI Ready, switching to user 'webui'..."
exec bash webui.sh -f $ARGS
