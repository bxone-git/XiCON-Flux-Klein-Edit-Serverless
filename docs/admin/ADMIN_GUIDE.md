# Admin Dashboard 사용설명서

> XiCON Admin Dashboard는 플랫폼의 사용자, 콘텐츠, 결제, 시스템을 관리하는 백오피스입니다.

## 목차

1. [접근 및 인증](#접근-및-인증)
2. [대시보드](#대시보드)
3. [사용자 관리](#사용자-관리)
4. [생성물 관리](#생성물-관리)
5. [크레딧 관리](#크레딧-관리)
6. [템플릿 관리](#템플릿-관리)
7. [생성 작업 관리](#생성-작업-관리)
8. [결제 관리](#결제-관리)
9. [콘텐츠 관리](#콘텐츠-관리)
10. [알림 발송](#알림-발송)
11. [Supabase 연동 정보](#supabase-연동-정보)

---

## 접근 및 인증

### 접근 URL
```
/app/admin
```

### 권한 요구사항
- `app_metadata.role`이 `admin` 또는 `super_admin`인 사용자만 접근 가능
- 권한이 없는 사용자는 자동으로 `/app`으로 리다이렉트

### 권한 부여 방법
Supabase Dashboard에서 `users` 테이블의 `raw_app_meta_data` 필드 수정:
```json
{
  "role": "admin"
}
```

---

## 대시보드

**경로**: `/app/admin`

### 주요 KPI 카드
| 카드 | 설명 | 데이터 소스 |
|------|------|-------------|
| 총 사용자 | 전체 가입자 수 | `users` 테이블 COUNT |
| 오늘 가입 | 당일 신규 가입자 | `users.created_at` 필터 |
| 활성 구독자 | 현재 유효한 구독 보유자 | `subscriptions` (status=active, expires_at > now) |
| 이번달 매출 | 당월 완료된 결제 합계 | `payment_history` (status=completed) SUM |

### 차트
- **가입 추이**: 최근 7일간 일별 신규 가입자 수
- **생성물 타입**: 타입별 생성물 분포 (브랜딩 리포트, 마케팅 카피, 홍보 이미지, 영상 콘텐츠)

### 최근 활동 피드
최근 20건의 활동 표시:
- 신규 가입 (`users.created_at`)
- 콘텐츠 생성 (`works.created_at`)
- 결제 완료 (`payment_history.created_at`)

---

## 사용자 관리

**경로**: `/app/admin/users`

### 기능
| 기능 | 설명 |
|------|------|
| 목록 조회 | 페이지네이션, 정렬 지원 |
| 검색 | 이메일, 닉네임으로 검색 |
| 역할 필터 | admin / user |
| 구독 필터 | 활성 / 비활성 / 만료 |
| 온보딩 필터 | 완료 / 미완료 |
| 상세 보기 | 사용자 프로필, 프로젝트, 생성물, 크레딧 내역 |
| 크레딧 조정 | 수동 지급/차감 |

### 사용자 상세 페이지
**경로**: `/app/admin/users/[userId]`

**탭 구조**:
1. **프로젝트 탭**: 사용자의 프로젝트 목록
2. **생성물 탭**: 사용자가 생성한 콘텐츠 목록
3. **크레딧 탭**: 크레딧 거래 내역 및 수동 조정 폼

### 연결된 테이블
- `users` - 사용자 정보
- `projects` - 프로젝트 목록
- `works` - 생성물
- `credit_transactions` - 크레딧 거래 내역
- `subscriptions` - 구독 정보

---

## 생성물 관리

**경로**: `/app/admin/works`

### 기능
| 기능 | 설명 |
|------|------|
| 목록 조회 | 카드 형식으로 표시 |
| 제목 검색 | 생성물 제목으로 검색 |
| 타입 필터 | branding_report / marketing_copy / promotional_image / video_content |
| 상태 필터 | pending / processing / completed / failed |
| 공개 토글 | 갤러리 공개 여부 전환 |
| 소프트 삭제 | `deleted_at` 설정 |

### 생성물 상세 페이지
**경로**: `/app/admin/works/[workId]`

표시 정보:
- 기본 정보 (제목, 설명, 생성일)
- 입력 데이터 (JSON)
- 출력 데이터 (JSON)
- 파일 정보 (썸네일, 출력 파일)
- 통계 (좋아요, 즐겨찾기)

### 연결된 테이블
- `works` - 생성물 메타데이터
- `files` - 파일 정보 (thumbnail_file_id, output_file_id FK)
- `users` - 생성자 정보

---

## 크레딧 관리

**경로**: `/app/admin/credits`

### 기능
| 기능 | 설명 |
|------|------|
| 통계 카드 | 총 지급량, 총 사용량, 현재 잔액 |
| 수동 지급 | 이메일 검색 후 크레딧 지급/차감 |
| 거래 내역 | 전체 거래 이력 조회 |
| 타입 필터 | admin_grant / admin_deduct / usage / refund 등 |

### 수동 크레딧 조정
1. 사용자 이메일 입력
2. 금액 입력 (양수: 지급, 음수: 차감)
3. 사유 입력 (선택)
4. 확인

### 연결된 테이블
- `credit_transactions` - 거래 내역
- `users` - 사용자 정보 및 잔액

### 거래 타입
| 타입 | 설명 |
|------|------|
| `admin_grant` | 관리자 수동 지급 |
| `admin_deduct` | 관리자 수동 차감 |
| `usage` | 생성 시 사용 |
| `subscription` | 구독 크레딧 |
| `purchase` | 크레딧 구매 |
| `refund` | 환불 |

---

## 템플릿 관리

**경로**: `/app/admin/templates`

### 기능
| 기능 | 설명 |
|------|------|
| 목록 조회 | 테이블 형식 |
| 타입 필터 | 생성물 타입별 필터 |
| 활성화 토글 | 템플릿 사용 여부 |
| 순서 변경 | display_order 조정 |
| 생성/수정 | 템플릿 CRUD |

### 템플릿 상세/수정 페이지
**경로**: `/app/admin/templates/[templateId]`

편집 가능 필드:
- 제목 (`title`)
- 설명 (`description`)
- 타입 (`type`)
- 예상 시간 (`estimated_minutes`)
- 폼 필드 스키마 (`form_fields` - JSON)
- 요청 DTO 스키마 (`request_dto` - JSON)
- 활성화 상태 (`is_active`)

### 연결된 테이블
- `templates` - 템플릿 정보
- `files` - 썸네일 파일

---

## 생성 작업 관리

**경로**: `/app/admin/jobs`

### 기능
| 기능 | 설명 |
|------|------|
| 상태별 카운트 | pending / processing / failed / completed |
| 상태 필터 | 상태별 조회 |
| 재시도 | 실패한 작업 재시도 |
| 강제 실패 | 처리 중인 작업 강제 실패 처리 |

### 작업 상태
| 상태 | 설명 |
|------|------|
| `pending` | 대기 중 |
| `processing` | 처리 중 |
| `completed` | 완료 |
| `failed` | 실패 |

### 연결된 테이블
- `generation_jobs` - 작업 큐
- `works` - 연결된 생성물
- `users` - 요청 사용자

### Edge Function 연동
- **재시도 시**: `generation_jobs.status`를 `pending`으로 변경하면 n8n 워크플로우가 재처리
- **retry-generation Edge Function**: 실패한 작업 일괄 재시도 지원

---

## 결제 관리

**경로**: `/app/admin/payments`

### 기능
| 기능 | 설명 |
|------|------|
| 통계 카드 | 이번달 매출, 총 거래 수, 완료된 결제 수 |
| 결제 내역 | 전체 결제 이력 |
| 상태 필터 | pending / completed / failed / refunded |
| 유형 필터 | subscription / credit_package |

### 요금제 관리
**경로**: `/app/admin/payments/plans`

- 구독 요금제 목록 조회
- 가격, 월간 크레딧, 순서 정보

### 크레딧 상품 관리
**경로**: `/app/admin/payments/packages`

- 크레딧 패키지 목록 조회
- 가격, 수량, 순서 정보

### 연결된 테이블
- `payment_history` - 결제 내역
- `subscription_plans` - 구독 요금제
- `credit_packages` - 크레딧 상품

---

## 콘텐츠 관리

### 배너 관리
**경로**: `/app/admin/content/banners`

| 기능 | 설명 |
|------|------|
| CRUD | 배너 생성, 수정, 삭제 |
| 활성화 토글 | 표시 여부 |
| 기간 설정 | starts_at, ends_at |
| 순서 변경 | display_order |

**필드**:
- `title` - 배너 제목
- `type` - hero / popup / inline
- `location` - home / app / pricing
- `image_url` - 배너 이미지 URL
- `link_url` - 클릭 시 이동 URL
- `is_dismissible` - 닫기 가능 여부

### 파트너사 관리
**경로**: `/app/admin/content/partners`

| 기능 | 설명 |
|------|------|
| CRUD | 파트너사 생성, 수정, 삭제 |
| 활성화 토글 | 표시 여부 |
| 순서 변경 | display_order |

**필드**:
- `name` - 파트너사명
- `logo_url` - 로고 이미지 URL
- `website_url` - 웹사이트 URL

### FAQ 관리
**경로**: `/app/admin/content/faqs`

| 기능 | 설명 |
|------|------|
| CRUD | FAQ 생성, 수정, 삭제 |
| 활성화 토글 | 표시 여부 |
| 카테고리 필터 | general / pricing / usage / technical |
| 순서 변경 | display_order |

**필드**:
- `question` - 질문
- `answer` - 답변 (마크다운 지원)
- `category` - 카테고리

### 연결된 테이블
- `banners` - 배너
- `partners` - 파트너사
- `faqs` - FAQ

---

## 알림 발송

**경로**: `/app/admin/notifications`

### 기능
| 기능 | 설명 |
|------|------|
| 전체 발송 | 모든 사용자에게 알림 |
| 개별 발송 | 특정 사용자에게 알림 |
| 발송 내역 | 알림 이력 조회 |
| 읽음 상태 | 읽음/안읽음 표시 |

### 알림 필드
- `title` - 알림 제목
- `message` - 알림 내용
- `type` - info / warning / success / error
- `link_url` - 클릭 시 이동 URL (선택)

### 연결된 테이블
- `notifications` - 알림 데이터
- `users` - 수신자 정보

---

## Supabase 연동 정보

### 데이터베이스 테이블

#### 사용자 관련
| 테이블 | 용도 | 주요 컬럼 |
|--------|------|-----------|
| `users` | 사용자 계정 | id, email, nickname, credits, created_at |
| `subscriptions` | 구독 정보 | user_id, plan_id, status, expires_at |
| `credit_transactions` | 크레딧 거래 | user_id, amount, type, description |

#### 콘텐츠 관련
| 테이블 | 용도 | 주요 컬럼 |
|--------|------|-----------|
| `works` | 생성물 | user_id, type, status, input_data, output_data |
| `templates` | 템플릿 | type, form_fields, request_dto, is_active |
| `projects` | 프로젝트 | user_id, title, brand_info |
| `generation_jobs` | 작업 큐 | work_id, status, error_message |

#### 결제 관련
| 테이블 | 용도 | 주요 컬럼 |
|--------|------|-----------|
| `payment_history` | 결제 내역 | user_id, amount, status, product_type |
| `subscription_plans` | 요금제 | name, price, monthly_credits |
| `credit_packages` | 크레딧 상품 | name, price, credit_amount |

#### 콘텐츠 관리
| 테이블 | 용도 | 주요 컬럼 |
|--------|------|-----------|
| `banners` | 배너 | title, image_url, is_active, starts_at, ends_at |
| `partners` | 파트너사 | name, logo_url, is_active |
| `faqs` | FAQ | question, answer, category, is_active |
| `notifications` | 알림 | user_id, title, message, is_read |

#### 파일 관리
| 테이블 | 용도 | 주요 컬럼 |
|--------|------|-----------|
| `files` | 파일 메타 | bucket_id, path, size, mime_type |

### Storage 버킷

| 버킷 | 용도 |
|------|------|
| `works` | 생성물 출력 파일 |
| `thumbnails` | 썸네일 이미지 |
| `templates` | 템플릿 미리보기 이미지 |
| `banners` | 배너 이미지 |
| `partners` | 파트너사 로고 |

### Edge Functions

| 함수 | 용도 | 트리거 |
|------|------|--------|
| `generate` | 콘텐츠 생성 오케스트레이션 | n8n 워크플로우 |
| `payment` | 결제 처리 및 웹훅 | 결제 시스템 |
| `retry-generation` | 실패 작업 재시도 | Admin 수동/스케줄 |

### Server Actions

모든 Admin 작업은 `features/admin/server/actions.ts`에 구현:

```typescript
// 크레딧 조정
adjustUserCredits({ userId, amount, description })

// 생성물 관리
toggleWorkPublic({ workId, isPublic })
deleteWork({ workId })

// 템플릿 관리
toggleTemplateActive({ templateId, isActive })
createTemplate(data)
updateTemplate({ templateId, data })
deleteTemplate({ templateId })
reorderTemplate({ templateId, direction })

// 작업 관리
retryJob({ jobId })
failJob({ jobId })

// 콘텐츠 관리 (배너, 파트너사, FAQ)
toggle[Type]Active({ id, isActive })
create[Type](data)
update[Type]({ id, data })
delete[Type]({ id })

// 알림 발송
sendNotification({ title, message, type, userId?, linkUrl? })
```

---

## 보안 고려사항

1. **인증**: 모든 Admin 페이지는 `layout.tsx`에서 세션 검증
2. **인가**: Server Actions에서 `app_metadata.role === "admin"` 검증
3. **RLS**: Supabase RLS 정책으로 데이터 접근 제어
4. **감사 로그**: 크레딧 조정 시 `credit_transactions` 테이블에 기록

---

## 테스트

### E2E 테스트 실행
```bash
# 전체 Admin 테스트
npx playwright test specs/admin/ --project=chromium

# 특정 파일만
npx playwright test specs/admin/dashboard.spec.ts --project=chromium

# UI 모드
npx playwright test specs/admin/ --project=chromium --ui
```

### 테스트 현황
- 전체 테스트: 109개
- 통과: 109개 (100%)
- 테스트 파일: 12개

상세 현황: `specs/admin/E2E_TEST_STATUS.md`
