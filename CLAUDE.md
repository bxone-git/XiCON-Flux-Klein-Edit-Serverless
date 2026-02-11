# XiCON RunPod Serverless 배포 프로젝트

## 프로젝트 개요
ComfyUI 기반 AI 모델을 RunPod Serverless로 패키징하고 배포하는 프로젝트.
각 서브디렉토리가 독립적인 RunPod Serverless 엔드포인트 패키지.

## 현재 배포 상태 (2026-02-10)

| 패키지 | 유형 | 상태 | 엔드포인트 ID | GPU |
|--------|------|------|--------------|-----|
| I2I_KELIN_9b | 이미지 편집 (9B) | 배포 완료 | p6tv6t2d0vjt9c | ADA_24 |
| T2I_KLEIN_4b | 텍스트→이미지 (4B) | 배포 완료 | z4qb2q1bblp36o | ADA_24 |
| I2I_MultiAngle | 8각도 이미지 편집 | 배포 완료 | md6m3pja5o59dw | ADA_24 |
| T2V_LTX2 | 텍스트→영상 (19B) | 배포 완료 | 2phnlzaiuyi5b1 | ADA_24 |

## T2V LTX-2 19B 배포 보고서

### 작업 내용
LTX-2 19B 모델을 사용한 텍스트→영상 생성 RunPod Serverless 엔드포인트를 구축, 배포, 테스트까지 완료.

### 배포 정보
- **GitHub Repo**: https://github.com/bxone-git/XiCON-LTX2-T2V-Serverless
- **Docker Image**: `ghcr.io/bxone-git/xicon-ltx2-t2v-serverless:latest`
- **RunPod Template ID**: `80nrniuq6g`
- **RunPod Endpoint ID**: `2phnlzaiuyi5b1`
- **RunPod Endpoint Name**: XiCON-LTX2-T2V
- **Network Volume**: d0gh9yjyva (XiCON, EU-RO-1)
- **Workers**: 현재 0 (비용 절감), 사용 시 1로 설정 필요

### Supabase 등록
- **Template Name**: XiCON_T2V_LTX2
- **Template ID**: `2ec171be-71e1-4a95-a28b-b533424ea98a`
- **Thumbnail**: 업로드 완료 (`templates/XiCON_T2V_LTX2/thumbnail.jpg`)
- **상태**: `is_active: false` (라이브 전환 시 true로 변경 필요)

### 모델 정보 (총 ~42GB, HuggingFace에서 자동 다운로드)
| 모델 | 파일명 | 크기 | 디렉토리 |
|------|--------|------|----------|
| LTX-2 19B FP8 | ltx-2-19b-dev-fp8.safetensors | 27.1GB | checkpoints |
| Gemma 3 12B Text Encoder | gemma_3_12B_it_fp4_mixed.safetensors | 6GB | text_encoders |
| Distilled LoRA | ltx-2-19b-distilled-lora-384.safetensors | 7.67GB | loras |
| Spatial Upscaler 2x | ltx-2-spatial-upscaler-x2-1.0.safetensors | 996MB | latent_upscale_models |

### 워크플로우 파이프라인
1. **Stage 1 (생성)**: EmptyImage → 0.5x 다운스케일 → EmptyLTXVLatentVideo + EmptyLatentAudio → ConcatAVLatent → SamplerCustomAdvanced (20 steps, cfg=4, euler_ancestral)
2. **Upscale**: SeparateAVLatent → LTXVLatentUpsampler (2x) → ConcatAVLatent
3. **Stage 2 (정제)**: LoRA(distilled) + ManualSigmas(4 steps) → SamplerCustomAdvanced (cfg=1)
4. **출력**: VAEDecodeTiled → AudioVAEDecode → CreateVideo → SaveVideo (mp4)

### API 사용법
```json
{
  "input": {
    "prompt": "영상 설명 (필수)",
    "width": 1280,
    "height": 720,
    "frame_count": 121,
    "seed": 0,
    "negative_prompt": "선택사항"
  }
}
```

### 응답 형식
```json
{
  "video": "base64 인코딩된 mp4",
  "seed": 42,
  "prompt_id": "uuid",
  "frame_count": 25,
  "duration_seconds": 1.04
}
```

### 테스트 결과

#### 1차 테스트 (저해상도, 모델 최초 다운로드)
- **프롬프트**: "A golden retriever puppy playing in a sunny meadow with wildflowers, cinematic lighting, 4k quality"
- **설정**: 640x480, 25프레임, seed=42
- **콜드 스타트**: ~17.7분 (27GB+ 모델 최초 다운로드 포함)
- **실행 시간**: ~2.8분 (영상 생성)
- **출력**: 242KB mp4 파일, 정상 생성 확인

#### 2차 테스트 (풀 해상도, 모델 캐시됨)
- **프롬프트**: "Cinematic drone shot of a futuristic neon-lit Tokyo street at night, rain reflections on the road, flying cars passing by, 4k quality"
- **설정**: 1280x720, 121프레임 (5.04초 @ 24fps), seed=777
- **콜드 스타트**: **228.9초 (~3.8분)** - 모델이 볼륨에 캐시되어 4.7배 단축
- **실행 시간**: **277.7초 (~4.6분)** - 2스테이지 파이프라인 풀 해상도
- **출력**: 2.8MB mp4 파일, 정상 생성 확인

#### 성능 요약
| 항목 | 최초 실행 | 캐시된 실행 | 비고 |
|------|-----------|-------------|------|
| 콜드 스타트 | 17.7분 | 3.8분 | 모델 다운로드 유무 차이 |
| 영상 생성 (저해상도) | 2.8분 | - | 640x480, 25프레임 |
| 영상 생성 (풀해상도) | - | 4.6분 | 1280x720, 121프레임 |

### n8n 워크플로우
- **Workflow ID**: `tqrmPp7oNO87pyZK`
- **Workflow Name**: XiCON_T2V_LTX2_V1
- **Webhook Path**: `ltx2_t2v`
- **상태**: inactive (비활성)
- **노드 수**: 20개
- **기반**: Dance SCAIL 워크플로우 (`iV7920K4Dbro29Ml`) 클론 후 수정
- **변경 사항**:
  - Webhook: `wan-scail-dance` → `ltx2_t2v`
  - SQL template_id → `2ec171be-71e1-4a95-a28b-b533424ea98a`
  - Build Payload: 이미지 입력 제거, prompt만 (1280x720, 121프레임)
  - RunPod endpoint → `2phnlzaiuyi5b1`
  - 파일명: `XiCON_T2V_` 접두사
  - 썸네일 노드 2개 제거 (T2V는 입력 이미지 없음)
- **플로우**: Webhook → SQL → Mark Taken → Build Payload → RunPod Submit → Polling Loop → Extract Video → Upload Storage → Create File → Update Works

### 배포 중 해결한 이슈들
1. **ManualSigmas 노드 오류**: `sigmas_string` → `sigmas`로 입력 키 이름 수정
2. **모델 파일 손상**: 체크포인트가 부분 다운로드(truncated)되어 `safetensors_rust.SafetensorError` 발생 → 파일 크기 검증 로직 추가 (27.1GB 최소 25GB 체크)
3. **심링크 순서**: 모델 다운로드 이후에 심링크 생성하도록 순서 수정
4. **Docker 빌드 캐싱**: GitHub Actions GHA 캐시로 첫 빌드 17분 → 이후 3-5분

## 배운 점 (Lessons Learned)

### ComfyUI 워크플로우
- `ManualSigmas` 노드의 입력 키는 `sigmas` (NOT `sigmas_string`)
- `SamplerCustomAdvanced`/`RandomNoise`는 `noise_seed` 키 사용 (KSampler는 `seed`)
- 서브그래프 노드는 `92:XX` 형식의 프리픽스 사용
- `LTXVAudioVAELoader`는 메인 체크포인트에서 오디오 VAE를 추출

### 모델 관리
- HuggingFace에서 실제 파일 크기를 반드시 확인 (LTX-2 FP8 = 27.1GB, 19GB가 아님!)
- `"incomplete metadata"` 에러 = 파일 손상/불완전, 메타데이터 문제 아님
- 파일 크기 검증은 실제 크기의 ~90%를 최소값으로 설정
- 모델 자동 다운로드 패턴: entrypoint.sh에서 download_if_missing() → 네트워크 볼륨에 영구 저장

### RunPod 배포
- `saveEndpoint` GraphQL에는 반드시 `name`과 `gpuIds` 필드 포함
- 워커 재시작: workersMax=0 → 15초 대기 → workersMax=1
- 콜드 스타트 시 모델 다운로드 시간 고려 (20GB+ = 5-10분)
- entrypoint.sh에서 `set -e` 절대 사용 금지

### Supabase 통합
- `templates` 테이블은 `work_type` 필드가 NOT NULL (필수)
- 썸네일 플로우: Storage 업로드 → files INSERT → templates에 thumbnail_file_id 연결
- 기존 레코드를 항상 참조하여 필드 패턴 확인

## 파일 구조
```
runpod_testby_claudecode/
├── I2I_KELIN_9b/          # Flux Klein 9B 이미지 편집
├── T2I_KLEIN_4b/          # Flux Klein 4B 텍스트→이미지
├── I2I_MultiAngle/        # 8각도 이미지 편집
├── T2V_LTX2/              # LTX-2 텍스트→영상 (최신)
│   ├── Dockerfile
│   ├── handler.py
│   ├── entrypoint.sh
│   ├── workflow_api.json
│   ├── config.ini
│   ├── setup_netvolume.sh
│   ├── .gitignore
│   ├── .github/workflows/docker-build.yml
│   └── test_output.mp4    # 테스트 출력 영상
├── docs/                  # 계획 문서
└── .env.local             # 인증 정보 (git 미추적)
```
