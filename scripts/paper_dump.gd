extends RefCounted

const Paper := preload("res://scripts/paper_geometry.gd")

static func encode(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2:
			return {"$type": "Vector2", "x": value.x, "y": value.y}
		TYPE_VECTOR3:
			return {"$type": "Vector3", "x": value.x, "y": value.y, "z": value.z}
		TYPE_TRANSFORM3D:
			return {"$type": "Transform3D", "x": encode(value.basis.x), "y": encode(value.basis.y), "z": encode(value.basis.z), "origin": encode(value.origin)}
		TYPE_PACKED_VECTOR2_ARRAY:
			var points: Array = []
			for point in value:
				points.append([point.x, point.y])
			return {"$type": "PackedVector2Array", "values": points}
		TYPE_PACKED_VECTOR3_ARRAY:
			var points: Array = []
			for point in value:
				points.append([point.x, point.y, point.z])
			return {"$type": "PackedVector3Array", "values": points}
		TYPE_PACKED_INT32_ARRAY:
			return {"$type": "PackedInt32Array", "values": Array(value)}
		TYPE_ARRAY:
			var result: Array = []
			for item in value:
				result.append(encode(item))
			return result
		TYPE_DICTIONARY:
			var result := {}
			for key in value:
				result[key] = encode(value[key])
			return result
	return value

static func decode(value: Variant) -> Variant:
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(decode(item))
		return result
	if value is Dictionary:
		match value.get("$type", ""):
			"Vector2":
				return Vector2(value.x, value.y)
			"Vector3":
				return Vector3(value.x, value.y, value.z)
			"Transform3D":
				return Transform3D(Basis(decode(value.x), decode(value.y), decode(value.z)), decode(value.origin))
			"PackedVector2Array":
				var points := PackedVector2Array()
				for point in value["values"]:
					points.append(Vector2(point[0], point[1]))
				return points
			"PackedVector3Array":
				var points := PackedVector3Array()
				for point in value["values"]:
					points.append(Vector3(point[0], point[1], point[2]))
				return points
			"PackedInt32Array":
				return PackedInt32Array(value["values"])
		var result := {}
		for key in value:
			result[key] = decode(value[key])
		return result
	return value

static func validate(snapshot: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if snapshot.get("format", "") != "pap-fold-dump" or snapshot.get("version", 0) != 1:
		return {"valid": false, "errors": ["Unsupported PAP dump format/version"]}
	var faces: Array[Dictionary] = []
	var input: Variant = snapshot.get("faces", null)
	if not input is Array or input.is_empty():
		return {"valid": false, "errors": ["No paper faces"]}
	for item in input:
		if not item is Dictionary:
			errors.append("Invalid face")
			continue
		if not item.get("points") is PackedVector2Array or not item.get("paper") is PackedVector2Array or not item.get("seams") is PackedInt32Array or not item.get("front") is bool:
			errors.append("Missing material coordinates or seam data")
			continue
		if item.points.size() < 3 or item.paper.size() != item.points.size() or item.seams.size() != item.points.size():
			errors.append("Face vertex/edge counts do not match")
			continue
		for point in item.points:
			if not point.is_finite():
				errors.append("Non-finite folded position")
		for point in item.paper:
			if not point.is_finite():
				errors.append("Non-finite material position")
		if absf(Paper.area(item.points) - Paper.area(item.paper)) > 0.000001:
			errors.append("Face was stretched or lost material")
		faces.append(item)
	if not errors.is_empty():
		return {"valid": false, "errors": errors}
	if not Paper.is_continuous(faces):
		errors.append("Material seams are detached or the sheet is disconnected")
	var material_area := 0.0
	for face in faces:
		material_area += Paper.area(face.paper)
	if absf(material_area - 0.04) > 0.000001:
		errors.append("Original 20cm square material area was not preserved")
	var historical_obstructions: Array[Dictionary] = []
	for entry in snapshot.get("history", []):
		if entry.get("kind", "") != "fold":
			continue
		var before: Array[Dictionary] = []
		before.assign(entry.faces)
		var blocked := Paper.layer_obstructions(before, entry.plan)
		for obstruction in blocked:
			obstruction.fold_number = int(entry.fold_count) + 1
			historical_obstructions.append(obstruction)
	if not historical_obstructions.is_empty():
		errors.append("Recorded folds lift buried paper through stationary upper layers")
	return {"valid": errors.is_empty(), "errors": errors, "face_count": faces.size(), "material_area_m2": material_area, "state": snapshot.get("interaction", {}).get("state", "unknown"), "historical_layer_obstructions": historical_obstructions}
