# PAP 접기 UX 개선 검증 — 2026-10-24

기획 세션의 `PAP-folding-review.md`에 요청된 6개 항목을 적용했다. 기존 미커밋 변경을 보존했고 이번 범위의 코드 변경은 `scripts/paper_fold.gd`, 검사 변경은 `tests/test_paper.gd`에 모았다. README에 조작과 배율 정책을 추가했다. 커밋·푸시·신뢰 설정 변경은 수행하지 않았다.

## 구현 내용

1. **작업 영역 분리:** 상·하단 UI와 가이드 오른쪽 열을 제외한 영역에 종이를 맞춘다. 기본 조작은 상단 HFlowContainer, 상태는 하단에 둔다. 640×360에서도 접기 UI의 14px 폰트가 절반으로 축소되지 않는다.
2. **놓기 판정 안내:** 기존 약 99도 기준과 즉시 확정을 유지한다. 확정 가능 여부를 상태 문구와 초록/주황 커서 테두리로 보여 주고, 부족한 각도에서 놓으면 더 넘기라는 안내를 남긴다. 연결·층 관통·면 수 검사는 유지한다.
3. **가이드 화살표:** 노란 잡는 원에서 목표점으로 이동 화살표를 그린다. 잡아끌기와 선 긋기의 설명을 구분한다. 작은 창 전체 재현에서 기존 스냅이 안내선 끝점을 다른 꼭짓점으로 끌던 문제가 발견돼, 가이드 표시 중에는 안내 위치도 스냅 후보에 포함했다. Shift 해제와 자유 접기는 유지한다.
4. **연결부 강조:** 이미 계산한 `fold_plan.move`의 면색과 경계선을 민트색으로 강조한다. 새 호버 해석기나 기하 엔진은 추가하지 않았다.
5. **가이드 끝의 비행 연결:** 마지막 단계에 기존 `_open_flight`를 호출하는 날려보기 버튼을 추가했다. 한 번만 접은 종이로도 이 버튼을 통해 비행 준비에 들어가는 검사를 포함해, 단계 번호가 완성 판정이 아님을 확인한다.
6. **접어 두는 도구:** 새 종이·기준 편집·옆에서 보기·정지·느리게·확정 비교·덤프는 도구 팝업에서 사용한다. 기존 단축키와 기능은 보존한다. 덤프 성공·실패 알림은 팝업 밖에 남겨 닫힌 상태에서도 보인다.

## 투영과 배율 정책

- 종이와 조작 대상의 배치가 갱신되는 것은 포인터 제스처 밖이다. 선 그리기·종이 잡아끌기·확정 대기·기준 드래그 중에는 카메라 변환과 배율을 유지한다.
- 가이드 열기/닫기, 접기 완료·뒤집기, 기존 창의 1280×720 ↔ 640×360 변경 후 `_paper_position(_screen(point))`의 왕복 오차와 UI 비겹침을 검사한다.
- 진행 중 창 크기가 바뀌면 좌표가 갑자기 바뀐 채 접히지 않도록 종이를 유지하며 조작을 취소한다.
- 비행 준비는 기존 1280×720 기준 배율을 사용한다. 복귀 시 `content_scale_size = ZERO`와 접기 투영을 복원하며 실제 마우스 접기를 다시 수행한다.
- headless의 초기 물리 창은 64×64일 수 있어 검사 크기를 디스플레이 초기화 이후 deferred `_run`에서 명시한다. 스냅 기대값을 낮추거나 제품 코드에 headless 전용 분기를 추가하지 않았다.

## 검사 결과

- GPU: `PAP: 9728 checks, 0 failures`.
- Headless: `PAP: 9728 checks, 0 failures`.
- Godot 4.7.1 mono / Compatibility / NVIDIA GeForce RTX 4060 Ti에서 렌더링 검사를 수행했다.
- 전체 기존 종이 연결·층 관통·비행·덤프·사용자 기준 검사와 추가 UX 회귀 검사를 실행했다.
- GPU PNG는 Godot 입력 이벤트와 `root.get_texture().get_image()`로 생성했다. Windows 창 캡처나 사람의 손으로 한 플레이 검증으로 주장하지 않는다.

로그:
- `D:/Works/Git/PAP/build/fold_ux_final_gpu.log`
- `D:/Works/Git/PAP/build/fold_ux_final_headless.log`

## 실제 열람할 PNG

모든 경로의 루트는 `D:/Works/Git/PAP/build/previews/`이다.

| PNG | 확인 내용 |
| --- | --- |
| `ux_01_guide_1280.png`, `ux_01_guide_640.png` | 기본 작업 영역, 가이드, 화살표, 글자 크기 |
| `ux_02_moving_region_1280.png`, `ux_02_moving_region_640.png` | 드래그 중 이동 범위 강조 |
| `ux_03_not_ready_1280.png`, `ux_03_not_ready_640.png` | 놓으면 취소될 상태의 문구·주황 표시 |
| `ux_04_ready_1280.png`, `ux_04_ready_640.png` | 놓으면 확정될 상태의 문구·초록 표시 |
| `ux_05_last_guide_1280.png`, `ux_05_last_guide_640.png` | 마지막 가이드의 날려보기 |
| `ux_06_flight_1280.png`, `ux_06_flight_640.png` | 기존 비행 준비 UI 왕복 |
| `ux_07_return_1280.png`, `ux_07_return_640.png` | 복귀 뒤 접기 배치 복원 |
| `ux_08_dump_notice_1280.png`, `ux_08_dump_notice_640.png` | 도구를 닫은 상태의 저장 알림 |
| `ux_09_completed_640.png` | 최소 크기에서 실제 입력으로 기본형 완주 |
| `13_basic_airplane.png`, `14_airplane_guide.png` | 정상 크기 기본형과 첫 가이드 |

## 남은 한계와 후속 과제

- 실제 손맛, 손가락으로 작은 모서리를 집는 피로, 스냅이 끌리는 느낌, 입력 지연은 사람의 플레이로 확인해야 한다.
- 최소 창의 긴 가이드 문구는 스크롤이 필요하고, 가늘게 접힌 후반 종이는 작게 보인다.
- 임의로 작업 영역 밖까지 끌어내는 모든 모양에 실시간 카메라 추종을 보장하지 않는다. 드래그 중 카메라를 고정하는 정책을 우선하며, 검사는 기본형 전체와 해당 조작 범위를 포함한다.
- 기획 세션이 전달한 ‘초기 능력으로 정상적으로 던진 비행 최소 약 3초’ 목표는 이번 작업에서 튜닝하지 않았다. 기본형 50% 샘플은 약 0.73초, 사용자 기체 50% 샘플은 약 1.65초다. 비행 후 추적 관람과 투척 강습에 따른 힘·각도 정밀도 성장도 별도 기획/구현 범위다.
## 재실행 명령

```powershell
& 'D:\Works\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe' --headless --path 'D:\Works\Git\PAP' --script res://tests/test_paper.gd --log-file 'D:\Works\Git\PAP\build\fold_ux_final_headless.log'
& 'D:\Works\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe' --path 'D:\Works\Git\PAP' --script res://tests/test_paper.gd --log-file 'D:\Works\Git\PAP\build\fold_ux_final_gpu.log' -- --screenshots
```