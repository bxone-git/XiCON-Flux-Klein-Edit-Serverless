# XiCON Klein I2I Workflow Documentation

## Overview

The **XiCON_KLEIN_I2I_V1** workflow is an n8n automation that orchestrates image-to-image generation using the Flux 2 Klein 9B model deployed on RunPod Serverless. It receives generation requests via webhook, translates prompts from Korean to English, submits jobs to RunPod, polls for completion, and stores the generated images in Supabase Storage.

This workflow bridges the XiCON web application with the I2I_KELIN_9b RunPod endpoint, providing a complete pipeline from user request to delivered image.

---

## Workflow Information

| Property | Value |
|----------|-------|
| **Workflow ID** | WAxnkqZN5dbadYu0 |
| **Workflow Name** | XiCON_KLEIN_I2I_V1 |
| **Webhook Path** | `/webhook/klein_i2i` |
| **Webhook URL** | `https://vpsn8n.xicon.co.kr/webhook/klein_i2i` |
| **Template ID** (Supabase) | `82064257-1bef-45d8-a6ba-715f33c887cc` |
| **RunPod Endpoint ID** | `p6tv6t2d0vjt9c` |
| **RunPod Endpoint Name** | XiCON-KLEIN-I2I |
| **Status** | Inactive (pending activation) |
| **Node Count** | 18 nodes |
| **Last Updated** | 2026-02-11T02:11:19.165Z |

---

## Workflow Architecture

### Overall Flow

```
Webhook → SQL Query → Job Validation → Mark as Taken
  ↓
AI Translation → Build Payload → RunPod Submission
  ↓
Wait 5 seconds → Poll RunPod Status
  ↓
[Status Check]
├── COMPLETED → Extract Image → Upload → Vision Title → Save Record → Update Work
├── FAILED → Update Works Status to Failed
├── CANCELLED → Update Works Status to Cancelled
└── PENDING → Loop back to Poll (preserve input and retry)
```

### Node Details

#### 1. **Webhook** (Entry Point)
- **Type**: n8n Webhook
- **Path**: `klein_i2i`
- **Purpose**: Receives generation job requests from the XiCON web app
- **Expected Payload**:
```json
{
  "body": {
    "record": {
      "id": "generation_job_id"
    }
  }
}
```

#### 2. **Execute SQL Query**
- **Type**: PostgreSQL Query
- **Purpose**: Fetches job details from the database
- **Query**: Joins `generation_jobs`, `works`, and `templates` tables
- **Filters**:
  - Job status = `pending`
  - Template ID = `82064257-1bef-45d8-a6ba-715f33c887cc` (Klein I2I)
  - Template is active (`is_active = true`)
- **Returns**: Job ID, work data, template metadata, and input parameters
- **Ordering**: By priority (desc), then creation timestamp (asc)

#### 3. **IF Jobs Exist** (Conditional)
- **Type**: Switch Node
- **Condition**: `$json.length > 0`
- **Purpose**: Only proceed if pending jobs are available
- **Default**: Stop execution if no jobs found

#### 4. **Mark as Taken**
- **Type**: Supabase Update
- **Table**: `generation_jobs`
- **Action**: Updates job status to `taken` with timestamp
- **Purpose**: Prevents race conditions in distributed environments

#### 5. **AI Agent** (Prompt Translation)
- **Type**: LangChain LM Chat (OpenRouter)
- **Model**: `openai/gpt-4o-mini`
- **Purpose**: Translates Korean prompts to English for image generation
- **System Prompt**: "You translate Korean user prompts to English for image generation. Output only the translated prompt, nothing else."
- **Input**: `input_data.prompt` from the work record
- **Output**: Translated English prompt

#### 6. **Build ComfyUI Payload**
- **Type**: JavaScript Code Node
- **Purpose**: Constructs the payload for RunPod submission
- **Input Processing**:
  - Extracts parameters from work's `input_data`
  - Applies defaults for optional parameters
  - Validates required fields (image reference)
- **Output Structure**:
```json
{
  "input": {
    "prompt": "translated_english_prompt",
    "seed": 0,
    "steps": 4,
    "cfg": 1.0,
    "megapixels": 1.0,
    "image_url": "url_or_omitted",
    "image_base64": "base64_or_omitted"
  },
  "work_id": "work_record_id",
  "generation_metadata": {
    "prompt": "translated_prompt",
    "original_prompt": "original_korean_prompt",
    "model": "XiCON_KLEIN_I2I",
    "width": 768,
    "height": 1024,
    "seed": "used_seed",
    "steps": "num_steps",
    "cfg": "cfg_value",
    "megapixels": "megapixels_value",
    "has_image_input": true,
    "submitted_at": "iso_timestamp"
  }
}
```

#### 7. **Submit to RunPod**
- **Type**: HTTP Request (POST)
- **URL**: `https://api.runpod.ai/v2/p6tv6t2d0vjt9c/run`
- **Authentication**: RunPod API Key
- **Payload**: Serialized input from previous node
- **Returns**: RunPod Job ID and initial status
- **Purpose**: Submits the image generation task to RunPod Serverless

#### 8. **Update Works to Processing**
- **Type**: Supabase Update
- **Table**: `works`
- **Updates**:
  - `status` → `processing`
  - `runpod_job_id` → RunPod job ID
  - `generation_metadata` → JSON metadata from payload
- **Purpose**: Tracks job progress in the database

#### 9. **Wait 5s**
- **Type**: Wait Node
- **Duration**: 5 seconds
- **Purpose**: Allows RunPod time to process before polling
- **Critical**: Prevents overwhelming RunPod with status requests

#### 10. **Check RunPod Status**
- **Type**: HTTP Request (GET)
- **URL**: `https://api.runpod.ai/v2/p6tv6t2d0vjt9c/status/{job_id}`
- **Authentication**: RunPod API Key
- **Returns**: Current job status, output data, and error information
- **Purpose**: Polls RunPod for job completion

#### 11. **Switch (Status)**
- **Type**: Switch Node
- **Routes Based On**: `$json.status` field
- **Cases**:
  - `COMPLETED` → Extract and process image (output 0)
  - `FAILED` → Update work status to failed (output 1)
  - `CANCELLED` → Update work status to cancelled (output 2)
  - `PENDING` → Preserve data and retry (output 3)

#### 12. **Extract Image Data** (Success Path)
- **Type**: JavaScript Code Node
- **Input**: RunPod status response
- **Output**: Extracted image base64 and metadata
- **Purpose**: Parses RunPod output structure
- **Critical Fix**: Maps `output.image` (not `output.image_base64`) to extracted data
- **Filename Handling**: Uses fixed default `output.png` since handler.py doesn't return filename

#### 13. **Convert to File**
- **Type**: Convert to File Node
- **Input**: Base64 image data
- **Output**: Binary file object
- **Format**: PNG detection/conversion
- **Purpose**: Prepares binary data for Supabase upload

#### 14. **Upload to Storage**
- **Type**: HTTP Request (POST)
- **URL**: `https://inwtsfxxunljfznahixt.supabase.co/storage/v1/object/works/{user_id}/{work_id}/{filename}`
- **Authentication**: Supabase Bearer Token (Service Role)
- **Purpose**: Stores generated image in Supabase Storage bucket `works`
- **Path Structure**: `works/{user_id}/{work_id}/{filename}.png`

#### 15. **Build Image URL**
- **Type**: JavaScript Code Node
- **Purpose**: Constructs the public image URL for the uploaded file
- **URL Format**: `https://inwtsfxxunljfznahixt.supabase.co/storage/v1/object/public/works/{user_id}/{work_id}/{filename}`

#### 16. **Call Vision API**
- **Type**: HTTP Request (POST)
- **URL**: `https://openrouter.ai/api/v1/chat/completions`
- **Model**: `openai/gpt-4o-mini` (with vision capability)
- **Purpose**: Generates a Korean title for the generated image
- **System Prompt**: "이미지를 보고 한국어로 짧은 제목을 생성해주세요. 10자 이내로 작성하세요." (Generate a short Korean title for the image, max 10 characters)
- **Input**: Image URL via vision API

#### 17. **Extract Title**
- **Type**: JavaScript Code Node
- **Purpose**: Parses Vision API response to extract title
- **Fallback**: Uses default title "I2I 작품" if extraction fails
- **Limit**: Truncates title to 10 characters

#### 18. **Create Files Record**
- **Type**: Supabase Insert
- **Table**: `files`
- **Fields**:
  - `bucket_id` → `works`
  - `path` → File storage path
  - `width` → `768`
  - `height` → `1024`
  - `user_id` → Original request user
- **Returns**: Created file record with `id` and `file_url`
- **Purpose**: Creates database record linking file to user and work

#### 19. **Prepare Update Data**
- **Type**: JavaScript Code Node
- **Purpose**: Assembles final data for work record update
- **Output**: File ID, work ID, title, and output data

#### 20. **Update Works to Completed**
- **Type**: Supabase Update
- **Table**: `works`
- **Updates**:
  - `status` → `completed`
  - `output_file_id` → Created file ID
  - `thumbnail_file_id` → Same as output file ID
  - `title` → Generated Korean title
  - `output_data_json` → Image URL and metadata
  - `tags` → `['I2I', 'Image_to_Image', 'AI생성']`
  - `completed_at` → Current timestamp
- **Purpose**: Marks work as completed and stores final results

#### 21. **Update Works to Failed** (Failure Path)
- **Type**: Supabase Update
- **Updates**: Sets status to `failed` with error message and timestamp
- **Purpose**: Records failure for debugging

#### 22. **Update Works to Cancelled** (Cancellation Path)
- **Type**: Supabase Update
- **Updates**: Sets status to `cancelled` with timestamp
- **Purpose**: Marks cancelled jobs

#### 23. **Preserve Input Data** (Retry Path)
- **Type**: JavaScript Code Node
- **Purpose**: Loops back to polling on pending status
- **Logic**: Feeds output back to Wait node for continued polling

---

## Input/Output Specification

### Webhook Request Format

```json
{
  "body": {
    "record": {
      "id": "generation_job_id"
    }
  }
}
```

### Work Record (from SQL Query)

The workflow expects the `works` table to contain an `input_data` JSON field with:

```json
{
  "prompt": "이미지 배경을 해변으로 바꿔줘",
  "image_url": "https://example.com/reference.jpg",
  "image_base64": "iVBORw0KGgoAAAANS...",
  "steps": 20,
  "cfg": 3.5,
  "seed": 12345,
  "megapixels": 1.0
}
```

### Required Input Fields

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `prompt` | string | Yes | - | Editing instructions (translated by AI) |
| `image_url` | string | Conditional | - | Reference image URL (one of `image_url` or `image_base64` required) |
| `image_base64` | string | Conditional | - | Reference image as base64-encoded string |
| `steps` | number | No | 4 | Sampling steps (1-40); Klein model optimized for 4 steps |
| `cfg` | number | No | 1.0 | Classifier-free guidance scale; Klein default is 1.0 |
| `seed` | number | No | 0 | Random seed (0 = random) |
| `megapixels` | number | No | 1.0 | Upscaling factor (0.5-2.0) |

### RunPod Request Body

```json
{
  "input": {
    "prompt": "Replace the background with a serene beach landscape",
    "image_url": "https://example.com/reference.jpg",
    "steps": 4,
    "cfg": 1.0,
    "seed": 12345,
    "megapixels": 1.0
  }
}
```

### RunPod Response (Success)

```json
{
  "status": "COMPLETED",
  "output": {
    "image": "iVBORw0KGgoAAAANS...",
    "seed": 12345,
    "prompt_id": "uuid"
  },
  "id": "runpod_job_id"
}
```

**Note**: The handler.py returns `output.image` (not `output.image_base64`) and does not include filename in response.

### RunPod Response (Processing)

```json
{
  "status": "IN_PROGRESS",
  "output": null,
  "id": "runpod_job_id"
}
```

### Final Work Record Update (Success)

```json
{
  "status": "completed",
  "output_file_id": "file_uuid",
  "thumbnail_file_id": "file_uuid",
  "title": "해변 풍경",
  "output_data_json": {
    "image_url": "https://inwtsfxxunljfznahixt.supabase.co/storage/v1/object/public/works/{user_id}/{work_id}/output.png",
    "filename": "output.png"
  },
  "tags": ["I2I", "Image_to_Image", "AI생성"],
  "completed_at": "2025-02-11T10:30:45.123Z"
}
```

---

## Database Integration

### Tables & Fields

#### `generation_jobs`
```sql
CREATE TABLE generation_jobs (
  id UUID PRIMARY KEY,
  work_id UUID NOT NULL REFERENCES works(id),
  status TEXT DEFAULT 'pending',
  taken_at TIMESTAMP,
  priority INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT now()
);
```

#### `works`
```sql
CREATE TABLE works (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  template_id UUID NOT NULL REFERENCES templates(id),
  input_data JSONB,
  status TEXT DEFAULT 'pending',
  runpod_job_id TEXT,
  generation_metadata JSONB,
  output_file_id UUID REFERENCES files(id),
  thumbnail_file_id UUID REFERENCES files(id),
  title TEXT,
  output_data_json JSONB,
  tags TEXT[],
  error_message TEXT,
  created_at TIMESTAMP DEFAULT now(),
  completed_at TIMESTAMP,
  failed_at TIMESTAMP,
  cancelled_at TIMESTAMP
};
```

#### `templates`
```sql
CREATE TABLE templates (
  id UUID PRIMARY KEY,
  template_name TEXT,
  is_active BOOLEAN DEFAULT false
);
```

#### `files`
```sql
CREATE TABLE files (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  bucket_id TEXT,
  path TEXT,
  width INTEGER,
  height INTEGER,
  file_url TEXT,
  created_at TIMESTAMP DEFAULT now()
);
```

### Status Lifecycle

```
pending → taken → processing → completed
       ↓           ↓
       ↓           └→ failed
       └→ cancelled
```

**Valid State Transitions**:
- `pending` → `taken` (job locked for processing)
- `taken` → `processing` (RunPod job submitted)
- `processing` → `completed` (generation successful)
- `processing` → `failed` (generation error)
- Any → `cancelled` (user cancellation)

---

## API Testing Guide

### Prerequisites

- n8n instance running at `https://vpsn8n.xicon.co.kr`
- Valid generation_job ID in database with status = `pending`
- Reference image uploaded to Supabase or URL accessible from RunPod

### Test 1: Manual Webhook Trigger

```bash
curl -X POST https://vpsn8n.xicon.co.kr/webhook/klein_i2i \
  -H "Content-Type: application/json" \
  -d '{
    "body": {
      "record": {
        "id": "12345678-1234-1234-1234-123456789abc"
      }
    }
  }'
```

**Expected Response**: HTTP 200 with workflow execution ID

### Test 2: Create Test Job via SQL

```sql
-- Create work record with image edit request
INSERT INTO works (
  id, user_id, template_id, input_data, status
) VALUES (
  'work-uuid-here',
  'user-uuid-here',
  '82064257-1bef-45d8-a6ba-715f33c887cc',
  jsonb_build_object(
    'prompt', '배경을 산 풍경으로 바꿔줘',
    'image_url', 'https://example.com/reference.jpg',
    'steps', 4,
    'cfg', 1.0,
    'seed', 0
  ),
  'pending'
);

-- Create generation job
INSERT INTO generation_jobs (
  id, work_id, status, priority
) VALUES (
  'job-uuid-here',
  'work-uuid-here',
  'pending',
  1
);

-- Trigger workflow
SELECT pg_notify(
  'generation_job_created',
  json_build_object('id', 'job-uuid-here')::text
);
```

### Test 3: Monitor Workflow Execution

In n8n UI:
1. Navigate to Workflow Details for **WAxnkqZN5dbadYu0**
2. Click "Show Executions"
3. Monitor real-time node execution
4. Check "Logs" tab for debug output from JavaScript nodes
5. Verify Supabase updates in database

### Test 4: End-to-End Test with All Parameters

```json
{
  "body": {
    "record": {
      "id": "test-job-uuid"
    }
  }
}
```

With database record containing:
```json
{
  "prompt": "Replace the sky with a dramatic sunset",
  "image_url": "https://cdn.example.com/sample.jpg",
  "steps": 4,
  "cfg": 1.0,
  "seed": 42,
  "megapixels": 1.2
}
```

### Test 5: Error Scenarios

#### Missing Image
```json
{
  "prompt": "edit prompt",
  "steps": 20
}
```
**Expected**: RunPod returns error, workflow updates work status to `failed`

#### Invalid Seed
```json
{
  "prompt": "edit prompt",
  "image_url": "...",
  "seed": -999
}
```
**Expected**: Workflow treats negative/invalid seeds as random

#### Network Timeout
**Expected**: RunPod polling loop retries up to failure threshold

---

## Monitoring & Debugging

### Key Metrics

| Metric | Target | Location |
|--------|--------|----------|
| Webhook Response Time | <100ms | n8n execution logs |
| SQL Query Time | <500ms | Postgres logs |
| AI Translation Time | 2-5s | OpenRouter API logs |
| RunPod Submit Time | <2s | HTTP node output |
| Image Generation Time | 30-120s | RunPod dashboard |
| Total End-to-End | 1-3min | n8n execution history |

### Debug Node Outputs

Enable "Show Full Output" in n8n for these nodes:
- **Build ComfyUI Payload**: Verify parameter injection
- **Check RunPod Status**: Verify status values
- **Extract Image Data**: Verify base64 integrity
- **Call Vision API**: Verify title generation

### Common Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| Workflow hangs at polling | RunPod endpoint offline | Check RunPod status in dashboard |
| "No output image from SaveImage" | ComfyUI workflow error | Check `generation_metadata` for invalid params |
| Vision API returns empty title | Image too small/unclear | Fallback to "I2I 작품" (already handled) |
| Supabase upload fails | Invalid bucket path | Verify `user_id` and `work_id` format |
| Korean prompt not translated | OpenRouter API unavailable | Add retry logic to AI Agent node |

### Logs & Traces

**n8n Execution Logs**:
- Location: n8n UI → Workflow Details → Show Executions
- Filter by: Execution date, duration, status
- Export: Click execution → Download logs

**RunPod Logs**:
- Location: RunPod dashboard → Endpoint → Logs
- Shows: Handler output, model loading, inference timing
- Useful for: Performance tuning, error diagnosis

**Supabase Logs**:
- Location: Supabase dashboard → Functions/Logs
- Tracks: Insert/Update operations, query time
- Useful for: Data consistency verification

---

## Integration with XiCON Web App

### Request Flow

```
Web App User → Click "Generate"
    ↓
Create work record + generation_job
    ↓
POST to /webhook/klein_i2i (via n8n)
    ↓
Workflow polls status
    ↓
User sees "Processing..." in UI
    ↓
Workflow completes, updates work status
    ↓
User sees generated image + Korean title
```

### UI Status Mapping

| Work Status | UI Display | User Action |
|------------|-----------|-------------|
| `pending` | "Queued" | Waiting for workflow to pick up |
| `taken` | "Starting..." | Job locked, about to submit |
| `processing` | "Generating..." | Running on RunPod |
| `completed` | "Done" + Image | Can view, save, or regenerate |
| `failed` | "Error" + Message | Can retry or try different params |
| `cancelled` | "Cancelled" | Removed from queue |

### Error Handling in Frontend

Catch these error responses from RunPod:
- `"error": "Missing required parameter: image"` → Validate image input
- `"error": "Processing failed: ..."` → Show error message to user
- Timeout (>5min) → Suggest retry or contact support

---

## Performance Characteristics

### Latency Breakdown (Typical)

| Stage | Duration | Notes |
|-------|----------|-------|
| Webhook → SQL | 0.2s | Simple database join |
| AI Translation | 2-4s | API call to OpenRouter |
| Build Payload | 0.1s | JavaScript execution |
| RunPod Submit | 0.5s | HTTP request + queue |
| Initial Wait | 5s | Hardcoded pause |
| Status Poll (1st) | 0.5s | Immediate return if pending |
| Image Generation | 20-40s | Klein 9B optimized for 4 steps + 1.0 cfg |
| Status Poll (2nd) | 0.5s | Get output from RunPod |
| Image Processing | 2-5s | Extract, upload, convert |
| Vision API | 3-5s | Generate Korean title |
| Database Updates | 1-2s | Multiple Supabase writes |
| **Total** | **35-70s** | User sees image in ~1 minute |

### Scaling Considerations

- **Workflow Concurrency**: n8n processes one webhook execution per request (parallel by default)
- **RunPod Capacity**: Check endpoint workers; scale to 2-5 for peak load
- **Database**: PostgreSQL connection pooling recommended (50+ concurrent connections)
- **Supabase Storage**: No bandwidth limits, but object size < 500MB

### Cost Estimation

| Component | Cost | Formula |
|-----------|------|---------|
| RunPod GPU Time | $0.24/hr | Varies by model (9B Klein = 2-3 min) |
| OpenRouter API | $0.002/1K tokens | ~50 tokens per translation |
| n8n Workflow | Execution-based | Platform dependent |
| Supabase Storage | $5/month + overage | 1 image ≈ 1-3MB |

**Per Image Cost**: ~$0.02 - $0.05 (GPU + API)

---

## Troubleshooting Guide

### Workflow Doesn't Start

**Symptoms**: Webhook receives request, but no execution starts
**Check**:
1. Webhook is activated in n8n (green checkmark)
2. Webhook path matches in n8n settings
3. SQL query credentials are configured
4. Database connection is working

**Fix**:
```bash
# Test webhook directly
curl -v https://vpsn8n.xicon.co.kr/webhook/klein_i2i \
  -H "Content-Type: application/json" \
  -d '{"body":{"record":{"id":"test"}}}'

# Should return 200 with execution ID
```

### Jobs Stuck in "taken" Status

**Symptoms**: Job never moves to `processing`
**Likely Cause**: RunPod submit node failed silently

**Fix**:
1. Check RunPod API credentials in n8n
2. Verify endpoint ID is correct: `p6tv6t2d0vjt9c`
3. Check RunPod dashboard for endpoint health
4. Monitor n8n execution logs for HTTP errors

**Manual Recovery**:
```sql
UPDATE generation_jobs
SET status = 'pending'
WHERE status = 'taken'
AND taken_at < now() - interval '10 minutes';
```

### Images Not Uploading to Supabase

**Symptoms**: Generation completes but file not in storage
**Check**:
1. Supabase Storage bucket `works` exists
2. Service Role token is valid (not public/anon)
3. Bucket path structure is correct
4. File size < 500MB

**Verify Bucket Path**:
```sql
-- Should return file record
SELECT id, path, user_id
FROM files
WHERE created_at > now() - interval '1 hour'
ORDER BY created_at DESC;
```

### Vision API Title Generation Fails

**Symptoms**: Title is always "I2I 작품"
**Likely Cause**: Vision API returned empty or invalid response

**Check**:
1. OpenRouter API key is valid
2. Model `openai/gpt-4o-mini` supports vision
3. Image URL is publicly accessible
4. Image is large enough to analyze

**Manual Title Update**:
```sql
UPDATE works
SET title = '수정된 이미지'
WHERE id = 'work-uuid'
AND status = 'completed'
AND title = 'I2I 작품';
```

### Polling Loop Never Exits

**Symptoms**: Workflow keeps polling forever
**Likely Cause**: RunPod job in invalid state (not COMPLETED/FAILED/CANCELLED)

**Fix**:
1. Check RunPod dashboard for job status
2. Manually fail job if stuck:
```bash
curl -X POST https://api.runpod.ai/v2/p6tv6t2d0vjt9c/cancel/{job_id} \
  -H "Authorization: Bearer YOUR_RUNPOD_API_KEY"
```

3. Then update work record:
```sql
UPDATE works
SET status = 'failed', error_message = 'RunPod job timeout'
WHERE runpod_job_id = '{job_id}';
```

---

## Dependencies & Credentials

### Required Credentials in n8n

| Credential | Type | Used By | Notes |
|-----------|------|---------|-------|
| `PostgreSQL account` | DB | SQL Query, Mark as Taken | Connection to Supabase PostgreSQL |
| `OpenRouter account` | API | AI Agent, Vision API | Must have sufficient balance |
| `runpod_serverless_api` | API Key | RunPod HTTP nodes | From RunPod dashboard |
| `Supabase_XICON(TBD)` | API | Supabase operations | Service Role key recommended |
| `Supabase_Role` | HTTP Bearer | Storage Upload | For object storage authentication |
| `OpenRouter_XiCON_2` | API Key | Vision API | Separate account/key |

### Environment Variables (for handler.py)

```bash
SERVER_ADDRESS=127.0.0.1          # ComfyUI server
COMFY_API_URL=http://127.0.0.1:8188
NETWORK_VOLUME_PATH=/runpod-volume
```

---

## Model & Hardware Specifications

### Model Information

| Component | Details |
|-----------|---------|
| **Base Model** | Flux 2 Klein 9B |
| **Type** | Image-to-Image (I2I) |
| **Precision** | FP8 (quantized) |
| **File Size** | ~9GB |
| **Text Encoder** | Qwen 3.8B FP8 |
| **VAE** | Flux2 VAE |
| **VRAM Required** | 24GB |
| **Supported GPU** | NVIDIA ADA (4080, 4090, etc.) |

### RunPod Hardware

| Setting | Value |
|---------|-------|
| **GPU Type** | NVIDIA ADA RTX 4090 (24GB VRAM) |
| **GPU Quantity** | 1 |
| **RAM** | 30GB |
| **vCPU** | 8 cores |
| **Network Volume** | Enabled (models cached) |

### ComfyUI Configuration

```ini
[default]
preview_method = auto
badge_mode = active
disable_gpu_warning = True
component_policy = workflow
model_download_by_agent = False
```

---

## Security Considerations

### Data Protection

- **Prompt Translation**: Sent to OpenRouter (third-party)
- **Image Storage**: Encrypted at rest in Supabase
- **API Keys**: Use environment variables, never hardcode
- **User Data**: Supabase RLS policies should enforce user isolation

### Recommended RLS Policies

```sql
-- Only users can see their own work
CREATE POLICY "Users see own work" ON works
  FOR SELECT USING (auth.uid() = user_id);

-- Only users can see their own files
CREATE POLICY "Users see own files" ON files
  FOR SELECT USING (auth.uid() = user_id);

-- Only service role can update work status
CREATE POLICY "Service role updates work" ON works
  FOR UPDATE USING (auth.jwt()->>'role' = 'service_role');
```

### API Rate Limiting

- **OpenRouter**: 100 req/min per key (shared across all requests)
- **RunPod**: No strict limits, but monitor for abuse
- **Supabase**: 100 req/sec per project
- **n8n**: Execution-based billing, no hard limits

### Secret Rotation

Rotate credentials every 90 days:
1. Generate new API key in provider dashboard
2. Update n8n credentials
3. Test workflow with new credentials
4. Revoke old credentials
5. Document rotation date

---

## Maintenance & Updates

### Regular Checks (Daily)

```bash
# Check workflow executions
- n8n UI → Workflow Details → Filter by "Last 24h"
- Look for error rate >5%

# Monitor RunPod endpoint
- RunPod dashboard → Endpoint stats
- Check: Error rate, average duration, worker health
```

### Weekly Tasks

```sql
-- Check for stuck jobs
SELECT COUNT(*) FROM generation_jobs
WHERE status = 'taken'
AND taken_at < now() - interval '1 hour';

-- Check failed/cancelled ratio
SELECT
  status,
  COUNT(*) as count
FROM works
WHERE created_at > now() - interval '7 days'
GROUP BY status;
```

### Monthly Maintenance

1. **Review Logs**: Identify recurring errors
2. **Update Models**: Check for new Flux 2 Klein versions
3. **Optimize SQL**: Review slow query logs
4. **Cost Analysis**: Review OpenRouter and RunPod usage
5. **Credential Audit**: Verify all API keys are still valid

### Migration/Upgrade Checklist

When updating the workflow:

- [ ] Export current workflow to backup: `n8n_workflow_backup_YYYY-MM-DD.json`
- [ ] Test changes in a cloned workflow first
- [ ] Update all node credentials
- [ ] Verify webhook path matches (shouldn't change)
- [ ] Test with sample work record
- [ ] Monitor first 10 executions closely
- [ ] Enable error notifications
- [ ] Document any breaking changes

---

## Appendix: Quick Reference

### Workflow Execution Checklist

For manual execution in n8n:

1. [ ] Webhook path configured: `klein_i2i`
2. [ ] PostgreSQL credentials set and tested
3. [ ] SQL query has correct template_id filter
4. [ ] AI Agent model is `openai/gpt-4o-mini`
5. [ ] RunPod endpoint ID is `p6tv6t2d0vjt9c`
6. [ ] RunPod API credentials configured
7. [ ] Supabase credentials set (service role)
8. [ ] Storage bucket name is `works`
9. [ ] Vision API credentials set
10. [ ] All credential tests pass (green checkmarks)

### Common Command Reference

```bash
# Test n8n webhook
curl -X POST https://vpsn8n.xicon.co.kr/webhook/klein_i2i \
  -H "Content-Type: application/json" \
  -d '{"body":{"record":{"id":"test-id"}}}'

# Check RunPod job status
curl https://api.runpod.ai/v2/p6tv6t2d0vjt9c/status/{job_id} \
  -H "Authorization: Bearer YOUR_API_KEY"

# Query pending jobs
psql -h YOUR_DB_HOST -U postgres -d xicon \
  -c "SELECT id, status FROM generation_jobs WHERE status='pending' LIMIT 5;"

# Monitor n8n logs
docker logs -f n8n_container | grep "klein_i2i"
```

### Parameter Presets

**Fast Mode** (for testing, ~20s generation):
```json
{
  "prompt": "prompt",
  "image_url": "url",
  "steps": 4,
  "cfg": 1.0,
  "megapixels": 0.5
}
```

**High Quality Mode** (~50s generation):
```json
{
  "prompt": "prompt",
  "image_url": "url",
  "steps": 10,
  "cfg": 2.0,
  "megapixels": 1.5
}
```

**Balanced Mode** (recommended, ~30s generation):
```json
{
  "prompt": "prompt",
  "image_url": "url",
  "steps": 4,
  "cfg": 1.0,
  "megapixels": 1.0
}
```

**Note**: Klein 9B is optimized for low-step inference (4 steps is the native default). Increasing steps beyond 10 provides diminishing quality returns while significantly increasing generation time.

---

## Support & Escalation

### Escalation Path

1. **First Level**: Check logs in n8n and RunPod dashboards
2. **Second Level**: Query database for data consistency
3. **Third Level**: Contact RunPod support (endpoint issues)
4. **Fourth Level**: Contact Supabase support (storage issues)
5. **Fifth Level**: Escalate to XiCON infrastructure team

### Useful Links

- **n8n Workflow**: https://vpsn8n.xicon.co.kr/workflow/WAxnkqZN5dbadYu0
- **RunPod Endpoint**: https://www.runpod.io/console/user/endpoints
- **Supabase Project**: https://app.supabase.com/
- **ComfyUI Server**: http://127.0.0.1:8188 (internal)

### Contact Information

- **Workflow Issues**: Check n8n error logs first
- **RunPod Endpoint**: Check RunPod dashboard
- **Database Issues**: PostgreSQL logs in Supabase
- **Storage Issues**: Supabase Storage settings

---

## Document Version

- **Version**: 1.1
- **Last Updated**: 2026-02-11T02:11:19.165Z
- **Author**: Technical Documentation
- **Status**: Inactive (pending activation)

### Recent Updates (2026-02-11 11:11 KST)

- Fixed critical Extract Image Data field mapping: `output.image_base64` → `output.image`
- Updated default parameters: steps 20→4, cfg 3.5→1.0 (Klein 9B native defaults)
- Updated latency breakdown and expected performance times
- Clarified parameter presets with generation time estimates
- Updated workflow status to "Inactive (pending activation)"

For the latest version of this document, refer to `/README_WORKFLOW.md` in the project repository.
