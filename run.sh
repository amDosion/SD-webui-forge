#!/bin/bash
echo "🚀 Starting Stable Diffusion WebUI..."

UI="${UI:-forge}"
ARGS="${ARGS:---xformers --api --listen --enable-insecure-extension-access --theme dark}"

# 可细分控制
ENABLE_DOWNLOAD_ALL="${ENABLE_DOWNLOAD:-true}"
ENABLE_DOWNLOAD_EXTS="${ENABLE_DOWNLOAD_EXTS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_MODELS="${ENABLE_DOWNLOAD_MODELS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_TRANSFORMERS="${ENABLE_DOWNLOAD_TRANSFORMERS:-$ENABLE_DOWNLOAD_ALL}"

export NO_TCMALLOC=1

# ✅ 安装 ffmpeg（仅容器首次运行时）
if [ ! -x /usr/local/bin/ffmpeg ]; then
  echo "📦 ffmpeg not found, installing bundled version..."
  cp /app/ffmpeg /usr/local/bin/ffmpeg
  chmod +x /usr/local/bin/ffmpeg
else
  echo "✅ ffmpeg already exists: $(/usr/local/bin/ffmpeg -version | head -n 1)"
fi

# ✅ 设置 WebUI 目标目录
if [ "$UI" = "auto" ]; then
  TARGET_DIR="/app/sd-webui"
  REPO="https://github.com/AUTOMATIC1111/stable-diffusion-webui.git"
elif [ "$UI" = "forge" ]; then
  TARGET_DIR="/app/sd-webui-forge"
  REPO="https://github.com/lllyasviel/stable-diffusion-webui-forge.git"
else
  echo "❌ Unknown UI: $UI"
  exit 1
fi

# ✅ 克隆主项目
if [ ! -d "$TARGET_DIR/.git" ]; then
  echo "📥 Cloning $UI WebUI..."
  git clone "$REPO" "$TARGET_DIR"
  chmod +x "$TARGET_DIR/webui.sh"
else
  echo "🔁 Updating Git repo..."
  git -C "$TARGET_DIR" pull --ff-only
fi

cd "$TARGET_DIR" || exit 1
chmod -R 777 .

# ✅ Python 虚拟环境安装
if [ ! -d "venv" ]; then
  echo "🐍 Creating Python venv..."
  python3 -m venv venv
  source venv/bin/activate

  pip install --upgrade pip
  pip install numpy==1.25.2 scikit-image==0.21.0 xformers gdown onnx onnxruntime insightface

  if [[ "$ENABLE_DOWNLOAD_TRANSFORMERS" == "true" ]]; then
    pip install transformers accelerate diffusers
  fi

  if grep -q avx2 /proc/cpuinfo; then
    pip uninstall -y tensorflow tensorflow-cpu || true
    pip install --no-cache-dir tensorflow-cpu-avx2==2.11.0
  else
    pip install --no-cache-dir tensorflow-cpu==2.11.0
  fi

  deactivate
else
  echo "✅ Python venv already exists"
fi

# ✅ 下载工具函数
clone_or_update_repo() {
  local dir="$1"
  local repo="$2"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" pull --ff-only || echo "⚠️ Failed to update $dir"
  elif [ -d "$dir" ]; then
    echo "✅ $dir exists (non-git), skipping"
  else
    echo "📥 Cloning: $repo → $dir"
    git clone --depth=1 "$repo" "$dir"
  fi
}

download_with_progress() {
  local output="$1"
  local url="$2"
  if [ ! -f "$output" ]; then
    echo "⬇️  Downloading: $output"
    mkdir -p "$(dirname "$output")"
    wget --show-progress -O "$output" "$url"
  else
    echo "✅ Already exists: $output"
  fi
}

# ✅ 检查网络
if curl -s --connect-timeout 3 https://www.google.com > /dev/null; then
  NET_OK=true
else
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

# ✅ 读取资源配置
echo "📚 Loading resources.txt..."
cp /app/resources.txt "$TARGET_DIR/resources.txt"

if [ -f "$TARGET_DIR/resources.txt" ]; then
  while IFS=, read -r dir url; do
    [[ "$dir" =~ ^#.*$ || -z "$dir" ]] && continue

    if should_skip "$dir"; then
      echo "⛔ Skipping: $dir"
      continue
    fi

    if [[ "$dir" == extensions/* && "$ENABLE_DOWNLOAD_EXTS" == "true" ]]; then
      clone_or_update_repo "$dir" "$url"
    elif [[ "$dir" == models/* && "$ENABLE_DOWNLOAD_MODELS" == "true" && "$NET_OK" == "true" ]]; then
      download_with_progress "$dir" "$url"
    else
      echo "⏭️  Skipping resource: $dir"
    fi
  done < "$TARGET_DIR/resources.txt"
fi

# ✅ HuggingFace 登录
if [[ -n "$HUGGINGFACE_TOKEN" ]]; then
  echo "$HUGGINGFACE_TOKEN" | huggingface-cli login --token || echo "⚠️ HuggingFace login failed"
fi

# ✅ Civitai 提示
if [[ -n "$CIVITAI_API_TOKEN" ]]; then
  echo "🔐 Civitai API Token Detected (length: ${#CIVITAI_API_TOKEN})"
fi

# ✅ 启动 WebUI
echo "🚀 Launching WebUI with args: $ARGS"
exec bash webui.sh -f $ARGS
