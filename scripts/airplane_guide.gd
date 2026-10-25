extends RefCounted

static func steps() -> Array[Dictionary]:
	var width := 0.2 * tan(PI / 8.0)
	return [
		_fold("중심선 잡기", "종이를 세로로 반 접습니다. 민트색 중심선을 기준으로 오른쪽 가장자리를 왼쪽으로 넘기세요.", Vector2(0, -0.1), Vector2(0, 0.1), Vector2(0.1, 0)),
		{"action": "unfold", "title": "다시 펼치기", "text": "U로 펼칩니다. 가운데 점과 중심 가이드를 이후 접기의 기준으로 사용하세요."},
		_fold("왼쪽 위 모서리", "왼쪽 위 꼭짓점을 가운데 점으로 접습니다. 2번 모드에서는 왼쪽 변 중앙과 위쪽 변 중앙을 잇는 선을 사용하세요.", Vector2(-0.1, 0), Vector2(0, -0.1), Vector2(-0.1, -0.1)),
		_fold("오른쪽 위 모서리", "오른쪽 위 꼭짓점도 가운데 점으로 접어 좌우를 맞춥니다.", Vector2(0, -0.1), Vector2(0.1, 0), Vector2(0.1, -0.1)),
		_fold("왼쪽을 한 번 더", "왼쪽의 비스듬한 가장자리를 세로 중심선에 맞춰 접어 코를 좁힙니다.", Vector2(0, -0.1), Vector2(-width, 0.1), Vector2(-0.1, 0)),
		_fold("오른쪽도 한 번 더", "오른쪽도 중심선에 맞춰 접습니다. 코 끝을 유지하고 좌우가 대칭인지 확인하세요.", Vector2(0, -0.1), Vector2(width, 0.1), Vector2(0.1, 0)),
		_fold("몸통 반 접기", "전체 층 모드로 세로 중심선을 따라 오른쪽을 왼쪽으로 접습니다.", Vector2(0, -0.1), Vector2(0, 0.1), Vector2(width, 0.1)),
		_fold("첫 번째 날개", "3번 위쪽 연결부 모드로 날개를 접습니다. 노란 선을 축으로 바깥 가장자리를 넘기세요.", Vector2(0, -0.1), Vector2(-width * 0.5, 0.1), Vector2(-width, 0.1), true),
		{"action": "flip", "title": "반대쪽으로 뒤집기", "text": "F로 종이를 뒤집어 반대쪽 날개를 위로 가져옵니다."},
		_fold("반대쪽 날개", "위쪽 연결부 모드로 반대쪽 날개도 접습니다. 양쪽 날개를 따로 접은 평평한 기본형입니다. B로 날기 테스트에 들어가 양쪽 날개 각도를 벌리고 발사해 보세요.", Vector2(-width, -0.1), Vector2(-width * 0.5, 0.1), Vector2(0, 0.1), true)
	]

static func _fold(title: String, text: String, a: Vector2, b: Vector2, grab: Vector2, single: bool = false) -> Dictionary:
	var normal := (b - a).normalized().orthogonal()
	var target := grab - normal * 2.0 * (grab - a).dot(normal)
	return {"action": "fold", "title": title, "text": text, "a": a, "b": b, "grab": grab, "target": target, "single_layer": single}
