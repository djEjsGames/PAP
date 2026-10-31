# 공원 최소 플레이 루프 1–5단계 검토본

구현·검증: 2026-10-26–27 (Asia/Seoul). [요청 범위](../planning/park-core-loop-2026-10-26.md)에 따라 이동부터 같은 기체의 회수·재투척까지 연결했다. 커밋·푸시·공개 Pages 배포는 하지 않았다.

## 실행과 연결된 흐름

F5의 시작 장면은 scenes/park.tscn이다. 기존 scenes/main.tscn은 독립 접기·비행 회귀 경로로 남겼다.

1. WASD로 공원을 이동한다. 우클릭 드래그로 시선, 휠로 거리를 조절한다. 기본 색종이 한 장과 고정 발견 비행기 하나를 제공한다.
2. 작업대 가까이에서 E를 누르면 기존 접기 편집기가 열린다. 공원과 다른 3D 월드를 쓰는 SubViewport 안에서 편집해 조명·충돌·카메라가 섞이지 않게 했다. 새 용지·가이드·부위 지정·내 도면·15° 스냅을 재사용한다.
3. **접기 마치고 보관 [B]**는 동일한 실물 ID의 상태를 갱신한다. **수정 취소 · 공원으로**는 원본을 유지한다. 두 출구 모두 원래 플레이어 위치·시선으로 돌아온다.
4. I로 보관함을 열고 목록에서 선택해 꺼낸다. 미리보기·용지 종류/크기·접기 횟수를 표시한다. 작업대 근처에서는 같은 기체를 수정할 수 있다.
5. Space로 현재 위치에서 투척 준비에 들어간다. 준비에서는 기체가 보이는 가까운 시점을 사용하며 우클릭으로 조준한다. 자세/날개 조정에서는 기존 수치·축 회전과 확대 시점을 사용한다.
6. Space/Enter로 게이지 시작 → 강도 확정 → 복귀 원점 입력을 한다. 발사와 함께 같은 기체가 손에서 월드로 이동한다.
7. B로 관람을 끝내면 플레이어 시점으로 돌아온다. 기체의 물리는 계속 실행된다. 착지 표식을 따라가 가까이에서 E로 회수하고 I로 꺼내 다시 던진다.

공원의 Ctrl+Shift+D는 pap-park-dump 형식으로 물건 ID·소유 상태·원본 종이·물성·현재 위치/속도·발사 상태와 기록을 덤프한다. 작업대에서는 기존 접기 덤프를 사용한다. 공원 덤프는 검사 용도이며 공원 저장 파일을 불러오는 기능은 아니다.

## 단계별 결과

| 단계 | 결과 |
|---|---|
| 1 이동·임시 공간 | 충돌 바닥·간단한 플레이어·작업대·시험 공간·외곽 경계. 가장 가까운 작업대/착지 기체 한 대상의 행동 안내 |
| 2 작업대 접기 | 기존 편집기 재사용. 명시적 보관/취소와 원래 위치·시선 복귀 |
| 3 실물 보관함 | ID별 저장/손/작업/비행/바닥 중 한 상태. 편집은 복사본에서 하고 보관 성공 시 같은 ID에 반영 |
| 4 월드 투척 | 발밑 지면 + 1.7m의 COM. 게이지 시작 시 위치·시선 yaw/pitch 고정. 벽/작업대와 겹치거나 바로 앞이 막힌 발사 거절 |
| 5 관람·회수 | 추적 종료와 비행 종료 분리. 실제 착지 후 표식·회수·같은 기체 재투척 |

최소 루프의 바닥·실물 보관함·비행 기록은 실행 중 세션 범위다. 내 도면의 영구 저장 경로와 원자적 저장 방식을 변경하지 않았다. 실물 수정이나 회수가 독립 저장 도면을 덮어쓰지 않는다.

## 유지한 규칙과 수정 지점

- park_flight.gd는 기존 flight_test.gd를 상속한다. 기체 구성·툰 재질·질량/관성·공력·게이지 계산·바람·자세 UI를 재사용하고, 월드 발사 위치·시선 방향·소유 전환·착지/관람 처리를 연결했다.
- 강도 확정 후 끝점까지 진행·복귀, 20px 원점, 고도각에만 적용하는 오차, 자동 빗맞음은 유지했다. 월드에서는 시선 고도각을 사용하며 독립 시험의 ↑↓ 입력은 적용하지 않는다.
- 월드 비행에는 독립 시험의 12초 종료/공중 고정을 적용하지 않는다. 접촉하고 충분히 느린 상태가 0.25초 이어지면 착지로 기록하며 몸체의 월드 물리는 계속 유지한다.
- 비유한 위치/속도/각속도 오류에는 같은 ID와 종이·설정을 보관함으로 복구한다. 중복 복구는 추가 기체나 중복 오류 기록을 만들지 않는다.
- 회전 링은 실제 몸체의 월드 자세에서 시작하고 공원 yaw를 제외한 자세 보정으로 변환한다. 일반 마우스 드래그로 기체를 돌리는 기능은 추가하지 않았다.
- 고정된 준비 기체를 월드로 옮긴 후 보간 기준도 갱신한다. 매 프레임 준비 초기화를 제거해 연속 회전 링 드래그가 끊기지 않게 했다.
- 색종이 15×15cm/80gsm, A4 21×29.7cm/80gsm, 신문 39.1×54.5cm/45gsm, 4절 39.4×54.5cm/120gsm과 이전 도면의 실제 좌표·평량을 유지했다.

## 검증

| 검사 | 결과 |
|---|---|
| 공원 연속 GPU·헤드리스 | 각각 178 checks, 0 failures |
| 기존 전체 GPU | 16,368 checks, 0 failures |
| 기존 전체 헤드리스 | 15,662 checks, 0 failures |
| 기존 독립 왕복 흐름 | 90 checks, 0 failures |
| 15° 선긋기·이전 용지 | 383 checks, 0 failures |
| Edge WebGL2 실제 키·마우스 | 19 checks, errors 없음 |
| 최종 로컬 Web 내보내기 | 성공 |

tests/test_park.gd는 두 해상도에서 이동→작업대→취소→접은 기체 보관→꺼내기→게이지→두 위치/좌우·상하 방향 발사→관람 종료→실제 착지→회수→재투척을 실행한다. 원본 재료 좌표/이력, 비대칭 날개 각도, 중복 입력·회수, 게이지 이동 잠금, 벽 차단, 지면 높이 1m 위의 2.7m 발사, 4절 실제 질량, 별도 도면 보호, 수치 오류 소유 복구도 검사한다. CI에 공원 검사를 추가했다.

웹에서는 실제 WASD·E·I·우클릭·휠·Space·Esc·B와 버튼 클릭으로 작업대 도면 저장, 투척 취소, 강도 확정 후 바깥 진행, 자동 빗맞음, 관람 종료 후 이동·회수, 640 창에서 같은 실물의 두 번째 투척을 확인했다. 브라우저 IndexedDB에서 저장된 도면의 형식과 이름도 확인했다. 웹의 이 연속 검사는 기본 평판 종이를 사용하며, 접힌 기체의 두 번 비행은 네이티브 연속 검사에서 확인했다.

로그: [공원 GPU](../../build/park_gpu.log), [공원 헤드리스](../../build/park_headless.log), [전체 GPU](../../build/park_full_gpu.log), [전체 헤드리스](../../build/park_full_headless.log), [왕복](../../build/park_flow_headless.log), [선긋기](../../build/park_line_headless.log), [웹](../../build/park_web_browser.log), [내보내기](../../build/park_web_export.log).

## 연속 검토 화면

아래는 각 단계에서 이어서 캡처한 네이티브 화면이다. 두 해상도에서 두 위치·방향의 투척과 회수를 반복한다.

| 단계 | 1280×720 | 640×360 |
|---|---|---|
| 시작 | [화면](../../build/previews/defaults_park_start_1280.png) | [화면](../../build/previews/defaults_park_start_640.png) |
| 이동·작업대 안내 | [화면](../../build/previews/defaults_park_bench_1280.png) | [화면](../../build/previews/defaults_park_bench_640.png) |
| 접기·보관 출구 | [화면](../../build/previews/defaults_park_folding_1280.png) | [화면](../../build/previews/defaults_park_folding_640.png) |
| 보관함 선택 | [화면](../../build/previews/defaults_park_inventory_1280.png) | [화면](../../build/previews/defaults_park_inventory_640.png) |
| 첫 위치·조준 | [화면](../../build/previews/defaults_park_aim_0_1280.png) | [화면](../../build/previews/defaults_park_aim_0_640.png) |
| 첫 발사 | [화면](../../build/previews/defaults_park_flight_0_1280.png) | [화면](../../build/previews/defaults_park_flight_0_640.png) |
| 관람 종료 | [화면](../../build/previews/defaults_park_exit_0_1280.png) | [화면](../../build/previews/defaults_park_exit_0_640.png) |
| 착지·회수 안내 | [화면](../../build/previews/defaults_park_recover_0_1280.png) | [화면](../../build/previews/defaults_park_recover_0_640.png) |
| 두 번째 위치·재조준 | [화면](../../build/previews/defaults_park_aim_1_1280.png) | [화면](../../build/previews/defaults_park_aim_1_640.png) |
| 재투척 | [화면](../../build/previews/defaults_park_flight_1_1280.png) | [화면](../../build/previews/defaults_park_flight_1_640.png) |
| 두 번째 회수 | [화면](../../build/previews/defaults_park_recover_1_1280.png) | [화면](../../build/previews/defaults_park_recover_1_640.png) |

웹 화면: [작업대](../../build/park_web_editor.png), [저장 완료](../../build/park_web_saved.png), [왕복 게이지](../../build/park_web_outbound.png), [월드 복귀](../../build/park_web_world.png), [회수](../../build/park_web_recovered.png), [640 보관함](../../build/park_web_small_inventory.png), [640 재투척](../../build/park_web_rethrow.png). build 화면과 로그는 로컬 산출물이며 Git에 올리지 않았다.

## 남은 범위와 한계

임시 블록 공간과 캡슐 플레이어이며 정식 공원 미술·캐릭터 애니메이션·손에 드는 애니메이션은 없다. 고정 발견 기체 하나만 제공하며 랜덤 모형/배치·경제·NPC·봉사 보상은 후속 6–7단계다. 공원/실물 인벤토리의 종료 후 복원, 도면에서 실물을 무제한 생성하는 기능은 추가하지 않았다.

사람이 직접 평가한 조작감, 실제 태블릿 터치·Safari, 장시간/다수 기체 부하 검증은 하지 않았다. 기존 비행 물리의 시간 간격별 궤적 수렴 과제도 남아 있다. 화면과 자동 검사는 최소 루프의 연결과 보존 확인이며 완성 게임의 품질 판정은 아니다.
