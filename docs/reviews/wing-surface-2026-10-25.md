# 펼친 종이층 표시 수정 — 2026-10-25

## 원인과 수정

대상은 `pap_2026-10-25T18-56-39_268779306.json`이다. 실제 날개 외곽·축·면적은 대칭이지만, 공면으로 겹친 종이층의 색 선택이 한쪽에서 뒤집혀 보였다.

기존 셰이더는 면 배열 인덱스를 COLOR.a로 받아 카메라 clip-space 깊이를 일괄 변경했다. 접힌 평면의 층 순서는 펼친 뒤 한쪽 날개에서 아래쪽, 다른 쪽에서 위쪽을 향할 수 있으므로 이 규칙은 보는 쪽에 맞는 노출면을 보존하지 못했다.

수정은 다음과 같다.

- `flight_model.gd`: 최종 접힌 평면의 원래 앞면 방향을 `layer_sign`으로 함께 반환한다. 기존 정점과 법선의 계산은 바꾸지 않는다.
- `flight_test.gd`: 접힌 층 순서와 `layer_sign`을 결합해 면 법선 방향의 표시 간격을 UV2에 전달한다. 전체 표시 스택은 최대 0.6mm, 중심에서 최대 0.3mm 이내다.
- `paper_toon.gdshader`: camera-depth 인덱스 편향을 제거하고, 법선 방향으로 표시 간격을 적용한다. 물체 회전과 시점 변화는 일반 깊이 검사에 맡긴다. 앞뒷면 색과 경계선은 그대로 둔다.
- 가까운 종이층의 깊이 정밀도를 위해 비행 카메라 near를 0.01m에서 0.03m로 조정한다. 카메라 조작 UI는 추가하지 않는다.

대칭을 강제로 만드는 보정이나 단색 처리, 경계선 삭제는 하지 않았다. 렌더링 간격은 물리 정점·접기선·연결·충돌 형상·질량·공기력에 적용하지 않는다.

## 보존한 동작

- 손잡이가 아래인 기본 자세와 날개 기본 90°/90°.
- 좌우 발사 방향 정면 고정, 고도각과 던지기 힘.
- 수동 X/Y/Z 회전과 기체 뒤집기.
- 두 날개 독립 조절. 70°/100°로 바꾸면 실제 모양이 바뀌며, 수동으로 뒤집은 자세도 유지된다.
- 기존 접기 가이드, 사용자 기준, 덤프, 비행 회귀 검사.

## 검사 결과

| 실행 | 결과 |
| --- | --- |
| 전체 GPU / Compatibility / RTX 4060 Ti | 12,950 checks, 0 failures |
| 전체 headless | 12,246 checks, 0 failures |
| 이전 자세 코드와 현재 코드 대조 | 9개 조건의 물리 정점·법선 차이 모두 0 |

기존 덤프 `user_completed_airplane`, `grip_orientation`과 새 회귀 fixture `wing_surface_overlap`를 사용한다.
각각 종이 뒤집기 전/후 × 기체 정상/뒤집힘 × 위/아래의 24개 시점에서 GPU 픽셀 색을 실제 렌더 메시에 대한 표면 판정과 비교한다. 픽셀 중심으로 역투영해 샘플 좌표를 맞추고, 접힌 선의 어두운 잉크는 별도로 피한다.
대칭 fixture는 대칭 위치에서 같은 재료 면이 노출되는지도 확인한다. 표시 간격의 상한과 접힌 층 방향, 연결 유지, 독립 날개 조절도 검사한다.

GPU와 headless의 검사 수 차이는 GPU 전용 픽셀·가시성 검사가 headless에서 제외되기 때문이다.
기존 기본형 비행 거리·체공시간과 힘 비교 결과는 수정 전 검사와 동일하다. 비행 성능을 튜닝한 작업이 아니다.

로그와 수치:

- `D:/Works/Git/PAP/build/wing_surface_fix/rendered.log`
- `D:/Works/Git/PAP/build/wing_surface_fix/headless.log`
- `D:/Works/Git/PAP/build/wing_surface_fix/metrics.json`
- `D:/Works/Git/PAP/build/wing_surface_fix/before_after.log`

## 동일 형상·시점의 전후 PNG

루트: `D:/Works/Git/PAP/build/wing_surface_fix/`

| 전 | 후 | 조건 |
| --- | --- | --- |
| `before_01_oblique.png` | `after_01_oblique.png` | 기본 기체 자세 3°, 기존 비스듬한 원근 시점 |
| `before_02_top.png` | `after_02_top.png` | 자세 0°, 평면 직교 |
| `before_03_bottom.png` | `after_03_bottom.png` | 자세 0°, 아래쪽 직교 |
| `before_04_oblique_inverted.png` | `after_04_oblique_inverted.png` | 수동으로 뒤집은 기체를 비스듬히 관찰 |
| `before_05_angles_70_100.png` | `after_05_angles_70_100.png` | 두 날개를 서로 다른 각도로 조절 |
| `before_06_front_wire.png` | `after_06_front_wire.png` | 정면 직교, 얇은 종이의 실제 경계선을 진단용으로 덧그림 |

전후 비교는 같은 물리 정점·자세·카메라를 사용한다. 전 화면은 보존한 이전 셰이더와 면 인덱스 편향을 진단 실행 안에서 복원해 그렸고, 후 화면은 제품의 수정된 셰이더를 사용한다. 양쪽 모두 같은 near 값이다. 실제 제품의 카메라 UI를 바꾼 것은 아니다.
정면의 선 오버레이는 원래 삼각형이 정확히 옆을 향해 보이지 않는 조건을 확인하기 위한 진단 표시다.

기존 분석 당시 02/03/04 PNG와 깊이 편향 반전 06 PNG는 `build/wing_asymmetry/`의 이전 분석 자료로 보존했다.

## 변경 파일

- `scripts/flight_model.gd`
- `scripts/flight_test.gd`
- `shaders/paper_toon.gdshader`
- `tests/test_paper.gd`
- `tests/fixtures/wing_surface_overlap.json`
- `README.md`
- 이 보고서

## 한계

표시용 간격으로 층을 구분하는 방식이며 실제 종이 두께·층간 접촉 시뮬레이션은 아니다. 날개 대상 추정과 임의의 복잡한 면 간 간섭 해석은 바꾸지 않았다.
원근 때문에 가까운 날개가 더 크게 보이는 현상은 남아 있다. 이번에는 실제 노출면의 색과 경계 오류를 수정했으며 대칭 확인용 카메라 UI는 추가하지 않았다.
검증은 Godot 내부 입력·GPU PNG·픽셀 판정 기반이다. Windows 창 캡처나 사람의 손으로 한 플레이 검증이라고 주장하지 않는다.