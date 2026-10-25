extends RefCounted

const Paper := preload("res://scripts/paper_geometry.gd")
const PAPER_DENSITY := 0.08 # kg/m2: 80 gsm paper.
const AIR_DENSITY := 1.2

static func wing_folds(history: Array[Dictionary]) -> Array[int]:
	var result: Array[int] = []
	for i in history.size():
		if history[i].kind == "fold" and history[i].get("single_layer", false):
			result.append(i)
	if result.size() > 2:
		result = result.slice(result.size() - 2)
	return result

static func launch_frame(faces: Array[Dictionary], history: Array[Dictionary]) -> Basis:
	if wing_folds(history).size() != 2:
		return Basis.IDENTITY
	# Use a fixed reference so adjusting wing angles never rotates the whole aircraft.
	var reference := pose(faces, history, Vector2(90, 90))
	var wings: Array[Dictionary] = []
	var grip: Array[Dictionary] = []
	for i in faces.size():
		var deployed := false
		for j in faces[i].points.size():
			var flat: Vector2 = faces[i].points[j]
			if reference[i].points[j].distance_to(Vector3(flat.x, 0, flat.y)) > 0.00001:
				deployed = true
		if deployed:
			wings.append(reference[i])
		else:
			grip.append(reference[i])
	var upright := Basis(Vector3.BACK, PI * 0.5)
	var largest := 0.0
	var normal := Vector3.UP
	for surface in panels(wings, Vector3.ZERO):
		if surface.area > largest:
			largest = surface.area
			normal = upright * surface.normal
	if normal.dot(Vector3.UP) < 0:
		normal = -normal
	upright = Basis(Quaternion(normal, Vector3.UP)) * upright
	# shortcut: without a distinct grip, keep this orientation; explicit wing binding is needed for arbitrary folds.
	if not grip.is_empty() and not wings.is_empty():
		var offset: Vector3 = properties(grip).center - properties(wings).center
		if (upright * offset).y > 0.000001:
			upright = Basis(Vector3.FORWARD, PI) * upright
	return upright

static func _around(origin: Vector3, axis: Vector3, angle: float) -> Transform3D:
	var basis := Basis(axis.normalized(), angle)
	return Transform3D(basis, origin - basis * origin)

static func pose(faces: Array[Dictionary], history: Array[Dictionary], openings: Vector2) -> Array[Dictionary]:
	var wings := wing_folds(history)
	var result: Array[Dictionary] = []
	for face in faces:
		var material_center := Vector2.ZERO
		for point in face.paper:
			material_center += point
		material_center /= face.paper.size()
		var flat := Transform3D.IDENTITY
		var posed := Transform3D.IDENTITY
		for index in history.size():
			var entry := history[index]
			if entry.kind == "flip":
				var before_flip: Array[Dictionary] = []
				before_flip.assign(entry.faces)
				var center := Vector3(Paper.flip_center(before_flip), 0, 0)
				var turn := _around(center, Vector3.BACK, PI)
				flat = turn * flat
				posed = turn * posed
				continue
			var affected := false
			for part in entry.plan.move:
				if Paper._inside_convex(part.paper, material_center):
					affected = true
					break
			if not affected:
				continue
			var normal: Vector2 = entry.plan.normal
			var a: Vector2 = entry.plan.origin
			var origin := Vector3(a.x, 0, a.y)
			var axis := Vector3(-normal.y, 0, normal.x)
			var mapping := posed * flat.affine_inverse()
			var angle := PI
			var wing := wings.find(index)
			if wing >= 0:
				angle -= deg_to_rad(openings[wing])
			posed = _around(mapping * origin, mapping.basis * axis, angle) * posed
			flat = _around(origin, axis, PI) * flat
		var points := PackedVector3Array()
		for uv in face.paper:
			points.append(posed * Vector3(uv.x, 0, uv.y))
		result.append({"points": points, "paper": face.paper, "seams": face.seams, "normal": posed.basis * Vector3.UP, "layer_sign": signf((flat.basis * Vector3.UP).y)})
	return result

static func properties(posed: Array[Dictionary]) -> Dictionary:
	var area := 0.0
	var center := Vector3.ZERO
	var moment := Vector3.ZERO
	for face in posed:
		for i in range(1, face.points.size() - 1):
			var a: Vector3 = face.points[0]
			var b: Vector3 = face.points[i]
			var c: Vector3 = face.points[i + 1]
			var patch_area := (b - a).cross(c - a).length() * 0.5
			area += patch_area
			center += (a + b + c) / 3.0 * patch_area
			var second := (a * a + b * b + c * c + a * b + a * c + b * c) / 6.0
			moment += Vector3(second.y + second.z, second.x + second.z, second.x + second.y) * patch_area
	if area > 0.0:
		center /= area
	var shift := Vector3(center.y * center.y + center.z * center.z, center.x * center.x + center.z * center.z, center.x * center.x + center.y * center.y)
	return {"area": area, "mass": area * PAPER_DENSITY, "center": center, "inertia": (moment - shift * area) * PAPER_DENSITY}

# Subtract coplanar overlaps before assigning aerodynamic area; folded layers do not multiply lift.
static func panels(posed: Array[Dictionary], center: Vector3) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in posed.size():
		var face := posed[index]
		var origin: Vector3 = face.points[0]
		var normal: Vector3 = face.normal.normalized()
		var u: Vector3 = (face.points[1] - origin).normalized()
		if u.length_squared() < 0.5:
			continue
		var v := normal.cross(u).normalized()
		var polygon := PackedVector2Array()
		for point in face.points:
			polygon.append(Vector2((point - origin).dot(u), (point - origin).dot(v)))
		if Geometry2D.is_polygon_clockwise(polygon):
			polygon.reverse()
		var visible: Array[PackedVector2Array] = [polygon]
		for other_index in range(index + 1, posed.size()):
			var other := posed[other_index]
			if absf(normal.dot(other.normal)) < 0.9999:
				continue
			var coplanar := true
			var cover := PackedVector2Array()
			for point in other.points:
				coplanar = coplanar and absf((point - origin).dot(normal)) < 0.000001
				cover.append(Vector2((point - origin).dot(u), (point - origin).dot(v)))
			if not coplanar:
				continue
			if Geometry2D.is_polygon_clockwise(cover):
				cover.reverse()
			var remaining: Array[PackedVector2Array] = []
			for part in visible:
				for uncovered in _subtract_convex(part, cover):
					remaining.append(uncovered)
			visible = remaining
		for part in visible:
			var triangles := Geometry2D.triangulate_polygon(part)
			for i in range(0, triangles.size(), 3):
				var a := part[triangles[i]]
				var b := part[triangles[i + 1]]
				var c := part[triangles[i + 2]]
				var area := absf((b - a).cross(c - a)) * 0.5
				if area > 0.00000001:
					var centroid := (a + b + c) / 3.0
					var position := origin + u * centroid.x + v * centroid.y - center
					var vertices := PackedVector3Array()
					for point in [a, b, c]:
						vertices.append(origin + u * point.x + v * point.y - center)
					var merged := false
					for surface in result:
						if absf(normal.dot(surface.normal)) > 0.9999 and absf((position - surface.position).dot(normal)) < 0.000001:
							surface.position = (surface.position * surface.area + position * area) / (surface.area + area)
							surface.area += area
							surface.points.append_array(vertices)
							merged = true
							break
					if not merged:
						result.append({"area": area, "normal": normal, "position": position, "points": vertices})
	return result

static func aerodynamic_coefficients(alpha: float) -> Vector3:
	# Li et al. (2022), JFM 937 A6, equations 5.1-5.6; alpha is in [-pi/2, pi/2].
	var angle := clampf(absf(alpha), 0.0, PI * 0.5)
	var attached := (1.0 - tanh((angle - deg_to_rad(14.0)) / deg_to_rad(6.0))) * 0.5
	var sine := sin(angle)
	var lift := attached * 5.2 * sine + (1.0 - attached) * 0.95 * sin(2.0 * angle)
	var drag := attached * (0.1 + 5.0 * sine * sine) + (1.0 - attached) * 1.9 * sine * sine
	var pressure := attached * (0.3 - 3.5 * angle * angle) + (1.0 - attached) * 0.2 * (1.0 - angle / (PI * 0.5))
	return Vector3(signf(alpha) * lift, drag, pressure)

static func aerodynamic_force(velocity: Vector3, normal: Vector3, area: float) -> Vector3:
	var speed := velocity.length()
	if speed < 0.01:
		return Vector3.ZERO
	var wind := -velocity / speed
	var sine := clampf(wind.dot(normal), -1.0, 1.0)
	var alpha := asin(sine)
	var coefficients := aerodynamic_coefficients(alpha)
	var lift_direction := (normal - wind * sine).normalized()
	var q := 0.5 * AIR_DENSITY * speed * speed * area
	return q * (lift_direction * coefficients.x + wind * coefficients.y)

static func aerodynamic_load(linear: Vector3, angular: Vector3, surface: Dictionary) -> Dictionary:
	# shortcut: quasi-steady 3D adaptation omits added-fluid-mass coupling; revisit for quantitative validation.
	var normal: Vector3 = surface.normal
	var velocity := linear + angular.cross(surface.position)
	var tangent := velocity - normal * velocity.dot(normal)
	if tangent.length_squared() < 0.00000001:
		tangent = angular.cross(normal)
	if tangent.length_squared() < 0.00000001:
		tangent = surface.points[1] - surface.points[0]
	tangent = tangent.normalized()
	var moments := _surface_moments(surface, tangent)
	var chord := moments.x
	if chord < 0.000001:
		return {"force": Vector3.ZERO, "torque": Vector3.ZERO}
	var speed := velocity.length()
	var alpha := asin(clampf(-velocity.normalized().dot(normal), -1.0, 1.0))
	var coefficients := aerodynamic_coefficients(alpha)
	var position: Vector3 = surface.position + tangent * (chord * coefficients.z)
	var force := aerodynamic_force(velocity, normal, surface.area)
	var axis := tangent.cross(normal).normalized()
	var rotation: float = angular.dot(axis)
	var lift_direction := (normal - velocity.normalized() * velocity.normalized().dot(normal)).normalized()
	# Equations 4.11/4.15: rotational lift acts centrally; rotational drag supplies the moment.
	var rotational_lift: Vector3 = lift_direction * (0.5 * AIR_DENSITY * surface.area * chord * 1.1 * rotation * speed)
	var rotational_drag: Vector3 = -axis * (0.5 * AIR_DENSITY * 1.9 * moments.y * rotation * absf(rotation))
	return {"force": force + rotational_lift, "torque": position.cross(force) + rotational_drag}

static func _surface_moments(surface: Dictionary, tangent: Vector3) -> Vector2:
	var span: Vector3 = surface.normal.cross(tangent).normalized()
	var projected := PackedVector2Array()
	var low := Vector2(INF, INF)
	var high := -low
	for point in surface.points:
		var p := Vector2(point.dot(tangent), point.dot(span))
		projected.append(p)
		low = low.min(p)
		high = high.max(p)
	var area := 0.0
	var chord_squared := 0.0
	var rotation_moment := 0.0
	var width := (high.y - low.y) / 16.0
	# shortcut: sixteen spanwise strips approximate arbitrary planforms; refine when shape convergence requires it.
	for strip in 16:
		var y := low.y + (strip + 0.5) * width
		var intervals: Array[Vector2] = []
		for triangle in range(0, projected.size(), 3):
			var hits: Array[float] = []
			for edge in 3:
				var a := projected[triangle + edge]
				var b := projected[triangle + (edge + 1) % 3]
				if (a.y <= y and b.y > y) or (b.y <= y and a.y > y):
					hits.append(lerpf(a.x, b.x, (y - a.y) / (b.y - a.y)))
			if hits.size() == 2:
				intervals.append(Vector2(minf(hits[0], hits[1]), maxf(hits[0], hits[1])))
		intervals.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var merged: Array[Vector2] = []
		for interval in intervals:
			if not merged.is_empty() and interval.x <= merged[-1].y + 0.000001:
				merged[-1] = Vector2(merged[-1].x, maxf(merged[-1].y, interval.y))
			else:
				merged.append(interval)
		for interval in merged:
			var length := interval.y - interval.x
			area += length * width
			chord_squared += length * length * width
			rotation_moment += (interval.y * pow(absf(interval.y), 3) - interval.x * pow(absf(interval.x), 3)) / 4.0 * width
	if area > 0.000000000001:
		return Vector2(chord_squared / area, rotation_moment * surface.area / area)
	var chord := maxf(high.x - low.x, 0.000001)
	return Vector2(chord, surface.area / chord * (high.x * pow(absf(high.x), 3) - low.x * pow(absf(low.x), 3)) / 4.0)

static func _clip(points: PackedVector2Array, origin: Vector2, normal: Vector2) -> PackedVector2Array:
	var output := PackedVector2Array()
	for i in points.size():
		var p := points[i]
		var q := points[(i + 1) % points.size()]
		var dp := (p - origin).dot(normal)
		var dq := (q - origin).dot(normal)
		if dp >= 0.0:
			output.append(p)
		if dp * dq < 0.0:
			output.append(p.lerp(q, dp / (dp - dq)))
	return output

static func _subtract_convex(subject: PackedVector2Array, cover: PackedVector2Array) -> Array[PackedVector2Array]:
	var output: Array[PackedVector2Array] = []
	var remaining := subject
	var center := Vector2.ZERO
	for point in cover:
		center += point
	center /= cover.size()
	for i in cover.size():
		var a := cover[i]
		var direction := cover[(i + 1) % cover.size()] - a
		if direction.length_squared() < 0.000000000001:
			continue
		var normal := direction.normalized().orthogonal()
		if (center - a).dot(normal) < 0.0:
			normal = -normal
		var outside := _clip(remaining, a, -normal)
		if Paper.area(outside) > 0.0000000001:
			output.append(outside)
		remaining = _clip(remaining, a, normal)
		if Paper.area(remaining) < 0.0000000001:
			break
	return output
static func is_joined(posed: Array[Dictionary]) -> bool:
	if posed.is_empty():
		return false
	var material: Array[Dictionary] = []
	for face in posed:
		material.append({"points": face.paper, "paper": face.paper, "seams": face.seams, "front": true})
	for link in Paper.connections(material):
		var a: Dictionary = posed[link.a]
		var b: Dictionary = posed[link.b]
		var next_a: int = (link.edge_a + 1) % a.points.size()
		var next_b: int = (link.edge_b + 1) % b.points.size()
		for pair in [[link.t0_a, link.t0_b], [link.t1_a, link.t1_b]]:
			var p: Vector3 = a.points[link.edge_a].lerp(a.points[next_a], pair[0])
			var q: Vector3 = b.points[link.edge_b].lerp(b.points[next_b], pair[1])
			if not p.is_finite() or not q.is_finite() or p.distance_to(q) > 0.00001:
				return false
	return true
