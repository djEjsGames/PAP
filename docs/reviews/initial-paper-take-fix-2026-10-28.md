# 시작 직후 색종이 꺼내기 오류 수정

2026-10-28. 초기 색종이의 빈 접기 이력을 생성할 때부터 Array[Dictionary]로 선언했다. 제품 수정은 scripts/park.gd의 초기화 두 줄뿐이다. Parts.valid, Model.pose, launch_frame의 타입 요구와 검증은 유지했다.

수정 전에는 시작→I→꺼내기 직후 손 소유 상태만 전환되고, 타입이 없는 history 때문에 매 프레임 Parts.valid 호출 오류가 나며 carried_id=-1과 빈 mesh가 남았다. 수정 후에는 최초 꺼내기에서 carried_id=1, 실제 손 표시 mesh가 생성되고 이후 프레임에서도 유지된다. 먼저 접기·저장·도면 로드를 할 필요가 없다.

회귀 테스트 tests/test_initial_take.gd는 테스트용 종이를 대입하거나 검증기로 초기 데이터를 정규화하지 않은 새 공원을 사용한다. 두 해상도 1280×720 / 640×360에서 실제 I 키와 꺼내기 버튼을 사용하고 다음을 확인한다.

- 최초 꺼내기 후 여러 프레임의 손 표시, typed 빈 이력, 원본 데이터 보존.
- 미접지 색종이 살펴보기와 같은 손 소유 상태로 복귀.
- 초기 색종이 투척 준비 및 B 취소.
- 작업대 열기→취소, 다시 열기→보관→꺼내기.
- 모든 단계에서 원본 형상·용지·빈 이력·ID·종이 개수 유지와 중복 물리 개체 방지.

| 검사 | 결과 |
|---|---:|
| 신규 초기 꺼내기 — 일반 엔진 헤드리스 | 50 통과 |
| 신규 초기 꺼내기 — GPU | 50 통과 |
| 신규 초기 꺼내기 — 사용자 설치 Mono 헤드리스 | 50 통과 |
| 기존 test_park.gd | 178 통과 |
| 기존 test_park_review.gd | 356 통과 |

최종 로그에서 SCRIPT ERROR / ERROR / WARNING은 없었다. Mono는 D:/Works/Godot_v4.7.1-stable_mono_win64의 Godot 4.7.1을 사용했다. GPU는 Compatibility / NVIDIA GeForce RTX 4060 Ti이며 초기 꺼내기 640×360 캡처도 직접 확인했다.

로그: build/initial_take_fix_headless.log, build/initial_take_fix_gpu.log, build/initial_take_fix_mono.log, build/initial_take_fix_park.log, build/initial_take_fix_park_review.log. 캡처: build/previews/defaults_initial_take_640.png 및 defaults_initial_take_1280.png.

준비 카메라·종이 검증 알고리즘·비행 물리는 변경하지 않았다. 브라우저 실행과 사람의 장시간 플레이는 미검증이다. 커밋·푸시·배포는 수행하지 않았다.
