# 용지 4종·15cm 기본·1.7m 발사 구현 — 2026-10-26

이 문서는 초기 규격 구현 기록입니다. 이후 사용자 요청에 따른 [신문·4절 새 규격과15° 스냅](line-angle-paper-sizes-2026-10-26.md)이 최신 기준이며, 기존15cm 파일은 보존합니다.

[승인 요구](../planning/paper-options-2026-10-26.md)의 최신 범위를 통합했습니다. 기존 반복 플레이 하단 행동·게이지·카메라·바람·종이 연결과 앞뒷면을 유지했습니다.

## 적용 값

| 용지 | 실제 치수 (m) | 면적 (m²) | 평량 (g/m²) | 질량 (kg) |
|---|---|---:|---:|---:|
| 색종이 | .15×.15 | .0225 | 80 | .0018 |
| A4 복사용지 | .21×.297 | .06237 | 80 | .0049896 |
| 신문지 재단지 | .15×.15 | .0225 | 45 | .0010125 |
| 얇은 도화지 재단지 | .15×.15 | .0225 | 120 | .0027 |
| 기존 도면 (카드 아님) | .20×.20 | .04 | 80 | .0032 |

새 발사 위치는 지면 Y=0에서 기체 **무게중심 Y=1.7m**입니다. 물리·표시 정점을 재료 무게중심 주위로 이동하고 RigidBody 로컬 무게중심은 0이므로 가장자리·카메라 높이를 뜻하지 않습니다. 새 종이·준비·재시도·접기 왕복에서 같은 높이를 사용합니다. 과거 덤프의 1.5m 발사 기록은 변경하지 않았습니다.

## 선택 UX와 보호

처음에는 팝업 없이 기본 색종이로 시작합니다. 용지 요약이 있는 상단 새 종이/R에서 2×2 카드로 비교합니다. 같은 물리 축척의 샘플과 이름·크기·반올림한 한 장 질량을 먼저, 평량·짧은 차이 설명을 보조로 표시합니다. 선택은 테두리·선택 문구·직접 그린 체크로 구분합니다. 웹 폰트의 체크 글리프 누락을 발견해 폰트에 의존하지 않게 했습니다.

카드는 원본을 바꾸지 않습니다. 취소/Esc는 준비한 접기선·이력·부위·실행 중 비행 맥락까지 유지합니다. 이 종이로 시작에서만 교체하며 기존 작업 교체를 창 안에 알립니다. 저장하고 시작은 기존 내 도면 창으로 연결합니다. 실패·취소 시 원본을 유지하고 예약을 해제하며, 저장 성공 뒤에만 새 종이를 만듭니다. 저장되는 것은 새 빈 종이가 아니라 이전 작업입니다. 덮어쓰기·불러오기 확인은 유지하고 다른 출구로 저장을 우회하지 못하도록 버튼/콜백을 보호합니다. 발사·재시도에는 선택 창을 추가하지 않았습니다.

## 실제 반영

- 원지는 실제 사각형 치수를 사용하며 A4를 자르거나 정사각형으로 늘리지 않습니다.
- Model.properties에 평량/1000(kg/m²)을 전달합니다. 같은 형상에서 질량·관성은 평량에 비례하며 같은 공력의 가속도는 질량에 반비례합니다. 겹친 층의 질량 보존·노출 면적 중복 제거는 유지합니다.
- 용지별 공력 계수·거리/양력 보너스·감쇠를 추가하지 않았습니다. 현재 강체 모델에 없는 강성·탄성·휘어짐은 구현하지 않았습니다.
- 자체 생성 인쇄 패턴과 옅은 질감을 카드와 실제 종이에 사용합니다. 재료 좌표 UV로 접기·펼침·비행에도 무늬가 재료를 따라갑니다. 비행 셰이더의 층 간격·외곽선·앞뒷면 입력은 유지했습니다. 외부 신문 이미지나 브랜드를 사용하지 않았습니다.
- 정사각형 가이드의 기존 좌표 템플릿만 해당 한 변에 맞게 균일 비례시킵니다. 저장된 도면은 변환하지 않습니다. A4에서는 정사각형 가이드임을 알리고 자유 접기를 허용합니다. 비균일 확대는 하지 않았습니다.
- 새 기본값에서 드러난 부위 미리보기 중복·공선 투영 정점의 삼각분할 오류는 표시용 convex hull로 정리했습니다. 실제 종이 정점·물리 형상은 바꾸지 않았습니다.

## 저장과 기존 데이터

paper_stock에 종류 id/이름·실제 size(Vector2, m)·gsm을 보존하고 프리셋/덤프/발사 기록/화면 왕복에 연결했습니다. 형식 버전 1을 유지하며 메타데이터가 없으면 재료 좌표의 치수와 기존 80g/m²의 이전 도면으로 해석합니다. 20cm 파일·fixture를 .75배 축소하거나 새 선택 항목으로 임의 분류하지 않았습니다.

치수와 재료 좌표 불일치, 승인 id와 다른 평량, 비유한 값 등은 저장/불러오기 검증에서 거절합니다. 이력은 해당 원래 사각형에서 시작해 검증합니다. 과거 기록은 깊은 복사로 보존하고 용지/기체 변경 전 기록을 구분합니다. 같은 기체 왕복은 용지·자세·날개·발사 조건·카메라·완료 기록을 유지합니다. 진행 게이지와 자동 발사 예약은 복원하지 않습니다.

기존 20cm/80g/m²/1.5m 재현 덤프의 240Hz 실행은 여전히 약 1.454초 착지와 기존 에너지 결과를 냈습니다. 새 높이를 과거 재현에 적용하지 않았습니다. 선택지는 정확히 4개이며 큰 20cm/크라프트 카드는 추가하지 않았습니다.

## 검증

| 항목 | 결과 |
|---|---|
| 전체 GPU 접기·층·게이지·카메라·바람 | 16,368 checks, 0 failures |
| 전체 헤드리스 | 15,662 checks, 0 failures |
| 용지 GPU·헤드리스 | 각각 274 checks, 0 failures |
| 기본값/20cm 저장 호환 GPU·헤드리스 | 각각 78 checks, 0 failures |
| 반복 플레이 헤드리스 | 90 checks, 0 failures |
| 기존 에너지/평판 회귀 | 10,120 / 36 checks, 0 failures |
| 로컬 Edge WebGL 2 실제 마우스·키 흐름 | 24 checks, errors 없음 |
| Web 내보내기 | 성공 |

네 용지 모두 두 해상도에서 실제 물리 비행을 완료했고 기록·재시도·접기 왕복의 물성이 유지됐습니다. A4는 일반 접기 컨트롤러와 실제 브라우저 마우스로 직사각형을 반 접었습니다. 평량의 질량/관성과 동일 공력의 가속 반응, 카드 비교/취소 비파괴, 준비된 접기선 보존, 실패/취소/성공 저장 후 시작, 잘못된 메타데이터 거절, 새 높이와 기존 기록 보존을 검사했습니다.

새 검사는 tests/test_defaults.gd와 tests/test_paper_stock.gd이며 배포 전 CI에 연결했습니다. 네이티브에서는 버튼 신호·실제 키 이벤트를, 웹에서는 실제 브라우저 마우스와 키를 사용했습니다. 사람의 손맛·발견 시간을 실측한 것은 아닙니다. 테스트 폴더는 build 아래로 분리했고 실제 사용자 도면을 교체하지 않았습니다.

로그: [전체 GPU](../../build/stocks_full_gpu.log), [전체 헤드리스](../../build/stocks_full_headless.log), [용지 GPU](../../build/stock_choices_gpu.log), [용지 헤드리스](../../build/stock_choices_headless.log), [기본/호환 GPU](../../build/stocks_defaults_gpu.log), [기본/호환 헤드리스](../../build/stock_defaults_headless.log), [반복 흐름](../../build/stock_flow_headless.log), [기존 에너지](../../build/stock_energy_legacy.log), [평판](../../build/stock_research.log), [웹 빌드](../../build/stock_web_export.log), [브라우저](../../build/stock_web_browser.log).

## 화면

| 화면 | 1280×720 | 640×360 |
|---|---|---|
| 네 카드 선택 | [화면](../../build/previews/defaults_stock_picker_0_1280.png) | [화면](../../build/previews/defaults_stock_picker_0_640.png) |
| 기본 색종이 | [화면](../../build/previews/defaults_stock_new_origami_1280.png) | [화면](../../build/previews/defaults_stock_new_origami_640.png) |
| A4 원래 비율 | [화면](../../build/previews/defaults_stock_new_a4_1280.png) | [화면](../../build/previews/defaults_stock_new_a4_640.png) |
| 신문지 인쇄 | [화면](../../build/previews/defaults_stock_new_news_1280.png) | [화면](../../build/previews/defaults_stock_new_news_640.png) |
| 도화지 질감 | [화면](../../build/previews/defaults_stock_new_board_1280.png) | [화면](../../build/previews/defaults_stock_new_board_640.png) |
| 색종이 비행 준비 | [화면](../../build/previews/defaults_stock_ready_origami_1280.png) | [화면](../../build/previews/defaults_stock_ready_origami_640.png) |
| A4 비행 준비 | [화면](../../build/previews/defaults_stock_ready_a4_1280.png) | [화면](../../build/previews/defaults_stock_ready_a4_640.png) |
| 신문지 비행 준비 | [화면](../../build/previews/defaults_stock_ready_news_1280.png) | [화면](../../build/previews/defaults_stock_ready_news_640.png) |
| 도화지 비행 준비 | [화면](../../build/previews/defaults_stock_ready_board_1280.png) | [화면](../../build/previews/defaults_stock_ready_board_640.png) |

기본15cm 접기 완료: [1280](../../build/previews/defaults_15_folded_1280.png) / [640](../../build/previews/defaults_15_folded_640.png).
웹: [큰 창 선택](../../build/stock_web_picker_1280.png), [작은 창 선택·체크](../../build/stock_web_picker_640.png), [신문지](../../build/stock_web_news_new.png), [A4 실제 접기](../../build/stock_web_a4_folded_640.png), [도화지 비행 준비](../../build/stock_web_board_ready_640.png), [도화지 불러오기 확인](../../build/stock_web_board_load_confirm.png). PNG와 웹 스크립트 build/stock-web-check.cjs는 로컬 build 산출물입니다.

## 남은 한계

영구 비행 기록·클라우드·추가 용지 관리 시스템은 만들지 않았습니다. 실행 중 결과 보존과 도면/덤프의 물성 보존까지입니다. 종류·치수·평량은 저장하지만 두께·강성·습도·휘어짐은 아직 물리로 모델링하지 않습니다. 카탈로그 밖 용지나 승인 규격 변경은 검증 정책과 호환 설계를 함께 확장해야 합니다.

대표 발사는 확인했지만 모든 접기·속도·바람에서 정확도나 시간 간격 수렴을 보장하지 않습니다. 기존 수치 적분 수렴 과제는 남아 있습니다. A4 전용 비행기 가이드는 제공하지 않습니다. Safari·실제 태블릿 터치·인간 플레이 체감은 검증하지 않았습니다. 커밋·푸시·공개 Pages 배포는 하지 않았습니다.
