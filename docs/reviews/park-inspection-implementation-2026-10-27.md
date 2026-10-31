# 공원 HUD·준비 구도·캐릭터·살펴보기 구현 — 2026-10-27

[후속 명세](park-review-and-inspection-2026-10-27.md)에 따라 네 항목을 구현했다. F5의 시작 장면은 기존 공원이다. 커밋·푸시·공개 Pages 배포는 하지 않았다. Web은 로컬 빌드와 실제 Edge 입력까지 검증했다.

## 적용 결과

| 항목 | 구현 |
|---|---|
| HUD | 현재 소지/보관 상태, 대상 행동, 고정된 하단 행동을 구분. 상태16px·하단 행동18px·대상20px. 짙은 바탕·패딩·윤곽 적용 |
| 준비 구도 | 실제 기체 COM은 지면+1.7m 유지. 카메라만 조정해 화면 높이48%에 배치. 실제 정점으로 기본 거리를 계산 |
| 캐릭터 | Kenney skaterMaleA/characterMedium 실제 FBX·스킨·idle/run 적용. 미터 단위·전방·발밑·충돌 캡슐 정렬과 손 소지/준비 자세 |
| 발견물 살펴보기 | 새로운 발견물 집기→3D 관찰→보관/다시 놓기/정리. 내 기체의 빠른 회수와 보관함 선택 관찰 유지 |

## HUD와 준비 카메라

상태는 왼쪽 위의 짙은 패널, 주요 행동은 고정 하단 영역, 대상 행동은 근처 표식으로 나눴다. 같은 대상이 선택되면 기존 거리 표식을 숨기고 이름·행동·거리를 한 안내로 표시한다. 보관함·투척·상호작용은 하단에서 사용할 수 있다. 미니맵·점수·보상 장식은 추가하지 않았다.

준비 카메라는 기체를 보는 어깨 관찰 구도다. 공원에서 정한 목표 yaw/pitch는 우클릭으로 조정하고 **목표 수치와 방향선**으로 표시한다. 카메라에는 기체를 위에서 보기 위한 yaw−35°와 pitch−25°의 구도 보정(관찰 pitch −55°~−20°)을 사용한다. 카메라의 중앙 광선을 별도의 새 발사 방향으로 적용하지 않는다. 실제 발사는 기존 목표값과 원점 오차 규칙을 사용한다.

따라서 이번 구도 조정은 기체를 화면용 위치에 따로 놓고 발사 때 이동시키는 방식이 아니다. 준비 모델과 실제 RigidBody의 위치/정점은 동일하며, 발사 COM·기체 자세·크기·질량은 구도로 보정하지 않았다. 준비 중 목표와 발사 값의 일치는 기존 공원 실제 비행 검사에서도 확인했다.

기본 거리에서는 상단 수치·하단 게이지·바람 HUD 밖에 모든 기체 정점이 오도록 맞춘다. 기본 최소 거리는0.45m이고, 사용자의 근접 확대에서는 부분 잘림을 허용한다. COM은 줌과 무관하게 화면높이48%를 유지한다. 독립 비행 시험의 카메라/조작은 보존했다.

| 검증 조건 | 결과 |
|---|---|
| 1280×720·640×360 × 네 용지 × pitch−10°/0°/+15° × zoom1.5/4/9 | 총72조건 |
| COM y/H | 약0.479999~0.480001 |
| 기본 zoom4의 기체 정점 투영 | 화면 안, 상단/하단 HUD와 비겹침 |
| 실제 COM·질량 | 기존 지면+1.7m와 용지별 질량 유지 |
| 기본 조건 손가락 본의 집는 점→손잡이 목표 | 최대 약2.9mm 오차 |

숫자는 엔진 투영/본 위치 측정이며 손으로 느끼는 조준감이나 실제 피부 표면 접촉을 실측한 결과는 아니다. 가까운 확대에서는 기체 앞을 가리는 캐릭터 조각에만 국소 투명 처리를 적용한다. 전체 시각 모델을 숨기는 처리는 제거했다.

측정: [72조건 JSON](../../build/park_review_camera_measurements.json).

## 캐릭터 자산과 실제 적용 범위

[Kenney Animated Characters Protagonists 공식 페이지](https://kenney.nl/assets/animated-characters-protagonists)의 동봉 CC0 자산을 적용했다. 선정된 characterMedium.fbx·skaterMaleA.png·idle.fbx·run.fbx만 가져왔고, 원문 [License.txt](../../assets/characters/kenney/License.txt)와 [출처·적용 기록](../../assets/characters/kenney/SOURCE.md)을 보존했다. 웹 패키지에도 라이선스/출처를 포함하며 로컬 웹 폴더와 CI 웹 산출물에 별도 사본을 둔다.

- 원본 FBX의 단위와 축을 미터 기준 약2.0m 캐릭터로 맞추고 전방을−Z로 정렬했다. 발밑 원점과 높이2.0m 충돌 캡슐을 사용한다.
- 실제 공급 idle/run을 AnimationPlayer에 연결하고 이동/정지에서 전환한다. 서로 다른 FBX의 생략된 불변 트랙은 해당 소스 리그의 기준 값으로 채워 이전 동작의 자세가 남지 않게 했다.
- 이동은 기존3m/s이며 이동 동작의 재생 속도도 연결했다. T포즈를 이동으로 대신하지 않았다.
- 손 크기는 원본의60%로 적용하고, 엄지·검지 끝의 집는 점을 실제 기체 손잡이(유효 binding 우선, 없으면 기존 후보)에 맞춘다. 보통 소지와 준비의 상체 자세를 구분했다.
- 소지 표시와 준비의 실제 몸체를 전환할 때 두 기체를 동시에 표시하지 않는다. 날개 설정이 바뀐 뒤에는 소지 표시도 새 설정으로 갱신한다.

이는 실제 스킨과 동작을 사용하는 임시 플레이어 적용이다. 새 walk/throw 클립, 점프 기능, 캐릭터 선택 UI를 만들지 않았다. 손 소지/준비는 절차적 자세이며 정식 투척 애니메이션의 품질을 주장하지 않는다.

## 발견물 관찰과 처리

새 발견물은 E로 집으면 같은 ID를 **inspecting**으로 예약한다. 원래 월드 기체는 숨기고 정지한 채 보관하며, 표시용 복사본을 별도 3D 월드에서 보여 준다. 이 복사본에는 물리 소유권이나 월드 상호작용이 없다. 다른 기체의 배경 비행은 계속된다.

큰3D 모델에서 왼쪽 드래그로 회전하고 휠로 확대한다. 이름·종류·실제 치수·질량을 표시하고 시점 초기화를 제공한다. 작은 창의 오른쪽 설명 영역은 스크롤하며 처리 버튼은 하단에 유지한다.

유효한 부위 binding을 우선하며, 없으면 기존 마지막 두 연결부 접기 후보와 연결 검증을 사용한다. 유효한 두 날개 축이 있을 때90° 펼친 모습을 기본으로 보여 주고 접힌/펼친 모습 전환을 제공한다. 축이 없는 종이에는 날개를 만들지 않는다. 이는 외형 인식 기능이 아니다.

| 행동 | 결과 |
|---|---|
| 보관하기 | 같은 ID를 stored로 전환, 원래 월드 몸체/표식 제거 |
| 다시 놓기 / 월드 관찰 Esc | 원래 transform·속도·정지 상태를 복원하고 world로 반환 |
| 정리하기 | 같은 ID를 cleared로 기록하고 별도의 정리 기록 추가. 보수/가격 없음 |
| 보관함 관찰 Esc | 원래 stored/hand 상태와 보관함으로 복귀 |
| 내 도면으로 남기기 | 기존 Presets 검증·원자적 저장 사용. 실물 처리와 독립적이며 기존 도면을 자동 덮어쓰지 않음 |

이미 내가 던진 기체는 계속 빠르게 회수한다. 보관함의 **살펴보기**로 선택 관찰할 수 있다. 관찰 중 이동·월드 시점·발사 입력을 막으며, 여는 키/홀드/중복 클릭이 보관·정리를 실행하지 않는다. 드래그를 정리 버튼 위에서 끝내도 처리하지 않는 것을 웹 실제 입력으로 확인했다.

관찰의 회전·확대·접힘 전환·도면 참고 저장은 실제 faces/history/material 좌표/stock/각도/자세/binding을 수정하지 않는다. source sheet와 flight_session의 직렬화를 전후 비교했다. 정리 후에도 먼저 저장한 참고 도면은 남는다.

Ctrl+Shift+D는 공원·보관함·살펴보기·관찰의 저장 팝업에서도 사용할 수 있다. 공원 덤프에는 관찰 상태, 정리 기록, 캐릭터 자세 요약, 실제 UI 영역을 포함한다. 기존 접기 덤프와 도면 형식은 변경하지 않았다.

## 검증 결과

| 검사 | 결과 |
|---|---|
| 새 공원 개선/관찰 GPU·헤드리스 | 각각328 checks, 0 failures |
| 기존 전체 GPU | 16,368 checks, 0 failures |
| 기존 전체 헤드리스 | 15,662 checks, 0 failures |
| 네 용지·이전 프로필 | 438 checks, 0 failures |
| 기존 공원 실물 루프 | 178 checks, 0 failures |
| 기존 독립 왕복 흐름 | 90 checks, 0 failures |
| 15°/Shift·이전 용지 | 383 checks, 0 failures |
| Edge WebGL2 실제 키·마우스 | 26 checks, errors 없음 |
| 최종 로컬 웹 내보내기 | 성공 |

새 tests/test_park_review.gd를 CI에 연결했다. 두 해상도의 카메라72조건, 동작 전환·소지 본 접촉, 네 용지의3D 관찰, binding 우선/날개 없는 종이, 원본 직렬화 불변, 보관/반환/정리/중복 처리, 손 소유 상태 복귀, 도면 참고와 정리의 분리, 배경 비행, 포커스 상실의 드래그 종료를 확인한다.

웹은 실제 입력으로 이동/idle↔run, 새 발견물 자동 관찰, 드래그/휠, 접힘 전환, 저장 팝업의 텍스트 입력, Esc 반환, 보관, 보관함 관찰, 준비의 일반 드래그 금지, 우클릭 목표/휠, 게이지의 바깥 진행·자동 발사, 관람 종료·실제 착지·내 기체 빠른 회수,640 관찰/재준비를 확인했다. 새로고침 후 새 발견물을 정리하고 기존 참고 도면이 IndexedDB에 남는 것도 확인했다.

로그: [개선 GPU](../../build/park_review_gpu.log), [개선 헤드리스](../../build/park_review_headless.log), [전체 GPU](../../build/park_review_full_gpu.log), [전체 헤드리스](../../build/park_review_full_headless.log), [용지](../../build/park_review_stock.log), [공원 루프](../../build/park_review_loop.log), [왕복](../../build/park_review_flow.log), [선긋기](../../build/park_review_line.log), [웹](../../build/park_review_web_browser.log), [내보내기](../../build/park_review_web_export.log).

## 연속 PNG

| 장면 | 1280×720 | 640×360 |
|---|---|---|
| 캐릭터 idle·HUD | [화면](../../build/previews/defaults_review_idle_1280.png) | [화면](../../build/previews/defaults_review_idle_640.png) |
| 실제 이동 동작 | [화면](../../build/previews/defaults_review_run_1280.png) | [화면](../../build/previews/defaults_review_run_640.png) |
| 밝은 작업대 안내 | [화면](../../build/previews/defaults_review_bench_1280.png) | [화면](../../build/previews/defaults_review_bench_640.png) |
| 기체 소지 | [화면](../../build/previews/defaults_review_hand_1280.png) | [화면](../../build/previews/defaults_review_hand_640.png) |
| 준비 목표−10° | [화면](../../build/previews/defaults_review_ready_origami_-10_1280.png) | [화면](../../build/previews/defaults_review_ready_origami_-10_640.png) |
| 준비 목표0° | [화면](../../build/previews/defaults_review_ready_origami_0_1280.png) | [화면](../../build/previews/defaults_review_ready_origami_0_640.png) |
| 준비 목표+15° | [화면](../../build/previews/defaults_review_ready_origami_15_1280.png) | [화면](../../build/previews/defaults_review_ready_origami_15_640.png) |
| 신문 준비 | [화면](../../build/previews/defaults_review_ready_news_0_1280.png) | [화면](../../build/previews/defaults_review_ready_news_0_640.png) |
| 4절 준비 | [화면](../../build/previews/defaults_review_ready_board_0_1280.png) | [화면](../../build/previews/defaults_review_ready_board_0_640.png) |
| 발견물 자동 관찰 | [화면](../../build/previews/defaults_review_discovery_1280.png) | [화면](../../build/previews/defaults_review_discovery_640.png) |
| 회전·확대 | [화면](../../build/previews/defaults_review_rotated_1280.png) | [화면](../../build/previews/defaults_review_rotated_640.png) |
| 접힌 모습 | [화면](../../build/previews/defaults_review_folded_1280.png) | [화면](../../build/previews/defaults_review_folded_640.png) |
| 도면 참고 저장 | [화면](../../build/previews/defaults_review_reference_1280.png) | [화면](../../build/previews/defaults_review_reference_640.png) |
| 정리 후 상태 | [화면](../../build/previews/defaults_review_cleared_1280.png) | [화면](../../build/previews/defaults_review_cleared_640.png) |

웹 연속 화면: [idle](../../build/park_review_web_idle.png), [이동](../../build/park_review_web_run.png), [발견물](../../build/park_review_web_discovery.png), [회전](../../build/park_review_web_rotated.png), [접힘](../../build/park_review_web_folded.png), [저장 팝업](../../build/park_review_web_reference_dialog.png), [반환](../../build/park_review_web_placed.png), [보관함](../../build/park_review_web_inventory.png), [준비](../../build/park_review_web_ready.png), [게이지](../../build/park_review_web_outbound.png), [관람 종료](../../build/park_review_web_view_exit.png), [640 관찰](../../build/park_review_web_small_inspection.png), [640 재준비](../../build/park_review_web_small_ready.png), [정리 직전](../../build/park_review_web_small_before_clear.png), [정리 후](../../build/park_review_web_cleared.png). 웹 덤프를 먼저 찍은 화면에는 검사 단축키의 덤프 알림이 표시될 수 있다.

build 로그·JSON·PNG는 로컬 검토 산출물이다.

## 남은 범위

사람의 손맛/읽기 시간, 실제 태블릿 터치·Safari·저사양 장시간 부하는 검증하지 않았다. 준비는 기체 중심의 어깨 관찰 구도이므로 목표 수치·방향선을 기준으로 조준하며, 이 구도의 체감은 사용자 플레이 검토가 필요하다. 손 소지/준비는 절차적 본 제어이고 전용 투척 클립·정교한 지형 발 IK는 없다.

발견물 랜덤 생성·여러 모형·정식 공원 미술·경제·공원/실물 전체 영구 저장은 후속이다. 기존 비행 물리의 시간 간격별 수렴 과제도 이번에 수정하지 않았다. 기존 내 도면 영구 저장은 유지한다.
