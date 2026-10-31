extends Node3D

signal closed
const AircraftVisual := preload("res://scripts/aircraft_visual.gd")
const PlayUI := preload("res://scripts/play_ui.gd")
const Stock := preload("res://scripts/paper_stock.gd")
const Parts := preload("res://scripts/flight_parts.gd")
const Model := preload("res://scripts/flight_model.gd")
const Body := preload("res://scripts/flight_body.gd")
const RotationGizmo := preload("res://scripts/rotation_gizmo.gd")
const WindArrow := preload("res://scripts/wind_arrow.gd")
const PaperToon := preload("res://shaders/paper_toon.gdshader")
const LAUNCH := Vector3(0, 1.7, 0)
const MAX_LAUNCH_SPEED := 8.16
const IMPACT_END := -0.2
const IMPACT_SPEED := 0.65
const POWER_SECONDS := 2.4
const POWER_SPEED := 0.99 / POWER_SECONDS
const ORIGIN_WIDTH_PX := 20.0
const MIN_WIND_SPEED := 0.5
const MAX_WIND_SPEED := 3.0
const ELEVATION_ERROR_SCALE := 30.0
var launch_power := 50.0
const PITCH := 3.0
var attitude := Basis(Vector3.RIGHT, deg_to_rad(PITCH))
var aim := Vector2(0, PITCH)
var dragging := false
var camera_dragging := false
var camera_angles := Vector2(atan2(0.34, 0.4), asin(0.23 / Vector3(0.34, 0.23, 0.4).length()))
var camera_zoom := 1.0
var preview_distance := Vector3(0.34, 0.23, 0.4).length()
var follow_distance := Vector3(1.5, 0.8, 2).length()
var pose_fields: Array[SpinBox] = []
var gizmo := RotationGizmo.new()
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
var binding: Dictionary = {}
var hud := Control.new()
var topbar := HFlowContainer.new()
var adjust_panel := PanelContainer.new()
var results_panel := PanelContainer.new()
var results_overlay := ColorRect.new()
var gauge_panel := PanelContainer.new()
var gauge_label := Label.new()
var elevation_value := Label.new()
var elevation_hint := Label.new()
var elevation_down: Button
var elevation_up: Button
var elevation_help := "↑↓ 또는 −/+ 로 조절\n기체 자세와 별개"
var gauge_track := Control.new()
var wind_hud := Control.new()
var wind_label := Label.new()
var wind_arrow := WindArrow.new()
var wind_random: Button
var wind_reset: Button
var parts_label := Label.new()
var adjust_button: Button
var result_button: Button
var result_retry: Button
var gauge_cancel: Button
var paper_stock: Dictionary = {}
var sheet_signature := ""
var context_notice := ""
var gauge_stage := 0
var gauge_phase := 0.0
var gauge_saved := Vector2.ZERO
var gauge_cursor := 0.0
var gauge_returning := false
var impact_tolerance := 0.0
var impact_deviation := 0.0
var impact_error := 0.0
var automatic_miss := false
var launch_keys: Dictionary = {}
var launched: Dictionary = {}
var last_gauge_frame := -1

func configure(source_faces: Array[Dictionary], source_history: Array[Dictionary], source: Node) -> void:
	faces = source_faces.duplicate(true)
	history = source_history.duplicate(true)
	paper_stock = Stock.legacy(faces) if source == null else source.paper_stock.duplicate(true)
	folding = source
	sheet_signature = Parts.signature(faces, history)
	if source != null and Parts.valid(source.flight_parts, faces, history): binding = source.flight_parts.duplicate(true)

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
	_restore_session()
	_rebuild()
	_refresh_results()
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
	canvas.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = preload("res://assets/fonts/NanumGothic-Regular.ttf")
	theme.default_font_size = 16
	hud.theme = theme
	hud.draw.connect(_draw_hud_back)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("182a30")
	style.set_content_margin_all(8)
	style.set_corner_radius_all(8)
	for panel in [adjust_panel, results_panel, gauge_panel]:
		hud.add_child(panel)
		panel.add_theme_stylebox_override("panel", style)
	hud.add_child(topbar)
	var title := Label.new()
	title.text = "비행 테스트"
	topbar.add_child(title)
	_button(topbar, "접기로 [B]", func() -> void: closed.emit())
	adjust_button = _button(topbar, "자세·날개", _toggle_adjust)
	_button(topbar, "부위 · 확정" if not binding.is_empty() else ("부위 · 재확인" if folding != null and not folding.flight_parts.is_empty() else "부위 · 추천"), func() -> void:
		closed.emit()
		if folding != null: folding.call_deferred("_open_parts")
	)
	_button(topbar, "원위치 [R]", reset_trial)
	Audio.add_button(topbar)
	result_button = _button(hud, "결과 (0)", _toggle_results)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	adjust_panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	_button(column, "조정 닫기", _toggle_adjust)
	parts_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parts_label.text = "확정 부위 사용" if not binding.is_empty() else "자동 추천 / 미확정 · 자유 비행 가능"
	column.add_child(parts_label)
	for i in 2:
		var label := Label.new()
		angle_labels.append(label)
		column.add_child(label)
		var slider := HSlider.new()
		slider.max_value = 150
		slider.value = 90
		slider.step = 1
		slider.focus_mode = Control.FOCUS_NONE
		slider.value_changed.connect(func(value: float) -> void: _angle_changed(i, value))
		sliders.append(slider)
		column.add_child(slider)
	linked.text = "양쪽 날개 함께 조절"
	linked.button_pressed = true
	linked.focus_mode = Control.FOCUS_NONE
	column.add_child(linked)
	for i in 3:
		var row := HBoxContainer.new()
		column.add_child(row)
		var label := Label.new()
		label.text = ["X", "Y", "Z"][i]
		label.modulate = RotationGizmo.COLORS[i]
		row.add_child(label)
		var field := SpinBox.new()
		field.min_value = -180
		field.max_value = 180
		field.allow_greater = true
		field.allow_lesser = true
		field.step = 0.1
		field.suffix = "°"
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.value_changed.connect(func(value: float) -> void: _pose_axis_changed(i, value))
		pose_fields.append(field)
		row.add_child(field)
	_button(column, "기본 자세로", _reset_attitude)
	var help := Label.new()
	help.text = "회전 링: 축별 회전 · Shift: 15°\n90°: 손잡이와 날개가 직각\n우클릭 드래그: 시점 회전 · 휠: 확대/축소"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(help)
	adjust_panel.hide()
	var result_column := VBoxContainer.new()
	results_panel.add_child(result_column)
	_button(result_column, "결과 닫기", _toggle_results)
	var result_scroll := ScrollContainer.new()
	result_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	result_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	result_column.add_child(result_scroll)
	results.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_scroll.add_child(results)
	results.text = "비행 결과가 아직 없습니다."
	var result_actions := HBoxContainer.new()
	result_column.add_child(result_actions)
	result_retry = _button(result_actions, "다시 던지기", func() -> void:
		if running: return
		results_panel.hide()
		_advance_gauge()
	)
	PlayUI.primary(result_retry)
	_button(result_actions, "접기 수정", func() -> void: closed.emit())
	results_panel.hide()
	hud.add_child(results_overlay)
	results_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	results_overlay.z_index = 100
	results_overlay.color = Color(0.015, 0.035, 0.045, 0.8)
	results_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	results_panel.reparent(results_overlay)
	results_overlay.hide()
	var gauge_column := VBoxContainer.new()
	gauge_panel.add_child(gauge_column)
	var elevation_row := HBoxContainer.new()
	gauge_column.add_child(elevation_row)
	var elevation_title := Label.new()
	elevation_title.text = "투척\n고도각"
	elevation_title.add_theme_font_size_override("font_size", 14)
	elevation_row.add_child(elevation_title)
	elevation_value.add_theme_font_size_override("font_size", 32)
	elevation_value.add_theme_color_override("font_color", Color("7de1d2"))
	elevation_value.custom_minimum_size.x = 92
	elevation_row.add_child(elevation_value)
	elevation_down = _button(elevation_row, "−", func() -> void: _aim_changed(1, aim.y - 1))
	elevation_up = _button(elevation_row, "+", func() -> void: _aim_changed(1, aim.y + 1))
	for button in [elevation_down, elevation_up]: button.custom_minimum_size = Vector2(32, 36)
	elevation_hint.add_theme_font_size_override("font_size", 13)
	elevation_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	elevation_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	elevation_row.add_child(elevation_hint)
	gauge_label.custom_minimum_size.y = 32
	gauge_label.max_lines_visible = 2
	gauge_column.add_child(gauge_label)
	gauge_track.custom_minimum_size.y = 26
	gauge_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge_track.draw.connect(_draw_gauge)
	gauge_column.add_child(gauge_track)
	var gauge_spacer := Control.new()
	gauge_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gauge_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge_column.add_child(gauge_spacer)
	var gauge_row := HBoxContainer.new()
	gauge_column.add_child(gauge_row)
	launch_button.focus_mode = Control.FOCUS_NONE
	launch_button.pressed.connect(_advance_gauge)
	launch_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gauge_row.add_child(launch_button)
	PlayUI.primary(launch_button)
	gauge_cancel = _button(gauge_row, "취소 [Esc]", _cancel_gauge)
	hud.add_child(metrics)
	metrics.mouse_filter = Control.MOUSE_FILTER_IGNORE
	metrics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.add_child(wind_hud)
	wind_hud.mouse_filter = Control.MOUSE_FILTER_STOP
	wind_hud.scale = Vector2(1.5, 1.5)
	wind_hud.tooltip_text = "현재 카메라에서 바라본, 바람이 불어가는 방향입니다."
	wind_hud.draw.connect(_draw_wind)
	wind_hud.add_child(wind_arrow)
	wind_arrow.position = Vector2(24, -3)
	wind_arrow.size = Vector2(56, 56)
	wind_hud.add_child(wind_label)
	wind_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wind_label.text = "무풍 · 0 m/s"
	wind_label.position = Vector2(0, 50)
	var wind_controls := HBoxContainer.new()
	wind_controls.position = Vector2(0, 72)
	wind_hud.add_child(wind_controls)
	wind_reset = _button(wind_controls, "리셋", func() -> void: _set_wind(Vector3.ZERO))
	wind_reset.tooltip_text = "바람 리셋 · 무풍으로"
	wind_random = _button(wind_controls, "랜덤", _randomize_wind)
	wind_random.tooltip_text = "수평 바람의 방향과 풍속을 무작위로 설정 (0.5–3.0 m/s)"
	_layout_hud()

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _layout_hud() -> void:
	var size := get_viewport().get_visible_rect().size
	topbar.position = Vector2(12, 8)
	topbar.size = Vector2(size.x - 120, 0)
	result_button.position = Vector2(size.x - 90, 8)
	result_button.size = Vector2(78, 24)
	var top := topbar.position.y + topbar.size.y + 8
	metrics.position = Vector2(12, top)
	metrics.size.x = size.x - 24
	var panel_top := top + 42
	adjust_panel.position = Vector2(12, panel_top)
	adjust_panel.size = Vector2(minf(320, size.x * 0.46), maxf(70, size.y - panel_top - 120))
	results_panel.size = Vector2(minf(560, size.x - 32), size.y - 48)
	results_panel.position = Vector2(size.x - results_panel.size.x - 16, (size.y - results_panel.size.y) * 0.5)
	results_overlay.visible = results_panel.visible
	gauge_panel.size = Vector2(minf(700, size.x - 200), 166)
	gauge_panel.position = Vector2((size.x - 184 - gauge_panel.size.x) * 0.5, size.y - 178)
	wind_hud.position = Vector2(size.x - 168, size.y - 154)
	wind_hud.size = Vector2(104, 96)
	wind_reset.disabled = running or gauge_stage != 0
	wind_random.disabled = running or gauge_stage != 0
	wind_hud.queue_redraw()
	result_button.disabled = gauge_stage != 0
	result_button.tooltip_text = "게이지 입력을 마친 후 결과를 열 수 있습니다." if gauge_stage != 0 else "최근 비행 결과"
	result_retry.disabled = running or not ready_to_launch
	gauge_cancel.disabled = gauge_stage == 0
	gizmo.visible = adjust_panel.visible and not running and gauge_stage == 0
	adjust_button.disabled = running or gauge_stage != 0
	hud.queue_redraw()
	_update_gauge()

func _draw_hud_back() -> void:
	hud.draw_style_box(gauge_panel.get_theme_stylebox("panel"), Rect2(Vector2(6, 4), Vector2(hud.size.x - 12, topbar.size.y + 10)))

func _toggle_adjust() -> void:
	if running or gauge_stage != 0: return
	adjust_panel.visible = not adjust_panel.visible
	Audio.play_sfx("open" if adjust_panel.visible else "close")
	results_panel.hide()
	dragging = false
	gizmo.end_drag()
	_layout_hud()

func _toggle_results() -> void:
	if gauge_stage != 0: return
	results_panel.visible = not results_panel.visible
	Audio.play_sfx("open" if results_panel.visible else "close")
	adjust_panel.hide()
	dragging = false
	camera_dragging = false
	gizmo.end_drag()
	_layout_hud()

func _advance_gauge() -> void:
	if last_gauge_frame == Engine.get_process_frames(): return
	last_gauge_frame = Engine.get_process_frames()
	if running or not ready_to_launch or results_panel.visible: return
	if gauge_stage == 0:
		if elapsed > 0: reset_trial()
		gauge_saved = Vector2(launch_power, aim.y)
		gauge_stage = 1
		Audio.play_sfx("gauge")
		gauge_phase = 0
		impact_error = 0
		impact_deviation = 0
		impact_tolerance = 0
		gauge_returning = false
		automatic_miss = false
		adjust_panel.hide()
		dragging = false
		gizmo.end_drag()
	elif gauge_stage == 1:
		gauge_stage = 2
		Audio.play_sfx("power")
		gauge_cursor = launch_power / 100.0
		gauge_returning = fmod(gauge_phase, 2.0) >= 1.0
	else:
		_commit_impact(false)
	_sync_pose_fields()
	_layout_hud()

func _cancel_gauge() -> void:
	if gauge_stage != 0:
		launch_power = gauge_saved.x
		aim.y = gauge_saved.y
		gauge_stage = 0
		gauge_cursor = 0
		gauge_returning = false
		impact_error = 0
		impact_deviation = 0
		impact_tolerance = 0
		_update_launch_arrow()
	_sync_pose_fields()
	_layout_hud()

func _commit_impact(missed: bool) -> void:
	if gauge_stage != 2 or running or not gauge_returning: return
	var error := gauge_cursor
	gauge_stage = 0
	launch(error, missed)
	if running: Audio.play_sfx("impact")

func _update_gauge() -> void:
	elevation_value.text = "%+.0f°" % aim.y
	elevation_down.disabled = running or gauge_stage != 0 or results_panel.visible
	elevation_up.disabled = elevation_down.disabled
	elevation_hint.text = elevation_help if not elevation_down.disabled else ("목표 고도각 고정" if not running else "실제 발사 %+.1f°" % effective_elevation())
	launch_button.text = ["다시 던지기 · Space/Enter" if elapsed > 0 else "던지기 준비 · Space/Enter", "강도 결정 · Space/Enter", "원점에서 던지기"][gauge_stage]
	if running: launch_button.text = "비행 중"
	launch_button.disabled = running or not ready_to_launch or (gauge_stage == 2 and not gauge_returning)
	if gauge_stage == 2 and not gauge_returning: launch_button.text = "끝점까지 진행 중…"
	var previous := ""
	if not trials.is_empty():
		var label := "기체 수정 전" if trials[-1].get("sheet_signature", sheet_signature) != sheet_signature or trials[-1].get("paper_stock", paper_stock) != paper_stock else "직전"
		previous = " · %s %.2fm / %.2fs" % [label, trials[-1].distance_m, trials[-1].duration_s]
	if running:
		gauge_label.text = "%s · 목표 %.0f° → 실제 %.1f° (%+.1f°)" % ["빗맞음 · 자동 발사" if automatic_miss else "비행 중", aim.y, effective_elevation(), effective_elevation() - aim.y]
	elif gauge_stage == 1: gauge_label.text = "강도 결정 · 현재 %.0f%% · 목표 고도각 %.0f° 고정" % [launch_power, aim.y]
	elif gauge_stage == 2: gauge_label.text = ("원점 영역 맞추기" if gauge_returning else "끝점까지 진행 · 돌아오면 입력하세요") + " · %.0f%% · 목표 %.0f°" % [launch_power, aim.y]
	else:
		gauge_label.text = "준비 · Space/Enter로 강도 선택" + previous
		if not context_notice.is_empty(): gauge_label.text += "\n" + context_notice
	gauge_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gauge_panel.tooltip_text = "강도를 선택해도 커서는 끝까지 간 뒤 돌아옵니다. 0의 20px 영역 안에서 누르면 목표 고도각으로 발사합니다. 일찍: 위쪽 편차 / 늦게: 아래쪽 편차. 끝까지 놓치면 자동 발사됩니다."
	gauge_track.queue_redraw()

func _gauge_x(value: float) -> float:
	return 4 + (value - IMPACT_END) / (1.0 - IMPACT_END) * (gauge_track.size.x - 8)

func _origin_half_range() -> float:
	return ORIGIN_WIDTH_PX * 0.5 / maxf(1.0, _gauge_x(1) - _gauge_x(0))

static func _timing_deviation(error: float, tolerance: float) -> float:
	return signf(error) * maxf(0, absf(error) - tolerance) * ELEVATION_ERROR_SCALE

func _draw_gauge() -> void:
	var size := gauge_track.size
	var origin := _gauge_x(0)
	gauge_track.draw_style_box(_track_style(), Rect2(Vector2.ZERO, Vector2(size.x, 18)))
	gauge_track.draw_rect(Rect2(0, 0, origin, 18), Color("263b45"))
	var power_x := _gauge_x(launch_power / 100.0)
	gauge_track.draw_rect(Rect2(origin, 2, maxf(0, power_x - origin), 14), Color(0.94, 0.78, 0.47, 0.2))
	for i in 11:
		var tick := _gauge_x(i / 10.0)
		gauge_track.draw_line(Vector2(tick, 12), Vector2(tick, 18), Color("71828a"))
	var zone := Rect2(origin - ORIGIN_WIDTH_PX * 0.5, 0, ORIGIN_WIDTH_PX, 18)
	gauge_track.draw_rect(zone, Color(0.49, 0.88, 0.82, 0.35))
	gauge_track.draw_rect(zone, Color("7de1d2"), false, 1)
	gauge_track.draw_line(Vector2(origin, 0), Vector2(origin, 20), Color.WHITE, 2)
	gauge_track.draw_string(hud.get_theme_default_font(), Vector2(origin - 4, 26), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
	if gauge_stage == 2: gauge_track.draw_line(Vector2(power_x, 0), Vector2(power_x, 18), Color("f0c878"), 2)
	var cursor := _gauge_x(gauge_cursor) if gauge_stage == 2 else power_x
	gauge_track.draw_line(Vector2(cursor, 0), Vector2(cursor, 18), Color("7de1d2"), 4)

func _track_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("344d56")
	return style

func _set_wind(value: Vector3) -> void:
	if running or gauge_stage != 0 or not value.is_finite(): return
	body.wind_velocity = value.limit_length(MAX_WIND_SPEED)
	wind_label.text = "무풍 · 0 m/s" if body.wind_velocity.length() < 0.001 else "%.1f m/s" % body.wind_velocity.length()
	wind_arrow.update_wind(_wind_camera_direction(), body.wind_velocity.length(), 0)
	wind_hud.queue_redraw()

func _randomize_wind() -> void:
	if running or gauge_stage != 0: return
	var direction := randf_range(-PI, PI)
	var speed := snappedf(randf_range(MIN_WIND_SPEED, MAX_WIND_SPEED), 0.1)
	_set_wind(Vector3(sin(direction), 0, -cos(direction)) * speed)

func _wind_camera_direction() -> Vector3:
	return camera.global_basis.inverse() * body.wind_velocity

func _wind_screen_direction() -> Vector2:
	var direction := _wind_camera_direction()
	var projected := Vector2(direction.x, -direction.y)
	return projected.normalized() if projected.length_squared() >= 0.00000001 else Vector2.ZERO

func _draw_wind() -> void:
	var center := Vector2(52, 25)
	wind_hud.draw_circle(center, 22, Color("344d56"))
	wind_hud.draw_arc(center, 22, 0, TAU, 48, Color("7de1d2"), 1.5, true)
	var wind: Vector3 = body.wind_velocity
	if wind.length() < 0.001:
		wind_hud.draw_circle(center, 3, Color("9bafb7"))

func _angle_changed(index: int, value: float) -> void:
	if running or gauge_stage != 0:
		return
	angles[index] = value
	if linked.button_pressed:
		angles[1 - index] = value
	for i in 2:
		sliders[i].set_value_no_signal(angles[i])
	_rebuild()

func _rebuild() -> void:
	var raw := Model.pose(faces, history, angles, binding)
	ready_to_launch = Model.is_joined(raw)
	if not ready_to_launch:
		mesh.visible = false
		launch_button.disabled = true
		metrics.text = "이 각도에서 종이 연결을 보존하지 못해 비행 준비를 중단했습니다."
		return
	mesh.visible = true
	var upright := Model.launch_frame(faces, history, binding)
	posed = []
	for face in raw:
		var points := PackedVector3Array()
		for point in face.points:
			points.append(upright * point)
		posed.append({"points": points, "paper": face.paper, "seams": face.seams, "normal": upright * face.normal, "layer_sign": face.layer_sign})
	properties = Model.properties(posed, paper_stock.gsm / 1000.0)
	var radius := 0.0
	for face in posed:
		for point in face.points: radius = maxf(radius, (point - properties.center).length())
	# Leave room for the lower flight controls when framing larger sheets.
	preview_distance = maxf(Vector3(0.34, 0.23, 0.4).length(), radius / sin(deg_to_rad(camera.fov * 0.5)) * 2.0)
	body.mass = maxf(properties.mass, 0.0001)
	body.panels = Model.panels(posed, properties.center)
	var visual := AircraftVisual.build(posed, properties.center, paper_stock)
	mesh.mesh = visual.mesh
	mesh.material_override = visual.material
	var collision_points: PackedVector3Array = visual.collision
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
		if Model.wing_folds(history, binding).size() < 2:
			sliders[i].editable = false
			angle_labels[i].text += " · 두 날개 접기 기록이 필요합니다"
	reset_trial()

func reset_trial() -> void:
	aim.x = 0
	if not ready_to_launch:
		return
	gauge_stage = 0
	gauge_cursor = 0
	gauge_returning = false
	impact_error = 0
	impact_tolerance = 0
	impact_deviation = 0
	automatic_miss = false
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
	for slider in sliders:
		slider.editable = Model.wing_folds(history, binding).size() == 2
	_sync_pose_fields()
	_update_launch_arrow()
	_update_metrics()
	_layout_hud()

func launch(timing_error: float = 0, missed: bool = false) -> void:
	if running or not ready_to_launch:
		return
	reset_trial()
	impact_error = clampf(timing_error, IMPACT_END, 1)
	impact_tolerance = _origin_half_range()
	impact_deviation = _timing_deviation(impact_error, impact_tolerance)
	automatic_miss = missed
	body.freeze = false
	body.sleeping = false
	body.linear_velocity = launch_velocity()
	launched = {"launch_power": launch_power, "aim_degrees": Vector2(0, effective_elevation()), "target_aim_degrees": aim, "timing_error": impact_error, "origin_width_px": ORIGIN_WIDTH_PX, "origin_tolerance": impact_tolerance, "origin_hit": absf(impact_error) <= impact_tolerance and not automatic_miss, "elevation_deviation": effective_elevation() - aim.y, "automatic_miss": automatic_miss, "launch_transform": Transform3D(attitude, LAUNCH), "launch_velocity": launch_velocity(), "angles": angles, "flight_parts": binding.duplicate(true), "paper_stock": paper_stock.duplicate(true), "wind_velocity": body.wind_velocity}
	running = true
	Audio.play_sfx("throw")
	_sync_pose_fields()
	gizmo.end_drag()
	launch_arrow.visible = false
	launch_button.disabled = true
	for slider in sliders:
		slider.editable = false
	_layout_hud()

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

func _process(delta: float) -> void:
	if gauge_stage == 1 and not running:
		gauge_phase += delta / POWER_SECONDS
		var fraction := 1.0 - absf(fmod(gauge_phase, 2.0) - 1.0)
		launch_power = roundf(lerpf(1, 100, fraction))
	elif gauge_stage == 2 and not running:
		var remaining := delta
		if not gauge_returning:
			var to_end := (1.0 - gauge_cursor) / POWER_SPEED
			if remaining < to_end:
				gauge_cursor += remaining * POWER_SPEED
				remaining = 0
			else:
				gauge_cursor = 1
				gauge_returning = true
				remaining -= to_end
		if gauge_returning:
			gauge_cursor = maxf(IMPACT_END, gauge_cursor - remaining * IMPACT_SPEED)
			if gauge_cursor <= IMPACT_END: _commit_impact(true)
	_layout_hud()
	_update_camera()
	wind_arrow.update_wind(_wind_camera_direction(), body.wind_velocity.length(), delta)

func _update_metrics() -> void:
	var distance := Vector2(body.position.x - LAUNCH.x, body.position.z - LAUNCH.z).length()
	metrics.text = "거리 %.2fm · 체공 %.2fs · %s · %.2fg · 발사 %.1fm" % [distance, elapsed, Stock.summary(paper_stock), body.mass * 1000.0, LAUNCH.y]

func _finish(reason: String) -> void:
	if not running: return
	if reason == "착지": Audio.play_sfx("land")
	running = false
	dragging = false
	body.freeze = true
	var distance := Vector2(body.position.x - LAUNCH.x, body.position.z - LAUNCH.z).length()
	var trial := launched.duplicate(true)
	trial.merge({"distance_m": distance, "duration_s": elapsed, "reason": reason, "mass_kg": body.mass, "sheet_signature": sheet_signature}, true)
	trials.append(trial)
	_sync_pose_fields()
	_refresh_results()
	launch_button.disabled = false
	for slider in sliders:
		slider.editable = Model.wing_folds(history, binding).size() == 2
	_layout_hud()

func _refresh_results() -> void:
	results.text = "비행 결과가 아직 없습니다." if trials.is_empty() else "최근 비행 기록\n"
	for i in range(trials.size() - 1, -1, -1):
		var item := trials[i]
		var changed := " · 기체 수정 전" if item.get("sheet_signature", sheet_signature) != sheet_signature or item.get("paper_stock", paper_stock) != paper_stock else ""
		results.text += "%d. 거리 %.2fm · 체공 %.2fs%s\n강도 %.0f%% · 목표 고도각 %.0f° → 실제 %.1f°\n편차 %+.1f°%s · 바람 %.1f m/s\n날개 %.0f° / %.0f° · %s\n\n" % [i + 1, item.distance_m, item.duration_s, changed, item.launch_power, item.target_aim_degrees.y, item.aim_degrees.y, item.elevation_deviation, " · 자동 빗맞음" if item.automatic_miss else "", item.wind_velocity.length(), item.angles.x, item.angles.y, item.reason + " · " + Stock.summary(item.get("paper_stock", paper_stock))]
	result_button.text = "결과 (%d)" % trials.size()

func session_state() -> Dictionary:
	return {"sheet_signature": sheet_signature, "paper_stock": paper_stock.duplicate(true), "binding": binding.duplicate(true), "attitude": attitude, "angles": angles, "aim": aim, "launch_power": gauge_saved.x if gauge_stage != 0 else launch_power, "wind": body.wind_velocity, "camera_angles": camera_angles, "camera_zoom": camera_zoom, "trials": trials.duplicate(true)}

func _restore_session() -> void:
	if folding == null or folding.flight_session.is_empty(): return
	var saved: Dictionary = folding.flight_session
	aim = saved.aim
	launch_power = saved.launch_power
	camera_angles = saved.camera_angles
	camera_zoom = saved.camera_zoom
	trials.assign(saved.trials.duplicate(true))
	_set_wind(saved.wind)
	if saved.sheet_signature == sheet_signature and saved.get("paper_stock", paper_stock) == paper_stock and saved.binding == binding:
		attitude = saved.attitude
		angles = saved.angles
	else:
		context_notice = "기체/부위 변경 · 자세·날개 기본값"
		parts_label.text += " · " + context_notice

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

func effective_elevation() -> float:
	# Keep forward flight even for an off-center hit near the target angle limits.
	return clampf(aim.y + impact_deviation, -89, 89)

func launch_velocity() -> Vector3:
	var elevation := deg_to_rad(effective_elevation())
	return Vector3(0, sin(elevation), -cos(elevation)) * (MAX_LAUNCH_SPEED * launch_power / 100.0)

func _power_changed(value: float) -> void:
	if running or gauge_stage != 0:
		return
	launch_power = clampf(value, 1, 100)
	reset_trial()

func _aim_changed(index: int, value: float) -> void:
	if running or gauge_stage != 0 or results_panel.visible:
		return
	if index == 0:
		aim.x = 0
		return
	aim[index] = clampf(value, -80, 80)
	reset_trial()

func _reset_attitude() -> void:
	if running or gauge_stage != 0:
		return
	attitude = Basis(Vector3.RIGHT, deg_to_rad(PITCH))
	reset_trial()

func _sync_pose_fields() -> void:
	var euler := attitude.get_euler()
	for i in pose_fields.size():
		pose_fields[i].set_value_no_signal(rad_to_deg(euler[i]))
		pose_fields[i].editable = not running and gauge_stage == 0

func _pose_axis_changed(index: int, degrees: float) -> void:
	if running or gauge_stage != 0:
		return
	var euler := attitude.get_euler()
	euler[index] = deg_to_rad(degrees)
	_set_attitude(Basis.from_euler(euler))

func _set_attitude(value: Basis) -> void:
	if running or gauge_stage != 0 or not ready_to_launch:
		return
	attitude = value.orthonormalized()
	var was_dragging := dragging
	reset_trial()
	dragging = was_dragging

func _update_camera() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var top := metrics.position.y + metrics.size.y + 12
	var bottom := minf(gauge_panel.position.y, wind_hud.position.y) - 10
	var base_distance := preview_distance if not running and elapsed == 0 else follow_distance
	if not running and elapsed == 0: base_distance *= maxf(1, viewport.y / maxf(40, bottom - top) * 0.5)
	var distance := clampf(base_distance * camera_zoom, 0.18, 25.0)
	var horizontal := cos(camera_angles.y)
	var direction := Vector3(sin(camera_angles.x) * horizontal, sin(camera_angles.y), cos(camera_angles.x) * horizontal)
	camera.position = body.position + direction * distance
	camera.look_at(body.position)
	var center_fraction := (top + bottom) * 0.5 / viewport.y
	camera.position += camera.global_basis.y * ((center_fraction - 0.5) * 2 * tan(deg_to_rad(camera.fov * 0.5)) * distance)
	wind_arrow.update_wind(_wind_camera_direction(), body.wind_velocity.length(), 0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		camera_dragging = false
		dragging = false
		gizmo.end_drag()

func _update_launch_arrow() -> void:
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
	if event is InputEventKey and not event.pressed: launch_keys.erase(event.physical_keycode)
	if results_panel.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_escape()
		return
	if event is InputEventMouseMotion and dragging:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if gizmo.selected_axis >= 0: gizmo.update_drag(event.position, event.shift_pressed)
			get_viewport().set_input_as_handled()
		else:
			dragging = false
			gizmo.end_drag()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		camera_dragging = false
	if event is InputEventMouseMotion and camera_dragging:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			camera_angles.x = wrapf(camera_angles.x - event.relative.x * 0.008, -PI, PI)
			camera_angles.y = clampf(camera_angles.y + event.relative.y * 0.008, deg_to_rad(-80), deg_to_rad(80))
			_update_camera()
			get_viewport().set_input_as_handled()
		else:
			camera_dragging = false
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_escape()
		return
	if event is InputEventKey and not event.pressed: launch_keys.erase(event.physical_keycode)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = false
		gizmo.end_drag()

func _unhandled_input(event: InputEvent) -> void:
	if results_panel.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE: _escape()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.physical_keycode in [KEY_UP, KEY_DOWN]:
		if not running and gauge_stage == 0 and not results_panel.visible:
			_aim_changed(1, aim.y + (1 if event.physical_keycode == KEY_UP else -1))
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			_escape()
			return
		if results_panel.visible: return
		match event.physical_keycode:
			KEY_ENTER, KEY_SPACE:
				if not launch_keys.has(event.physical_keycode):
					launch_keys[event.physical_keycode] = true
					_advance_gauge()
			KEY_R: reset_trial()
			KEY_B:
				get_viewport().set_input_as_handled()
				closed.emit()
			KEY_D:
				if event.ctrl_pressed and event.shift_pressed and not event.alt_pressed and folding != null:
					folding._dump_state()
					metrics.text = folding.dump_notice.text
		return
	if event is InputEventMouseButton and event.pressed and not dragging:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			camera_dragging = true
			get_viewport().set_input_as_handled()
			return
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			camera_zoom = clampf(camera_zoom * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.9), 0.35, 8.0)
			_update_camera()
			get_viewport().set_input_as_handled()
			return
	if results_panel.visible or gauge_stage != 0: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not running and ready_to_launch and not camera_dragging:
			dragging = gizmo.visible and gizmo.begin_drag(event.position)
	elif event is InputEventMouseMotion and dragging:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if gizmo.selected_axis >= 0: gizmo.update_drag(event.position, event.shift_pressed)
		else: dragging = false

func snapshot() -> Dictionary:
	return {"paper_stock": paper_stock.duplicate(true), "flight_parts": binding.duplicate(true), "gauge": {"stage": gauge_stage, "power": launch_power, "target_elevation": aim.y, "cursor": gauge_cursor, "returning": gauge_returning, "origin_width_px": ORIGIN_WIDTH_PX, "timing_error": impact_error, "automatic_miss": automatic_miss}, "wind_velocity": body.wind_velocity, "wind_screen_direction": _wind_screen_direction(), "wind_camera_direction": _wind_camera_direction(), "wind_arrow_roll": wind_arrow.phase, "wind_arrow_spin_rad_s": wind_arrow.angular_speed, "camera_transform": camera.global_transform, "camera_angles": camera_angles, "camera_zoom": camera_zoom, "launch_power": launch_power, "target_aim_degrees": aim, "aim_degrees": Vector2(0, effective_elevation()), "timing_error": impact_error, "origin_width_px": ORIGIN_WIDTH_PX, "origin_tolerance": impact_tolerance, "origin_hit": absf(impact_error) <= impact_tolerance and not automatic_miss, "elevation_deviation": effective_elevation() - aim.y, "automatic_miss": automatic_miss, "launch_transform": Transform3D(attitude, LAUNCH), "launch_velocity": launch_velocity(), "angles": angles, "running": running, "elapsed_s": elapsed, "trials": trials, "body_transform": body.transform, "velocity": body.linear_velocity, "angular_velocity": body.angular_velocity, "posed": posed, "panels": body.panels, "mass_kg": body.mass, "trajectory": Array(trajectory)}

func _escape() -> void:
	if results_panel.visible: _toggle_results()
	elif adjust_panel.visible: _toggle_adjust()
	elif gauge_stage != 0: _cancel_gauge()
	else: closed.emit()
