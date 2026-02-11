# Admin Dashboard 개발 가이드

> Admin Dashboard 개발을 위한 도구, 설정, 패턴 안내

## 목차

1. [개발 환경 설정](#개발-환경-설정)
2. [MCP 서버 설정](#mcp-서버-설정)
3. [데이터베이스 마이그레이션](#데이터베이스-마이그레이션)
4. [컴포넌트 패턴](#컴포넌트-패턴)
5. [테스트 실행](#테스트-실행)
6. [트러블슈팅](#트러블슈팅)

---

## 개발 환경 설정

### 사전 요구사항

```bash
# 패키지 설치
pnpm install

# Supabase 타입 동기화
pnpm sb:types

# 개발 서버 실행
pnpm dev
```

### Admin 테스트 계정 설정

Supabase Studio에서 사용자의 `app_metadata`에 Admin 권한 부여:

```sql
UPDATE auth.users
SET raw_app_meta_data = jsonb_set(
  COALESCE(raw_app_meta_data, '{}'::jsonb),
  '{role}',
  '"admin"'
)
WHERE email = 'YOUR_EMAIL';
```

---

## MCP 서버 설정

Claude Code에서 Admin Dashboard 개발 시 유용한 MCP 서버:

### 1. Filesystem MCP (필수)

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-filesystem",
        "/Users/leokim/Documents/XiCON"
      ]
    }
  }
}
```

### 2. PostgreSQL MCP (권장)

```json
{
  "mcpServers": {
    "postgres": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-postgres",
        "postgresql://postgres:[PASSWORD]@db.[PROJECT_REF].supabase.co:5432/postgres"
      ]
    }
  }
}
```

**Supabase 연결 문자열 찾기:**
1. Supabase Dashboard → Project Settings → Database
2. "Connection string" → "URI" 복사
3. `[PASSWORD]`를 실제 DB 비밀번호로 치환

---

## 데이터베이스 마이그레이션

### 마이그레이션 생성

```bash
# 새 마이그레이션 파일 생성
pnpm supabase migration new [마이그레이션_이름]

# 마이그레이션 파일 위치
# supabase/migrations/[timestamp]_[이름].sql
```

### Admin RLS 정책 템플릿

```sql
-- is_admin() 헬퍼 함수
CREATE OR REPLACE FUNCTION is_admin()
RETURNS boolean AS $$
  SELECT (
    auth.jwt() -> 'app_metadata' ->> 'role'
  ) IN ('admin', 'super_admin');
$$ LANGUAGE sql SECURITY DEFINER;

-- Admin SELECT 정책
CREATE POLICY "admin_select_[TABLE]" ON [TABLE]
  FOR SELECT TO authenticated
  USING (is_admin());

-- Admin UPDATE 정책
CREATE POLICY "admin_update_[TABLE]" ON [TABLE]
  FOR UPDATE TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());
```

### 마이그레이션 적용

```bash
# 로컬 적용
pnpm supabase migration up

# 프로덕션 적용
pnpm supabase db push
```

---

## 컴포넌트 패턴

### Server Component 페이지

```tsx
// app/app/admin/[feature]/page.tsx
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { createAppError } from "@/lib/errors/factory";
import { SUPABASE_TABLES } from "@/constants/supabase";

export default async function FeaturePage() {
  const supabase = await createSupabaseServerClient();

  const { data, error } = await supabase
    .from(SUPABASE_TABLES.USERS)
    .select("*")
    .order("created_at", { ascending: false })
    .range(0, 19);

  if (error) throw createAppError(error);

  return (
    <div className="container mx-auto p-6">
      <div className="mb-6">
        <h1 className="text-3xl font-bold">페이지 제목</h1>
        <p className="text-frg-3">설명</p>
      </div>
      <ClientComponent data={data} />
    </div>
  );
}
```

### Stats Card 컴포넌트

```tsx
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

interface Props {
  title: string;
  value: string | number;
  description?: string;
  icon?: React.ReactNode;
}

export function StatsCard({ title, value, description, icon }: Props) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between pb-2">
        <CardTitle className="text-sm font-medium text-frg-3">{title}</CardTitle>
        {icon}
      </CardHeader>
      <CardContent>
        <div className="text-3xl font-bold">{value}</div>
        {description && (
          <p className="text-xs text-frg-4 mt-1">{description}</p>
        )}
      </CardContent>
    </Card>
  );
}
```

### DataTable 패턴

```tsx
"use client";

import { ColumnDef } from "@tanstack/react-table";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  useReactTable,
  getCoreRowModel,
  flexRender,
} from "@tanstack/react-table";

interface DataTableProps<TData> {
  columns: ColumnDef<TData>[];
  data: TData[];
}

export function DataTable<TData>({ columns, data }: DataTableProps<TData>) {
  const table = useReactTable({
    data,
    columns,
    getCoreRowModel: getCoreRowModel(),
  });

  return (
    <Table>
      <TableHeader>
        {table.getHeaderGroups().map((headerGroup) => (
          <TableRow key={headerGroup.id}>
            {headerGroup.headers.map((header) => (
              <TableHead key={header.id}>
                {flexRender(header.column.columnDef.header, header.getContext())}
              </TableHead>
            ))}
          </TableRow>
        ))}
      </TableHeader>
      <TableBody>
        {table.getRowModel().rows.map((row) => (
          <TableRow key={row.id}>
            {row.getVisibleCells().map((cell) => (
              <TableCell key={cell.id}>
                {flexRender(cell.column.columnDef.cell, cell.getContext())}
              </TableCell>
            ))}
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
```

---

## 테스트 실행

### E2E 테스트

```bash
# 전체 Admin 테스트
npx playwright test specs/admin/ --project=chromium

# 특정 파일만
npx playwright test specs/admin/dashboard.spec.ts --project=chromium

# UI 모드 (디버깅)
npx playwright test specs/admin/ --project=chromium --ui

# 실패한 테스트만 재실행
npx playwright test specs/admin/ --project=chromium --last-failed
```

### 인증 토큰 생성

테스트 실행 전 인증 토큰이 필요합니다:

```bash
# 1. 개발 서버 실행
pnpm dev

# 2. Playwright codegen 실행
npx playwright codegen --save-storage=specs/.auth/admin.json http://localhost:3000

# 3. 브라우저에서 Admin 계정으로 로그인
# 4. /app/admin 페이지 접속 후 브라우저 닫기
```

**참고:** `admin.fixture.ts`가 토큰 만료 5분 전 자동 갱신을 수행합니다.

---

## 트러블슈팅

### RLS 정책 테스트 실패

```sql
-- is_admin() 함수 동작 확인
SELECT is_admin(); -- true여야 함

-- RLS 정책 목록 확인
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE schemaname = 'public';
```

### 타입 에러

```bash
# 타입 재생성
pnpm sb:types

# Supabase 로컬 재시작
pnpm supabase stop
pnpm supabase start
```

### 인증 실패

`specs/.auth/admin.json` 파일을 삭제하고 새로 생성:

```bash
rm specs/.auth/admin.json
npx playwright codegen --save-storage=specs/.auth/admin.json http://localhost:3000
```

---

## 관련 문서

| 문서 | 설명 |
|------|------|
| [ADMIN_GUIDE.md](./ADMIN_GUIDE.md) | Admin Dashboard 사용 설명서 |
| [SUPABASE_API.md](./SUPABASE_API.md) | Admin Supabase API 명세 |
| [OVERVIEW.md](../backend/OVERVIEW.md) | 시스템 아키텍처 개요 |
| [E2E_TEST_STATUS.md](../../specs/admin/E2E_TEST_STATUS.md) | E2E 테스트 현황 |
