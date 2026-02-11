# XiCON Admin Supabase API

> Admin 대시보드에서 사용하는 Supabase API 및 서버 액션 명세

## 개요

XiCON Admin 패널은 서비스 관리자가 사용자, 콘텐츠, 결제, 템플릿 등을 관리할 수 있는 전용 인터페이스입니다. 모든 Admin API는 JWT 기반 권한 검증을 거쳐 실행됩니다.

---

## 인증 및 권한 부여

### Admin 역할 구조

Admin 권한은 Supabase Auth의 `app_metadata`에 저장됩니다:

```typescript
// JWT app_metadata 구조
{
  role: "admin" | "super_admin" | null
}
```

### 권한 검증 패턴

모든 Admin 서버 액션에서 사용하는 권한 검증:

```typescript
// features/admin/server/actions.ts
const { session } = await safeGetSession();
const isAdmin = session?.user?.app_metadata?.role === "admin";

if (!isAdmin) {
  return failure("관리자 권한이 필요합니다.", "UNAUTHORIZED");
}
```

### RLS Helper Function

데이터베이스 레벨에서의 Admin 권한 검증:

```sql
-- 현재 사용자가 admin인지 확인하는 헬퍼 함수
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
BEGIN
  RETURN (
    SELECT COALESCE(
      (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin',
      FALSE
    )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

---

## Admin RLS 정책

### 정책 구조

Admin은 모든 테이블에 대해 확장된 접근 권한을 가집니다:

| 테이블 | SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|--------|
| users | ✓ | - | ✓ | - |
| projects | ✓ | - | ✓ | - |
| works | ✓ | - | ✓ | ✓ |
| files | ✓ | - | - | - |
| templates | ✓ | ✓ | ✓ | ✓ |
| generation_jobs | ✓ | - | ✓ | ✓ |
| credit_transactions | ✓ | ✓ | - | - |
| credit_packages | ✓ | ✓ | ✓ | ✓ |
| subscription_plans | ✓ | ✓ | ✓ | ✓ |
| subscriptions | ✓ | - | ✓ | - |
| payment_methods | ✓ | - | - | - |
| payment_history | ✓ | - | - | - |
| notifications | ✓ | ✓ | - | - |
| banners | ✓ | ✓ | ✓ | ✓ |
| partners | ✓ | ✓ | ✓ | ✓ |
| faqs | ✓ | ✓ | ✓ | ✓ |

### RLS 정책 예시

```sql
-- users 테이블 Admin 읽기 정책
CREATE POLICY "admin_select_users" ON users
  FOR SELECT TO authenticated
  USING (is_admin());

-- users 테이블 Admin 수정 정책
CREATE POLICY "admin_update_users" ON users
  FOR UPDATE TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());

-- templates 테이블 Admin 전체 권한
CREATE POLICY "admin_all_templates" ON templates
  FOR ALL TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());
```

---

## Admin 서버 액션 API

모든 서버 액션은 `/features/admin/server/actions.ts`에 위치하며, 동일한 응답 패턴을 따릅니다:

```typescript
// 성공 응답
{ success: true, data: T }

// 실패 응답
{ success: false, error: string, code?: string }
```

---

### 1. 사용자 관리

#### 크레딧 수동 조정

```typescript
adjustUserCredits(params: {
  userId: string;
  creditType: "subscription" | "purchased";
  amount: number;  // 양수: 지급, 음수: 차감
  reason: string;
}): Promise<ActionResult<void>>
```

**동작:**
1. 사용자 현재 크레딧 잔액 조회
2. 지정된 타입의 크레딧 업데이트
3. `credit_transactions` 레코드 생성 (감사 추적)
4. 실패 시 자동 롤백

**credit_transactions 기록:**
- `type`: `admin_grant` (지급) 또는 `admin_deduct` (차감)
- `description`: 관리자가 입력한 사유

---

### 2. 생성물(Works) 관리

#### 공개/비공개 전환

```typescript
toggleWorkPublic(params: {
  workId: string;
  isPublic: boolean;
}): Promise<ActionResult<void>>
```

**동작:**
- `works.is_public` 값 업데이트
- 공개 시 갤러리에 노출, 비공개 시 숨김

#### 생성물 삭제 (Soft Delete)

```typescript
deleteWork(params: {
  workId: string;
}): Promise<ActionResult<void>>
```

**동작:**
- `works.deleted_at` 타임스탬프 설정
- 사용자 휴지통에서 복구 가능

---

### 3. 작업(Jobs) 관리

#### 작업 재시도

```typescript
retryJob(params: {
  jobId: string;
}): Promise<ActionResult<void>>
```

**동작:**
1. 실패한 작업의 `status`를 `pending`으로 변경
2. n8n이 다시 작업을 픽업하여 처리

#### 작업 강제 실패

```typescript
failJob(params: {
  jobId: string;
  reason?: string;
}): Promise<ActionResult<void>>
```

**동작:**
1. `generation_jobs.status`를 `failed`로 변경
2. 연결된 `works.status`도 `failed`로 변경
3. DB 트리거가 자동으로 크레딧 환불 처리

---

### 4. 템플릿 관리

#### 템플릿 생성

```typescript
createTemplate(params: {
  work_type: "promotional_image" | "video_content";
  template_name: string;      // AI 워커 식별자
  title: string;              // UI 표시 제목
  description?: string;
  estimated_time?: number;    // 예상 시간 (초)
  form_fields?: Json;         // 동적 폼 필드 정의
  request_dto?: Json;         // API 요청 스키마
}): Promise<ActionResult<{ id: string }>>
```

#### 템플릿 수정

```typescript
updateTemplate(params: {
  templateId: string;
  data: {
    title?: string;
    description?: string;
    work_type?: string;
    is_active?: boolean;
    estimated_time?: number;
    form_fields?: Json;
    thumbnail_file_id?: string;
  };
}): Promise<ActionResult<void>>
```

#### 템플릿 활성화/비활성화

```typescript
toggleTemplateActive(params: {
  templateId: string;
  isActive: boolean;
}): Promise<ActionResult<void>>
```

**동작:**
- `is_active = false`: 사용자 UI에서 숨김
- 비활성화해도 기존 생성물에는 영향 없음

#### 템플릿 순서 변경

```typescript
reorderTemplate(params: {
  templateId: string;
  newOrder: number;
  swapWithId: string;      // 교환 대상 템플릿
  swapWithOrder: number;   // 교환 대상 순서
}): Promise<ActionResult<void>>
```

**동작:**
- 두 템플릿의 `display_order` 값을 교환
- 트랜잭션으로 원자적 처리

#### 템플릿 삭제

```typescript
deleteTemplate(params: {
  templateId: string;
}): Promise<ActionResult<void>>
```

---

### 5. 배너 관리

#### 배너 생성

```typescript
createBanner(params: {
  title: string;
  description?: string;
  image_url?: string;
  link_url?: string;
  link_target?: "_blank" | "_self";
  started_at?: string;     // ISO 8601
  ended_at?: string;       // ISO 8601
  is_active?: boolean;
}): Promise<ActionResult<{ id: string }>>
```

#### 배너 수정

```typescript
updateBanner(params: {
  bannerId: string;
  data: {
    title?: string;
    description?: string;
    image_url?: string;
    link_url?: string;
    link_target?: string;
    started_at?: string;
    ended_at?: string;
    is_active?: boolean;
  };
}): Promise<ActionResult<void>>
```

#### 배너 활성화/비활성화

```typescript
toggleBannerActive(params: {
  bannerId: string;
  isActive: boolean;
}): Promise<ActionResult<void>>
```

#### 배너 삭제

```typescript
deleteBanner(params: {
  bannerId: string;
}): Promise<ActionResult<void>>
```

---

### 6. 파트너(광고 배너) 관리

#### 파트너 테이블 스키마

파트너 테이블은 광고/제휴 배너 관리를 위해 확장된 스키마를 사용합니다:

```sql
CREATE TABLE partners (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,              -- 배너명
  logo_url TEXT,                   -- 로고/배너 이미지
  website_url TEXT,                -- 링크 URL
  description TEXT,                -- 설명
  is_active BOOLEAN DEFAULT true,  -- 활성화 상태
  display_order INTEGER DEFAULT 0, -- 표시 순서

  -- 광고 관리 확장 필드
  client_name TEXT,                -- 고객사명
  project_name TEXT,               -- 프로젝트명
  start_date DATE,                 -- 게재 시작일
  end_date DATE,                   -- 게재 종료일
  payment_amount INTEGER,          -- 결제 금액

  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
```

#### 파트너 생성

```typescript
createPartner(params: {
  name: string;            // 배너명
  logo_url?: string;
  website_url?: string;
  description?: string;
  client_name?: string;    // 고객사
  project_name?: string;   // 프로젝트
  start_date?: string;     // YYYY-MM-DD
  end_date?: string;       // YYYY-MM-DD
  payment_amount?: number; // 결제 금액
  is_active?: boolean;
}): Promise<ActionResult<{ id: string }>>
```

#### 파트너 수정

```typescript
updatePartner(params: {
  partnerId: string;
  data: {
    name?: string;
    logo_url?: string;
    website_url?: string;
    description?: string;
    client_name?: string;
    project_name?: string;
    start_date?: string;
    end_date?: string;
    payment_amount?: number;
    is_active?: boolean;
  };
}): Promise<ActionResult<void>>
```

#### 파트너 활성화/비활성화

```typescript
togglePartnerActive(params: {
  partnerId: string;
  isActive: boolean;
}): Promise<ActionResult<void>>
```

#### 파트너 삭제

```typescript
deletePartner(params: {
  partnerId: string;
}): Promise<ActionResult<void>>
```

---

### 7. FAQ 관리

#### FAQ 생성

```typescript
createFaq(params: {
  question: string;
  answer: string;
  category?: string;
  is_active?: boolean;
}): Promise<ActionResult<{ id: string }>>
```

#### FAQ 수정

```typescript
updateFaq(params: {
  faqId: string;
  data: {
    question?: string;
    answer?: string;
    category?: string;
    is_active?: boolean;
  };
}): Promise<ActionResult<void>>
```

#### FAQ 활성화/비활성화

```typescript
toggleFaqActive(params: {
  faqId: string;
  isActive: boolean;
}): Promise<ActionResult<void>>
```

#### FAQ 순서 변경

```typescript
reorderFaq(params: {
  faqId: string;
  direction: "up" | "down";
}): Promise<ActionResult<void>>
```

**동작:**
- 인접한 FAQ와 `display_order` 교환
- 이미 최상단/최하단이면 무시

#### FAQ 삭제

```typescript
deleteFaq(params: {
  faqId: string;
}): Promise<ActionResult<void>>
```

---

### 8. 구독 요금제 관리

#### 요금제 생성

```typescript
createSubscriptionPlan(params: {
  name: string;               // 플랜명 (예: "Basic", "Pro")
  description?: string;
  monthly_price: number;      // 월간 가격
  yearly_price?: number;      // 연간 가격
  monthly_credits: number;    // 월간 크레딧 할당량
  features?: string[];        // 기능 목록
  is_active?: boolean;
}): Promise<ActionResult<{ id: string }>>
```

#### 요금제 수정

```typescript
updateSubscriptionPlan(params: {
  planId: string;
  data: {
    name?: string;
    description?: string;
    monthly_price?: number;
    yearly_price?: number;
    monthly_credits?: number;
    features?: string[];
    is_active?: boolean;
  };
}): Promise<ActionResult<void>>
```

---

### 9. 크레딧 상품 관리

#### 크레딧 상품 생성

```typescript
createCreditPackage(params: {
  name: string;           // 상품명
  description?: string;
  credits: number;        // 크레딧 수량
  price: number;          // 가격
  bonus_credits?: number; // 보너스 크레딧
  is_active?: boolean;
}): Promise<ActionResult<{ id: string }>>
```

#### 크레딧 상품 수정

```typescript
updateCreditPackage(params: {
  packageId: string;
  data: {
    name?: string;
    description?: string;
    credits?: number;
    price?: number;
    bonus_credits?: number;
    is_active?: boolean;
  };
}): Promise<ActionResult<void>>
```

---

### 10. 알림 발송

#### 알림 발송

```typescript
sendNotification(params: {
  title: string;
  message: string;
  type: NotificationType;
  targetGroup: TargetGroup;
  targetUserId?: string;    // targetGroup이 "specific"일 때 필수
}): Promise<ActionResult<{ sentCount: number }>>
```

**NotificationType:**
- `system`: 시스템 공지
- `promotion`: 프로모션
- `update`: 서비스 업데이트

**TargetGroup:**
- `all`: 모든 사용자
- `subscribers`: 활성 구독자
- `non_subscribers`: 미구독자
- `expired_subscribers`: 구독 만료자
- `specific`: 특정 사용자 (targetUserId 필수)

**동작:**
1. 타겟 그룹에 해당하는 사용자 목록 조회
2. 각 사용자에게 `notifications` 레코드 생성
3. 발송된 알림 수 반환

---

## Admin 대시보드 데이터 쿼리

### 통계 데이터 조회

Admin 대시보드에서 사용하는 주요 통계 쿼리:

```typescript
// 총 사용자 수
const { count: totalUsers } = await supabase
  .from("users")
  .select("*", { count: "exact", head: true });

// 활성 구독자 수
const { count: activeSubscribers } = await supabase
  .from("subscriptions")
  .select("*", { count: "exact", head: true })
  .eq("status", "active");

// 오늘 생성된 works 수
const { count: todayWorks } = await supabase
  .from("works")
  .select("*", { count: "exact", head: true })
  .gte("created_at", new Date().toISOString().split("T")[0]);

// 총 매출 (이번 달)
const { data: monthlyRevenue } = await supabase
  .from("payment_history")
  .select("amount")
  .eq("status", "completed")
  .gte("created_at", firstDayOfMonth);
```

### 사용자 목록 조회 (페이지네이션)

```typescript
const { data: users, count } = await supabase
  .from("users")
  .select(`
    id,
    email,
    nickname,
    avatar_url,
    role,
    provider,
    subscription_credits,
    purchased_credits,
    created_at,
    subscription:subscriptions!left(
      id,
      status,
      subscription_plan:subscription_plans(name)
    )
  `, { count: "exact" })
  .order("created_at", { ascending: false })
  .range(offset, offset + pageSize - 1);
```

### 생성물 목록 조회 (필터링)

```typescript
const query = supabase
  .from("works")
  .select(`
    id,
    type,
    title,
    status,
    is_public,
    credits_used,
    created_at,
    deleted_at,
    user:users!works_user_id_fkey(id, nickname, email),
    thumbnail_file:files!works_thumbnail_file_id_fkey(file_path, bucket_id)
  `, { count: "exact" });

// 필터 적용
if (type) query.eq("type", type);
if (status) query.eq("status", status);
if (showDeleted) query.not("deleted_at", "is", null);
else query.is("deleted_at", null);

const { data, count } = await query
  .order("created_at", { ascending: false })
  .range(offset, offset + pageSize - 1);
```

---

## 감사 추적 (Audit Trail)

### credit_transactions 테이블

모든 크레딧 변동은 `credit_transactions` 테이블에 기록됩니다:

```sql
CREATE TABLE credit_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id),
  type TEXT NOT NULL,         -- 거래 타입
  amount INTEGER NOT NULL,    -- 변동량 (양수/음수)
  balance_after INTEGER NOT NULL,
  description TEXT,           -- 상세 설명
  work_id UUID REFERENCES works(id),
  created_at TIMESTAMPTZ DEFAULT now()
);
```

**Admin 관련 거래 타입:**
- `admin_grant`: 관리자 크레딧 지급
- `admin_deduct`: 관리자 크레딧 차감

### 변경 이력 추적

주요 테이블의 `updated_at` 필드가 자동으로 업데이트됩니다:

```sql
-- updated_at 자동 업데이트 트리거
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON {table_name}
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();
```

---

## 에러 처리

### 에러 코드

| 코드 | 설명 |
|------|------|
| `UNAUTHORIZED` | Admin 권한 없음 |
| `NOT_FOUND` | 리소스를 찾을 수 없음 |
| `VALIDATION_ERROR` | 입력값 검증 실패 |
| `DATABASE_ERROR` | 데이터베이스 작업 실패 |

### 에러 응답 형식

```typescript
{
  success: false,
  error: "에러 메시지",
  code: "ERROR_CODE"
}
```

---

## 캐시 무효화

모든 Admin 서버 액션은 성공 시 해당 경로의 캐시를 무효화합니다:

```typescript
// 예: 템플릿 토글 후
revalidatePath("/app/admin/templates");

// 예: 알림 발송 후
revalidatePath("/app/admin/notifications");
```

---

## 관련 문서

- [OVERVIEW.md](./OVERVIEW.md) - 시스템 아키텍처 개요
- [supabase-api-plan.md](./supabase-api-plan.md) - 전체 Supabase API 명세
- [template-config-spec.md](./template-config-spec.md) - 템플릿 설정 명세
