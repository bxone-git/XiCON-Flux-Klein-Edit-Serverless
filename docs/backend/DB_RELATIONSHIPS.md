# XiCON 데이터베이스 관계도 (DB_RELATIONSHIPS)

> works, files, generation_jobs 테이블 간의 관계와 데이터 흐름을 상세히 문서화합니다.

---

## 개요

XiCON의 핵심 데이터 흐름은 **생성 요청 → 작업 큐 → 비동기 처리 → 결과 파일 저장**으로 이루어집니다. 이 문서는 이 프로세스를 주도하는 세 가지 테이블 간의 관계를 상세히 설명합니다.

---

## Entity Relationship Diagram

```mermaid
erDiagram
    users ||--o{ projects : "1:N"
    users ||--o{ works : "1:N"
    users ||--o{ files : "1:N"
    projects ||--o{ works : "1:N"
    works ||--|| files : "1:1 output"
    works ||--o| files : "1:1 thumbnail"
    works ||--o{ generation_jobs : "1:N"
    works }o--|| works : "branding_report_id (self-ref)"
    templates ||--o{ works : "1:N"

    users : uuid id PK
    users : string email
    users : int subscription_credits
    users : int purchased_credits

    projects : uuid id PK
    projects : uuid user_id FK
    projects : string name

    works : uuid id PK
    works : uuid user_id FK
    works : uuid project_id FK
    works : uuid template_id FK
    works : uuid branding_report_id FK (self)
    works : uuid batch_id
    works : uuid output_file_id FK (1:1)
    works : uuid thumbnail_file_id FK (1:1)
    works : string type
    works : string status
    works : jsonb input_data
    works : jsonb output_data
    works : boolean is_public
    works : string idempotency_key

    files : uuid id PK
    files : uuid user_id FK
    files : uuid work_id FK
    files : uuid project_id FK
    files : string bucket_id
    files : string file_path
    files : string file_url

    generation_jobs : uuid id PK
    generation_jobs : uuid work_id FK
    generation_jobs : string status
    generation_jobs : int priority

    templates : uuid id PK
    templates : string work_type
    templates : uuid output_file_id FK
```

---

## works 테이블 상세

### 역할

모든 종류의 생성 컨텐츠(브랜딩 리포트, 마케팅 문구, 홍보 이미지, 영상)를 통합 관리하는 핵심 테이블입니다.

### 주요 컬럼

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | uuid | PK - 생성물 고유 ID |
| `user_id` | uuid | FK → users.id (소유자) |
| `project_id` | uuid | FK → projects.id (프로젝트 소속) |
| `template_id` | uuid | FK → templates.id (이미지/영상만) |
| `type` | text | 생성 타입: `branding_report`, `marketing_copy`, `promotional_image`, `video_content` |
| `status` | text | 상태: `pending` → `processing` → `completed` / `failed` |
| `input_data` | jsonb | 생성 입력 데이터 (템플릿 필드값 포함) |
| `output_data` | jsonb | AI 생성 메타데이터 (프롬프트, 모델 설정, 시드, 처리 시간, 토큰 사용량, 에러 메시지) |
| `output_file_id` | uuid | FK → files.id (결과 파일) - **1 work : 1 file 관계** |
| `thumbnail_file_id` | uuid | FK → files.id (썸네일 파일) - **1 work : 1 file 관계** |
| `branding_report_id` | uuid | FK → works.id (자기 참조) - 마케팅 문구/이미지/영상이 참조하는 브랜딩 리포트 |
| `batch_id` | uuid | 배치 생성 그룹 ID - 같은 요청에서 여러 work 생성 시 그룹화 (예: 4개 이미지 출력) |
| `idempotency_key` | text | 중복 요청 방지 키 (5분 TTL) |
| `credits_used` | int | 사용된 총 크레딧 |
| `subscription_credits_used` | int | 차감된 정기 크레딧 수량 |
| `purchased_credits_used` | int | 차감된 충전 크레딧 수량 |
| `is_public` | boolean | 공개 여부 (기본값: false) |
| `like_count` | int | 좋아요 수 (비정규화) |
| `favorite_count` | int | 즐겨찾기 수 (비정규화) |
| `created_at` | timestamptz | 생성일 |
| `deleted_at` | timestamptz | 휴지통 이동 시간 (NULL = 활성) |
| `timeout_at` | timestamptz | 타임아웃 시점 (pg_cron이 이 시간 이후 자동 실패 처리) |

### 상태 전환 다이어그램

```
pending
   ↓
processing (n8n이 작업 시작)
   ↓
completed (성공) OR failed (실패)
```

**상태 전환 주체:**
- `pending` → `processing`: n8n이 generation_jobs 상태를 `taken`으로 변경할 때
- `processing` → `completed/failed`: n8n이 작업 완료/실패 후 works 직접 업데이트

### 배치 그룹화 (batch_id)

사용자가 "출력 4장"을 선택하면:
1. 4개의 독립적인 work 생성
2. 모두 같은 `batch_id` 할당
3. 각 work는 독립적으로 공개/비공개, 삭제, 피드백 가능

```
Batch ID: abc123
├─ Work 1: status=processing
├─ Work 2: status=completed
├─ Work 3: status=pending
└─ Work 4: status=failed
```

### 중복 요청 방지 (idempotency_key)

- **목적**: 네트워크 재시도나 사용자 중복 클릭 방지
- **형식**: `{user_id}:{generation_type}:{input_hash}:{timestamp}`
- **TTL**: 5분 (생성 시작 후 5분 이내 같은 키로 재요청 시 기존 work 반환)
- **이점**: 크레딧 중복 차감 방지, 네트워크 안정성 향상

---

## generation_jobs 테이블 상세

### 역할

비동기 컨텐츠 생성 작업을 관리하는 **Fire & Forget 패턴**의 작업 큐입니다.

### 관계: 1 work : N jobs

**왜 N개 가능한가?**
- 생성 실패 시 재시도를 위해 **새로운 job을 생성**
- 같은 work에 대해 여러 job이 순차적으로 생성될 수 있음

**예시:**
```
Work ID: xyz789 (marketing_copy)
├─ Job 1: status=pending → taken → 실패 (네트워크 오류)
├─ Job 2: status=pending → taken → 실패 (GPU 부족)
└─ Job 3: status=pending → taken → 성공
```

### 주요 컬럼

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | uuid | PK - 작업 고유 ID |
| `work_id` | uuid | FK → works.id (생성 결과 기록용) |
| `status` | text | 상태: `pending` (대기) → `taken` (처리 중) |
| `priority` | int | 우선순위 (높을수록 먼저 처리) |
| `created_at` | timestamptz | 작업 생성 시간 |

### 상태 흐름

```
pending (Edge Function이 INSERT)
   ↓
Database Webhook이 자동으로 n8n 웹훅 호출
   ↓
taken (n8n이 상태 변경)
   ↓
완료 후 DELETE (n8n이 작업 완료 시 삭제)
```

### Fire & Forget 패턴

```
1. 클라이언트: POST /functions/v1/generate 요청
2. Edge Function: 작업 검증 및 크레딧 차감
3. Edge Function: generation_jobs INSERT (status: pending)
4. Edge Function: 202 Accepted 응답 (클라이언트에게 즉시 반환)
5. [클라이언트가 기다리지 않음]
6. Database Webhook: generation_jobs INSERT 감지
7. Webhook: n8n에 POST 요청
8. n8n: 작업을 `taken`으로 변경 후 처리
9. n8n: 완료 후 generation_jobs DELETE
10. Realtime: 클라이언트에게 상태 업데이트 브로드캐스트
```

**장점:**
- Edge Function이 n8n 응답을 기다리지 않음
- 사용자 경험 향상 (빠른 응답)
- n8n 워커 부하 분산 가능

---

## files 테이블 상세

### 역할

모든 Storage 버킷의 파일 메타데이터를 중앙에서 관리합니다.

### 주요 컬럼

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | uuid | PK |
| `bucket_id` | text | 버킷 이름 (works, uploads, avatars, templates, assets 등) |
| `file_path` | text | Storage 내 전체 경로 |
| `file_name` | text | 원본 파일명 (다운로드용) |
| `file_size` | int | 파일 크기 (bytes) |
| `file_type` | text | MIME 타입 (image/jpeg, video/mp4, application/pdf 등) |
| `width` | int | 이미지/영상 너비 (px) - NULL 가능 |
| `height` | int | 이미지/영상 높이 (px) - NULL 가능 |
| `duration` | int | 영상 길이 (초) - NULL 가능 |
| `user_id` | uuid | FK → users.id (파일 소유자) |
| `work_id` | uuid | FK → works.id (생성물 파일인 경우) |
| `project_id` | uuid | FK → projects.id (업로드 파일인 경우) |
| `file_url` | text | Storage 공개 URL (트리거로 자동 생성) |
| `created_at` | timestamptz | 업로드 시간 |
| `deleted_at` | timestamptz | Soft delete (정리 작업용) |

### 버킷 타입과 경로 패턴

| 버킷 | 용도 | 경로 패턴 |
|------|------|---------|
| `works` | 생성된 결과물 | `works/{user_id}/{work_id}/output.{ext}` |
| `works` | 생성된 썸네일 | `works/{user_id}/{work_id}/thumbnail.{ext}` |
| `uploads` | 사용자 업로드 | `uploads/{user_id}/{project_id}/{uuid}.{ext}` |
| `avatars` | 프로필 이미지 | `avatars/{user_id}/avatar.{ext}` |
| `templates` | 템플릿 미리보기 | `templates/{template_id}/preview.{ext}` |
| `assets` | 정적 자산 | `assets/banners/{filename}.{ext}` |

### works 테이블과의 관계

```
works.output_file_id → files.id (1:1)
  - works에서 output_file_id가 NOT NULL이면 해당 files 레코드 참조
  - 생성 완료 후 n8n이 파일 업로드 → files INSERT → works.output_file_id 업데이트

works.thumbnail_file_id → files.id (1:1)
  - 썸네일이 있으면 참조
  - 이미지/영상 타입에서만 주로 사용
```

### file_url 자동 생성 (트리거)

**트리거명:** `trg_generate_file_url`

**동작 시점:** files 테이블 INSERT/UPDATE 시

**로직:**
```sql
file_url = 'https://{project_id}.supabase.co/storage/v1/object/public/{bucket_id}/{file_path}'
```

**효과:**
- 파일 업로드 시 file_url이 자동 생성됨
- 수동으로 URL을 생성할 필요 없음
- works 상세 조회 시 file_url이 바로 사용 가능

---

## 트리거 동작 상세

### 1. handle_new_user (회원가입 자동 생성)

**트리거:** auth.users INSERT 시

**동작:**
```
1. users 테이블에 프로필 생성
   - 닉네임 충돌 방지 (suffix 추가)
   - email, provider, provider_account_id 저장

2. projects 테이블에 기본 프로젝트 생성
   - name: "내 첫 프로젝트"

3. subscriptions 테이블에 STARTER 플랜 할당
   - plan_id: STARTER 플랜
   - status: active
   - expires_at: 9999-12-31 (무기한)

4. credit_transactions 테이블에 웰컴 크레딧 기록
   - type: subscription
   - amount: +50 (초기 웰컴 크레딧)

5. users.subscription_credits 업데이트
   - 50 크레딧 할당
```

### 2. trg_refund_credits_on_failure (실패 시 환불)

**트리거:** works UPDATE 시 (status → 'failed')

**동작:**
```
1. works.subscription_credits_used 만큼 users.subscription_credits에 더하기
2. works.purchased_credits_used 만큼 users.purchased_credits에 더하기
3. credit_transactions 레코드 생성
   - type: refund
   - amount: -(subscription_credits_used + purchased_credits_used)
   - description: "생성 실패로 인한 크레딧 환불"
```

**핵심 원칙:**
- 구독 크레딧에서 차감했으면 구독 크레딧으로 환불
- 구매 크레딧에서 차감했으면 구매 크레딧으로 환불

### 3. trg_notify_work_status_change (상태 변경 알림)

**트리거:** works UPDATE 시 (status 변경)

**동작:**
```
status = 'completed' 경우:
├─ notifications INSERT
├─ type: generation_completed
├─ title: "생성 완료"
└─ data: { work_id, work_type }

status = 'failed' 경우:
├─ notifications INSERT
├─ type: generation_failed
├─ title: "생성 실패"
└─ data: { work_id, failure_reason, refunded_credits }
```

**Realtime 브로드캐스트:**
```
채널: notifications:{user_id}
이벤트: INSERT
→ 클라이언트가 실시간으로 알림 수신
```

### 4. trg_generate_file_url (파일 URL 자동 생성)

**트리거:** files INSERT/UPDATE 시

**로직:**
```sql
UPDATE files
SET file_url = 'https://{project_id}.supabase.co/storage/v1/object/public/' || bucket_id || '/' || file_path
WHERE id = NEW.id AND file_url IS NULL;
```

### 5. Database Webhook Triggers (n8n 연동)

**목적:** PostgreSQL 데이터베이스 이벤트를 자동으로 n8n 웹훅으로 전송

#### 아키텍처 결정: Broadcast 패턴 (ADR-2026-02-04)

**설계 원칙:** 모든 트리거가 모든 INSERT에 대해 발동하고, n8n workflow가 자기 타입만 필터링하여 처리

```
┌─────────────────────────────────────────────────────────────────┐
│ generation_jobs INSERT                                          │
└─────────────────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
   │ marketing-  │     │ image-edit  │     │ video-dance │
   │ report      │     │ -qwen       │     │             │
   │ webhook     │     │ webhook     │     │ webhook     │
   └──────┬──────┘     └──────┬──────┘     └──────┬──────┘
          │                   │                   │
          ▼                   ▼                   ▼
   ┌─────────────────────────────────────────────────────────────┐
   │ 각 n8n workflow: WHERE w.type = '자기타입' 으로 필터링       │
   │ → 매칭되면 처리, 매칭 안되면 조용히 종료                      │
   └─────────────────────────────────────────────────────────────┘
```

**왜 이 패턴을 선택했는가?**

| 고려사항 | Smart Trigger (대안) | Broadcast (선택) |
|----------|---------------------|------------------|
| 트리거 부하 | ❌ 매 INSERT마다 works JOIN | ✅ 단순 HTTP 호출 |
| 새 타입 추가 | ❌ 트리거 함수 수정 필요 | ✅ n8n workflow만 추가 |
| 장애 격리 | ❌ 트리거 오류 시 전체 중단 | ✅ 개별 workflow 독립 |
| 수평 확장 | ❌ DB 트리거 확장 어려움 | ✅ n8n 워커 확장 용이 |
| 배포 독립성 | ❌ DB 배포 필요 | ✅ n8n만 배포 |

**예상되는 동작:**
- 1개 INSERT → N개 webhook 호출 (현재 4개)
- 매칭되지 않는 n8n workflow는 즉시 종료 (에러 아님)
- n8n 로그에 "No pending jobs" 메시지 발생 가능 (정상)

**n8n workflow 필터링 쿼리 패턴:**
```sql
SELECT ...
FROM generation_jobs gj
INNER JOIN works w ON w.id = gj.work_id
WHERE gj.status = 'pending'
  AND w.type = 'branding_report'  -- 각 workflow가 자기 타입만 필터링
ORDER BY gj.priority DESC, gj.created_at ASC
LIMIT 1
FOR UPDATE SKIP LOCKED  -- 동시성 처리 최적화
```

---

**설정된 트리거들:**

#### XiCON_MARCOMM (브랜딩 리포트)
```sql
CREATE TRIGGER "XiCON_MARCOMM"
  AFTER INSERT ON generation_jobs
  FOR EACH ROW
  EXECUTE FUNCTION supabase_functions.http_request(
    'https://vpsn8n.xicon.co.kr/webhook/marketing-report',
    'POST',
    '{"Content-type":"application/json"}',
    '{}',
    '5000'
  );
```

**동작:**
- generation_jobs INSERT 감지 (모든 타입)
- n8n marketing-report webhook 호출
- n8n이 `w.type = 'branding_report'` 필터링 후 처리

#### XiCON_Supabase_Image-edit-qwen (홍보 이미지)
```sql
CREATE TRIGGER "XiCON_Supabase_Image-edit-qwen_2511"
  AFTER INSERT ON generation_jobs
  FOR EACH ROW
  EXECUTE FUNCTION supabase_functions.http_request(
    'https://vpsn8n.xicon.co.kr/webhook/image-edit-qwen',
    'POST',
    '{"Content-type":"application/json"}',
    '{}',
    '5000'
  );
```

#### XiCON_Wan_SCAIL_Dance (영상 컨텐츠)
```sql
CREATE TRIGGER "XiCON_Wan_SCAIL_Dance"
  AFTER INSERT ON generation_jobs
  FOR EACH ROW
  EXECUTE FUNCTION supabase_functions.http_request(
    'https://vpsn8n.xicon.co.kr/webhook/wan-scail-dance',
    'POST',
    '{"Content-type":"application/json"}',
    '{}',
    '5000'
  );
```

#### XiCON_Supabase_Submit_v0 (레거시/기타)
```sql
CREATE TRIGGER "XiCON_Supabase_Submit_v0"
  AFTER INSERT ON generation_jobs
  FOR EACH ROW
  EXECUTE FUNCTION supabase_functions.http_request(
    'https://vpsn8n.xicon.co.kr/webhook/ade44f2a-e59c-44e5-921a-193499a32c86',
    'POST',
    '{"Content-type":"application/json"}',
    '{}',
    '5000'
  );
```

### 6. fail_stuck_works (pg_cron - 타임아웃 자동 실패)

**스케줄:** `*/2 * * * *` (2분마다 실행)

**목적:** n8n 워커가 응답하지 않아 stuck된 작업을 자동으로 실패 처리

**동작:**
```sql
-- 1. timeout_at < NOW()인 작업 찾기
SELECT * FROM works
WHERE status IN ('pending', 'processing')
  AND timeout_at < NOW();

-- 2. 각 작업에 대해:
UPDATE works
SET status = 'failed',
    output_data = jsonb_set(output_data, '{failure_reason}', '"timeout"')
WHERE id = work_id;

-- 3. 트리거 자동 실행:
--    - trg_refund_credits_on_failure: 크레딧 환불
--    - trg_notify_work_status_change: 실패 알림
--    - generation_jobs DELETE: 작업 제거
```

**타임아웃 계산:**
```
timeout_at = created_at + (estimated_time × 2) + 2분 버퍼

예시:
- marketing_copy (30초): 3분 후 자동 실패
- promotional_image (60초): 4분 후 자동 실패
- branding_report (120초): 6분 후 자동 실패
- video_content (180초): 8분 후 자동 실패
```

**Race Condition 방지:**

n8n이 작업 완료를 시도할 때:
```sql
UPDATE works
SET status = 'completed',
    output_data = $output_data,
    completed_at = NOW()
WHERE id = $work_id
  AND status IN ('pending', 'processing');  -- 중요!
```

**효과:**
- pg_cron이 이미 실패 처리했으면 UPDATE 대상이 없음 (0행)
- n8n이 정상 완료했으면 UPDATE 성공 (1행)
- 타임아웃 실패가 n8n 성공으로 덮어써지지 않음

---

## 브랜딩 리포트 연계 관계

### 관계 구조

```
Branding Report (works.type = branding_report)
├─ Marketing Copy (works.branding_report_id → branding_report.id)
├─ Promotional Image (works.branding_report_id → branding_report.id)
└─ Video Content (works.branding_report_id → branding_report.id)
```

### 생성 흐름

1. **사용자가 브랜딩 리포트 생성**
   - works INSERT (type='branding_report', branding_report_id=NULL)
   - generation_jobs INSERT
   - Edge Function: 202 응답

2. **브랜딩 리포트 완료**
   - n8n: works UPDATE (status='completed', output_file_id=file_id)
   - 파일 URL 자동 생성

3. **사용자가 마케팅 문구 생성**
   - works INSERT (type='marketing_copy', branding_report_id={위 리포트 ID})
   - generation_jobs INSERT
   - n8n이 branding_report의 input_data와 output_data 활용

4. **마케팅 문구 완료**
   - 같은 과정으로 완료

### 쿼리 예시

**특정 브랜딩 리포트의 모든 파생 작업 조회:**
```sql
SELECT *
FROM works
WHERE branding_report_id = 'abc-123'
  AND deleted_at IS NULL;

-- 결과: marketing_copy, promotional_image, video_content 등
```

---

## 알려진 이슈

### Issue: output_file_id 미연결 문제

#### 현상
2026-02-01 11:00 이전에 완료된 works 중 `output_file_id`가 NULL인 경우가 존재합니다.

**영향을 받는 작업:**
```sql
SELECT COUNT(*)
FROM works
WHERE status = 'completed'
  AND output_file_id IS NULL
  AND created_at < '2026-02-01 11:00:00';
```

#### 원인
n8n 워크플로우에서 파일 생성 후 Supabase Storage에 업로드는 성공했으나, `files` 테이블 INSERT와 `works.output_file_id` 업데이트를 누락했습니다.

**n8n 워크플로우 검증 필요:**
1. 파일 생성 완료
2. Storage에 업로드
3. files 테이블 INSERT (bucket_id, file_path, file_name, file_size, file_type, user_id, work_id)
4. works UPDATE (output_file_id=file.id)

#### 영향
- 라이브러리에서 해당 작업의 결과 파일 조회 불가
- 갤러리에서 이미지/영상이 표시되지 않음
- API 응답에서 file_url이 NULL

#### 해결 방법

**1. n8n 워크플로우 수정 (근본 해결)**
```javascript
// n8n 워크플로우에 추가 스텝:
// Step 1: 파일 생성 및 업로드
// Step 2: files 테이블 INSERT
// Step 3: works UPDATE (output_file_id 설정)
```

**2. 기존 데이터 복구 (임시)**
```sql
-- 파일이 Storage에는 있으나 DB에 연결되지 않은 경우:
INSERT INTO files (
  bucket_id, file_path, file_name, file_size, file_type, user_id, work_id, file_id
) SELECT
  'works' as bucket_id,
  CONCAT('user_id/work_id/output.ext') as file_path,
  'output.ext' as file_name,
  0 as file_size,
  'image/jpeg' as file_type,
  w.user_id,
  w.id as work_id,
  gen_random_uuid()::text as file_id
FROM works w
WHERE w.status = 'completed'
  AND w.output_file_id IS NULL
  AND w.created_at < '2026-02-01 11:00:00'
RETURNING id;

-- 반환된 files.id를 사용하여 works 업데이트:
UPDATE works
SET output_file_id = (SELECT id FROM files WHERE work_id = works.id LIMIT 1)
WHERE status = 'completed'
  AND output_file_id IS NULL;
```

---

## 관련 문서

| 문서 | 용도 |
|------|------|
| [OVERVIEW.md](./OVERVIEW.md) | 시스템 아키텍처, 기술 스택, 핵심 개념 |
| [supabase-api-plan.md](./supabase-api-plan.md) | 데이터베이스 스키마 상세, API 엔드포인트, RLS 정책 |
| [template-config-spec.md](./template-config-spec.md) | 템플릿 form_fields와 request_dto 명세 |

---

## 색인

### 주요 관계도
- **users (1) → (N) projects**
- **users (1) → (N) works**
- **projects (1) → (N) works**
- **works (1) → (1) files** (output_file_id)
- **works (1) → (1) files** (thumbnail_file_id)
- **works (1) → (N) generation_jobs**
- **works (N) → (1) works** (branding_report_id - 자기참조)
- **templates (1) → (N) works**

### 주요 트리거
- `handle_new_user` - 회원가입 자동 생성
- `trg_refund_credits_on_failure` - 실패 시 환불
- `trg_notify_work_status_change` - 상태 변경 알림
- `trg_generate_file_url` - 파일 URL 자동 생성
- `XiCON_MARCOMM` - n8n 웹훅 (Broadcast 패턴, 브랜딩 리포트)
- `XiCON_Supabase_Image-edit-qwen_2511` - n8n 웹훅 (Broadcast 패턴, 홍보 이미지)
- `XiCON_Wan_SCAIL_Dance` - n8n 웹훅 (Broadcast 패턴, 영상 컨텐츠)
- `XiCON_Supabase_Submit_v0` - n8n 웹훅 (Broadcast 패턴, 레거시)
- `fail_stuck_works` - 타임아웃 자동 실패 (pg_cron)

### 주요 패턴
- **Fire & Forget**: Edge Function이 job INSERT 후 즉시 응답
- **Broadcast 웹훅**: 모든 트리거가 모든 INSERT에 발동, n8n이 자기 타입만 필터링 (ADR-2026-02-04)
- **배치 그룹화**: 같은 요청의 여러 work를 batch_id로 그룹화
- **중복 요청 방지**: idempotency_key로 5분 내 재요청 감지
- **자동 환불**: 실패 시 트리거가 원래 출처로 정확히 환불
- **FOR UPDATE SKIP LOCKED**: n8n의 동시성 처리를 위한 PostgreSQL 큐 패턴
- **Race Condition 방지**: n8n이 상태 조건절 확인 후 UPDATE
