extends RefCounted
const Dump := preload("res://scripts/paper_dump.gd")
const Paper := preload("res://scripts/paper_geometry.gd")
const MAX_BYTES := 16 * 1024 * 1024
var folder: String
var list_errors := PackedStringArray()

func _init(directory: String = "user://presets") -> void:
	folder = directory

func path_for(name: String) -> String:
	return folder.path_join(name.strip_edges().sha256_text() + ".json")

func list_presets() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	list_errors.clear()
	if not DirAccess.dir_exists_absolute(folder): return items
	for filename in DirAccess.get_files_at(folder):
		if filename.get_extension() != "json": continue
		var path := folder.path_join(filename)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > MAX_BYTES:
			list_errors.append(filename)
			continue
		var json := JSON.new()
		if json.parse(file.get_as_text()) != OK:
			list_errors.append(filename)
			continue
		var value: Variant = json.data
		if value is Dictionary and value.get("format") == "pap-fold-preset" and value.get("name") is String:
			items.append({"name": value.name, "path": path})
		else:
			list_errors.append(filename)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name < b.name)
	return items

func save_preset(name: String, state: Dictionary, overwrite: bool = false) -> Dictionary:
	name = name.strip_edges()
	if name.is_empty() or name.length() > 64: return {"ok": false, "error": "이름을 1–64자로 입력해 주세요."}
	var copy := state.duplicate(true)
	var problem := _validate_state(copy)
	if not problem.is_empty(): return {"ok": false, "error": problem}
	var path := path_for(name)
	if FileAccess.file_exists(path) and not overwrite: return {"ok": false, "error": "같은 이름의 프리셋이 있습니다."}
	var error := DirAccess.make_dir_recursive_absolute(folder)
	if error != OK: return {"ok": false, "error": error_string(error)}
	var text := JSON.stringify(Dump.encode({"format": "pap-fold-preset", "version": 1, "name": name, "saved_at": Time.get_datetime_string_from_system(), "sheet": copy}), "  ", true, true)
	if text.to_utf8_buffer().size() > MAX_BYTES: return {"ok": false, "error": "프리셋 파일이 저장 크기 한도를 넘었습니다."}
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return {"ok": false, "error": error_string(FileAccess.get_open_error())}
	file.store_string(text)
	file.flush()
	error = file.get_error()
	file.close()
	if error == OK: error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "error": error_string(error)}
	return {"ok": true, "path": path, "name": name}

func load_preset(path: String) -> Dictionary:
	if path.get_base_dir() != folder: return {"ok": false, "error": "프리셋 폴더의 파일을 선택해 주세요."}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok": false, "error": "파일을 열지 못했습니다: " + error_string(FileAccess.get_open_error())}
	if file.get_length() > MAX_BYTES: return {"ok": false, "error": "프리셋 파일이 너무 큽니다."}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK: return {"ok": false, "error": "JSON 파일이 손상되었습니다."}
	var value: Variant = json.data
	if not value is Dictionary or value.get("format") != "pap-fold-preset" or value.get("version") != 1 or not value.get("name") is String:
		return {"ok": false, "error": "지원하지 않는 프리셋 형식입니다."}
	if not _encoded_value_valid(value): return {"ok": false, "error": "프리셋의 좌표 데이터가 올바르지 않습니다."}
	var decoded: Dictionary = Dump.decode(value)
	if not decoded.get("sheet") is Dictionary: return {"ok": false, "error": "종이 데이터가 없습니다."}
	var problem := _validate_state(decoded.sheet)
	if not problem.is_empty(): return {"ok": false, "error": problem}
	return {"ok": true, "name": decoded.name, "sheet": decoded.sheet}

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _encoded_value_valid(value: Variant, depth: int = 0) -> bool:
	if depth > 24: return false
	if value is Dictionary:
		if value.has("$type"):
			match value["$type"]:
				"Vector2": return _number(value.get("x")) and _number(value.get("y"))
				"PackedVector2Array":
					if not value.get("values") is Array: return false
					for point in value["values"]:
						if not point is Array or point.size() != 2 or not _number(point[0]) or not _number(point[1]): return false
					return true
				"PackedInt32Array":
					if not value.get("values") is Array: return false
					for number in value["values"]:
						if not _number(number) or number != floor(number) or number < 0 or number > 2147483647: return false
					return true
				_: return false
		for child in value.values():
			if not _encoded_value_valid(child, depth + 1): return false
	elif value is Array:
		for child in value:
			if not _encoded_value_valid(child, depth + 1): return false
	elif value is float:
		return is_finite(value)
	return true

static func _face_list_valid(value: Variant) -> bool:
	if not value is Array or value.size() > 2048: return false
	for face in value:
		if not face is Dictionary or not face.get("points") is PackedVector2Array or not face.get("paper") is PackedVector2Array or not face.get("seams") is PackedInt32Array or not face.get("front") is bool: return false
		if face.points.size() < 3 or face.points.size() != face.paper.size() or face.points.size() != face.seams.size(): return false
		for point in face.points:
			if not point.is_finite(): return false
		for point in face.paper:
			if not point.is_finite(): return false
	return true

static func _same_faces(a: Array[Dictionary], b: Array[Dictionary]) -> bool:
	if a.size() != b.size(): return false
	for i in a.size():
		if a[i].front != b[i].front or a[i].seams != b[i].seams or a[i].points.size() != b[i].points.size(): return false
		for j in a[i].points.size():
			if a[i].points[j].distance_to(b[i].points[j]) > Paper.JOIN_EPS or a[i].paper[j].distance_to(b[i].paper[j]) > Paper.JOIN_EPS: return false
	return true

static func _validate_state(state: Dictionary) -> String:
	if not _face_list_valid(state.get("faces")) or not state.get("history") is Array or not _number(state.get("fold_count")): return "종이 또는 접기 이력이 올바르지 않습니다."
	if state.history.size() > 512: return "접기 이력이 너무 깁니다."
	var typed_faces: Array[Dictionary] = []
	typed_faces.assign(state.faces)
	state.faces = typed_faces
	var typed_history: Array[Dictionary] = []
	for entry in state.history:
		if not entry is Dictionary: return "접기 이력이 올바르지 않습니다."
		typed_history.append(entry)
	state.history = typed_history
	var expected := Paper.square()
	var count := 0
	for entry in state.history:
		if not entry is Dictionary or not _face_list_valid(entry.get("faces")) or entry.get("fold_count", -1) != count or not entry.get("single_layer", false) is bool: return "접기 이력이 올바르지 않습니다."
		var before: Array[Dictionary] = []
		before.assign(entry.faces)
		entry.faces = before
		if not _same_faces(before, expected): return "접기 이력의 순서가 일치하지 않습니다."
		match entry.get("kind"):
			"flip": expected = Paper.flipped(before)
			"fold":
				var plan: Variant = entry.get("plan")
				if not plan is Dictionary or not _face_list_valid(plan.get("stay")) or not _face_list_valid(plan.get("move")) or not plan.get("origin") is Vector2 or not plan.get("normal") is Vector2: return "접기선 데이터가 올바르지 않습니다."
				if not plan.origin.is_finite() or not plan.normal.is_finite() or absf(plan.normal.length() - 1) > 0.0001: return "접기선 좌표가 올바르지 않습니다."
				var stay: Array[Dictionary] = []
				var move: Array[Dictionary] = []
				stay.assign(plan.stay)
				move.assign(plan.move)
				if stay.is_empty() or move.is_empty(): return "접기선의 움직일 부분이 없습니다."
				plan.stay = stay
				plan.move = move
				expected = Paper.folded(plan)
				count += 1
			_: return "지원하지 않는 접기 이력입니다."
		entry.fold_count = int(entry.fold_count)
		entry.single_layer = entry.get("single_layer", false)
	if state.fold_count != count or not _same_faces(typed_faces, expected): return "접기 이력과 현재 종이가 일치하지 않습니다."
	var reference: Variant = state.get("reference", {})
	if not reference is Dictionary: return "기준점 데이터가 올바르지 않습니다."
	if not reference.is_empty():
		if reference.get("kind") == "point":
			if not reference.get("point") is Vector2 or not reference.point.is_finite(): return "기준점 좌표가 올바르지 않습니다."
		elif reference.get("kind") == "line":
			if not reference.get("segments") is Array or reference.segments.is_empty(): return "기준선 데이터가 올바르지 않습니다."
			for segment in reference.segments:
				if not segment is PackedVector2Array or segment.size() != 2 or not segment[0].is_finite() or not segment[1].is_finite(): return "기준선 좌표가 올바르지 않습니다."
		else: return "지원하지 않는 기준점입니다."
	state.reference = reference
	state.fold_count = count
	var report := Dump.validate({"format": "pap-fold-dump", "version": 1, "faces": typed_faces, "history": state.history})
	if not report.valid: return "종이 검증 실패: " + "; ".join(PackedStringArray(report.errors))
	return ""