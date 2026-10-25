extends Node3D

signal closed
const Model := preload("res://scripts/flight_model.gd")
const Body := preload("res://scripts/flight_body.gd")
const RotationGizmo := preload("res://scripts/rotation_gizmo.gd")
const PaperToon := preload("res://shaders/paper_toon.gdshader")
const LAUNCH := Vector3(0, 1.5, 0)
const MAX_LAUNCH_SPEED := 8.16
var launch_power := 50.0
var power_slider := HSlider.new()
var power_label := Label.new()
const PITCH := 3.0
var attitude := Basis(Vector3.RIGHT, deg_to_rad(PITCH))
var aim := Vector2(0, PITCH)
var dragging := false
var pose_fields: Array[SpinBox] = []
var gizmo := RotationGizmo.new()
var aim_sliders: Array[HSlider] = []
var aim_labels: Array[Label] = []
var launch_arrow := MeshInstance3D.new()
var folding: Node
var faces: Array[Dictionary] = []
var history: Array[Dictionary] = []
var angles := Vector2(90, 90)
var body: RigidBody3D
var mesh := MeshInstance3D.new()
var camera := Camera3D.new()
var sliders: Array[HSlider] = []
var angle_labels: Array[Label] = []
var linked := CheckButton.new()
var results := Label.new()
var metrics := Label.new()
var launch_button := Button.new()
var running := false
var ready_to_launch := false
var elapsed := 0.0
var trials: Array[Dictionary] = []
var posed: Array[Dictionary] = []
var properties: Dictionary = {}
var trajectory := PackedVector3Array()
var trail := MeshInstance3D.new()
var trail_timer := 0.0

func configure(source_faces: Array[Dictionary], source_history: Array[Dictionary], source: Node) -> void:
	faces = source_faces.duplicate(true)
	history = source_history.duplicate(true)
	folding = source

func _ready() -> void:
	body = Body.new()
	body.freeze = true
	body.collision_layer = 2
	body.collision_mask = 1
	body.contact_monitor = true
	body.max_contacts_reported = 8
	body.continuous_cd = true
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp = 0.0
	add_child(body)
	body.add_child(mesh)
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 48
	# Keep close paper layers distinguishable in the depth buffer, including the follow camera.
	camera.near = 0.03
	camera.far = 200
	add_child(camera)
	camera.make_current()
	add_child(trail)
	add_child(launch_arrow)
	_build_ground()
	_build_ui()
	_rebuild()
	_process(0.0)

func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.position.y = -0.1
	add_child(ground)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 0.2, 100)
	shape.shape = box
	ground.add_child(shape)
	var visual := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	visual.mesh = box_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("243b45")
	visual.material_override = material
	ground.add_child(visual)
	var grid := MeshInstance3D.new()
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-20, 21):
		lines.surface_add_vertex(Vector3(i, 0.001, -20))
		lines.surface_add_vertex(Vector3(i, 0.001, 20))
		lines.surface_add_vertex(Vector3(-20, 0.001, i))
		lines.surface_add_vertex(Vector3(20, 0.001, i))
	lines.surface_end()
	grid.mesh = lines
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = Color("46606b")
	grid.material_override = ink
	add_child(grid)

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	gizmo.flight = self
	canvas.add_child(gizmo)
	var panel := PanelContainer.new()
	canvas.add_child(panel)
	panel.position = Vector2(20, 16)
	panel.custom_minimum_size.x = 460
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Malgun Gothic"])
	theme.default_font = font
	theme.default_font_size = 15
	panel.theme = theme
	var style := StyleBoxFlat.new()
	style.bg_color = Color("182a30")
	style.set_content_margin_all(16)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	var title := Label.new()
	title.text = "PAP / 날개와 비행 테스트"
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)
	for i in 2:
		var label := Label.new()
		angle_labels.append(label)
		column.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 150
		slider.value = 90
		slider.step = 1
		slider.custom_minimum_size.x = 420
		slider.focus_mode = Control.FOCUS_NONE
		slider.value_changed.connect(func(value: float) -> void: _angle_changed(i, value))
		sliders.append(slider)
		column.add_child(slider)
	linked.text = "양쪽 각도 함께 조절 · 90°는 몸통과 직각"
	linked.button_pressed = true
	linked.focus_mode = Control.FOCUS_NONE
	column.add_child(linked)
	var conditions := Label.new()
	conditions.text = "높이 1.5m · 바람 없음\n회전 링 드래그: X·Y·Z 월드축 회전 · Shift: 15° 스냅\n좌우는 정면 고정 · 민트 화살표에 기수를 맞추세요."
	column.add_child(conditions)
	for i in 2:
		var label := Label.new()
		aim_labels.append(label)
		column.add_child(label)
		var slider := HSlider.new()
		slider.min_value = -180 if i == 0 else -80
		slider.max_value = 180 if i == 0 else 80
		slider.step = 1
		slider.value = aim[i]
		slider.editable = i == 1
		slider.focus_mode = Control.FOCUS_NONE
		slider.value_changed.connect(func(value: float) -> void: _aim_changed(i, value))
		aim_sliders.append(slider)
		column.add_child(slider)
	column.add_child(power_label)
	power_slider.min_value = 1
	power_slider.max_value = 100
	power_slider.step = 1
	power_slider.value = launch_power
	power_slider.focus_mode = Control.FOCUS_NONE
	power_slider.value_changed.connect(_power_changed)
	column.add_child(power_slider)
	var pose_row := HBoxContainer.new()
	column.add_child(pose_row)
	for i in 3:
		var label := Label.new()
		label.text = ["X", "Y", "Z"][i]
		label.modulate = RotationGizmo.COLORS[i]
		pose_row.add_child(label)
		var field := SpinBox.new()
		field.min_value = -180
		field.max_value = 180
		field.allow_greater = true
		field.allow_lesser = true
		field.step = 0.1
		field.suffix = "°"
		field.custom_minimum_size.x = 116
		field.value_changed.connect(func(value: float) -> void: _pose_axis_changed(i, value))
		pose_fields.append(field)
		pose_row.add_child(field)
	var pose_reset := Button.new()
	pose_reset.text = "기체 자세 초기화"
	pose_reset.focus_mode = Control.FOCUS_NONE
	pose_reset.pressed.connect(_reset_attitude)
	column.add_child(pose_reset)
	var row := HBoxContainer.new()
	column.add_child(row)
	launch_button.text = "발사 [Enter]"
	launch_button.pressed.connect(launch)
	row.add_child(launch_button)
	var reset := Button.new()
	reset.text = "발사 위치 [R]"
	reset.pressed.connect(reset_trial)
	row.add_child(reset)
	var back := Button.new()
	back.text = "접기로 [B / Esc]"
	back.pressed.connect(func() -> void: closed.emit())
	row.add_child(back)
	for child in row.get_children():
		child.focus_mode = Control.FOCUS_NONE
	column.add_child(metrics)
	column.add_child(results)
	var disclaimer := Label.new()
	disclaimer.text = "첫 근사 모델 · 결과는 이 화면에서만 유지 · Ctrl+Shift+D 상태 덤프"
	disclaimer.add_theme_font_size_override("font_size", 12)
	column.add_child(disclaimer)

func _angle_changed(index: int, value: float) -> void:
	if running:
		return
	angles[index] = value
	if linked.button_pressed:
		angles[1 - index] = value
	for i in 2:
		sliders[i].set_value_no_signal(angles[i])
	_rebuild()

func _rebuild() -> void:
	var raw := Model.pose(faces, history, angles)
	ready_to_launch = Model.is_joined(raw)
	if not ready_to_launch:
		mesh.visible = false
		launch_button.disabled = true
		metrics.text = "이 각도에서 종이 연결을 보존하지 못해 비행 준비를 중단했습니다."
		return
	mesh.visible = true
	var upright := Model.launch_frame(faces, history)
	posed = []
	for face in raw:
		var points := PackedVector3Array()
		for point in face.points:
			points.append(upright * point)
		posed.append({"points": points, "paper": face.paper, "seams": face.seams, "normal": upright * face.normal, "layer_sign": face.layer_sign})
	properties = Model.properties(posed)
	body.mass = maxf(properties.mass, 0.0001)
	body.panels = Model.panels(posed, properties.center)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var collision_points := PackedVector3Array()
	# Display spacing only: physical vertices, seams and collision remain unchanged.
	var stack_depth := minf(0.000025 * (posed.size() - 1), 0.0006)
	for face_index in posed.size():
		var face: Dictionary = posed[face_index]
		var layer_offset: float = (float(face_index) / maxi(1, posed.size() - 1) - 0.5) * stack_depth * face.layer_sign
		for i in range(1, face.points.size() - 1):
			var triangle := [face.points[0] - properties.center, face.points[i] - properties.center, face.points[i + 1] - properties.center]
			var boundary_mask := Color(1, 1 if i + 1 == face.points.size() - 1 else 0, 1 if i == 1 else 0)
			for vertex_index in 3:
				var point: Vector3 = triangle[vertex_index]
				tool.set_color(boundary_mask)
				tool.set_uv([Vector2(1, 0), Vector2(0, 1), Vector2.ZERO][vertex_index])
				tool.set_uv2(Vector2(layer_offset, 0))
				tool.set_normal(face.normal)
				tool.add_vertex(point)
				collision_points.append(point + face.normal * 0.0001)
				collision_points.append(point - face.normal * 0.0001)
	mesh.mesh = tool.commit()
	var material := ShaderMaterial.new()
	material.shader = PaperToon
	mesh.material_override = material
	for child in body.get_children():
		if child is CollisionShape3D:
			body.remove_child(child)
			child.queue_free()
	var shape := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	hull.points = collision_points
	hull.margin = 0.0001
	shape.shape = hull
	body.add_child(shape)
	var inertia: Vector3 = properties.inertia
	body.inertia = Vector3(maxf(inertia.x, 0.00000001), maxf(inertia.y, 0.00000001), maxf(inertia.z, 0.00000001))
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = Vector3.ZERO
	for i in 2:
		angle_labels[i].text = "날개 %d 벌림: %.0f°" % [i + 1, angles[i]]
		if Model.wing_folds(history).size() < 2:
			sliders[i].editable = false
			angle_labels[i].text += " · 두 날개 접기 기록이 필요합니다"
	reset_trial()

func reset_trial() -> void:
	aim.x = 0
	aim_sliders[0].set_value_no_signal(0)
	if not ready_to_launch:
		return
	running = false
	dragging = false
	body.freeze = true
	body.transform = Transform3D(attitude, LAUNCH)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.reset_physics_interpolation()
	elapsed = 0.0
	trajectory = PackedVector3Array([LAUNCH])
	trail.mesh = null
	launch_button.disabled = false
	for i in aim_sliders.size():
		aim_sliders[i].editable = i == 1
	for slider in sliders:
		slider.editable = Model.wing_folds(history).size() == 2
	_sync_pose_fields()
	power_slider.editable = true
	power_label.text = "던지기 힘: %.0f%%" % launch_power
	_update_launch_arrow()
	_update_metrics()

func launch() -> void:
	if not ready_to_launch:
		return
	reset_trial()
	body.freeze = false
	body.sleeping = false
	body.linear_velocity = launch_velocity()
	running = true
	power_slider.editable = false
	_sync_pose_fields()
	gizmo.end_drag()
	launch_arrow.visible = false
	for slider in aim_sliders:
		slider.editable = false
	launch_button.disabled = true
	for slider in sliders:
		slider.editable = false

func _physics_process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	trail_timer += delta
	if trail_timer >= 0.05:
		trail_timer = 0.0
		trajectory.append(body.position)
		_draw_trail()
	_update_metrics()
	if not body.position.is_finite() or not body.linear_velocity.is_finite():
		_finish("수치 오류")
	elif elapsed > 0.05 and body.get_contact_count() > 0:
		_finish("착지")
	elif elapsed >= 12.0 or body.position.y < -0.1:
		_finish("테스트 종료")

func _process(_delta: float) -> void:
	var target := body.position
	camera.position = target + (Vector3(0.45, 0.25, 0.5) if not running and elapsed == 0 else Vector3(1.5, 0.8, 2))
	camera.look_at(target)

func _update_metrics() -> void:
	var distance := Vector2(body.position.x - LAUNCH.x, body.position.z - LAUNCH.z).length()
	metrics.text = "거리 %.2fm · 체공 %.2fs · 종이 %.2fg" % [distance, elapsed, body.mass * 1000.0]

func _finish(reason: String) -> void:
	running = false
	dragging = false
	body.freeze = true
	var distance := Vector2(body.position.x - LAUNCH.x, body.position.z - LAUNCH.z).length()
	trials.append({"launch_power": launch_power, "aim_degrees": aim, "launch_transform": Transform3D(attitude, LAUNCH), "launch_velocity": launch_velocity(), "angles": angles, "distance_m": distance, "duration_s": elapsed, "reason": reason, "mass_kg": body.mass})
	power_slider.editable = true
	_sync_pose_fields()
	results.text = "최근 결과\n"
	for i in range(maxi(0, trials.size() - 4), trials.size()):
		var trial := trials[i]
		results.text += "%d. 힘 %.0f%% · %.0f°/%.0f° · %.2fm · %.2fs · %s\n" % [i + 1, trial.launch_power, trial.angles.x, trial.angles.y, trial.distance_m, trial.duration_s, trial.reason]
	launch_button.disabled = false
	for i in aim_sliders.size():
		aim_sliders[i].editable = i == 1
	for slider in sliders:
		slider.editable = Model.wing_folds(history).size() == 2

func _draw_trail() -> void:
	if trajectory.size() < 2:
		return
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in trajectory:
		lines.surface_add_vertex(point)
	lines.surface_end()
	trail.mesh = lines
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("7de1d2")
	trail.material_override = material

func launch_velocity() -> Vector3:
	var elevation := deg_to_rad(aim.y)
	return Vector3(0, sin(elevation), -cos(elevation)) * (MAX_LAUNCH_SPEED * launch_power / 100.0)

func _power_changed(value: float) -> void:
	if running:
		return
	launch_power = clampf(value, 1, 100)
	power_slider.set_value_no_signal(launch_power)
	reset_trial()

func _aim_changed(index: int, value: float) -> void:
	if running:
		return
	if index == 0:
		aim.x = 0
		aim_sliders[0].set_value_no_signal(0)
		return
	aim[index] = value
	reset_trial()

func _reset_attitude() -> void:
	if running:
		return
	attitude = Basis(Vector3.RIGHT, deg_to_rad(PITCH))
	reset_trial()

func _sync_pose_fields() -> void:
	var euler := attitude.get_euler()
	for i in pose_fields.size():
		pose_fields[i].set_value_no_signal(rad_to_deg(euler[i]))
		pose_fields[i].editable = not running

func _pose_axis_changed(index: int, degrees: float) -> void:
	if running:
		return
	var euler := attitude.get_euler()
	euler[index] = deg_to_rad(degrees)
	_set_attitude(Basis.from_euler(euler))

func _set_attitude(value: Basis) -> void:
	if running or not ready_to_launch:
		return
	attitude = value.orthonormalized()
	var was_dragging := dragging
	reset_trial()
	dragging = was_dragging

func _rotate_preview(relative: Vector2, roll: bool) -> void:
	if running or not ready_to_launch:
		return
	var turn: Basis
	if roll:
		turn = Basis(camera.global_basis.z, -relative.x * 0.01)
	else:
		turn = Basis(camera.global_basis.y, -relative.x * 0.01) * Basis(camera.global_basis.x, -relative.y * 0.01)
	_set_attitude(turn * attitude)

func _update_launch_arrow() -> void:
	aim_labels[0].text = "발사 좌우 방향: 정면 0° · 고정"
	aim_labels[1].text = "발사 고도각: %.0f°" % aim.y
	var direction := launch_velocity().normalized()
	var side := direction.cross(Vector3.UP).normalized() * 0.045
	var tip := LAUNCH + direction * 0.6
	var base := tip - direction * 0.1
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for point in [LAUNCH + direction * 0.12, tip, tip, base + side, tip, base - side]:
		lines.surface_add_vertex(point)
	lines.surface_end()
	launch_arrow.mesh = lines
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = Color("7de1d2")
	launch_arrow.material_override = ink
	launch_arrow.visible = true

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = false
		gizmo.end_drag()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not running and ready_to_launch:
			if elapsed > 0:
				reset_trial()
			dragging = true
			gizmo.begin_drag(event.position)
	elif event is InputEventMouseMotion and dragging:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if gizmo.selected_axis >= 0:
				gizmo.update_drag(event.position, event.shift_pressed)
			else:
				_rotate_preview(event.relative, event.shift_pressed)
		else:
			dragging = false
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ENTER: launch()
			KEY_R: reset_trial()
			KEY_B, KEY_ESCAPE: closed.emit()
			KEY_D:
				if event.ctrl_pressed and event.shift_pressed and not event.alt_pressed:
					folding._dump_state()
					metrics.text = folding.dump_notice.text

func snapshot() -> Dictionary:
	return {"launch_power": launch_power, "aim_degrees": aim, "launch_transform": Transform3D(attitude, LAUNCH), "launch_velocity": launch_velocity(), "angles": angles, "running": running, "elapsed_s": elapsed, "trials": trials, "body_transform": body.transform, "velocity": body.linear_velocity, "angular_velocity": body.angular_velocity, "posed": posed, "panels": body.panels, "mass_kg": body.mass, "trajectory": Array(trajectory)}
