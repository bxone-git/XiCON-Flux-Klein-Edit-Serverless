# 템플릿 설정값 명세서

---

## 1. 개요

### 1.1 목적

- 선택된 템플릿에 따라 폼을 동적으로 구성(`form_fields`)하고, API 요청의 `works.input_data`에 포함될 필드와 타입을 정의(`request_dto`)합니다.

### 1.2 적용 범위

- `work_type = 'promotional_image'` (홍보 이미지)
- `work_type = 'video_content'` (영상 컨텐츠)

---

## 2. 지원 필드 타입 (9개) 📌

| 타입 | 용도 | Request 값 타입 |
| --- | --- | --- |
| **text** | 한 줄 텍스트 입력 | `string` |
| **textarea** | 여러 줄 텍스트 입력 | `string` |
| **number** | 숫자 입력 | `number` |
| **select** | 드롭다운 선택 (단일 선택) | `string` |
| **radio** | 라디오 버튼 그룹 (단일 선택) | `string` |
| **checkbox** | 체크박스 (단일 선택) | `boolean` |
| **checkbox-group** | 체크박스 그룹 (다중 선택) | `string[]` |
| **switch** | 토글 스위치 (단일 선택) | `boolean` |
| **file** | 파일 업로드 | `string` (URL) |

---

## 3. 데이터베이스 컬럼 구조

`templates` 테이블에는 두 개의 JSONB 컬럼이 있습니다:

### 3.1 `form_fields` 컬럼 (필수)

사용자 입력 폼의 UI 정의를 저장합니다.

```typescript
type FormFieldsConfig = DynamicFieldConfig[];  // 폼 필드 배열 (순서 = 표시 순서)
```

**예시:**

```json
[
  {
    "type": "file",
    "name": "product_image",
    "label": "제품 이미지",
    "required": true
  },
  {
    "type": "textarea",
    "name": "copy_text",
    "label": "홍보 문구",
    "required": true
  }
]
```

### 3.2 `request_dto` 컬럼 (필수)

API 요청의 `input_data`에 포함될 필드와 타입을 정의합니다.

```typescript
type RequestDto = Record<string, "string" | "number" | "boolean" | "string[]">;
```

**예시:**

```json
{
  "product_image": "string",
  "copy_text": "string",
  "font_style": "string"
}
```

### 3.3 관계

- `form_fields`의 각 필드는 `request_key`와 `request_value_type`을 통해 `request_dto`의 키와 값 타입을 명시적으로 정의합니다
- 예: 파일 필드 `{ name: "product_image", request_key: "product_image", request_value_type: "string" }` → request_dto: `{ "product_image": "string" }`
- 두 컬럼 모두 필수(NOT NULL)이며, 독립적으로 조회/수정 가능합니다

---

## 4. 고정 필드

다음 필드는 프론트엔드에서 항상 제공되므로 config에 정의할 필요가 없습니다.

| 필드명 | 타입 | 설명 |
| --- | --- | --- |
| `template_id` | hidden | URL 파라미터에서 자동 설정 |
| `output_count` | select | 생성 개수 (이미지: 1~4, 영상: 1~2) |

---

## 5. 필드 네이밍 규칙

### 5.1 snake_case 사용

모든 필드 `name`은 snake_case를 사용합니다:

```json
✅ "copy_text"
✅ "font_style"
✅ "primary_color"

❌ "copyText"
❌ "fontStyle"
❌ "primaryColor"
```

### 5.2 Request 매핑 네이밍

필드의 `request_key`는 API 요청의 `input_data`에 사용될 키를 명시적으로 정의합니다. 파일 필드의 경우, `request_key`와 `name`을 동일하게 사용할 수 있습니다:

**예시:**

```json
{
  "type": "file",
  "name": "product_image",
  "label": "제품 이미지",
  "request_key": "product_image",
  "request_value_type": "string"
}
```

프론트엔드 처리:

1. 사용자가 파일 업로드
2. Storage에 업로드 → URL 획득
3. Request: `{ product_image: "https://..." }` (request_key 사용)

### 5.3 예약어 피하기

다음 이름은 사용하지 마세요:

- `template_id` (고정 필드)
- `project_id` (시스템 필드)
- `output_count` (고정 UI)

---

## 6. 공통 필드 속성

모든 필드 타입에 적용되는 공통 속성입니다.

| 속성 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `type` | `string` | O | 필드 타입 (섹션 7 참조) |
| `name` | `string` | O | 필드 고유 식별자 (snake_case) |
| `label` | `string` | O | 필드 레이블 (한국어) |
| `description` | `string` | X | 레이블 아래 표시되는 설명 |
| `required` | `boolean` | X | 필수 입력 여부 (기본: `false`) |
| `disabled` | `boolean` | X | 비활성화 여부 (기본: `false`) |
| `request_key` | `string` | O | API 요청의 input_data에서 사용될 키 |
| `request_value_type` | `"string" \| "number" \| "boolean" \| "string[]"` | O | API 요청의 input_data에서 사용될 값 타입 |

---

## 7. 필드 타입별 속성

### 7.1 text - 텍스트 입력

한 줄 텍스트 입력 필드입니다.

| 속성 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `type` | `"text"` | O | |
| `placeholder` | `string` | X | 입력 힌트 텍스트 |
| `default_value` | `string` | X | 기본값 |
| `min_length` | `number` | X | 최소 글자 수 |
| `max_length` | `number` | X | 최대 글자 수 |
| `pattern` | `string` | X | 정규식 패턴 (검증용) |
| `pattern_message` | `string` | X | 패턴 불일치 시 에러 메시지 |

**예시:**

```json
{
  "type": "text",
  "name": "cta_text",
  "label": "CTA 버튼 텍스트",
  "request_key": "cta_text",
  "request_value_type": "string",
  "placeholder": "예) 지금 구매하기",
  "required": true,
  "max_length": 20
}
```

---

### 7.2 textarea - 텍스트 영역

여러 줄 텍스트 입력 필드입니다.

| 속성 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `type` | `"textarea"` | O | |
| `placeholder` | `string` | X | 입력 힌트 텍스트 |
| `default_value` | `string` | X | 기본값 |
| `min_length` | `number` | X | 최소 글자 수 |
| `max_length` | `number` | X | 최대 글자 수 |
| `rows` | `number` | X | 표시 행 수 (기본: 3) |

**예시:**

```json
{
  "type": "textarea",
  "name": "copy_text",
  "label": "홍보 문구",
  "request_key": "copy_text",
  "request_value_type": "string",
  "description": "이미지에 표시될 메인 카피를 입력하세요",
  "placeholder": "예) 35% off, Order Now",
  "required": true,
  "max_length": 100,
  "rows": 3
}
```

---

### 7.3 number - 숫자 입력

숫자 입력 필드입니다.

| 속성 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `type` | `"number"` | O | |
| `placeholder` | `string` | X | 입력 힌트 텍스트 |
| `default_value` | `number` | X | 기본값 |
| `min` | `number` | X | 최소값 |
| `max` | `number` | X | 최대값 |
| `step` | `number` | X | 증감 단위 (기본: 1) |

**예시:**

```json
{
  "type": "number",
  "name": "border_radius",
  "label": "모서리 둥글기",
  "request_key": "border_radius",
  "request_value_type": "number",
  "placeholder": "0-50 사이 값",
  "min": 0,
  "max": 50,
  "step": 1,
  "default_value": 8
}
```

---

### 7.4 select - 드롭다운 선택

드롭다운 선택 필드입니다.

| 속성 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `type` | `"select"` | O | |
| `options` | `SelectOption[]` | O | 선택 옵션 목록 |
| `placeholder` | `string` | X | 미선택 시 표시 텍스트 |
| `default_value` | `string` | X | 기본 선택값 (option.value) |

**SelectOption 구조:**

| 속성 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `value` | `string` | O | 값 (폼 제출 시 사용) |
| `label` | `string` | O | 표시 텍스트 |
| `disabled` | `boolean` | X | 옵션 비활성화 여부 |

**예시:**

```json
{
  "type": "select",
  "name": "font_style",
  "label": "폰트 스타일",
  "request_key": "font_style",
  "request_value_type": "string",
  "placeholder": "폰트를 선택하세요",
  "required": true,
  "options": [
    { "value": "modern", "label": "모던" },
    { "value": "classic", "label": "클래식" },
    { "value": "handwritten", "label": "손글씨" },
    { "value": "bold", "label": "볼드" }
  ],
  "default_value": "modern"
}
```

---

### 7.5 radio - 라디오 버튼

라디오 버튼 그룹 필드입니다.

| 속성 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `type` | `"radio"` | O | |
| `options` | `SelectOption[]` | O | 선택 옵션 목록 |
| `default_value` | `string` | X | 기본 선택값 |
| `horizontal` | `boolean` | X | 가로 배치 여부 (기본: `false` = 세로) |

**예시:**

```json
{
  "type": "radio",
  "name": "text_position",
  "label": "텍스트 위치",
  "request_key": "text_position",
  "request_value_type": "string",
  "required": true,
  "options": [
    { "value": "top", "label": "상단" },
    { "value": "center", "label": "중앙" },
    { "value": "bottom", "label": "하단" }
  ],
  "default_value": "center",
  "horizontal": true
}
```

---

### 7.6 checkbox - 체크박스

단일 체크박스 필드입니다 (boolean 값).

| 속성 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `type` | `"checkbox"` | O | |
| `default_value` | `boolean` | X | 기본 체크 상태 (기본: `false`) |
| `checkbox_label` | `string` | X | 체크박스 옆에 표시될 텍스트 |

**예시:**

```json
{
  "type": "checkbox",
  "name": "add_shadow",
  "label": "그림자 효과",
  "request_key": "add_shadow",
  "request_value_type": "boolean",
  "checkbox_label": "텍스트에 그림자 효과 추가",
  "default_value": false
}
```

---

### 7.7 checkbox-group - 체크박스 그룹

다중 선택 체크박스 그룹 필드입니다 (배열 값).

| 속성 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `type` | `"checkbox-group"` | O | |
| `options` | `SelectOption[]` | O | 선택 옵션 목록 |
| `default_value` | `string[]` | X | 기본 선택값 배열 |
| `min_selections` | `number` | X | 최소 선택 개수 |
| `max_selections` | `number` | X | 최대 선택 개수 |

**예시:**

```json
{
  "type": "checkbox-group",
  "name": "visual_effects",
  "label": "시각 효과",
  "request_key": "visual_effects",
  "request_value_type": "string[]",
  "description": "적용할 효과를 모두 선택하세요",
  "required": true,
  "options": [
    { "value": "shadow", "label": "그림자" },
    { "value": "glow", "label": "글로우" },
    { "value": "gradient", "label": "그라디언트" },
    { "value": "outline", "label": "외곽선" }
  ],
  "default_value": ["shadow"],
  "min_selections": 1,
  "max_selections": 3
}
```

---

### 7.8 switch - 토글 스위치

단일 토글 스위치 필드입니다 (boolean 값). 체크박스와 동일한 기능이지만 UI가 다릅니다.

| 속성 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `type` | `"switch"` | O | |
| `default_value` | `boolean` | X | 기본 활성화 상태 (기본: `false`) |
| `switch_label` | `string` | X | 스위치 옆에 표시될 텍스트 |

**예시:**

```json
{
  "type": "switch",
  "name": "enable_animation",
  "label": "애니메이션",
  "request_key": "enable_animation",
  "request_value_type": "boolean",
  "switch_label": "텍스트 애니메이션 활성화",
  "default_value": true
}
```

---

### 7.9 file - 파일 업로드

파일 업로드 필드입니다. **프론트엔드가 업로드 후 URL로 변환하여 전송합니다.**

| 속성 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `type` | `"file"` | O | |
| `accept` | `string` | X | 허용 확장자 (예: `".jpg,.png,.pdf"`) |
| `max_size` | `number` | X | 최대 파일 크기 (bytes, 예: `20971520` = 20MB) |
| `max_files` | `number` | X | 최대 파일 개수 (기본: 1) |
| `upload_label` | `string` | X | 업로드 영역 안내 텍스트 |
| `upload_description` | `string` | X | 업로드 영역 설명 텍스트 |

**예시:**

```json
{
  "type": "file",
  "name": "background_overlay",
  "label": "배경 오버레이 (선택)",
  "request_key": "background_overlay",
  "request_value_type": "string",
  "description": "제품 이미지 위에 오버레이할 배경 이미지",
  "accept": ".png,.jpg,.jpeg",
  "max_size": 10485760,
  "max_files": 1,
  "upload_label": "배경 이미지를 업로드하세요",
  "upload_description": "PNG, JPG 파일 | 10MB 이하"
}
```

---

## 8. Request 매핑

### 8.1 폼 → Request 변환

각 필드의 `request_key`와 `request_value_type`이 API Request의 `input_data` 구조를 명시적으로 정의합니다.

**`form_fields` 컬럼:**

```json
[
  { "type": "file", "name": "product_image", "request_key": "product_image", "request_value_type": "string", ... },
  { "type": "textarea", "name": "copy_text", "request_key": "copy_text", "request_value_type": "string", ... },
  { "type": "select", "name": "font_style", "request_key": "font_style", "request_value_type": "string", ... }
]
```

**`request_dto` 컬럼:**

```json
{
  "product_image": "string",
  "copy_text": "string",
  "font_style": "string",
  "primary_color": "string"
}
```

**사용자 입력 (Frontend Form):**

```javascript
{
  product_image: File,          // File 객체
  copy_text: "35% off",
  font_style: "modern",
  primary_color: "#FF5733"
}
```

**API Request:**

```json
{
  "type": "promotional_image",
  "project_id": "uuid",
  "template_id": "uuid",
  "output_count": 4,
  "input_data": {
    "product_image": "https://storage.supabase.co/.../image.jpg",
    "copy_text": "35% off",
    "font_style": "modern",
    "primary_color": "#FF5733"
  }
}
```

### 8.2 파일 필드 변환

파일 필드는 다음 과정을 거칩니다:

1. 사용자가 파일 선택 (`File` 객체)
2. Frontend가 Supabase Storage에 업로드
3. Storage URL 획득
4. Request의 `input_data`에 필드의 `request_key`로 URL 포함

**예시:**

```json
// Config
{ "type": "file", "name": "logo_image", "request_key": "logo_image", "request_value_type": "string" }

// Request
{ "input_data": { "logo_image": "https://..." } }
```

---

## 9. 전체 예시

### 9.1 홍보 이미지 템플릿 (promotional_image)

**`form_fields` 컬럼:**

```json
[
  {
    "type": "file",
    "name": "product_image",
    "label": "제품 이미지",
    "request_key": "product_image",
    "request_value_type": "string",
    "required": true,
    "accept": ".jpg,.png,.jpeg",
    "max_size": 20971520,
    "max_files": 1,
    "upload_label": "제품 또는 상품 이미지를 업로드하세요",
    "upload_description": "JPG, PNG 파일 | 20MB 이하"
  },
  {
    "type": "textarea",
    "name": "copy_text",
    "label": "홍보 문구",
    "request_key": "copy_text",
    "request_value_type": "string",
    "description": "이미지에 표시될 메인 카피를 입력하세요",
    "placeholder": "예) 35% off, Order Now",
    "required": true,
    "max_length": 100,
    "rows": 3
  },
  {
    "type": "select",
    "name": "font_style",
    "label": "폰트 스타일",
    "request_key": "font_style",
    "request_value_type": "string",
    "placeholder": "폰트를 선택하세요",
    "required": true,
    "options": [
      { "value": "modern", "label": "모던" },
      { "value": "classic", "label": "클래식" },
      { "value": "handwritten", "label": "손글씨" },
      { "value": "bold", "label": "볼드" }
    ],
    "default_value": "modern"
  },
  {
    "type": "radio",
    "name": "text_position",
    "label": "텍스트 위치",
    "request_key": "text_position",
    "request_value_type": "string",
    "required": true,
    "options": [
      { "value": "top", "label": "상단" },
      { "value": "center", "label": "중앙" },
      { "value": "bottom", "label": "하단" }
    ],
    "default_value": "center",
    "horizontal": true
  },
  {
    "type": "checkbox",
    "name": "add_shadow",
    "label": "그림자 효과",
    "request_key": "add_shadow",
    "request_value_type": "boolean",
    "checkbox_label": "텍스트에 그림자 효과 추가",
    "default_value": false
  }
]
```

**`request_dto` 컬럼:**

```json
{
  "product_image": "string",
  "copy_text": "string",
  "font_style": "string",
  "text_position": "string",
  "add_shadow": "boolean"
}
```

### 9.2 영상 컨텐츠 템플릿 (video_content)

**`form_fields` 컬럼:**

```json
[
  {
    "type": "file",
    "name": "product_image",
    "label": "제품 이미지",
    "request_key": "product_image",
    "request_value_type": "string",
    "required": true,
    "accept": ".jpg,.png,.jpeg",
    "max_size": 20971520,
    "max_files": 1
  },
  {
    "type": "textarea",
    "name": "copy_text",
    "label": "영상 홍보 문구",
    "request_key": "copy_text",
    "request_value_type": "string",
    "placeholder": "예) 지금 바로 만나보세요",
    "required": true,
    "max_length": 50
  },
  {
    "type": "select",
    "name": "animation_style",
    "label": "애니메이션 스타일",
    "request_key": "animation_style",
    "request_value_type": "string",
    "required": true,
    "options": [
      { "value": "fade", "label": "페이드" },
      { "value": "slide", "label": "슬라이드" },
      { "value": "zoom", "label": "줌" },
      { "value": "bounce", "label": "바운스" }
    ],
    "default_value": "fade"
  },
  {
    "type": "checkbox",
    "name": "add_bgm",
    "label": "배경음악",
    "request_key": "add_bgm",
    "request_value_type": "boolean",
    "checkbox_label": "배경음악 추가",
    "default_value": true
  }
]
```

**`request_dto` 컬럼:**

```json
{
  "product_image": "string",
  "copy_text": "string",
  "animation_style": "string",
  "add_bgm": "boolean"
}
```

### 9.3 필드 없는 단순 템플릿

동적 필드가 필요 없는 경우 빈 배열/객체로 설정합니다. (권장 패턴 필드만 사용)

**`form_fields` 컬럼:**

```json
[]
```

**`request_dto` 컬럼:**

```json
{}
```

---

## 10. 작성 가이드라인

### 10.1 필드 순서

1. **필수 입력 필드를 먼저 배치**
2. **관련 필드끼리 그룹화**
3. **선택적 고급 옵션은 마지막에 배치**

### 10.2 검증 규칙

- 텍스트 필드: `max_length` 설정 권장 (과도한 입력 방지)
- 숫자 필드: `min`, `max` 범위 설정 필수
- 선택 필드: 최소 2개 이상의 옵션 제공
- 파일 필드: `accept`, `max_size` 설정 권장

### 10.3 기본값

- 자주 사용되는 값을 `default_value`로 설정
- 사용자 경험 개선을 위해 적절한 기본값 제공
- 필수 필드도 기본값을 가질 수 있음

### 10.4 주의사항

1. **name 중복 금지**: 같은 config 내에서 `name`은 유일해야 함
2. **JSON 유효성**: Supabase에 저장하기 전 JSON 유효성 검증 필수
3. **타입 일관성**: `type`에 따른 필수 속성 준수 (예: `number`는 `min`, `max` 필수, `checkbox-group`는 `options` 필수)
4. **Request 매핑 일관성**: 모든 필드는 `request_key`와 `request_value_type`을 반드시 포함해야 함
