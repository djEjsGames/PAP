extends RefCounted
const Paper := preload("res://scripts/paper_geometry.gd")

static func material_point(face: Dictionary, position: Vector2) -> Vector2:
	return Paper._map_material_point({"paper": face.points, "points": face.paper}, position)

# Clip a guide to a convex face, preserving each layer's own material coordinates.
static func line_segment(polygon: PackedVector2Array, a: Vector2, b: Vector2, finite: bool) -> PackedVector2Array:
	if a.distance_to(b) < Paper.EPS:
		return PackedVector2Array()
	var direction := (b - a).normalized()
	var normal := direction.orthogonal()
	var low := INF
	var high := -INF
	for i in polygon.size():
		var p := polygon[i]
		var q := polygon[(i + 1) % polygon.size()]
		var dp := (p - a).dot(normal)
		var dq := (q - a).dot(normal)
		if absf(dp) <= Paper.EPS:
			var t := (p - a).dot(direction)
			low = minf(low, t)
			high = maxf(high, t)
		if dp * dq < 0:
			var t := (p.lerp(q, dp / (dp - dq)) - a).dot(direction)
			low = minf(low, t)
			high = maxf(high, t)
	if finite:
		low = maxf(low, 0)
		high = minf(high, a.distance_to(b))
	if high - low <= Paper.EPS:
		return PackedVector2Array()
	return PackedVector2Array([a + direction * low, a + direction * high])

static func point_definition(faces: Array[Dictionary], position: Vector2) -> Dictionary:
	var index := Paper.top_face(faces, position)
	if index < 0:
		return {}
	var point := material_point(faces[index], position)
	return {"kind": "point", "point": point} if point.is_finite() else {}

static func line_definition(faces: Array[Dictionary], a: Vector2, b: Vector2) -> Dictionary:
	var segments: Array[PackedVector2Array] = []
	for face in faces:
		var segment := line_segment(face.points, a, b, false)
		if segment.size() == 2:
			var p := material_point(face, segment[0])
			var q := material_point(face, segment[1])
			if p.is_finite() and q.is_finite():
				segments.append(PackedVector2Array([p, q]))
	return {"kind": "line", "segments": segments} if not segments.is_empty() else {}

static func geometry(faces: Array[Dictionary], definition: Dictionary) -> Dictionary:
	if definition.is_empty():
		return Paper.reference_geometry(faces)
	var centers := PackedVector2Array()
	var segments: Array[PackedVector2Array] = []
	for face in faces:
		if definition.kind == "point":
			if Paper._inside_convex(face.paper, definition.point):
				var mapped := Paper._map_material_point(face, definition.point)
				var duplicate := false
				for existing in centers:
					duplicate = duplicate or existing.distance_to(mapped) < Paper.EPS
				if mapped.is_finite() and not duplicate:
					centers.append(mapped)
		else:
			for material_segment in definition.segments:
				var clipped := line_segment(face.paper, material_segment[0], material_segment[1], true)
				if clipped.size() == 2:
					var p := Paper._map_material_point(face, clipped[0])
					var q := Paper._map_material_point(face, clipped[1])
					if p.is_finite() and q.is_finite() and p.distance_to(q) > Paper.EPS:
						segments.append(PackedVector2Array([p, q]))
	return {"centers": centers, "segments": segments}