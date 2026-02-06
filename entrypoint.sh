#!/bin/bash
# NEVER use set -e: handler must start for worker to register as ready

echo "=========================================="
echo "Flux 2 Klein Image Edit - Container startup - $(date)"
echo "=========================================="

# Network Volume Setup
NETVOLUME="${NETWORK_VOLUME_PATH:-/runpod-volume}"

echo "Checking Network Volume at $NETVOLUME..."
if [ ! -d "$NETVOLUME" ]; then
    echo "WARNING: Network Volume not found at $NETVOLUME"
    echo "Handler will start but jobs will fail without models"
fi

# Create symlinks (only if volume exists)
if [ -d "$NETVOLUME/models" ]; then
    echo "Creating symlinks..."
    rm -rf /ComfyUI/models/diffusion_models
    rm -rf /ComfyUI/models/text_encoders
    rm -rf /ComfyUI/models/clip
    rm -rf /ComfyUI/models/vae

    ln -sf $NETVOLUME/models/diffusion_models /ComfyUI/models/diffusion_models
    ln -sf $NETVOLUME/models/text_encoders /ComfyUI/models/text_encoders
    ln -sf $NETVOLUME/models/text_encoders /ComfyUI/models/clip
    ln -sf $NETVOLUME/models/vae /ComfyUI/models/vae
    echo "Symlinks created!"
else
    echo "WARNING: $NETVOLUME/models not found, skipping symlinks"
fi

# Model verification (warnings only, never exit)
check_model() {
    local model_path="$1"
    local model_name="$2"

    if [ ! -f "$model_path" ]; then
        echo "  [MISSING] $model_name ($model_path)"
    else
        echo "  [OK] $model_name"
    fi
}

echo "Verifying models..."
check_model "$NETVOLUME/models/diffusion_models/flux-2-klein-9b-fp8.safetensors" "Flux 2 Klein 9B FP8"
check_model "$NETVOLUME/models/text_encoders/qwen_3_8b_fp8mixed.safetensors" "Qwen 3.8B CLIP"
check_model "$NETVOLUME/models/vae/flux2-vae.safetensors" "Flux2 VAE"

# GPU Detection
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "Unknown")
echo "Detected GPU: $GPU_NAME"

# Start ComfyUI
echo "Starting ComfyUI..."
python /ComfyUI/main.py --listen &

# Wait for ComfyUI
echo "Waiting for ComfyUI..."
max_wait=180
wait_count=0
while [ $wait_count -lt $max_wait ]; do
    if curl -s http://127.0.0.1:8188/ > /dev/null 2>&1; then
        echo "ComfyUI is ready!"
        break
    fi
    sleep 2
    wait_count=$((wait_count + 2))
done

if [ $wait_count -ge $max_wait ]; then
    echo "WARNING: ComfyUI failed to start within timeout, starting handler anyway"
fi

# CRITICAL: Handler MUST start for worker to register as ready
echo "Starting handler..."
exec python handler.py
