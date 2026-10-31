extends RefCounted

const EPS := 0.0000001
const JOIN_EPS := 0.000001
const MIN_AREA := 0.00000000000001
const DEFAULT_SIZE := 0.15
const MIN_OVERLAP_AREA := 0.0000000001
const FLOAT32_RELATIVE_EPS := 0.00000011920928955078125

static func square(size: float = DEFAULT_SIZE) -> Array[Dictionary]:
	return rectangle(Vector2.ONE * size)

static func rectangle(size: Vector2) -> Array[Dictionary]:
	var half := size * 0.5
	var points := PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y)])
	return [{"points": points, "paper": points.duplicate(), "seams": PackedInt32Array([0, 1, 2, 3]), "front": true}]

static func material_size(faces: Array[Dictionary]) -> Vector2:
	var low := Vector2(INF, INF)
	var high := -low
	for face in faces:
		for point in face.paper:
			low = low.min(point)
			high = high.max(point)
	if not low.is_finite() or not high.is_finite() or (low + high).length() > JOIN_EPS: return Vector2.ZERO
	return high - low

static func square_size(faces: Array[Dictionary]) -> float:
	var size := material_size(faces)
	return size.x if absf(size.x - size.y) <= JOIN_EPS else 0

static func area(points: PackedVector2Array) -> float:
	var result := 0.0
	for i in range(1, points.size() - 1):
		result += (points[i] - points[0]).cross(points[i + 1] - points[0])
	return absf(result) * 0.5

static func total_area(faces: Array[Dictionary]) -> float:
	var result := 0.0
	for face in faces:
		result += area(face.points)
	return result

static func contains(faces: Array[Dictionary], point: Vector2) -> bool:
	return top_face(faces, point) >= 0

static func top_face(faces: Array[Dictionary], point: Vector2) -> int:
	for i in range(faces.size() - 1, -1, -1):
		if _inside_convex(faces[i].points, point):
			return i
	return -1

static func _inside_convex(points: PackedVector2Array, point: Vector2) -> bool:
	var positive := false
	var negative := false
	for i in points.size():
		var cross := (points[(i + 1) % points.size()] - points[i]).cross(point - points[i])
		positive = positive or cross > 0.00000000001
		negative = negative or cross < -0.00000000001
		if positive and negative:
			return false
	return positive or negative

# Paper coordinates never move: a shared material edge remains a hinge after folding.
static func _clip_face(face: Dictionary, origin: Vector2, normal: Vector2, new_seam: int) -> Dictionary:
	var points := PackedVector2Array()
	var paper := PackedVector2Array()
	var source: PackedVector2Array = face.points
	var material: PackedVector2Array = face.paper
	var all_inside := true
	for p in source:
		if (p - origin).dot(normal) < 0.0:
			all_inside = false
			break
	if all_inside:
		return face.duplicate(true)
	for i in source.size():
		var next := (i + 1) % source.size()
		var dp := (source[i] - origin).dot(normal)
		var dq := (source[next] - origin).dot(normal)
		if dp >= 0.0:
			_append_vertex(points, paper, source[i], material[i])
		if (dp > 0.0 and dq < 0.0) or (dp < 0.0 and dq > 0.0):
			var t := dp / (dp - dq)
			_append_vertex(points, paper, source[i].lerp(source[next], t), material[i].lerp(material[next], t))
	if paper.size() > 1 and paper[0].distance_to(paper[-1]) < EPS * 0.01:
		points.remove_at(points.size() - 1)
		paper.remove_at(paper.size() - 1)
	if area(paper) <= MIN_AREA:
		return {}
	var seams := PackedInt32Array()
	for i in paper.size():
		var seam := new_seam
		for j in material.size():
			var p := material[j]
			var q := material[(j + 1) % material.size()]
			if _on_segment(paper[i], p, q) and _on_segment(paper[(i + 1) % paper.size()], p, q):
				seam = face.seams[j]
				break
		seams.append(seam)
	return {"points": points, "paper": paper, "seams": seams, "front": face.front}

static func _on_segment(point: Vector2, a: Vector2, b: Vector2) -> bool:
	return point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)) <= EPS

static func _append_vertex(points: PackedVector2Array, paper: PackedVector2Array, position: Vector2, material: Vector2) -> void:
	if paper.is_empty() or paper[-1].distance_to(material) > EPS * 0.01:
		points.append(position)
		paper.append(material)

# Match only edges with the same material seam, including partial/T-junction edges.
# Spatial overlap alone does not mean that two stacked layers are joined.
static func connections(faces: Array[Dictionary]) -> Array[Dictionary]:
	var seams := {}
	for index in faces.size():
		var face := faces[index]
		for edge in face.paper.size():
			var id: int = face.seams[edge]
			if not seams.has(id):
				seams[id] = []
			seams[id].append(Vector2i(index, edge))
	var result: Array[Dictionary] = []
	for entries in seams.values():
		for i in entries.size():
			var left: Vector2i = entries[i]
			for j in range(i + 1, entries.size()):
				var right: Vector2i = entries[j]
				if left.x == right.x:
					continue
				var link := _overlap(faces[left.x], left.y, faces[right.x], right.y)
				if not link.is_empty():
					link.a = left.x
					link.b = right.x
					result.append(link)
	return result

static func _overlap(left: Dictionary, edge_a: int, right: Dictionary, edge_b: int) -> Dictionary:
	var next_a: int = (edge_a + 1) % left.paper.size()
	var next_b: int = (edge_b + 1) % right.paper.size()
	var a: Vector2 = left.paper[edge_a]
	var b: Vector2 = left.paper[next_a]
	var c: Vector2 = right.paper[edge_b]
	var d: Vector2 = right.paper[next_b]
	var length := a.distance_to(b)
	# Sub-tolerance edges have unreliable directions and cannot define a shared interval.
	if length < EPS or c.distance_to(d) < EPS:
		return {}
	var direction := (b - a) / length
	var tc := (c - a).dot(direction)
	var td := (d - a).dot(direction)
	var low := maxf(0.0, minf(tc, td))
	var high := minf(length, maxf(tc, td))
	if high - low <= EPS * 0.01:
		return {}
	var p: Vector2 = left.points[edge_a].lerp(left.points[next_a], low / length)
	var q: Vector2 = left.points[edge_a].lerp(left.points[next_a], high / length)
	var other_p: Vector2 = right.points[edge_b].lerp(right.points[next_b], (low - tc) / (td - tc))
	var other_q: Vector2 = right.points[edge_b].lerp(right.points[next_b], (high - tc) / (td - tc))
	return {"p": p, "q": q, "other_p": other_p, "other_q": other_q, "edge_a": edge_a, "edge_b": edge_b, "t0_a": low / length, "t1_a": high / length, "t0_b": (low - tc) / (td - tc), "t1_b": (high - tc) / (td - tc)}

static func is_continuous(faces: Array[Dictionary]) -> bool:
	if faces.is_empty():
		return false
	var neighbors: Array = []
	for _face in faces:
		neighbors.append([])
	for link in connections(faces):
		if link.p.distance_to(link.other_p) > JOIN_EPS or link.q.distance_to(link.other_q) > JOIN_EPS:
			return false
		neighbors[link.a].append(link.b)
		neighbors[link.b].append(link.a)
	var visited := {0: true}
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var index: int = queue.pop_back()
		for next in neighbors[index]:
			if not visited.has(next):
				visited[next] = true
				queue.append(next)
	return visited.size() == faces.size()

static func plan(faces: Array[Dictionary], a: Vector2, b: Vector2, grabbed: Vector2, selected_layer: int = -1) -> Dictionary:
	if a.distance_to(b) < EPS:
		return {}
	var normal := (b - a).normalized().orthogonal()
	if (grabbed - a).dot(normal) < 0.0:
		normal = -normal
	if absf((grabbed - a).dot(normal)) < EPS:
		return {}
	var next_seam := 0
	for face in faces:
		for id in face.seams:
			next_seam = maxi(next_seam, id + 1)
	var pieces: Array[Dictionary] = []
	var source_indices: Array[int] = []
	var positive: Array[bool] = []
	var moving := {}
	for index in faces.size():
		for side in [-1.0, 1.0]:
			var part := _clip_face(faces[index], a, normal * side, next_seam + index)
			if part.is_empty():
				continue
			var piece_index := pieces.size()
			pieces.append(part)
			source_indices.append(index)
			positive.append(side > 0.0)
			if side > 0.0 and (selected_layer < 0 or index == selected_layer):
				moving[piece_index] = true
	if moving.is_empty():
		return {}
	var neighbors: Array = []
	for _piece in pieces:
		neighbors.append([])
	for link in connections(pieces):
		if link.p.distance_to(link.other_p) > JOIN_EPS or link.q.distance_to(link.other_q) > JOIN_EPS:
			return {}
		var on_hinge: bool = absf((link.p - a).dot(normal)) <= EPS and absf((link.q - a).dot(normal)) <= EPS
		if not on_hinge:
			neighbors[link.a].append(link.b)
			neighbors[link.b].append(link.a)
	var bounds: Array[Rect2] = []
	for piece in pieces:
		bounds.append(_bounds(piece.points))
	var queue: Array = moving.keys()
	while not queue.is_empty():
		var index: int = queue.pop_back()
		for next in neighbors[index]:
			if moving.has(next):
				continue
			if not positive[next]:
				return {}
			moving[next] = true
			queue.append(next)
		# A buried part cannot lift through an unchanged upper layer.
		# Carry blocking upper parts too, then follow their material connections.
		for next in pieces.size():
			if moving.has(next) or not positive[next] or source_indices[next] <= source_indices[index]:
				continue
			if bounds[index].intersects(bounds[next]) and overlap_area(pieces[index].points, pieces[next].points) > MIN_OVERLAP_AREA:
				moving[next] = true
				queue.append(next)
	var stay: Array[Dictionary] = []
	var move: Array[Dictionary] = []
	var moved_sources := {}
	for i in moving:
		moved_sources[source_indices[i]] = true
	var kept_sources := {}
	for i in pieces.size():
		var index := source_indices[i]
		if not moved_sources.has(index):
			if not kept_sources.has(index):
				stay.append(faces[index].duplicate(true))
				kept_sources[index] = true
		elif moving.has(i):
			move.append(pieces[i])
		else:
			stay.append(pieces[i])
	if stay.is_empty():
		return {}
	return {"stay": stay, "move": move, "origin": a, "normal": normal}

static func folded(plan_data: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(plan_data.stay.duplicate(true))
	var moving: Array[Dictionary] = []
	moving.assign(plan_data.move)
	for i in range(moving.size() - 1, -1, -1):
		var face: Dictionary = moving[i].duplicate(true)
		var points := PackedVector2Array()
		for p in face.points:
			points.append(p - 2.0 * plan_data.normal * (p - plan_data.origin).dot(plan_data.normal))
		face.points = points
		face.front = not face.front
		result.append(face)
	return result

static func edge_near(faces: Array[Dictionary], point: Vector2, radius: float) -> Dictionary:
	var best := radius
	var result := {}
	for index in faces.size():
		var points: PackedVector2Array = faces[index].points
		for i in points.size():
			var a := points[i]
			var b := points[(i + 1) % points.size()]
			if a.distance_to(b) < EPS:
				continue
			var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
			var distance := point.distance_to(closest)
			if distance > best:
				continue
			var offset := (b - a).normalized().orthogonal() * 0.00001
			var left := top_face(faces, closest + offset)
			var right := top_face(faces, closest - offset)
			if left == right or maxi(left, right) != index:
				continue
			best = distance
			result = {"point": closest, "layer": index}
	return result

static func snap(faces: Array[Dictionary], point: Vector2, radius: float, include_reference: bool = true, override_reference: Dictionary = {}) -> Vector2:
	return snap_candidate(faces, point, radius, include_reference, override_reference).point

static func snap_candidate(faces: Array[Dictionary], point: Vector2, radius: float, include_reference: bool = true, override_reference: Dictionary = {}) -> Dictionary:
	var best := radius
	var result := point
	for face in faces:
		var points: PackedVector2Array = face.points
		for i in points.size():
			for candidate in [points[i], (points[i] + points[(i + 1) % points.size()]) * 0.5]:
				var distance: float = point.distance_to(candidate)
				if distance < best:
					best = distance
					result = candidate
	if not include_reference:
		return {"point": result, "snapped": best < radius}
	var reference := reference_geometry(faces) if override_reference.is_empty() else override_reference
	for candidate in reference.centers:
		var distance: float = point.distance_to(candidate)
		if distance < best:
			best = distance
			result = candidate
	if best < radius:
		return {"point": result, "snapped": best < radius}
	for segment in reference.segments:
		var candidate := Geometry2D.get_closest_point_to_segment(point, segment[0], segment[1])
		var distance := point.distance_to(candidate)
		if distance < minf(best, radius * 0.5):
			best = distance
			result = candidate
	return {"point": result, "snapped": best < radius}

static func flip_center(faces: Array[Dictionary]) -> float:
	var low := INF
	var high := -INF
	for face in faces:
		for point in face.points:
			low = minf(low, point.x)
			high = maxf(high, point.x)
	return (low + high) * 0.5

static func flipped(faces: Array[Dictionary]) -> Array[Dictionary]:
	var center := flip_center(faces)
	var result: Array[Dictionary] = []
	for i in range(faces.size() - 1, -1, -1):
		var face: Dictionary = faces[i].duplicate(true)
		var points := PackedVector2Array()
		for point in face.points:
			points.append(Vector2(2.0 * center - point.x, point.y))
		face.points = points
		face.front = not face.front
		result.append(face)
	return result

static func _bounds(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds

static func overlap_area(left: PackedVector2Array, right: PackedVector2Array) -> float:
	if left.size() < 3 or right.size() < 3: return 0.0
	if not _bounds(left).intersects(_bounds(right)):
		return 0.0
	if _boundary_separated(left, right) or _boundary_separated(right, left): return 0.0
	return _convex_overlap_area(left, right)

static func _convex_overlap_area(left: PackedVector2Array, right: PackedVector2Array) -> float:
	# Faces stay convex after straight cuts. Keep clipping intermediates out of float32 Vector2.
	var polygon := PackedFloat64Array()
	for point in left:
		polygon.append(point.x)
		polygon.append(point.y)
	var winding := 0.0
	for i in range(1, right.size() - 1):
		winding += (float(right[i].x) - right[0].x) * (float(right[i + 1].y) - right[0].y) - (float(right[i].y) - right[0].y) * (float(right[i + 1].x) - right[0].x)
	if winding == 0.0: return 0.0
	var orientation := signf(winding)
	var resolved_edges: Array[bool] = []
	for edge in right.size():
		resolved_edges.append(_has_edge_interior(right, right[edge], right[(edge + 1) % right.size()], orientation))
	for edge in right.size():
		if polygon.size() < 6: return 0.0
		var a := right[edge]
		var b := right[(edge + 1) % right.size()]
		var dx := float(b.x) - a.x
		var dy := float(b.y) - a.y
		# A wholly sub-resolution sliver still needs its actual clipping constraints for material mapping.
		if resolved_edges.has(true) and not resolved_edges[edge]: continue
		var clipped := PackedFloat64Array()
		var px := polygon[-2]
		var py := polygon[-1]
		var previous_distance := orientation * (dx * (py - a.y) - dy * (px - a.x))
		for vertex in range(0, polygon.size(), 2):
			var qx := polygon[vertex]
			var qy := polygon[vertex + 1]
			var distance := orientation * (dx * (qy - a.y) - dy * (qx - a.x))
			if (previous_distance < 0.0) != (distance < 0.0):
				var t := previous_distance / (previous_distance - distance)
				clipped.append(px + t * (qx - px))
				clipped.append(py + t * (qy - py))
			if distance >= 0.0:
				clipped.append(qx)
				clipped.append(qy)
			px = qx
			py = qy
			previous_distance = distance
		polygon = clipped
	if polygon.size() < 6: return 0.0
	var result := 0.0
	for i in range(2, polygon.size() - 2, 2):
		result += (polygon[i] - polygon[0]) * (polygon[i + 3] - polygon[1]) - (polygon[i + 1] - polygon[1]) * (polygon[i + 2] - polygon[0])
	return minf(absf(result) * 0.5, minf(area(left), area(right)))

static func _has_edge_interior(points: PackedVector2Array, a: Vector2, b: Vector2, orientation: float) -> bool:
	var dx := float(b.x) - a.x
	var dy := float(b.y) - a.y
	for p in points:
		var rx := float(p.x) - a.x
		var ry := float(p.y) - a.y
		var scale := maxf(maxf(absf(a.x), absf(a.y)), maxf(maxf(absf(b.x), absf(b.y)), maxf(absf(p.x), absf(p.y))))
		var uncertainty := scale * FLOAT32_RELATIVE_EPS
		var error := 2.0 * uncertainty * (absf(dx) + absf(dy) + absf(rx) + absf(ry)) + 8.0 * uncertainty * uncertainty
		if orientation * (dx * ry - dy * rx) > error: return true
	return false

static func _boundary_separated(subject: PackedVector2Array, boundary: PackedVector2Array) -> bool:
	var winding := 0.0
	for i in range(1, boundary.size() - 1):
		winding += (float(boundary[i].x) - boundary[0].x) * (float(boundary[i + 1].y) - boundary[0].y) - (float(boundary[i].y) - boundary[0].y) * (float(boundary[i + 1].x) - boundary[0].x)
	var orientation := signf(winding)
	if orientation == 0.0: return true
	for edge in boundary.size():
		var a := boundary[edge]
		var b := boundary[(edge + 1) % boundary.size()]
		# An axis must resolve its own polygon's interior before it can prove separation.
		if _has_edge_interior(boundary, a, b, orientation) and not _has_edge_interior(subject, a, b, orientation): return true
	return false

# Audit an existing plan against the pre-fold stack, including old dump files.
static func layer_obstructions(before: Array[Dictionary], plan_data: Dictionary) -> Array[Dictionary]:
	var blocked: Array[Dictionary] = []
	var moving_sources: Array[int] = []
	var fixed_sources: Array[int] = []
	for part in plan_data.move:
		moving_sources.append(_material_source(before, part))
	for part in plan_data.stay:
		fixed_sources.append(_material_source(before, part))
	for group in ["move", "stay"]:
		var sources: Array[int] = moving_sources if group == "move" else fixed_sources
		for index in sources.size():
			if sources[index] < 0: blocked.append({"kind":"source_mapping", "part_group":group, "part_index":index})
	for m in plan_data.move.size():
		var moving: Dictionary = plan_data.move[m]
		var source_m := moving_sources[m]
		for s in plan_data.stay.size():
			var fixed: Dictionary = plan_data.stay[s]
			var source_s := fixed_sources[s]
			if source_m < 0 or source_s < 0 or source_s <= source_m:
				continue
			if _crease_separates(moving.points, fixed.points, plan_data.origin, plan_data.normal): continue
			var overlap := overlap_area(moving.points, fixed.points)
			if overlap > MIN_OVERLAP_AREA:
				blocked.append({"moving_layer": source_m, "upper_fixed_layer": source_s, "area_m2": overlap})
	return blocked

static func _crease_separates(left: PackedVector2Array, right: PackedVector2Array, origin: Vector2, normal: Vector2) -> bool:
	if not origin.is_finite() or not normal.is_finite() or normal.is_zero_approx(): return false
	# The recorded hinge is an additional separating axis when both faces are roundoff-width slivers.
	var positive: Array[bool] = []
	var negative: Array[bool] = []
	for points in [left, right]:
		var all_positive := true
		var all_negative := true
		for p in points:
			var distance := (float(p.x) - origin.x) * normal.x + (float(p.y) - origin.y) * normal.y
			var scale := maxf(maxf(absf(p.x), absf(p.y)), maxf(absf(origin.x), absf(origin.y)))
			var error := 2.0 * scale * FLOAT32_RELATIVE_EPS * (absf(normal.x) + absf(normal.y))
			all_positive = all_positive and distance >= -error
			all_negative = all_negative and distance <= error
		positive.append(all_positive)
		negative.append(all_negative)
	return (positive[0] and negative[1]) or (negative[0] and positive[1])

static func _material_source(before: Array[Dictionary], part: Dictionary) -> int:
	var index := -1
	var best := 0.0
	for i in before.size():
		# Material fragments need a source even when their width is only coordinate roundoff.
		if part.paper == before[i].paper: return i
		if not _bounds(part.paper).intersects(_bounds(before[i].paper)): continue
		var overlap := _convex_overlap_area(part.paper, before[i].paper)
		if overlap > best:
			best = overlap
			index = i
	return index
# Keep reference axes attached to the original sheet, not the changing silhouette bounds.
static func reference_geometry(faces: Array[Dictionary]) -> Dictionary:
	var centers := PackedVector2Array()
	var segments: Array[PackedVector2Array] = []
	for face in faces:
		if _inside_convex(face.paper, Vector2.ZERO):
			var center := _map_material_point(face, Vector2.ZERO)
			var duplicate := false
			for existing in centers:
				duplicate = duplicate or existing.distance_to(center) < EPS
			if not duplicate and center.is_finite():
				centers.append(center)
		for axis in 2:
			var low := INF
			var high := -INF
			var start := Vector2.ZERO
			var finish := Vector2.ZERO
			for i in face.paper.size():
				var j: int = (i + 1) % face.paper.size()
				var p: Vector2 = face.paper[i]
				var q: Vector2 = face.paper[j]
				var candidates: Array[float] = []
				if absf(p[axis]) <= EPS:
					candidates.append(0.0)
				if p[axis] * q[axis] < 0.0:
					candidates.append(p[axis] / (p[axis] - q[axis]))
				for t in candidates:
					var material := p.lerp(q, t)
					var position: Vector2 = face.points[i].lerp(face.points[j], t)
					if material[1 - axis] < low:
						low = material[1 - axis]
						start = position
					if material[1 - axis] > high:
						high = material[1 - axis]
						finish = position
			if high - low > EPS and start.distance_to(finish) > EPS:
				segments.append(PackedVector2Array([start, finish]))
	return {"centers": centers, "segments": segments}

static func _map_material_point(face: Dictionary, point: Vector2) -> Vector2:
	for i in range(1, face.paper.size() - 1):
		var u: Vector2 = face.paper[i] - face.paper[0]
		var v: Vector2 = face.paper[i + 1] - face.paper[0]
		var determinant := u.cross(v)
		if absf(determinant) <= MIN_AREA:
			continue
		var offset: Vector2 = point - face.paper[0]
		var s := offset.cross(v) / determinant
		var t := u.cross(offset) / determinant
		return face.points[0] + (face.points[i] - face.points[0]) * s + (face.points[i + 1] - face.points[0]) * t
	return Vector2.INF
