# Follow-Up Tasks for I2I_KELIN_9b Workflow

**Date**: 2026-02-11
**Status**: Non-blocking recommendations for production hardening

---

## Overview

The I2I_KELIN_9b n8n workflow is **production-ready** for initial testing and deployment. The Architect has verified all critical fixes are correct. The following are **recommended follow-up improvements** for unattended production use.

---

## Recommended Improvements

### 1. Add Polling Timeout (MODERATE PRIORITY)

**Issue**: The RunPod status polling loop has no timeout or max-retry limit. If a RunPod job gets stuck in `IN_PROGRESS` or `IN_QUEUE` indefinitely, the n8n execution will loop forever.

**Impact**:
- Risk: Stuck RunPod jobs cause infinite n8n executions
- Over time, multiple stuck executions could exhaust n8n's execution concurrency
- Low risk for manual testing, moderate risk for unattended production

**Recommendation**: Add retry counter or timestamp check in "Preserve Input Data" node

**Implementation**:
```javascript
// In "Preserve Input Data" node, add retry tracking:
const retryCount = $json.retry_count || 0;
const maxRetries = 60; // 5 minutes at 5s intervals

if (retryCount >= maxRetries) {
  throw new Error(`RunPod job timeout after ${maxRetries * 5} seconds`);
}

return {
  json: {
    work_id: $('Execute a SQL query').item.json.id,
    runpod_job_id: $json.id,
    user_id: $('Execute a SQL query').item.json.user_id,
    retry_count: retryCount + 1
  }
};
```

**Effort**: Low (modify 1 code node, ~15 minutes)
**Priority**: HIGH for unattended production, LOW for manual testing

---

### 2. Handle RunPod TIMED_OUT Status (LOW PRIORITY)

**Issue**: The Switch node only handles `COMPLETED`, `FAILED`, `CANCELLED`. The `TIMED_OUT` status goes to fallback (infinite loop).

**Implementation**: Add a case to the Switch node or handle in Preserve Input Data:
```javascript
// In Switch node, add case:
{
  "conditions": {
    "conditions": [
      {
        "leftValue": "={{ $json.status }}",
        "rightValue": "TIMED_OUT",
        "operator": {"type": "string", "operation": "equals"}
      }
    ]
  },
  "renameOutput": true,
  "outputKey": "timed_out"
}
```

Then connect `timed_out` output to "Update Works to Failed" node.

**Effort**: Low (add 1 switch case + 1 connection, ~10 minutes)
**Priority**: LOW (edge case)

---

### 3. Fix Test Example Defaults in Documentation (TRIVIAL)

**Issue**: `DEPLOYMENT_STATUS.md` test example still shows old defaults (steps: 20, cfg: 3.5) instead of new defaults (steps: 4, cfg: 1.0).

**Location**: Line 100-101 of DEPLOYMENT_STATUS.md

**Fix**: Update the JSON example:
```json
{
  "prompt": "테스트 프롬프트",
  "image_url": "https://example.com/test.jpg",
  "steps": 4,      // Changed from 20
  "cfg": 1.0,      // Changed from 3.5
  "seed": 42,
  "megapixels": 1.0
}
```

**Effort**: Trivial (~2 minutes)
**Priority**: LOW (documentation only)

---

## Trade-offs

| Option | Pros | Cons |
|--------|------|------|
| **Deploy as-is** (activate now) | ✅ Fastest to production<br>✅ All critical bugs fixed | ⚠️ Infinite loop risk on stuck RunPod jobs |
| **Fix polling timeout first** | ✅ Eliminates stuck-execution risk<br>✅ Still fast (~15 min delay) | ⏱️ Delays initial testing |
| **Full hardening** (all 3 fixes) | ✅ Most robust for production<br>✅ No known issues | ⏱️ Delays activation (~30 min) |

---

## Architect Verdict

**"Can you complete the ralph loop? YES."**

The claimed fixes are verified against the source code. The workflow is ready for activation and manual end-to-end testing. The polling timeout is a pre-existing architectural gap (inherited from T2I reference workflow), not a regression from the fixes applied.

**Recommendation**:
- For **manual testing and low-traffic deployment**: Deploy as-is ✅
- For **unattended production with high traffic**: Fix polling timeout first before deploying

---

## Current Status

✅ **COMPLETED** - All critical data-contract bugs fixed:
1. Extract Image Data field mapping (`output.image`)
2. Filename handling (fixed default)
3. Default parameters (steps: 4, cfg: 1.0)
4. Workflow re-imported and verified

⏳ **RECOMMENDED** - Production hardening tasks:
1. Add polling timeout (moderate priority)
2. Handle TIMED_OUT status (low priority)
3. Fix test example docs (trivial)

---

## Next Steps

**Immediate** (Required):
1. Activate workflow in n8n UI: https://vpsn8n.xicon.co.kr
2. Run end-to-end test with real image input
3. Verify image generation and Supabase updates

**Follow-up** (Recommended before production launch):
1. Implement polling timeout (15 minutes)
2. Handle TIMED_OUT status (10 minutes)
3. Update test example docs (2 minutes)

---

## References

- Architect verification: 2026-02-11 11:15 KST
- All critical fixes verified in source code
- No hard blockers identified
- Workflow approved for activation and testing
