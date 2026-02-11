# Flux2 Klein 9B Workflow Documentation

> AI-powered image editing workflow using the Flux2 Klein 9B model for promotional image generation

## Overview

**Template Name**: `XiCON_KLEIN_Poster_Maker_v1` (Database ID)
**Workflow Name**: `flux2-klein` (Flux2 Klein 9B model)
**Work Type**: `promotional_image`
**Model**: Flux2 Klein 9B FP8 (9 billion parameters, FP8 quantization)
**GPU Requirement**: RTX 5090
**Estimated Time**: 30 seconds

Flux2 Klein is an image-to-image editing model that transforms input images based on text prompts. It generates high-quality edited images suitable for promotional and marketing content.

### Why `promotional_image` Work Type?

Flux2 Klein is categorized as `promotional_image` because:
- Outputs static images (not video)
- Primary use case is marketing and promotional content creation
- Follows the same UI flow as other promotional image templates
- Suitable for product images, social media content, and advertising materials

## Architecture

### Data Flow

```
┌──────────────┐
│   Frontend   │ User uploads image + prompt
└──────┬───────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────┐
│ Edge Function: /functions/works/generate                     │
│ - Validate credits                                           │
│ - Deduct credits (subscription first, then purchased)        │
│ - Create work record (status: pending)                       │
│ - INSERT generation_jobs (status: pending)                   │
│ - Return work_id immediately (Fire & Forget)                 │
└──────┬───────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────┐
│ generation_jobs Table (PostgreSQL Queue)                     │
│ - work_id, status: 'pending', priority, created_at           │
└──────┬───────────────────────────────────────────────────────┘
       │
       ▼ (n8n polling or DB webhook trigger)
┌──────────────────────────────────────────────────────────────┐
│ n8n Workflow Engine                                          │
│ 1. SELECT pending job (FOR UPDATE SKIP LOCKED)               │
│ 2. UPDATE job status to 'taken'                              │
│ 3. UPDATE work status to 'processing'                        │
│ 4. Check template_name = 'XiCON_KLEIN_Poster_Maker_v1'    │
│ 5. Extract input_data fields                                 │
└──────┬───────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────┐
│ RunPod Serverless Endpoint (ComfyUI)                         │
│ - Load workflow.json                                         │
│ - Map inputs to workflow nodes:                              │
│   • Node 76: Load reference image                            │
│   • Node 75:74: Apply text prompt                            │
│   • Node 75:73: Set random seed                              │
│ - Execute workflow (steps=4, cfg=1, sampler=euler)           │
│ - Return generated image                                     │
└──────┬───────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────┐
│ n8n Post-Processing                                          │
│ - Download generated image from ComfyUI                      │
│ - Upload to Supabase Storage (works bucket)                  │
│ - INSERT files table record                                  │
│ - UPDATE works (status: completed, file_id, output_data)     │
│ - DELETE generation_jobs record                              │
└──────┬───────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────┐
│ Database Triggers (Automatic)                                │
│ - trg_notify_work_status_change: Create notification         │
│ - If failed: trg_refund_credits_on_failure                   │
└──────┬───────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────┐
│ Supabase Realtime                                            │
│ - Push notification to client                                │
│ - Client updates UI with completed work                      │
└──────────────────────────────────────────────────────────────┘
```

## Template Configuration

### Database Record

The template is stored in the `templates` table:

| Field | Value |
|-------|-------|
| `template_name` | `XiCON_KLEIN_Poster_Maker_v1` |
| `work_type` | `promotional_image` |
| `title` | `Flux2 Klein 이미지 편집` |
| `description` | Flux2 Klein 9B 모델을 사용한 고품질 이미지 편집. 프롬프트 기반으로 이미지를 자연스럽게 수정합니다. |
| `estimated_time` | `30` (seconds) |
| `is_active` | `true` |
| `display_order` | `100` |

### Form Fields

The `form_fields` JSONB column defines the dynamic UI form:

#### 1. Reference Image (File Upload)

```json
{
  "type": "file",
  "name": "reference_image",
  "label": "참조 이미지",
  "request_key": "reference_image",
  "request_value_type": "string",
  "required": true,
  "accept": ".jpg,.png,.jpeg",
  "max_size": 20971520,
  "upload_label": "편집할 이미지를 업로드하세요",
  "upload_description": "JPG, PNG 파일 | 20MB 이하"
}
```

**Behavior**: User uploads image → Frontend uploads to Storage → URL stored in input_data

#### 2. Edit Prompt (Textarea)

```json
{
  "type": "textarea",
  "name": "prompt",
  "label": "편집 프롬프트",
  "request_key": "prompt",
  "request_value_type": "string",
  "required": true,
  "placeholder": "이미지를 어떻게 편집할지 설명하세요",
  "max_length": 500,
  "rows": 3
}
```

**Example**: "Replace the background with a quiet coastal cliff at overcast sunset"

#### 3. Random Seed (Number)

```json
{
  "type": "number",
  "name": "seed",
  "label": "랜덤 시드",
  "request_key": "seed",
  "request_value_type": "number",
  "required": false,
  "min": 0,
  "max": 9999999999999,
  "step": 1,
  "default_value": 432262096973502,
  "description": "같은 값 사용 시 동일한 결과 생성 (재현성)"
}
```

### Request DTO

The `request_dto` JSONB column defines API input validation:

```json
{
  "reference_image": "string",
  "prompt": "string",
  "seed": "number"
}
```

### API Request Example

**Endpoint**: `POST /functions/v1/works/generate`

```json
{
  "type": "promotional_image",
  "project_id": "uuid",
  "template_id": "uuid",
  "output_count": 1,
  "input_data": {
    "reference_image": "https://storage.supabase.co/.../reference.jpg",
    "prompt": "Replace the background with mountains at sunset",
    "seed": 432262096973502
  }
}
```

## ComfyUI Workflow Details

### Model Files

| Model Type | File | Size | Location |
|------------|------|------|----------|
| UNET (Diffusion) | `flux-2-klein-9b-fp8.safetensors` | ~9GB | `/workspace/runpod-slim/ComfyUI/models/unet/` |
| CLIP (Text Encoder) | `qwen_3_8b_fp8mixed.safetensors` | ~3GB | `/workspace/runpod-slim/ComfyUI/models/clip/` |
| VAE (Encoder/Decoder) | `flux2-vae.safetensors` | ~200MB | `/workspace/runpod-slim/ComfyUI/models/vae/` |

### Node Mapping

The workflow uses ComfyUI's node-based architecture. Input mapping:

| Input Field | Node ID | Node Type | Property |
|-------------|---------|-----------|----------|
| `reference_image` | `76` | LoadImage | `inputs.image` |
| `prompt` | `75:74` | CLIPTextEncode | `inputs.text` |
| `seed` | `75:73` | RandomNoise | `inputs.noise_seed` |

### Key Workflow Nodes

```
Node 76: LoadImage
  └─> Node 75:80: ImageScaleToTotalPixels (resize to 1MP)
      └─> Node 75:81: GetImageSize
          └─> Node 75:66: EmptyFlux2LatentImage (create latent)

Node 75:70: UNETLoader (flux-2-klein-9b-fp8.safetensors)
Node 75:71: CLIPLoader (qwen_3_8b_fp8mixed.safetensors)
Node 75:72: VAELoader (flux2-vae.safetensors)

Node 75:74: CLIPTextEncode (prompt → positive conditioning)
Node 75:82: ConditioningZeroOut (empty → negative conditioning)

Node 75:79:78: VAEEncode (reference image → latent)
Node 75:79:77: ReferenceLatent (positive + reference latent)
Node 75:79:76: ReferenceLatent (negative + reference latent)

Node 75:62: Flux2Scheduler (steps=4)
Node 75:61: KSamplerSelect (sampler=euler)
Node 75:63: CFGGuider (cfg=1)
Node 75:64: SamplerCustomAdvanced (main sampling)

Node 75:65: VAEDecode (latent → image)
Node 9: SaveImage (output)
```

### Generation Parameters

| Parameter | Value | Purpose |
|-----------|-------|---------|
| Steps | 4 | Inference steps (fast generation) |
| CFG Scale | 1 | Guidance strength (low = more creative) |
| Sampler | euler | Sampling method |
| Image Size | 1 megapixel | Automatically scaled from input |

## n8n Integration

### Workflow Detection

n8n detects Flux2 Klein jobs by checking the template_name:

```sql
SELECT
  gj.id,
  gj.work_id,
  w.input_data,
  t.template_name
FROM generation_jobs gj
JOIN works w ON gj.work_id = w.id
JOIN templates t ON w.template_id = t.id
WHERE gj.status = 'pending'
  AND t.template_name = 'XiCON_KLEIN_Poster_Maker_v1'
ORDER BY gj.priority DESC, gj.created_at ASC
LIMIT 1
FOR UPDATE SKIP LOCKED;
```

### Processing Steps

1. **Job Acquisition**
   ```sql
   UPDATE generation_jobs
   SET status = 'taken', updated_at = NOW()
   WHERE id = :job_id;
   ```

2. **Work Status Update**
   ```sql
   UPDATE works
   SET status = 'processing', updated_at = NOW()
   WHERE id = :work_id;
   ```

3. **Extract Input Data**
   ```javascript
   const input_data = work.input_data;
   const reference_image = input_data.reference_image;
   const prompt = input_data.prompt;
   const seed = input_data.seed || 432262096973502;
   ```

4. **Download Reference Image**
   ```javascript
   const imageBuffer = await axios.get(reference_image, {
     responseType: 'arraybuffer'
   });
   ```

5. **Prepare ComfyUI Workflow**
   ```javascript
   const workflow = JSON.parse(fs.readFileSync('workflow.json'));
   workflow['76'].inputs.image = 'reference_image.jpg';
   workflow['75:74'].inputs.text = prompt;
   workflow['75:73'].inputs.noise_seed = seed;
   ```

6. **Call RunPod Endpoint**
   ```javascript
   const response = await axios.post(
     process.env.RUNPOD_FLUX_KLEIN_ENDPOINT,
     {
       input: {
         workflow: workflow,
         images: {
           'reference_image.jpg': base64Image
         }
       }
     }
   );
   ```

7. **Upload Result to Storage**
   ```javascript
   const filePath = `${userId}/${workId}/output.png`;
   await supabase.storage
     .from('works')
     .upload(filePath, outputImage, {
       contentType: 'image/png',
       upsert: true
     });
   ```

8. **Update Work Record**
   ```sql
   UPDATE works
   SET
     status = 'completed',
     file_id = :file_id,
     output_data = jsonb_build_object(
       'model', 'flux-2-klein-9b-fp8',
       'steps', 4,
       'cfg', 1,
       'sampler', 'euler',
       'seed', :seed,
       'processing_time', :elapsed_time
     ),
     updated_at = NOW()
   WHERE id = :work_id;
   ```

9. **Cleanup**
   ```sql
   DELETE FROM generation_jobs WHERE id = :job_id;
   ```

### Error Handling

If any step fails:

1. n8n updates work status directly:
   ```sql
   UPDATE works
   SET
     status = 'failed',
     output_data = jsonb_build_object('error', :error_message),
     updated_at = NOW()
   WHERE id = :work_id;
   ```

2. Database trigger `trg_refund_credits_on_failure` automatically:
   - Refunds `subscription_credits_used` to `subscription_credits`
   - Refunds `purchased_credits_used` to `purchased_credits`
   - Creates `credit_transactions` record (type = 'refund')

3. Database trigger `trg_notify_work_status_change` automatically:
   - Creates notification with error message
   - Includes refunded credit amount

4. n8n deletes the generation_jobs record:
   ```sql
   DELETE FROM generation_jobs WHERE id = :job_id;
   ```

## Testing Procedures

### 1. Database Verification

```sql
-- Check template exists
SELECT id, template_name, work_type, is_active
FROM templates
WHERE template_name = 'XiCON_KLEIN_Poster_Maker_v1';

-- Verify form_fields structure
SELECT
  jsonb_array_length(form_fields) as field_count,
  form_fields
FROM templates
WHERE template_name = 'XiCON_KLEIN_Poster_Maker_v1';

-- Check request_dto
SELECT request_dto
FROM templates
WHERE template_name = 'XiCON_KLEIN_Poster_Maker_v1';
```

### 2. Frontend UI Test

1. Navigate to Promotional Image generation page
2. Select "Flux2 Klein 이미지 편집" template
3. Verify form displays:
   - File upload field (reference_image)
   - Textarea field (prompt)
   - Number field (seed)
4. Upload test image (< 20MB, JPG/PNG)
5. Enter test prompt
6. Set output_count = 1
7. Submit generation request

### 3. API Test (curl)

```bash
# Get auth token first
AUTH_TOKEN="your_supabase_auth_token"
PROJECT_ID="your_project_uuid"
TEMPLATE_ID="your_template_uuid"

# Submit generation request
curl -X POST "https://your-project.supabase.co/functions/v1/works/generate" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "promotional_image",
    "project_id": "'$PROJECT_ID'",
    "template_id": "'$TEMPLATE_ID'",
    "output_count": 1,
    "input_data": {
      "reference_image": "https://storage.supabase.co/.../test.jpg",
      "prompt": "Replace background with mountains at sunset",
      "seed": 12345
    }
  }'

# Response (immediate):
# {
#   "work_id": "uuid",
#   "status": "pending",
#   "estimated_time": 30
# }
```

### 4. Monitor Generation Progress

```sql
-- Check work status
SELECT id, status, created_at, updated_at
FROM works
WHERE id = :work_id;

-- Check job queue
SELECT id, status, priority, created_at
FROM generation_jobs
WHERE work_id = :work_id;

-- Check notifications
SELECT type, title, message, created_at
FROM notifications
WHERE user_id = :user_id
ORDER BY created_at DESC
LIMIT 5;
```

### 5. Verify Completed Work

```sql
-- Check final result
SELECT
  w.id,
  w.status,
  w.credits_used,
  w.output_data,
  f.file_path,
  f.file_size,
  f.mime_type
FROM works w
LEFT JOIN files f ON w.file_id = f.id
WHERE w.id = :work_id;
```

## Troubleshooting Guide

### Issue: Template Not Appearing in UI

**Possible Causes**:
- Template `is_active = false`
- Template `work_type` mismatch
- Frontend cache issue

**Solution**:
```sql
-- Check template status
SELECT id, template_name, is_active, display_order
FROM templates
WHERE template_name = 'XiCON_KLEIN_Poster_Maker_v1';

-- Activate if needed
UPDATE templates
SET is_active = true
WHERE template_name = 'XiCON_KLEIN_Poster_Maker_v1';
```

### Issue: Generation Stuck in Pending

**Possible Causes**:
- n8n not polling generation_jobs
- Database webhook not triggering
- n8n workflow error

**Solution**:
```sql
-- Check stuck jobs
SELECT gj.id, gj.created_at, gj.status, w.id as work_id
FROM generation_jobs gj
JOIN works w ON gj.work_id = w.id
WHERE gj.status = 'pending'
  AND gj.created_at < NOW() - INTERVAL '5 minutes';

-- Manual retry (create new job)
INSERT INTO generation_jobs (work_id, status, priority)
SELECT work_id, 'pending', priority
FROM generation_jobs
WHERE id = :stuck_job_id;

-- Delete stuck job
DELETE FROM generation_jobs WHERE id = :stuck_job_id;
```

### Issue: Generation Failed with Error

**Possible Causes**:
- Invalid reference image URL
- RunPod endpoint timeout
- GPU out of memory
- ComfyUI workflow error

**Solution**:
```sql
-- Check error details
SELECT output_data->>'error' as error_message
FROM works
WHERE id = :work_id;

-- Check if credits refunded
SELECT type, amount, created_at
FROM credit_transactions
WHERE work_id = :work_id
ORDER BY created_at DESC;

-- Verify refund
SELECT subscription_credits, purchased_credits
FROM users
WHERE id = :user_id;
```

### Issue: Image Upload Fails

**Possible Causes**:
- File too large (> 20MB)
- Invalid file type
- Storage quota exceeded
- Network timeout

**Solution**:
- Check file size and type before upload
- Verify Storage bucket exists and is accessible
- Check Storage quota in Supabase dashboard
- Use smaller images or compress before upload

### Issue: RunPod Endpoint Not Responding

**Possible Causes**:
- Endpoint not deployed
- GPU worker not started
- Network/firewall issue
- Model files not loaded

**Solution**:
1. Check RunPod endpoint status in dashboard
2. Verify GPU pod is running
3. SSH into pod and check ComfyUI logs:
   ```bash
   docker logs comfyui-container
   ```
4. Verify model files exist:
   ```bash
   ls -lh /workspace/runpod-slim/ComfyUI/models/unet/flux-2-klein-9b-fp8.safetensors
   ```

## Environment Requirements

### GPU Requirements

| Component | Requirement |
|-----------|-------------|
| GPU Model | NVIDIA RTX 5090 |
| VRAM | 24GB minimum |
| CUDA | 12.1 or higher |

### Model Files Needed

Download and place in appropriate directories:

```bash
# UNET model
/workspace/runpod-slim/ComfyUI/models/unet/flux-2-klein-9b-fp8.safetensors

# CLIP model
/workspace/runpod-slim/ComfyUI/models/clip/qwen_3_8b_fp8mixed.safetensors

# VAE model
/workspace/runpod-slim/ComfyUI/models/vae/flux2-vae.safetensors
```

### ComfyUI Custom Nodes

Required custom nodes (if any):
- `comfyui-flux2` (Flux2 specific nodes)
- `comfyui-reference-latent` (ReferenceLatent node)

Install via ComfyUI Manager or manually:
```bash
cd /workspace/runpod-slim/ComfyUI/custom_nodes
git clone https://github.com/example/comfyui-flux2
git clone https://github.com/example/comfyui-reference-latent
```

### Docker Image

Base image for RunPod deployment:
```dockerfile
FROM runpod/pytorch:2.1.0-py3.10-cuda12.1.0-devel

# Install ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI /workspace/runpod-slim/ComfyUI
WORKDIR /workspace/runpod-slim/ComfyUI
RUN pip install -r requirements.txt

# Copy workflow
COPY workflow.json /workspace/runpod-slim/ComfyUI/workflow.json

# Expose ComfyUI port
EXPOSE 8188

CMD ["python", "main.py", "--listen", "0.0.0.0"]
```

## Deployment Checklist

### Database Setup

- [ ] Run SQL migration to insert template record
- [ ] Verify template appears in templates table
- [ ] Check form_fields and request_dto are valid JSONB
- [ ] Confirm is_active = true
- [ ] Test template query with work_type filter

### Model Files

- [ ] Download flux-2-klein-9b-fp8.safetensors (~9GB)
- [ ] Download qwen_3_8b_fp8mixed.safetensors (~3GB)
- [ ] Download flux2-vae.safetensors (~200MB)
- [ ] Upload to RunPod network volume
- [ ] Verify file checksums

### RunPod Configuration

- [ ] Create RunPod template with Docker image
- [ ] Attach network volume to /workspace/runpod-slim/ComfyUI/models
- [ ] Configure RTX 5090 GPU
- [ ] Set environment variables (if any)
- [ ] Deploy serverless endpoint
- [ ] Test endpoint with sample request

### n8n Workflow

- [ ] Create or update n8n workflow for XiCON_KLEIN_Poster_Maker_v1 routing (flux2-klein model)
- [ ] Configure Supabase credentials
- [ ] Set RunPod endpoint URL
- [ ] Add error handling and retry logic
- [ ] Test workflow with sample generation_jobs record
- [ ] Enable workflow and set to active

### Frontend Integration

- [ ] Clear frontend cache
- [ ] Verify template appears in template list
- [ ] Test form rendering with all fields
- [ ] Test file upload to Storage
- [ ] Test form validation
- [ ] Submit test generation request
- [ ] Monitor Realtime updates

### End-to-End Test

- [ ] Create test account with sufficient credits
- [ ] Upload test reference image
- [ ] Enter test prompt
- [ ] Submit generation (output_count = 1)
- [ ] Verify generation_jobs INSERT
- [ ] Monitor n8n execution
- [ ] Verify work status updates (pending → processing → completed)
- [ ] Check result uploaded to Storage
- [ ] Verify file record in files table
- [ ] Confirm notification created
- [ ] Verify credits deducted correctly

### Monitoring

- [ ] Set up n8n execution logging
- [ ] Monitor generation_jobs queue size
- [ ] Track average processing time
- [ ] Monitor RunPod GPU utilization
- [ ] Set up alerts for failed generations
- [ ] Monitor Storage usage

## Related Documentation

- [Backend Overview](../OVERVIEW.md) - System architecture
- [Supabase API Plan](../supabase-api-plan.md) - Complete API specification
- [Template Config Spec](../template-config-spec.md) - Form field configuration guide
- [Flux Klein RunPod Worker README](/Users/blendx/Documents/XiCON/runpod/Wan_Animate_Runpod_hub_v1/runpod_worker_flux_klein/README.md) - Worker deployment guide

## Support

For issues or questions:
- Check n8n execution logs for workflow errors
- Review RunPod pod logs for GPU/model issues
- Query generation_jobs and works tables for status
- Check Supabase logs for Edge Function errors
