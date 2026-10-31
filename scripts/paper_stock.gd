extends RefCounted
const Paper := preload("res://scripts/paper_geometry.gd")
const OPTIONS := [
	{"id": "origami", "name": "색종이", "size": Vector2(0.15, 0.15), "gsm": 80.0, "description": "기본 정사각형"},
	{"id": "a4", "name": "A4 복사용지", "size": Vector2(0.21, 0.297), "gsm": 80.0, "description": "긴 직사각형"},
	{"id": "news", "name": "신문지", "size": Vector2(0.391, 0.545), "gsm": 45.0, "description": "국내 대판 · 한 면"},
	{"id": "board", "name": "4절 도화지", "size": Vector2(0.394, 0.545), "gsm": 120.0, "description": "4절 · 사륙 규격"}
]
static var textures: Dictionary = {}

static func option(index: int) -> Dictionary:
	return OPTIONS[index].duplicate(true)

static func legacy(faces: Array[Dictionary]) -> Dictionary:
	return {"id": "legacy", "name": "이전 도면", "size": Paper.material_size(faces), "gsm": 80.0}

static func read(value: Variant, faces: Array[Dictionary]) -> Dictionary:
	var dimensions := Paper.material_size(faces)
	if dimensions == Vector2.ZERO: return {}
	if value == null: value = legacy(faces)
	if not value is Dictionary or not value.get("size") is Vector2 or not (value.get("gsm") is float or value.get("gsm") is int): return {}
	if not value.size.is_finite() or not is_finite(float(value.gsm)) or value.size.distance_to(dimensions) > Paper.JOIN_EPS: return {}
	var expected := {}
	for entry in OPTIONS:
		if entry.id == value.get("id"): expected = entry.duplicate(true)
	# Preserve the initial release's 15cm newsprint/drawing sheets as stored.
	if value.get("id") in ["news", "board"] and value.size.distance_to(Vector2(0.15, 0.15)) <= Paper.JOIN_EPS:
		expected.size = Vector2(0.15, 0.15)
		expected.name = "신문지" if value.id == "news" else "얇은 도화지"
		expected.description = "같은 크기에서 더 가벼움" if value.id == "news" else "같은 크기에서 더 무거움"
	if value.get("id") == "legacy":
		if dimensions.distance_to(Vector2(0.2, 0.2)) > Paper.JOIN_EPS and dimensions.distance_to(Vector2(0.15, 0.15)) > Paper.JOIN_EPS and dimensions.distance_to(Vector2(0.21, 0.297)) > Paper.JOIN_EPS: return {}
		expected = legacy(faces)
	if expected.is_empty() or expected.size.distance_to(value.size) > Paper.JOIN_EPS or not is_equal_approx(float(expected.gsm), float(value.gsm)): return {}
	return expected

static func summary(stock: Dictionary) -> String:
	return "%s · %s×%scm" % [stock.name, String.num(stock.size.x * 100, 1).trim_suffix(".0"), String.num(stock.size.y * 100, 1).trim_suffix(".0")]

static func mass(stock: Dictionary) -> float:
	return stock.size.x * stock.size.y * stock.gsm / 1000.0

static func front(stock: Dictionary) -> Color:
	return {"origami": Color("ed745c"), "legacy": Color("ed745c"), "a4": Color("f7f6f0"), "news": Color("d8d5c9"), "board": Color("eee5d2")}.get(stock.id, Color.WHITE)

static func back(stock: Dictionary) -> Color:
	return Color("fff0cf") if stock.id in ["origami", "legacy"] else front(stock).darkened(0.025)

static func texture(stock: Dictionary) -> Texture2D:
	if stock.id not in ["news", "board"]: return null
	if textures.has(stock.id): return textures[stock.id]
	var image := Image.create(128, 128, false, Image.FORMAT_RGB8)
	image.fill(Color.WHITE)
	for y in 128:
		for x in 128:
			var shade := 1.0
			if stock.id == "news":
				if y % 9 < 2 and x % 42 > 3 and x % 42 < 37: shade = 0.76
				if y < 8 and x > 4 and x < 122: shade = 0.7
			else:
				shade = 0.965 + float((x * 17 + y * 31) % 13) / 400.0
			image.set_pixel(x, y, Color(shade, shade, shade))
	var result := ImageTexture.create_from_image(image)
	textures[stock.id] = result
	return result

static func same(a: Dictionary, b: Dictionary) -> bool:
	return a.get("id") == b.get("id") and a.get("size") == b.get("size") and a.get("gsm") == b.get("gsm")
