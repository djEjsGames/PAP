extends RefCounted
const Paper := preload("res://scripts/paper_geometry.gd")
const Dump := preload("res://scripts/paper_dump.gd")
const COLORS := [Color("7de1d2"), Color("f0c878"), Color("c5a6ef")]
const NAMES := ["날개 1", "날개 2", "손잡이"]

static func signature(faces: Array[Dictionary], history: Array[Dictionary]) -> String:
	var geometry: Array[Dictionary] = []
	for entry in history:
		geometry.append({"kind": entry.kind, "faces": entry.faces, "plan": entry.get("plan", {}), "single_layer": entry.get("single_layer", false)})
	return JSON.stringify(Dump.encode({"faces": faces, "history": geometry}), "", true, true).sha256_text()

static func schema(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true
	if not value.get("signature") is String or value.signature.length() != 64 or not value.get("wings") is Array or value.wings.size() != 2: return false
	for index in value.wings + [value.get("grip")]:
		if not (index is int or index is float) or not is_finite(float(index)) or index != floor(index) or index < 0 or index > 100000: return false
	return true

static func valid(value: Dictionary, faces: Array[Dictionary], history: Array[Dictionary]) -> bool:
	if not schema(value) or value.is_empty() or value.signature != signature(faces, history): return false
	if value.wings[0] == value.wings[1] or value.grip >= faces.size(): return false
	for index in value.wings:
		if index >= history.size() or history[int(index)].kind != "fold": return false
	return not affected(faces[int(value.grip)], history[int(value.wings[0])]) and not affected(faces[int(value.grip)], history[int(value.wings[1])])

static func affected(face: Dictionary, entry: Dictionary) -> bool:
	var center := Vector2.ZERO
	for point in face.paper: center += point
	center /= face.paper.size()
	for part in entry.plan.move:
		if Paper._inside_convex(part.paper, center): return true
	return false

static func role(face_index: int, faces: Array[Dictionary], history: Array[Dictionary], wings: Array[int], grip: int) -> int:
	if face_index == grip: return 2
	for i in wings.size():
		if wings[i] >= 0 and wings[i] < history.size() and affected(faces[face_index], history[wings[i]]): return i
	return -1
