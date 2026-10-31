extends Node3D

const Character := preload("res://scripts/park_character.gd")
const Inspection := preload("res://scripts/paper_inspection.gd")
const Visual := preload("res://scripts/aircraft_visual.gd")
const Model := preload("res://scripts/flight_model.gd")
const Paper := preload("res://scripts/paper_geometry.gd")
const Stock := preload("res://scripts/paper_stock.gd")
const Guide := preload("res://scripts/airplane_guide.gd")
const Parts := preload("res://scripts/flight_parts.gd")
const Flight := preload("res://scripts/park_flight.gd")
const Presets := preload("res://scripts/paper_presets.gd")
const Dump := preload("res://scripts/paper_dump.gd")
const PlayUI := preload("res://scripts/play_ui.gd")
const BENCH := Vector3(0, 0, -2.5)
const PRACTICE_START := Vector3(4, 0, 1)
const PRACTICE_CENTER := Vector3(4, 0.002, -3)
const PRACTICE_RADIUS := 1.0

var player := CharacterBody3D.new()
var camera := Camera3D.new()
var view_angles := Vector2(0, deg_to_rad(-12))
var zoom := 4.0
var camera_dragging := false
var move_keys: Dictionary = {}
var items: Dictionary = {}
var next_id := 1
var selected_id := -1
var held_id := -1
var editor: Node3D
var editing_id := -1
var active_flight: Node3D
var hud := Control.new()
var header := HFlowContainer.new()
var status := Label.new()
var hint := Label.new()
var inventory := PanelContainer.new()
var inventory_list := ItemList.new()
var inventory_ids: Array[int] = []
var preview := Control.new()
var inventory_info := Label.new()
var take_button: Button
var edit_button: Button
var target_id := -1
var bench_target := false
var notice := ""
var workbench: MeshInstance3D
var trials: Array[Dictionary] = []
var character := Character.new()
var carried := MeshInstance3D.new()
var carried_id := -1
var carried_grip := Vector3.ZERO
var inspection: Control
var inspection_id := -1
var inspection_origin: Dictionary = {}
var cleaning_records: Array[Dictionary] = []
var status_panel := PanelContainer.new()
var actions_panel := PanelContainer.new()
var action_help := Label.new()
var throw_button: Button
var interact_button: Button
var inspect_button: Button
var footstep_time := 0.0
var practice_active := false
var practice_button: Button
var practice_labels: Array[Label3D] = []

func _ready() -> void:
	get_window().content_scale_size = Vector2i.ZERO
	_build_world()
	_build_ui()
	var history: Array[Dictionary] = []
	var sheet := {"faces": Paper.square(), "history": history, "fold_count": 0, "reference": {}, "flight_parts": {}, "paper_stock": Stock.option(0)}
	selected_id = add_item("내 색종이", sheet)
	# shortcut: one fixed discovery; random variants follow after the full loop is reviewed.
	var found := _starter_plane()
	var found_id := add_item("공원에서 발견한 비행기", found)
	items[found_id].known = false
	_spawn_found(found_id, Vector3(2.5, 0.08, -3))
	get_window().focus_exited.connect(func() -> void:
		move_keys.clear()
		camera_dragging = false
	)
	_update_camera()

func add_item(label: String, sheet: Dictionary) -> int:
	var id := next_id
	next_id += 1
	items[id] = {"id": id, "name": label, "sheet": sheet.duplicate(true), "state": "stored", "flight_session": {}, "flight": null, "marker": null, "known": true}
	return id

func _build_practice() -> void:
	var line := ImmediateMesh.new()
	line.surface_begin(Mesh.PRIMITIVE_LINES)
	line.surface_add_vertex(PRACTICE_START + Vector3(-1, 0.025, 0))
	line.surface_add_vertex(PRACTICE_START + Vector3(1, 0.025, 0))
	for i in 64:
		for angle in [TAU * i / 64, TAU * (i + 1) / 64]:
			line.surface_add_vertex(PRACTICE_CENTER + Vector3(cos(angle), 0, sin(angle)) * PRACTICE_RADIUS)
	for z in [0.5, -0.5, -1.5]:
		line.surface_add_vertex(Vector3(4, 0.025, z))
		line.surface_add_vertex(Vector3(4, 0.025, z - 0.4))
	line.surface_end()
	var marking := MeshInstance3D.new()
	marking.mesh = line
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = Color("fff09a")
	marking.material_override = ink
	add_child(marking)
	var target := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = PRACTICE_RADIUS
	disc.bottom_radius = PRACTICE_RADIUS
	disc.height = 0.0004
	target.mesh = disc
	target.position = PRACTICE_CENTER - Vector3.UP * 0.0005
	var fill := StandardMaterial3D.new()
	fill.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill.albedo_color = Color(0.7, 0.95, 0.6, 0.35)
	target.material_override = fill
	add_child(target)
	for position in [PRACTICE_START + Vector3(0, 0.6, 0), PRACTICE_CENTER + Vector3(0, 0.3, 0)]:
		var label := Label3D.new()
		label.font = preload("res://assets/fonts/NanumGothic-Regular.ttf")
		label.text = "표적 연습 [T]" if position.z > 0 else "4m 착지 표적"
		label.font_size = 28
		label.pixel_size = 0.005
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = position + (Vector3(-1.5, 0, 0) if position.z > 0 else Vector3(0, 0, -1.5))
		add_child(label)
		practice_labels.append(label)

func toggle_practice() -> void:
	if editor != null or inspection != null or active_flight != null or inventory.visible: return
	if practice_active:
		practice_active = false
		notice = "자유 투척 · 연습 기록은 기체에 남아 있습니다."
	elif Vector2(player.position.x - PRACTICE_START.x, player.position.z - PRACTICE_START.z).length() > 1.0:
		notice = "작업대 오른쪽 밝은 시작선에서 T. 기체는 발견물을 보관하거나 직접 접어 사용하세요."
	else:
		practice_active = true
		view_angles.x = 0
		notice = "연습 · 정면 4m 원에 첫 접촉\n기준: 힘 60% · 고도각 10° · 날개 90°"

func practice_target() -> Dictionary:
	if not practice_active or Vector2(player.position.x - PRACTICE_START.x, player.position.z - PRACTICE_START.z).length() > 1.0: return {}
	return {"center":PRACTICE_CENTER, "radius":PRACTICE_RADIUS}

func _starter_plane() -> Dictionary:
	var faces := Paper.square()
	var history: Array[Dictionary] = []
	var count := 0
	for step in Guide.steps(0.15):
		if step.action == "unfold":
			faces = history.pop_back().faces
			count -= 1
		elif step.action == "flip":
			history.append({"kind": "flip", "faces": faces.duplicate(true), "fold_count": count, "single_layer": false})
			faces = Paper.flipped(faces)
		else:
			var layer := int(Paper.edge_near(faces, step.grab, 0.00001).layer) if step.single_layer else -1
			var plan := Paper.plan(faces, step.a, step.b, step.grab, layer)
			assert(not plan.is_empty(), "Starter must use valid connected folds")
			history.append({"kind": "fold", "faces": faces.duplicate(true), "fold_count": count, "single_layer": step.single_layer, "plan": plan})
			faces = Paper.folded(plan)
			count += 1
	return {"faces": faces, "history": history, "fold_count": count, "reference": {}, "flight_parts": {}, "paper_stock": Stock.option(0)}

func _box(pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var solid := StaticBody3D.new()
	solid.position = pos
	solid.collision_layer = 1
	solid.collision_mask = 3
	add_child(solid)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	solid.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1
	visual.material_override = material
	solid.add_child(visual)
	return visual

func _build_world() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("8eb6c6")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d8e9f0")
	settings.ambient_light_energy = 0.35
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 0.65
	sun.shadow_enabled = true
	add_child(sun)
	_box(Vector3(0, -0.15, 0), Vector3(100, 0.3, 100), Color("638b6d")).get_parent().set_meta("pap_ground", true)
	for x in [-40, 40]:
		_box(Vector3(x, 1.5, 0), Vector3(0.3, 3, 80), Color("627c6b"))
	for z in [-40, 40]:
		_box(Vector3(0, 1.5, z), Vector3(80, 3, 0.3), Color("627c6b"))
	_box(Vector3(0, 0.005, -5), Vector3(6, 0.01, 18), Color("b6b69a")).get_parent().set_meta("pap_ground", true)
	_build_practice()
	workbench = _box(BENCH + Vector3.UP * 0.9, Vector3(1.8, 0.15, 0.85), Color("b98556"))
	for x in [-0.65, 0.65]:
		_box(BENCH + Vector3(x, 0.43, 0), Vector3(0.1, 0.86, 0.6), Color("41535b"))
	_box(Vector3(-7, 1, -8), Vector3(0.25, 2, 12), Color("84979b"))
	for pos in [Vector3(-5, 0, -3), Vector3(6, 0, -9), Vector3(-8, 0, 5)]:
		_box(pos + Vector3.UP, Vector3(0.35, 2, 0.35), Color("795d48"))
		_box(pos + Vector3.UP * 2.7, Vector3(2, 1.8, 2), Color("3d7654"))
	player.position = Vector3(0, 0.01, 0.1)
	player.collision_layer = 4
	player.collision_mask = 1
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.22
	capsule.height = 2.0
	shape.shape = capsule
	shape.position.y = 1.0
	player.add_child(shape)
	player.add_child(character)
	add_child(carried)
	add_child(player)
	camera.fov = 60
	camera.near = 0.05
	camera.far = 180
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	camera.make_current()

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	canvas.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = preload("res://assets/fonts/NanumGothic-Regular.ttf")
	theme.default_font_size = 16
	hud.theme = theme
	hud.add_child(status_panel)
	status_panel.add_theme_stylebox_override("panel", _hud_style())
	status_panel.add_child(status)
	status.add_theme_font_size_override("font_size", 16)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(actions_panel)
	actions_panel.add_theme_stylebox_override("panel", _hud_style())
	var actions := VBoxContainer.new()
	actions.add_child(action_help)
	action_help.text = "WASD 이동 · 우클릭 시선 · 휠 거리"
	actions_panel.add_child(actions)
	actions.add_child(header)
	_button(header, "보관함 [Tab]", _toggle_inventory)
	throw_button = _button(header, "투척 준비 [Space]", prepare_throw)
	PlayUI.primary(throw_button)
	interact_button = _button(header, "작업대 접기 [E]", interact)
	Audio.add_button(header)
	practice_button = _button(header, "표적 연습 [T]", toggle_practice)
	for button in header.get_children(): button.add_theme_font_size_override("font_size", 18)
	hud.add_child(hint)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_color_override("font_color", Color("fff2b2"))
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_constant_override("outline_size", 1)
	hint.add_theme_stylebox_override("normal", _hud_style())
	var style := StyleBoxFlat.new()
	style.bg_color = Color("182a30")
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	hud.add_child(inventory)
	inventory.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	inventory.add_child(column)
	var title := Label.new()
	title.text = "실물 기체 · 도면 저장과 별개"
	column.add_child(title)
	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(middle)
	inventory_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_list.custom_minimum_size.x = 180
	inventory_list.item_selected.connect(_select_inventory)
	middle.add_child(inventory_list)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(details)
	preview.custom_minimum_size = Vector2(140, 75)
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.draw.connect(_draw_preview)
	details.add_child(preview)
	inventory_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(inventory_info)
	var inventory_actions := HFlowContainer.new()
	column.add_child(inventory_actions)
	take_button = _button(inventory_actions, "꺼내기 · 손에 들기", _take_selected)
	PlayUI.primary(take_button)
	edit_button = _button(inventory_actions, "작업대에서 수정", func() -> void: open_editor(selected_id))
	inspect_button = _button(inventory_actions, "살펴보기", func() -> void: open_inspection(selected_id, false))
	_button(inventory_actions, "닫기 [Tab/Esc]", _toggle_inventory)
	inventory.hide()

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _hud_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.10, 0.12, 0.94)
	style.border_color = Color("527078")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	return style

func _process(_delta: float) -> void:
	_update_character()
	for label in practice_labels: label.visible = active_flight == null and player.position.distance_to(label.position) > 2
	if editor != null or inspection != null: return
	_update_camera()
	if active_flight != null: return
	var size := get_viewport().get_visible_rect().size
	status_panel.size = Vector2(minf(360, size.x - 24), 0)
	status_panel.position = Vector2(12, 12)
	var held: String = items[held_id].name if held_id != -1 else "없음"
	status.text = "손에 든 기체 · %s\n보관함 · %d개" % [held, stored_count()]
	if not notice.is_empty(): status.text += "\n" + notice
	actions_panel.size = Vector2(size.x - 24, 0)
	actions_panel.position = Vector2(12, size.y - actions_panel.size.y - 12)
	throw_button.disabled = held_id == -1
	practice_button.text = "연습 나가기 [T]" if practice_active else "표적 연습 [T]"
	_update_target()
	interact_button.disabled = not bench_target and target_id == -1
	interact_button.text = "작업대 접기 [E]" if bench_target else ("기체 회수 [E]" if target_id != -1 else "가까운 대상 [E]")
	inventory.size = Vector2(minf(600, size.x - 24), minf(400, size.y - 24))
	inventory.position = (size - inventory.size) * 0.5
	edit_button.disabled = player.position.distance_to(BENCH) > 2.2 or selected_id == -1
	for id in items:
		var data: Dictionary = items[id]
		if data.marker != null and is_instance_valid(data.marker) and data.flight != null:
			var point: Vector3 = data.flight.body.global_position + Vector3.UP * 0.25
			var screen := camera.unproject_position(point)
			data.marker.text = "%s %s · %.1fm" % ["↶" if camera.is_position_behind(point) else "◇", data.name, player.position.distance_to(point)]
			data.marker.position = Vector2(clampf(screen.x - 65, 12, maxf(12, size.x - data.marker.size.x - 12)), clampf(screen.y, status_panel.position.y + status_panel.size.y + 12, actions_panel.position.y - data.marker.size.y - 12))
			data.marker.visible = not inventory.visible and id != target_id and data.state == "world"

func _update_character() -> void:
	character.visible = active_flight == null
	character.moving = move_keys.size() > 0 and Vector2(player.velocity.x, player.velocity.z).length() > 0.05 and inspection == null and editor == null and (active_flight == null or (not active_flight.released and active_flight.gauge_stage == 0))
	var holding: bool = held_id != -1 and items[held_id].state == "hand" and inspection == null and editor == null
	character.holding = holding
	character.preparing = holding and active_flight != null
	character.material.set_shader_parameter("clear_held", holding and active_flight != null and active_flight.camera.global_position.distance_to(active_flight.body.global_position) < 0.35)
	carried.visible = holding and active_flight == null
	if not holding: return
	if carried_id != held_id:
		var data: Dictionary = items[held_id]
		var binding: Dictionary = data.sheet.flight_parts if Parts.valid(data.sheet.flight_parts, data.sheet.faces, data.sheet.history) else {}
		var openings := Vector2(90, 90)
		if data.flight_session.get("sheet_signature") == Parts.signature(data.sheet.faces, data.sheet.history) and data.flight_session.get("binding") == binding:
			openings = data.flight_session.angles
		var posed := Model.pose(data.sheet.faces, data.sheet.history, openings, binding)
		var frame := Model.launch_frame(data.sheet.faces, data.sheet.history, binding)
		for face in posed:
			for i in face.points.size(): face.points[i] = frame * face.points[i]
			face.normal = frame * face.normal
		var properties := Model.properties(posed)
		var visual := Visual.build(posed, properties.center, data.sheet.paper_stock)
		carried.mesh = visual.mesh
		carried.material_override = visual.material
		carried_grip = Visual.grip_offset(posed, data.sheet.faces, data.sheet.history, binding, properties.center)
		carried_id = held_id
	var basis := player.global_basis
	if active_flight != null:
		character.hand_target = active_flight.grip_position()
		character.material.set_shader_parameter("held_world", active_flight.body.global_position)
		character.material.set_shader_parameter("clearance_radius", minf(0.16, maxf(0.06, active_flight.mesh.mesh.get_aabb().size.length() * 0.55)))
	else:
		character.hand_target = player.position + basis * Vector3(0.30, 1.30, -0.20)
		carried.global_transform = Transform3D(basis, character.hand_position() - basis * carried_grip)


func _physics_process(delta: float) -> void:
	if editor != null or inspection != null or inventory.visible or Audio.settings.visible or (active_flight != null and (active_flight.released or active_flight.gauge_stage != 0 or active_flight.adjust_panel.visible or active_flight.results_panel.visible)):
		move_keys.clear()
		footstep_time = 0
		return
	var input := Vector3(float(move_keys.has(KEY_D)) - float(move_keys.has(KEY_A)), 0, float(move_keys.has(KEY_S)) - float(move_keys.has(KEY_W)))
	var direction := Basis(Vector3.UP, view_angles.x) * input.normalized()
	player.velocity.x = direction.x * 3
	player.velocity.z = direction.z * 3
	player.velocity.y -= 9.8 * delta
	var previous_position := player.position
	player.move_and_slide()
	if player.is_on_floor() and Vector2(player.position.x - previous_position.x, player.position.z - previous_position.z).length() > 0.0001:
		footstep_time -= delta
		if footstep_time <= 0:
			Audio.play_sfx("step")
			footstep_time = 0.4
	else: footstep_time = 0
	# Face movement intent even when a wall blocks or redirects the step.
	if not direction.is_zero_approx(): player.rotation.y = atan2(-direction.x, -direction.z)

func _update_camera() -> void:
	var target := player.position + Vector3.UP * 1.45
	var direction := Basis(Vector3.UP, view_angles.x) * Vector3(0, sin(view_angles.y), -cos(view_angles.y))
	var desired := target - direction * zoom
	var query := PhysicsRayQueryParameters3D.create(target, desired, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	camera.position = hit.position + hit.normal * 0.15 if not hit.is_empty() else desired
	camera.look_at(camera.position + direction)
	if active_flight == null and editor == null: camera.make_current()

func launch_position() -> Vector3:
	var from := player.position + Vector3.UP * 0.2
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 20, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var floor_y: float = hit.position.y if not hit.is_empty() else player.position.y
	return Vector3(player.position.x, floor_y + 1.7, player.position.z)

func rotate_view(relative: Vector2) -> void:
	view_angles.x = wrapf(view_angles.x - relative.x * 0.006, -PI, PI)
	view_angles.y = clampf(view_angles.y - relative.y * 0.006, deg_to_rad(-70), deg_to_rad(70))

func _update_target() -> void:
	bench_target = false
	target_id = -1
	var best := 2.2
	var bench_distance := player.position.distance_to(BENCH)
	if bench_distance < best:
		bench_target = true
		best = bench_distance
	for id in items:
		if items[id].state != "world": continue
		var distance := player.position.distance_to(items[id].flight.body.position)
		if distance < best:
			best = distance
			bench_target = false
			target_id = id
	workbench.material_override.albedo_color = Color("e6bd67") if bench_target else Color("b98556")
	hint.visible = not inventory.visible and (bench_target or target_id != -1)
	var target := BENCH + Vector3.UP * 1.2 if bench_target else Vector3.ZERO
	if target_id != -1: target = items[target_id].flight.body.position + Vector3.UP * 0.4
	hint.text = "작업대 · 접기 [E]" if bench_target else "%s · %s [E] · %.1fm" % [items[target_id].name if target_id != -1 else "", "회수" if target_id != -1 and items[target_id].known else "살펴보기", best]
	var size := get_viewport().get_visible_rect().size
	var screen := camera.unproject_position(target)
	hint.position = Vector2(clampf(screen.x - hint.size.x * 0.5, 12, maxf(12, size.x - hint.size.x - 12)), clampf(screen.y, status_panel.position.y + status_panel.size.y + 12, actions_panel.position.y - hint.size.y - 12))

func interact() -> void:
	if editor != null or inspection != null or active_flight != null or inventory.visible: return
	_update_target()
	if target_id != -1: recover_item(target_id)
	elif bench_target:
		var id := held_id if held_id != -1 else selected_id
		if id != -1 and items[id].state in ["stored", "hand"]: open_editor(id)
		else:
			notice = "보관함에서 수정할 기체를 선택하세요."
			_toggle_inventory()

func open_editor(id: int) -> void:
	if editor != null or inspection != null or active_flight != null or id == -1 or not items.has(id) or items[id].state not in ["stored", "hand"] or player.position.distance_to(BENCH) > 2.2: return
	inventory.hide()
	move_keys.clear()
	var data: Dictionary = items[id]
	data["before_work"] = data.state
	data.state = "work"
	editing_id = id
	editor = preload("res://scenes/main.tscn").instantiate()
	editor.park_mode = true
	editor.park_stored.connect(func() -> void: finish_edit(true))
	editor.park_cancelled.connect(func() -> void: finish_edit(false))
	# Keep editor lighting and collision isolated from the live park.
	var viewport := SubViewport.new()
	viewport.name = "FoldingViewport"
	viewport.own_world_3d = true
	viewport.handle_input_locally = true
	viewport.size = Vector2i(get_viewport().get_visible_rect().size)
	var container := SubViewportContainer.new()
	container.name = "FoldingScreen"
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	hud.get_parent().add_child(container)
	container.add_child(viewport)
	viewport.add_child(editor)
	editor.restore_sheet(data.sheet)
	editor.flight_session = data.flight_session.duplicate(true)
	hud.hide()

func finish_edit(store: bool) -> void:
	if editor == null or editing_id == -1 or editor.state != editor.State.IDLE: return
	var data: Dictionary = items[editing_id]
	if store:
		var sheet: Dictionary = editor._preset_state()
		var error: String = Presets._validate_state(sheet)
		if not error.is_empty():
			editor.dump_notice.text = "보관 불가: " + error
			Audio.play_sfx("error")
			return
		data.sheet = sheet.duplicate(true)
		Audio.play_sfx("save")
		carried_id = -1
		data.state = "stored"
		if held_id == editing_id: held_id = -1
		notice = "접은 기체를 보관했습니다. Tab으로 꺼내세요."
	else:
		data.state = data.before_work
	data.erase("before_work")
	editor.process_mode = Node.PROCESS_MODE_DISABLED
	hud.get_parent().get_node("FoldingScreen").queue_free()
	editor = null
	editing_id = -1
	hud.show()
	camera.make_current()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_refresh_inventory()

func stored_count() -> int:
	var count := 0
	for data in items.values():
		if data.state == "stored": count += 1
	return count

func _toggle_inventory() -> void:
	if editor != null or inspection != null or active_flight != null: return
	inventory.visible = not inventory.visible
	Audio.play_sfx("open" if inventory.visible else "close")
	move_keys.clear()
	if inventory.visible: _refresh_inventory()

func _refresh_inventory() -> void:
	inventory_list.clear()
	inventory_ids.clear()
	for id in items:
		if items[id].state not in ["stored", "hand"]: continue
		inventory_ids.append(id)
		inventory_list.add_item(items[id].name + (" · 손" if id == held_id else ""))
	var index := inventory_ids.find(selected_id)
	if index < 0 and not inventory_ids.is_empty(): index = 0
	selected_id = inventory_ids[index] if index >= 0 else -1
	if index >= 0: inventory_list.select(index)
	_select_inventory(index)

func _select_inventory(index: int) -> void:
	selected_id = inventory_ids[index] if index >= 0 and index < inventory_ids.size() else -1
	take_button.disabled = selected_id == -1
	inspect_button.disabled = selected_id == -1
	inventory_info.text = Stock.summary(items[selected_id].sheet.paper_stock) + "\n접기 %d회" % items[selected_id].sheet.fold_count if selected_id != -1 else "보관 중인 기체가 없습니다."
	preview.queue_redraw()

func _draw_preview() -> void:
	if selected_id == -1: return
	var faces: Array = items[selected_id].sheet.faces
	var points := PackedVector2Array()
	for face in faces: points.append_array(face.points)
	if points.is_empty(): return
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points: bounds = bounds.expand(point)
	var scale_factor := minf((preview.size.x - 16) / maxf(bounds.size.x, 0.001), (preview.size.y - 16) / maxf(bounds.size.y, 0.001))
	for face in faces:
		var polygon := PackedVector2Array()
		for point in face.points: polygon.append((point - bounds.get_center()) * scale_factor + preview.size * 0.5)
		preview.draw_colored_polygon(polygon, Stock.front(items[selected_id].sheet.paper_stock))
		polygon.append(polygon[0])
		preview.draw_polyline(polygon, Color("fff0cf"), 1)

func _take_selected() -> void:
	if selected_id == -1 or items[selected_id].state not in ["stored", "hand"] or active_flight != null or inspection != null: return
	if held_id != -1: items[held_id].state = "stored"
	held_id = selected_id
	carried_id = -1
	items[held_id].state = "hand"
	Audio.play_sfx("take")
	inventory.hide()
	notice = "Space로 투척 준비 · 우클릭으로 조준"

func prepare_throw() -> void:
	if held_id == -1 or editor != null or inspection != null or active_flight != null or inventory.visible: return
	move_keys.clear()
	var flight := Flight.new()
	flight.configure_item(self, held_id, items[held_id])
	active_flight = flight
	flight.closed.connect(exit_flight)
	add_child(flight)
	if not flight.ready_to_launch:
		notice = "연결이 보존된 기체만 던질 수 있습니다."
		exit_flight()
		return
	hud.hide()

func clear_launch(flight: Node) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = flight.body.get_child(flight.body.get_child_count() - 1).shape
	query.transform = flight.body.transform
	query.collision_mask = 1
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return false
	var ray := PhysicsRayQueryParameters3D.create(flight.launch_origin, flight.launch_origin + flight.launch_velocity().normalized() * 0.65, 1)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func release_item(flight: Node) -> void:
	var data: Dictionary = items[flight.item_id]
	assert(data.state == "hand" and held_id == flight.item_id)
	data.state = "flying"
	data.flight = flight
	data.flight_session = flight.session_state()
	held_id = -1
	move_keys.clear()

func exit_flight() -> void:
	if active_flight == null: return
	var flight := active_flight
	var data: Dictionary = items[flight.item_id]
	data.flight_session = flight.session_state()
	flight.watching = false
	flight.set_process_input(false)
	flight.set_process_unhandled_input(false)
	flight.hud.hide()
	flight.gizmo.hide()
	flight.camera_dragging = false
	if not flight.released: flight.queue_free()
	active_flight = null
	carried_id = -1
	move_keys.clear()
	hud.show()
	camera.make_current()
	notice = "기체 위치의 표식을 따라가 E로 회수하세요." if flight.released else "준비 취소 · 기체는 손에 있습니다."

func land_item(flight: Node) -> void:
	var data: Dictionary = items[flight.item_id]
	data.state = "world"
	data.flight_session = flight.session_state()
	trials.append(flight.trials[-1].duplicate(true))
	_add_marker(data)

func _add_marker(data: Dictionary) -> void:
	var marker := Label.new()
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.add_theme_color_override("font_color", Color("fff2b2"))
	marker.add_theme_color_override("font_outline_color", Color("182a30"))
	marker.add_theme_constant_override("outline_size", 4)
	hud.add_child(marker)
	data.marker = marker

func _spawn_found(id: int, pos: Vector3) -> void:
	var flight := Flight.new()
	flight.configure_item(self, id, items[id])
	flight.watching = false
	add_child(flight)
	flight.released = true
	flight.landed = true
	flight.body.position = pos
	flight.body.freeze = false
	flight.hud.hide()
	flight.gizmo.hide()
	flight.launch_arrow.hide()
	flight.set_process_input(false)
	flight.set_process_unhandled_input(false)
	items[id].state = "world"
	items[id].flight_session = flight.session_state()
	items[id].flight = flight
	_add_marker(items[id])
	camera.make_current()

func recover_item(id: int) -> void:
	if editor != null or inspection != null or active_flight != null or not items.has(id) or items[id].state != "world": return
	var data: Dictionary = items[id]
	if player.position.distance_to(data.flight.body.position) > 2.2: return
	if not data.known:
		open_inspection(id, true)
		return
	data.flight_session = data.flight.session_state()
	data.flight.queue_free()
	data.flight = null
	if data.marker != null: data.marker.queue_free()
	data.marker = null
	if held_id != -1: items[held_id].state = "stored"
	data.state = "hand"
	held_id = id
	carried_id = -1
	selected_id = id
	Audio.play_sfx("recover")
	notice = "같은 기체를 손에 들었습니다. 시작선으로 걸어가 Space로 다시 준비하세요." if practice_active else "같은 기체를 손에 들었습니다. Space로 다시 준비하세요."
	_refresh_inventory()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and not event.pressed: move_keys.erase(event.physical_keycode)
	if event is InputEventKey and event.physical_keycode == KEY_TAB and editor == null and inspection == null and active_flight == null:
		if event.pressed and not event.echo: _toggle_inventory()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed: camera_dragging = false
	if editor != null or inspection != null or active_flight != null or inventory.visible: return
	if event is InputEventMouseMotion and camera_dragging:
		rotate_view(event.relative)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if editor != null or inspection != null or active_flight != null: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_D and event.ctrl_pressed and event.shift_pressed:
			get_viewport().set_input_as_handled()
			dump_state()
			return
		if inventory.visible:
			if event.physical_keycode == KEY_ESCAPE: _toggle_inventory()
			get_viewport().set_input_as_handled()
			return
		match event.physical_keycode:
			KEY_T: toggle_practice()
			KEY_W, KEY_A, KEY_S, KEY_D: move_keys[event.physical_keycode] = true
			KEY_E: interact()
			KEY_SPACE:
				get_viewport().set_input_as_handled()
				prepare_throw()
	if inventory.visible: return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT: camera_dragging = true
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP: zoom = maxf(1.5, zoom * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: zoom = minf(9, zoom / 0.9)

func snapshot() -> Dictionary:
	var records: Array[Dictionary] = []
	for data in items.values():
		records.append({"id": data.id, "name": data.name, "state": data.state, "sheet": data.sheet.duplicate(true), "flight_session": data.flight_session.duplicate(true), "world_position": data.flight.body.position if data.flight != null else null, "world_velocity": data.flight.body.linear_velocity if data.flight != null else null})
	return {"format": "pap-park-dump", "version": 1, "player_position": player.position, "view_angles": view_angles, "zoom": zoom, "held_id": held_id, "selected_id": selected_id, "items": records, "trials": trials.duplicate(true), "active_flight": active_flight.snapshot() if active_flight != null else null, "cleaning_records": cleaning_records.duplicate(true), "inventory": {"visible": inventory.visible, "take": {"position": take_button.global_position, "size": take_button.size}, "inspect": {"position": inspect_button.global_position, "size": inspect_button.size}}, "inspection": null if inspection == null else inspection.snapshot(), "character": {"motion": character.motion, "holding": character.holding, "hand_position": character.hand_position(), "hand_target": character.hand_target, "reach_error": character.reach_error}}

func dump_state() -> void:
	var text := JSON.stringify(Dump.encode(snapshot()), "\t")
	var filename := "pap_park_" + Time.get_datetime_string_from_system().replace(":", "-") + ".json"
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), filename, "application/json")
	else:
		DirAccess.make_dir_recursive_absolute("user://dumps")
		var file := FileAccess.open("user://dumps/" + filename, FileAccess.WRITE)
		if file != null: file.store_string(text)
	notice = "공원 상태 덤프: " + filename

func restore_failed_flight(flight: Node) -> void:
	var data: Dictionary = items[flight.item_id]
	if data.state != "flying": return
	if active_flight == flight: exit_flight()
	data.flight_session = flight.session_state()
	data.flight = null
	data.state = "stored"
	flight.set_physics_process(false)
	flight.body.freeze = true
	flight.queue_free()
	notice = "비행 수치 오류 · 같은 기체를 보관함으로 복구했습니다."
	trials.append({"item_id": data.id, "reason": "수치 오류 · 보관함 복구", "duration_s": flight.elapsed})

func open_inspection(id: int, world_source: bool) -> void:
	if inspection != null or editor != null or active_flight != null or not items.has(id): return
	var data: Dictionary = items[id]
	if world_source:
		if data.state != "world" or player.position.distance_to(data.flight.body.position) > 2.2: return
	else:
		if data.state not in ["stored", "hand"]: return
	inspection_origin = {"state": data.state, "inventory": inventory.visible}
	if world_source:
		var body: RigidBody3D = data.flight.body
		inspection_origin.merge({"transform": body.transform, "velocity": body.linear_velocity, "angular": body.angular_velocity, "freeze": body.freeze})
		body.freeze = true
		data.flight.hide()
		if data.marker != null: data.marker.hide()
	inspection_id = id
	data.state = "inspecting"
	move_keys.clear()
	camera_dragging = false
	inspection = Inspection.new()
	Audio.play_sfx("open")
	inspection.theme = hud.theme
	inspection.configure(data, world_source)
	inspection.decided.connect(finish_inspection)
	inspection.dump_requested.connect(dump_state)
	hud.get_parent().add_child(inspection)
	hud.hide()

func finish_inspection(action: String) -> void:
	if inspection == null or inspection_id == -1: return
	var id := inspection_id
	var data: Dictionary = items[id]
	var world_source: bool = inspection_origin.state == "world"
	var panel := inspection
	inspection = null
	inspection_id = -1
	panel.set_process_input(false)
	panel.queue_free()
	if world_source and action in ["store", "clear"]:
		Audio.play_sfx("recover" if action == "store" else "clear")
		data.flight_session = data.flight.session_state()
		data.flight.queue_free()
		data.flight = null
		if data.marker != null: data.marker.queue_free()
		data.marker = null
		data.known = true
		data.state = "stored" if action == "store" else "cleared"
		if action == "store": selected_id = id
		else: cleaning_records.append({"item_id": id, "name": data.name, "paper_stock": data.sheet.paper_stock.duplicate(true)})
		notice = "기체를 보관했습니다." if action == "store" else "발견물 정리 기록을 남겼습니다. 보수는 없습니다."
	else:
		data.state = inspection_origin.state
		Audio.play_sfx("close")
		if world_source:
			var body: RigidBody3D = data.flight.body
			body.transform = inspection_origin.transform
			body.linear_velocity = inspection_origin.velocity
			body.angular_velocity = inspection_origin.angular
			body.freeze = inspection_origin.freeze
			body.reset_physics_interpolation()
			data.flight.show()
		else:
			inventory.visible = inspection_origin.inventory
	inspection_origin.clear()
	move_keys.clear()
	hud.show()
	camera.make_current()
	_refresh_inventory()
