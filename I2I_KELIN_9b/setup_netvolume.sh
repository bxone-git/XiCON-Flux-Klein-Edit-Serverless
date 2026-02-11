#!/bin/bash
set -e

NETVOLUME="/runpod-volume"

echo "=========================================="
echo "Flux 2 Klein Image Edit - Network Volume Setup"
echo "Network Volume: XiCON"
echo "=========================================="

if [ ! -d "$NETVOLUME" ]; then
    echo "ERROR: Network Volume not found at $NETVOLUME"
    echo "Please attach network volume 'XiCON' with mount path /runpod-volume"
    exit 1
fi

# Create directory structure
echo "Creating directory structure..."
mkdir -p $NETVOLUME/models/diffusion_models
mkdir -p $NETVOLUME/models/text_encoders
mkdir -p $NETVOLUME/models/vae

# [1/3] Klein model (GATED - requires HF auth)
echo ""
echo "[1/3] Klein model (~9GB) - GATED MODEL"
if [ ! -f "$NETVOLUME/models/diffusion_models/flux-2-klein-9b-fp8.safetensors" ]; then
    echo "Downloading Klein model..."
    echo "NOTE: Requires HuggingFace authentication. Run 'huggingface-cli login' first."
    huggingface-cli download \
        black-forest-labs/FLUX.2-klein-base-9b-fp8 \
        flux-2-klein-9b-fp8.safetensors \
        --local-dir "$NETVOLUME/models/diffusion_models" \
        --local-dir-use-symlinks False
    echo "Klein model downloaded!"
else
    echo "[SKIP] Klein model already exists"
fi

# [2/3] Text Encoder (public URL)
echo ""
echo "[2/3] Text Encoder model (~8GB)"
if [ ! -f "$NETVOLUME/models/text_encoders/qwen_3_8b_fp8mixed.safetensors" ]; then
    echo "Downloading Text Encoder model..."
    wget -q --show-progress \
        "https://huggingface.co/Comfy-Org/vae-text-encorder-for-flux-klein-9b/resolve/main/split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors" \
        -O "$NETVOLUME/models/text_encoders/qwen_3_8b_fp8mixed.safetensors"
    echo "Text Encoder model downloaded!"
else
    echo "[SKIP] Text Encoder model already exists"
fi

# [3/3] VAE (public URL)
echo ""
echo "[3/3] VAE model (~300MB)"
if [ ! -f "$NETVOLUME/models/vae/flux2-vae.safetensors" ]; then
    echo "Downloading VAE model..."
    wget -q --show-progress \
        "https://huggingface.co/Comfy-Org/vae-text-encorder-for-flux-klein-9b/resolve/main/split_files/vae/flux2-vae.safetensors" \
        -O "$NETVOLUME/models/vae/flux2-vae.safetensors"
    echo "VAE model downloaded!"
else
    echo "[SKIP] VAE model already exists"
fi

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Model sizes:"
du -sh $NETVOLUME/models/diffusion_models 2>/dev/null || echo "  diffusion_models: (pending)"
du -sh $NETVOLUME/models/text_encoders 2>/dev/null || echo "  text_encoders: (pending)"
du -sh $NETVOLUME/models/vae 2>/dev/null || echo "  vae: (pending)"
echo ""
echo "Total:"
du -sh $NETVOLUME/models
