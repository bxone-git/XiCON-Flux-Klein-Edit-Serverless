# Admin Dashboard 아키텍처 및 구현 가이드

> Claude Code가 Admin 페이지를 개발하거나 새로운 프로젝트에서 Admin 시스템을 구축할 때 참고하는 설계 문서

## 목차

1. [아키텍처 개요](#아키텍처-개요)
2. [디렉토리 구조](#디렉토리-구조)
3. [권한 시스템 (RLS 기반)](#권한-시스템-rls-기반)
4. [데이터 페칭 패턴](#데이터-페칭-패턴)
5. [Server Actions 패턴](#server-actions-패턴)
6. [활동 로그 시스템](#활동-로그-시스템)
7. [구독 상태 판별 로직](#구독-상태-판별-로직)
8. [주의사항 및 흔한 실수](#주의사항-및-흔한-실수)
9. [새 Admin 페이지 추가 체크리스트](#새-admin-페이지-추가-체크리스트)

---

## 아키텍처 개요

### 핵심 원칙

1. **RLS 기반 권한 관리**: Service Role Key 사용 금지, JWT의 `app_metadata.role`로 권한 판별
2. **Server Component First**: 페이지는 Server Component, 인터랙티브 UI만 Client Component
3. **Server Actions로 뮤테이션**: 모든 데이터 변경은 Server Actions를 통해 수행
4. **활동 로그 기록**: 모든 Admin 액션은 `admin_activity_logs` 테이블에 기록

### 기술 스택

```
Next.js 15 (App Router) + Supabase + TanStack Query
├── 페이지: Server Component (데이터 페칭)
├── 인터랙티브 UI: Client Component
├── 뮤테이션: Server Actions (features/admin/server/actions.ts)
├── 권한: Supabase RLS + JWT app_metadata
└── 상태: URL Search Params (필터/페이지네이션)
```

---

## 디렉토리 구조

```
app/app/admin/
├── layout.tsx                    # Admin 레이아웃 + 권한 체크
├── page.tsx                      # 대시보드
├── users/
│   ├── page.tsx                  # 사용자 목록
│   └── [userId]/page.tsx         # 사용자 상세
├── works/
│   ├── page.tsx                  # 생성물 목록
│   └── [workId]/page.tsx         # 생성물 상세
├── templates/
│   ├── page.tsx                  # 템플릿 목록
│   └── [templateId]/page.tsx     # 템플릿 상세/수정
├── credits/page.tsx              # 크레딧 관리
├── notifications/page.tsx        # 알림 발송
├── activity-logs/page.tsx        # 활동 로그
├── jobs/page.tsx                 # 생성 작업 관리
├── payments/
│   ├── page.tsx                  # 결제 내역
│   ├── plans/page.tsx            # 구독 요금제
│   └── packages/page.tsx         # 크레딧 상품
└── content/
    ├── banners/page.tsx          # 배너 관리
    ├── partners/page.tsx         # 파트너사 관리
    └── faqs/page.tsx             # FAQ 관리

features/admin/
├── components/                   # Admin 전용 UI 컴포넌트
│   ├── dashboard-content.tsx
│   ├── users-table.tsx
│   ├── stats-card.tsx
│   ├── *-edit-modal.tsx          # 편집 모달들
│   └── ...
└── server/
    └── actions.ts                # 모든 Admin Server Actions

constants/
├── routes.ts                     # ROUTES.ADMIN.* 경로 정의
└── nav-items.ts                  # ADMIN_SIDEBAR_MENU_ITEMS 사이드바 메뉴
```

---

## 권한 시스템 (RLS 기반)

### 핵심: Service Role Key 사용 금지

```typescript
// ❌ 절대 사용 금지 - 보안 위험
import { createClient } from "@supabase/supabase-js";
const adminClient = createClient(url, SERVICE_ROLE_KEY);

// ✅ 올바른 방법 - RLS 정책으로 권한 관리
import { createSupabaseServerClient } from "@/lib/supabase/server";
const supabase = await createSupabaseServerClient();
```

### Admin 권한 부여 방법

```sql
-- Supabase SQL Editor에서 실행
UPDATE auth.users
SET raw_app_meta_data = jsonb_set(
  COALESCE(raw_app_meta_data, '{}'::jsonb),
  '{role}',
  '"admin"'
)
WHERE email = 'admin@example.com';

-- ※ 권한 부여 후 재로그인 필요 (새 JWT 발급)
```

### RLS 정책 패턴

> ⚠️ **중요**: 반드시 JWT 직접 접근 패턴 사용! 서브쿼리 패턴은 동작하지 않을 수 있음

```sql
-- ✅ 올바른 패턴 - JWT 직접 접근
(auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'

-- ❌ 잘못된 패턴 - 서브쿼리 (동작하지 않을 수 있음)
(SELECT raw_app_meta_data ->> 'role' FROM auth.users WHERE id = auth.uid()) = 'admin'
```

```sql
-- 1. Admin 전용 SELECT 정책
CREATE POLICY "Admins can view all [table_name]"
ON public.[table_name] FOR SELECT TO authenticated
USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- 2. Admin 전용 INSERT 정책
CREATE POLICY "Admins can insert [table_name]"
ON public.[table_name] FOR INSERT TO authenticated
WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- 3. Admin 전용 UPDATE 정책
CREATE POLICY "Admins can update [table_name]"
ON public.[table_name] FOR UPDATE TO authenticated
USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- 4. Admin 전용 DELETE 정책
CREATE POLICY "Admins can delete [table_name]"
ON public.[table_name] FOR DELETE TO authenticated
USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
```

### 필수 RLS 정책 테이블

Admin이 접근해야 하는 모든 테이블에 RLS 정책 추가 필요:

| 테이블 | SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|--------|
| users | ✅ | - | ✅ | - |
| subscriptions | ✅ | - | - | - |
| notifications | ✅ | ✅ | - | - |
| admin_activity_logs | ✅ | ✅ | - | - |
| templates | ✅ | ✅ | ✅ | ✅ |
| banners | ✅ | ✅ | ✅ | ✅ |
| partners | ✅ | ✅ | ✅ | ✅ |
| faqs | ✅ | ✅ | ✅ | ✅ |
| works | ✅ | - | ✅ | - |
| credit_transactions | ✅ | ✅ | - | - |
| payment_history | ✅ | - | - | - |
| subscription_plans | ✅ | ✅ | ✅ | - |
| credit_packages | ✅ | ✅ | ✅ | - |
| generation_jobs | ✅ | - | ✅ | - |

---

## 데이터 페칭 패턴

### Server Component 페이지 패턴

```typescript
// app/app/admin/[feature]/page.tsx
import { ScrollArea } from "@/components/ui/scroll-area";
import { FeatureTable } from "@/features/admin/components/feature-table";
import { createAppError } from "@/lib/errors/factory";
import { createSupabaseServerClient } from "@/lib/supabase/server";

interface Props {
  searchParams: Promise<{
    page?: string;
    q?: string;
    // 다른 필터들...
  }>;
}

export default async function AdminFeaturePage({ searchParams }: Props) {
  const params = await searchParams;  // Next.js 15: searchParams는 Promise

  const page = Math.max(1, parseInt(params.page ?? "1", 10));
  const pageSize = 20;
  const q = params.q ?? "";

  const supabase = await createSupabaseServerClient();

  // 데이터 조회
  let query = supabase
    .from("table_name")
    .select("*", { count: "exact" })
    .order("created_at", { ascending: false });

  // 검색 필터
  if (q) {
    query = query.or(`name.ilike.%${q}%,email.ilike.%${q}%`);
  }

  // 페이지네이션
  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;
  query = query.range(from, to);

  const { data, count, error } = await query;

  if (error) throw createAppError(error);

  return (
    <ScrollArea className="h-full">
      <div className="container mx-auto space-y-6 p-6">
        <div>
          <h1 className="text-3xl font-bold">페이지 제목</h1>
          <p className="text-frg-3">설명</p>
        </div>

        <FeatureTable
          data={data ?? []}
          totalCount={count ?? 0}
          page={page}
          pageSize={pageSize}
          q={q}
        />
      </div>
    </ScrollArea>
  );
}
```

### Client Component 테이블 패턴

```typescript
"use client";

import { useRouter, usePathname, useSearchParams } from "next/navigation";
import { useCallback, useTransition } from "react";

interface Props {
  data: DataType[];
  totalCount: number;
  page: number;
  pageSize: number;
  q: string;
}

export function FeatureTable({ data, totalCount, page, pageSize, q }: Props) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [isPending, startTransition] = useTransition();

  // URL 파라미터 업데이트 (필터/페이지 변경)
  const updateParams = useCallback(
    (updates: Record<string, string>) => {
      const params = new URLSearchParams(searchParams.toString());
      Object.entries(updates).forEach(([key, value]) => {
        if (value) {
          params.set(key, value);
        } else {
          params.delete(key);
        }
      });
      startTransition(() => {
        router.push(`${pathname}?${params.toString()}`);
      });
    },
    [pathname, router, searchParams],
  );

  // 렌더링...
}
```

---

## Server Actions 패턴

### 기본 구조

```typescript
// features/admin/server/actions.ts
"use server";

import { revalidatePath } from "next/cache";
import { createAppError } from "@/lib/errors/factory";
import { failure, success, type ActionResult } from "@/lib/server/action-result";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { safeGetSession } from "@/lib/supabase/server-auth";

// 1. Admin 권한 체크
export async function adminAction(params: Params): Promise<ActionResult<ReturnType>> {
  try {
    // 권한 체크
    const { session } = await safeGetSession();
    const isAdmin = session?.user?.app_metadata?.role === "admin";

    if (!isAdmin) {
      return failure("관리자 권한이 필요합니다.", "UNAUTHORIZED");
    }

    const supabase = await createSupabaseServerClient();

    // 2. 비즈니스 로직 수행
    const { data, error } = await supabase
      .from("table")
      .update(params.data)
      .eq("id", params.id);

    if (error) throw createAppError(error);

    // 3. 활동 로그 기록
    await logAdminActivity({
      adminId: session.user.id,
      action: "update",
      resourceType: "resource_name",
      resourceId: params.id,
      description: "설명",
    });

    // 4. 캐시 무효화
    revalidatePath("/app/admin/feature");

    return success(data);
  } catch (error) {
    console.error("[adminAction Error]", error);
    return failure("작업 중 오류가 발생했습니다.");
  }
}
```

### 활동 로그 기록 함수

> ⚠️ **중요**: Supabase는 에러를 throw하지 않고 `{ data, error }` 형태로 반환하므로 반드시 error 체크 필요!

```typescript
type AdminAction = "create" | "update" | "delete" | "toggle" | "send" | "adjust";
type ResourceType =
  | "template" | "banner" | "faq" | "partner"
  | "user" | "notification" | "credit"
  | "subscription_plan" | "credit_package" | "work" | "job";

async function logAdminActivity(params: {
  adminId: string;
  action: AdminAction;
  resourceType: ResourceType;
  resourceId?: string;
  description: string;
  metadata?: Json;
}) {
  try {
    const supabase = await createSupabaseServerClient();
    // ✅ 반드시 error를 구조분해하여 체크!
    const { error } = await supabase.from("admin_activity_logs").insert({
      admin_id: params.adminId,
      action: params.action,
      resource_type: params.resourceType,
      resource_id: params.resourceId ?? null,
      description: params.description,
      metadata: params.metadata ?? {},
    });

    // Supabase는 에러를 throw하지 않고 { data, error } 형태로 반환
    if (error) {
      console.error("[logAdminActivity Supabase Error]", error);
    }
  } catch (error) {
    // 로그 실패는 메인 작업에 영향을 주지 않음
    console.error("[logAdminActivity Error]", error);
  }
}
```

### Supabase 에러 처리 패턴

```typescript
// ❌ 잘못된 패턴 - 에러가 무시됨
await supabase.from("table").insert(data);

// ✅ 올바른 패턴 - 에러 체크 필수
const { data, error } = await supabase.from("table").insert(data);
if (error) {
  throw createAppError(error);
  // 또는
  console.error("Error:", error);
}
```

---

## 활동 로그 시스템

### 테이블 스키마

```sql
CREATE TABLE admin_activity_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id UUID NOT NULL REFERENCES auth.users(id),
  action TEXT NOT NULL,           -- create, update, delete, toggle, send, adjust
  resource_type TEXT NOT NULL,    -- template, banner, user, etc.
  resource_id TEXT,               -- 대상 리소스 ID (nullable)
  description TEXT NOT NULL,      -- 사람이 읽을 수 있는 설명
  metadata JSONB DEFAULT '{}',    -- 추가 데이터
  created_at TIMESTAMPTZ DEFAULT now()
);

-- RLS 정책
CREATE POLICY "Admin can view activity logs"
ON admin_activity_logs FOR SELECT TO authenticated
USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

CREATE POLICY "Admin can insert activity logs"
ON admin_activity_logs FOR INSERT TO authenticated
WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
```

### 로그 기록 시점

모든 Admin Server Action에서 성공 후 로그 기록:

- 템플릿: 생성, 수정, 삭제, 활성화/비활성화
- 배너: 생성, 수정, 삭제, 활성화/비활성화
- 파트너사: 생성, 수정, 삭제, 활성화/비활성화
- FAQ: 생성, 수정, 삭제, 활성화/비활성화
- 알림: 발송
- 크레딧: 수동 조정

---

## 구독 상태 판별 로직

### 핵심 규칙

```
유료 플랜: STANDARD, PROFESSIONAL
무료 플랜: STARTER (미구독으로 취급)

유료 구독자 = 유료 플랜 + status='active' + expires_at > now()
비구독자 = 전체 사용자 - 유료 구독자
```

### 올바른 쿼리 패턴

```typescript
// ✅ 유료 구독자 카운트
const { data: paidPlans } = await supabase
  .from("subscription_plans")
  .select("id")
  .in("name", ["STANDARD", "PROFESSIONAL"]);

const paidPlanIds = paidPlans?.map((p) => p.id) ?? [];

const { count: paidSubscribers } = await supabase
  .from("subscriptions")
  .select("*", { count: "exact", head: true })
  .in("plan_id", paidPlanIds)
  .eq("status", "active")
  .gt("expires_at", new Date().toISOString());

// ✅ 비구독자 = 전체 - 유료 구독자
const nonSubscribers = totalUsers - paidSubscribers;
```

### 흔한 실수

```typescript
// ❌ 잘못된 쿼리 - STARTER도 포함됨
const { count } = await supabase
  .from("subscriptions")
  .select("*", { count: "exact", head: true })
  .eq("status", "active");  // STARTER 플랜도 active일 수 있음!

// ❌ 잘못된 쿼리 - 만료된 구독도 포함
const { count } = await supabase
  .from("subscriptions")
  .select("*", { count: "exact", head: true })
  .in("plan_id", paidPlanIds)
  .eq("status", "active");  // expires_at 체크 누락!
```

### 사용자별 구독 정보 조회 (복수 구독 처리)

```typescript
// 한 사용자가 여러 구독 기록을 가질 수 있으므로 정렬 필요
const { data: subscriptions } = await supabase
  .from("subscriptions")
  .select("user_id, status, plan:subscription_plans(name)")
  .in("user_id", userIds)
  .order("status", { ascending: true })      // active가 먼저 (알파벳순)
  .order("started_at", { ascending: false }); // 최신순

// user_id별로 첫 번째(active 우선, 최신) 구독만 사용
const subscriptionMap = new Map();
for (const sub of subscriptions ?? []) {
  if (!subscriptionMap.has(sub.user_id)) {
    subscriptionMap.set(sub.user_id, {
      status: sub.status,
      planName: sub.plan?.name ?? null,
    });
  }
}
```

---

## 주의사항 및 흔한 실수

### 1. Service Role Key 사용 금지

```typescript
// ❌ 보안 위험 - 절대 사용 금지
const adminClient = createClient(url, process.env.SUPABASE_SERVICE_ROLE_KEY);

// ✅ RLS 정책으로 권한 관리
const supabase = await createSupabaseServerClient();
```

### 2. Next.js 15 비동기 Props

```typescript
// ❌ Next.js 15에서 에러
export default function Page({ searchParams }) {
  const page = searchParams.page;  // Error!
}

// ✅ Promise로 받아서 await
export default async function Page({ searchParams }: { searchParams: Promise<...> }) {
  const params = await searchParams;
  const page = params.page;
}
```

### 3. Server Component에서 실시간 업데이트 불가

```typescript
// Server Component는 페이지 새로고침 시에만 데이터 갱신
// 실시간 업데이트가 필요하면:
// 1. Client Component로 전환
// 2. TanStack Query의 refetchInterval 사용
// 3. Supabase Realtime 사용
```

### 4. RLS 정책 누락

새 테이블 추가 시 Admin RLS 정책 추가 필수:

```sql
-- 잊지 말고 추가!
CREATE POLICY "Admins can view all new_table"
ON public.new_table FOR SELECT TO authenticated
USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
```

### 5. 활동 로그 누락

모든 데이터 변경 Server Action에 `logAdminActivity()` 호출 추가:

```typescript
// 잊지 말고 추가!
await logAdminActivity({
  adminId: session.user.id,
  action: "update",
  resourceType: "resource_name",
  resourceId: id,
  description: "설명",
});
```

### 6. revalidatePath 누락

Server Action 후 캐시 무효화 필수:

```typescript
// 잊지 말고 추가!
revalidatePath("/app/admin/feature");
```

### 7. Icons 존재 여부 확인

```typescript
// ❌ 존재하지 않는 아이콘 사용
icon={Icons.user}  // Error!

// ✅ @/components/icons.tsx에서 확인 후 사용
icon={Icons.userCircle}
```

### 8. 테이블 Check Constraint 확인

새로운 값을 삽입할 때 기존 check constraint 위반 주의:

```sql
-- 예: credit_transactions.type 컬럼의 허용 값 확인
SELECT conname, pg_get_constraintdef(oid) as definition
FROM pg_constraint
WHERE conrelid = 'credit_transactions'::regclass
AND contype = 'c';

-- 결과: CHECK (type IN ('subscription', 'purchase', 'usage', 'refund', 'admin_grant', 'admin_deduct'))
```

**credit_transactions.type 허용 값:**

| 값 | 설명 |
|------|------|
| `subscription` | 구독 크레딧 지급 |
| `purchase` | 크레딧 구매 |
| `usage` | 생성 시 사용 |
| `refund` | 환불 |
| `admin_grant` | 관리자 수동 지급 |
| `admin_deduct` | 관리자 수동 차감 |

새 타입 추가 시 constraint 수정 필요:

```sql
ALTER TABLE credit_transactions DROP CONSTRAINT credit_transactions_type_check;
ALTER TABLE credit_transactions ADD CONSTRAINT credit_transactions_type_check
CHECK (type IN ('subscription', 'purchase', 'usage', 'refund', 'admin_grant', 'admin_deduct', 'new_type'));
```

### 9. 크레딧 조정 시 필요한 RLS 정책

Admin 크레딧 조정 기능에는 다음 RLS 정책이 필요:

```sql
-- users 테이블 UPDATE 정책 (크레딧 컬럼 수정용)
CREATE POLICY "Admins can update users"
ON public.users FOR UPDATE TO authenticated
USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- credit_transactions 테이블 SELECT 정책 (거래 내역 조회용)
CREATE POLICY "Admins can view all credit_transactions"
ON public.credit_transactions FOR SELECT TO authenticated
USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- credit_transactions 테이블 INSERT 정책 (거래 기록용)
CREATE POLICY "Admins can insert credit_transactions"
ON public.credit_transactions FOR INSERT TO authenticated
WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
```

### 10. RLS 정책 작성 시 JWT 패턴 사용

```sql
-- ❌ 서브쿼리 패턴 - 동작하지 않을 수 있음
CREATE POLICY "Bad pattern" ON some_table FOR SELECT TO authenticated
USING ((SELECT raw_app_meta_data ->> 'role' FROM auth.users WHERE id = auth.uid()) = 'admin');

-- ✅ JWT 직접 접근 패턴 - 권장
CREATE POLICY "Good pattern" ON some_table FOR SELECT TO authenticated
USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
```

**주의**: 서브쿼리 패턴은 일부 상황에서 작동하지 않습니다. 항상 `auth.jwt()` 직접 접근 패턴을 사용하세요.

### 11. Supabase 에러 처리 필수

```typescript
// ❌ 에러가 무시됨 - 조용히 실패
await supabase.from("table").insert(data);

// ✅ 에러 체크 필수
const { error } = await supabase.from("table").insert(data);
if (error) {
  console.error("Error:", error);
  // 또는 throw createAppError(error);
}
```

**주의**: Supabase 클라이언트는 에러 발생 시 Promise를 reject하지 않고 `{ data, error }` 형태로 반환합니다. 반드시 `error`를 구조분해하여 체크해야 합니다.

---

## 새 Admin 페이지 추가 체크리스트

### 1. 라우트 추가

```typescript
// constants/routes.ts
export const ROUTES = {
  ADMIN: {
    // ...기존
    NEW_FEATURE: "/app/admin/new-feature",
  },
};
```

### 2. 사이드바 메뉴 추가

```typescript
// constants/nav-items.ts
export const ADMIN_SIDEBAR_MENU_ITEMS = {
  MANAGEMENT: [
    // ...기존
    { title: "새 기능", href: ROUTES.ADMIN.NEW_FEATURE, icon: Icons.star },
  ],
};
```

### 3. RLS 정책 추가 (필요시)

```sql
-- 새 테이블이 있다면 RLS 정책 추가
CREATE POLICY "Admins can view all new_table"
ON public.new_table FOR SELECT TO authenticated
USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
```

### 4. 페이지 파일 생성

```
app/app/admin/new-feature/
├── page.tsx           # Server Component
└── [id]/page.tsx      # 상세 페이지 (필요시)
```

### 5. 컴포넌트 생성

```
features/admin/components/
├── new-feature-table.tsx
├── new-feature-edit-modal.tsx
└── ...
```

### 6. Server Actions 추가

```typescript
// features/admin/server/actions.ts
export async function createNewFeature(data) { ... }
export async function updateNewFeature(params) { ... }
export async function deleteNewFeature(params) { ... }
```

### 7. 활동 로그 타입 추가 (필요시)

```typescript
// features/admin/server/actions.ts
type ResourceType =
  | "template" | "banner" | ...
  | "new_feature";  // 추가
```

### 8. 타입 체크

```bash
pnpm typecheck
```

---

## 관련 문서

| 문서 | 설명 |
|------|------|
| [ADMIN_GUIDE.md](./ADMIN_GUIDE.md) | Admin Dashboard 사용 설명서 |
| [DEVELOPMENT_GUIDE.md](./DEVELOPMENT_GUIDE.md) | 개발 환경 설정 및 패턴 |
| [SUPABASE_API.md](./SUPABASE_API.md) | Supabase API 명세 |
| [../backend/OVERVIEW.md](../backend/OVERVIEW.md) | 시스템 아키텍처 개요 |
