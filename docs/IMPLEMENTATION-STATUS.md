# XiCON 구현 현황 문서

> 작성일: 2026-01-27
> 대상: 개발자 인수인계용

---

## 1. 요약

| 영역 | 상태 | 비고 |
|------|------|------|
| 프론트엔드 | 90% | 마케팅 문구 비활성화 |
| 백엔드 (DB) | 100% | 20개 테이블, RLS 적용 |
| Edge Functions | 부분 | 생성/결제 함수 배포됨 |
| 소셜 로그인 | 100% | Google OAuth |

---

## 2. 프론트엔드 구현 현황

### 2.1 공통 컴포넌트

| 컴포넌트 | 상태 | 파일 경로 |
|----------|------|-----------|
| 인증 모달 | ✅ 완료 | `features/auth/components/auth-modal.tsx` |
| 갤러리 상세 모달 | ✅ 완료 | `features/gallery/components/gallery-detail-modal/` |

### 2.2 앱 (Private) 페이지

| 페이지 | 상태 | 라우트 |
|--------|------|--------|
| 앱 헤더 | ✅ 완료 | `components/layouts/app-header/` |
| 앱 사이드바 | ✅ 완료 | `components/layouts/app-sidebar/` |
| 설정 모달 | ✅ 완료 | `features/settings/components/settings-modal.tsx` |
| 홈 | ✅ 완료 | `/app` |
| 브랜딩 리포트 | ✅ 완료 | `/app/branding-report` |
| 마케팅 문구 | ⛔ 비활성화 | `/app/marketing-copy` (blur 오버레이) |
| 홍보 이미지 | ✅ 완료 | `/app/promotional-image` |
| 영상 컨텐츠 | ✅ 완료 | `/app/video-content` |
| 라이브러리 | ✅ 완료 | `/app/library` |
| 휴지통 | ✅ 완료 | `/app/trash` |

### 2.3 홈페이지 (Public) 페이지

| 페이지 | 상태 | 라우트 |
|--------|------|--------|
| 헤더 | ✅ 완료 | `components/layouts/homepage-header.tsx` |
| 푸터 | ✅ 완료 | `components/layouts/homepage-footer.tsx` |
| 랜딩 페이지 | ✅ 완료 | `/` |
| 공개 갤러리 | ✅ 완료 | `/gallery` |
| 가격/구독 | ✅ 완료 | `/pricing` |
| OAuth 콜백 | ✅ 완료 | `/auth/callback` |

---

## 3. 백엔드 구현 현황

### 3.1 데이터베이스 테이블 (전체 구현됨)

| 테이블 | 행 수 | RLS |
|--------|-------|-----|
| users | 7 | ✅ |
| projects | 40 | ✅ |
| works | 196 | ✅ |
| templates | 21 | ✅ |
| files | 261 | ✅ |
| generation_jobs | 127 | ✅ |
| notifications | 486 | ✅ |
| user_favorite_works | 43 | ✅ |
| user_like_works | 1 | ✅ |
| banners | 4 | ✅ |
| faqs | 7 | ✅ |
| partners | 0 | ✅ |
| subscription_plans | 3 | ✅ |
| subscriptions | 7 | ✅ |
| credit_packages | 4 | ✅ |
| credit_transactions | 132 | ✅ |
| payment_methods | 2 | ✅ |
| payment_history | 3 | ✅ |
| user_dismissed_banners | 0 | ✅ |

### 3.2 Edge Functions

| 함수 | 상태 | verify_jwt |
|------|------|------------|
| `generate` | ✅ 배포됨 | false |
| `retry-generation` | ✅ 배포됨 | true |
| `payment` | ✅ 배포됨 | true |

**미구현 함수:**

- `onboarding-status`
- `delete-account`
- `payment-webhook`
- `register-payment-method`
- `cancel-subscription`

### 3.3 주요 DB 트리거

- `handle_new_user` - 신규 가입 시 유저/프로젝트/구독/크레딧 자동 생성
- `trg_notify_work_status_change` - 생성 완료/실패 알림
- `trg_notify_generation_started` - 생성 시작 알림
- `trg_refund_credits_on_failure` - 실패 시 크레딧 환불
- `trg_generate_file_url` - 파일 URL 자동 생성
- `fail_stuck_works` (pg_cron) - 타임아웃 작업 자동 실패 처리

---

## 4. 주요 기능별 구현 상태

### 4.1 인증/온보딩

- [x] Google OAuth 로그인
- [x] 자동 유저 생성 (트리거)
- [x] 초기 크레딧 지급 (50)
- [x] 첫 프로젝트 자동 생성
- [x] 온보딩 플로우
- [ ] 계정 삭제

### 4.2 콘텐츠 생성

- [x] 브랜딩 리포트 생성 요청
- [x] 홍보 이미지 생성 요청
- [x] 영상 콘텐츠 생성 요청
- [ ] 마케팅 문구 생성 (비활성화)
- [x] 생성 상태 실시간 업데이트 (Realtime)
- [x] 실패 시 재시도
- [x] 타임아웃 자동 실패 처리

### 4.3 라이브러리/휴지통

- [x] 생성물 목록 조회
- [x] 상세 보기 모달
- [x] 공개/비공개 토글
- [x] 즐겨찾기
- [x] 만족도 피드백
- [x] 다운로드 (이미지/영상/PDF)
- [x] 휴지통 이동
- [x] 복원/영구 삭제

### 4.4 갤러리

- [x] 공개 갤러리 조회
- [x] 좋아요
- [x] 무한 스크롤
- [x] 상세 모달

### 4.5 알림

- [x] 생성 시작/완료/실패 알림
- [x] 크레딧 관련 알림
- [x] 실시간 알림 (Realtime)
- [x] 읽음 처리

### 4.6 결제/구독

- [x] 요금제/크레딧 상품 조회
- [x] 결제 UI (설정 모달)
- [ ] 결제수단 관리
- [ ] 실제 PG 연동 (토스페이먼츠/스트라이프)
- [ ] 정기결제

---

## 5. 더미 데이터 사용 현황

DB 테이블이 존재하지만 하드코딩된 상수를 사용하는 기능:

| 기능 | 더미 데이터 위치 | DB 테이블 | 비고 |
|------|------------------|-----------|------|
| 파트너 로고 | `constants/partners.ts` | `partners` (0행) | 로컬 SVG 사용 (의도적) |
| 결제 수단 추가 | `features/settings/components/tabs/payment-tab.tsx` | - | 랜덤 mock 카드 생성 |
