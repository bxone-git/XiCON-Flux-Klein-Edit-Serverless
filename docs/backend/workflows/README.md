# Workflow Documentation

This directory contains detailed documentation for each AI generation workflow template in the XiCON system.

## Available Workflows

### Image Generation

- [Flux2 Klein](./flux2-klein.md) - AI-powered image editing using Flux2 Klein 9B model

## Overview

Each workflow documentation includes:

- Architecture and data flow
- Template configuration details
- Input/output specifications
- ComfyUI workflow structure
- n8n integration guide
- Testing procedures
- Troubleshooting guide
- Deployment requirements

## Workflow Architecture

All workflows follow the XiCON standard generation pipeline:

```
User Request → Edge Function → generation_jobs → n8n → ComfyUI/AI Service → Storage → works
```

1. User submits generation request via Next.js frontend
2. Edge Function validates, deducts credits, creates work and generation_jobs records
3. n8n polls generation_jobs queue and picks up pending work
4. n8n routes to appropriate AI service based on template_name
5. AI service processes request and returns output
6. n8n uploads result to Supabase Storage
7. n8n updates works table with completed status
8. Database triggers create notifications
9. Realtime pushes updates to client

## Template Configuration

Templates are defined in the `templates` table with:

- `template_name`: Identifier used by n8n for routing
- `work_type`: Category (promotional_image, video_content)
- `form_fields`: Dynamic UI form definition (JSONB)
- `request_dto`: API request schema definition (JSONB)
- `estimated_time`: Expected generation time in seconds

See [template-config-spec.md](../template-config-spec.md) for detailed configuration specifications.

## Adding New Workflows

To add a new workflow:

1. Create SQL migration to insert template record
2. Configure n8n workflow for routing and processing
3. Document workflow in this directory
4. Test end-to-end generation flow
5. Deploy ComfyUI workflow or AI service integration

## Related Documentation

- [Backend Overview](../OVERVIEW.md) - System architecture
- [Supabase API Plan](../supabase-api-plan.md) - Complete API specification
- [Template Config Spec](../template-config-spec.md) - Form field configuration guide
