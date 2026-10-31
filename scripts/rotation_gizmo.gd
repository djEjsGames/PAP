extends Node2D

const RADIUS := 0.16
const SEGMENTS := 96
const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const COLORS := [Color("f57575"), Color("8cde7c"), Color("7faaff")]
var flight: Node
var selected_axis := -1
var start_vector := Vector3.ZERO
var start_attitude := Basis.IDENTITY

func _process(_delta: float) -> void:
	queue_redraw()

func available() -> bool:
	return visible and flight != null and flight.gauge_stage == 0 and flight.ready_to_launch and not flight.running and flight.elapsed == 0

func ring_points(axis: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var u: Vector3 = AXES[(axis + 1) % 3]
	var v: Vector3 = AXES[(axis + 2) % 3]
	for i in SEGMENTS + 1:
		var angle := TAU * i / SEGMENTS
		points.append(flight.camera.unproject_position(flight.body.global_position + RADIUS * (u * cos(angle) + v * sin(angle))))
	return points

func pick_axis(point: Vector2) -> int:
	if not available():
		return -1
	var best := 8.0
	var result := -1
	for axis in 3:
		var points := ring_points(axis)
		for i in SEGMENTS:
			var distance := point.distance_to(Geometry2D.get_closest_point_to_segment(point, points[i], points[i + 1]))
			if distance < best:
				best = distance
				result = axis
	return result

func _vector_on_plane(point: Vector2, axis: int) -> Vector3:
	var origin: Vector3 = flight.camera.project_ray_origin(point)
	var direction: Vector3 = flight.camera.project_ray_normal(point)
	var normal: Vector3 = AXES[axis]
	var denominator := direction.dot(normal)
	if absf(denominator) < 0.00001:
		return Vector3.ZERO
	var distance: float = (flight.body.global_position - origin).dot(normal) / denominator
	if distance < 0:
		return Vector3.ZERO
	return (origin + direction * distance - flight.body.global_position).normalized()

func begin_drag(point: Vector2) -> bool:
	selected_axis = pick_axis(point)
	if selected_axis < 0:
		return false
	start_vector = _vector_on_plane(point, selected_axis)
	if start_vector.length_squared() < 0.5:
		selected_axis = -1
		return false
	start_attitude = flight.body.global_basis
	return true

func update_drag(point: Vector2, snap: bool) -> void:
	if selected_axis < 0 or not available():
		return
	var current := _vector_on_plane(point, selected_axis)
	if current.length_squared() < 0.5:
		return
	var angle := start_vector.signed_angle_to(current, AXES[selected_axis])
	if snap:
		angle = snappedf(angle, deg_to_rad(15))
	flight._set_attitude(Basis(AXES[selected_axis], angle) * start_attitude)

func end_drag() -> void:
	selected_axis = -1

func _draw() -> void:
	if not available():
		return
	for axis in 3:
		var color: Color = Color.WHITE if axis == selected_axis else COLORS[axis]
		draw_polyline(ring_points(axis), color, 3.5 if axis == selected_axis else 2.0, true)
		var end: Vector2 = flight.camera.unproject_position(flight.body.global_position + AXES[axis] * RADIUS)
		var center: Vector2 = flight.camera.unproject_position(flight.body.global_position)
		draw_line(center, end, color * Color(1, 1, 1, 0.5), 1.0, true)
		draw_string(ThemeDB.fallback_font, end + Vector2(5, -5), ["X", "Y", "Z"][axis], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, color)