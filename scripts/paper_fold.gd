extends Node3D

signal park_stored
signal park_cancelled
var park_mode := false

const PlayUI := preload("res://scripts/play_ui.gd")
const Stock := preload("res://scripts/paper_stock.gd")
const Picker := preload("res://scripts/paper_picker.gd")
const Paper := preload("res://scripts/paper_geometry.gd")
const Dump := preload("res://scripts/paper_dump.gd")
const Parts := preload("res://scripts/flight_parts.gd")
const PartsEditor := preload("res://scripts/flight_parts_editor.gd")
const Presets := preload("res://scripts/paper_presets.gd")
const FoldReference := preload("res://scripts/fold_reference.gd")
const AirplaneGuide := preload("res://scripts/airplane_guide.gd")
const FlightTest := preload("res://scripts/flight_test.gd")
const PAPER_Y := 0.001
const LAYER_GAP := 0.000025
const FRONT := Color("ed745c")
const BACK := Color("fff0cf")
const INK := Color("533e39")
const GUIDE := Color("7de1d2")
const SNAP_RADIUS_PX := 28.0
const COMMIT_ANGLE := PI * 0.55
const READY_COLOR := Color("a6edac")
const WAIT_COLOR := Color("f0c47c")
enum State { IDLE, DRAWING, DRAGGING, PENDING, SETTLING, FLIPPING, UNFOLDING }

var paper_stock := Stock.option(0)
var picker := Picker.new()
var pending_stock: Dictionary = {}
var faces: Array[Dictionary] = Paper.square()
var history: Array[Dictionary] = []
var flight_parts: Dictionary = {}
var parts_button := Button.new()
var parts_editor := PartsEditor.new()
var state := State.IDLE
var mode := 1
var click_to_confirm := false
var single_layer := false
var grabbed_layer := -1
var flip_angle := 0.0
var line_ready := false
var line_a := Vector2.ZERO
var line_b := Vector2.ZERO
var grab := Vector2.ZERO
var pointer := Vector2.ZERO
var line_hover := Vector2.INF
var line_hover_snapped := false
var fold_plan: Dictionary = {}
var fold_angle := 0.0
var fold_count := 0
var hover: Dictionary = {}
var last_drag_point := Vector2.ZERO
var snap_marker := Vector2.INF
var paper_mesh := MeshInstance3D.new()
var edge_mesh := MeshInstance3D.new()
var paper_material := StandardMaterial3D.new()
var edge_material := StandardMaterial3D.new()
var overlay := Control.new()
var status := Label.new()
var counter := Label.new()
var mode_one := Button.new()
var mode_two := Button.new()
var confirm_toggle := CheckButton.new()
var undo_button := Button.new()
var reset_button := Button.new()
var layer_toggle := CheckButton.new()
var flip_button := Button.new()
var unfold_button := Button.new()
var view_button := Button.new()
var pause_button := Button.new()
var slow_toggle := CheckButton.new()
var dump_button := Button.new()
var dump_folder_button := Button.new()
var dump_notice := Label.new()
var toolbar := PanelContainer.new()
var footer := VBoxContainer.new()
var action_bar := PanelContainer.new()
var flight_session: Dictionary = {}
var preset_fly := Button.new()
var preset_store := Presets.new()
var preset_button := Button.new()
var preset_shade := ColorRect.new()
var preset_panel := PanelContainer.new()
var preset_name := LineEdit.new()
var preset_list := ItemList.new()
var preset_notice := Label.new()
var preset_save := Button.new()
var preset_load := Button.new()
var preset_confirm := Button.new()
var preset_cancel := Button.new()
var preset_entries: Array[Dictionary] = []
var preset_pending: Dictionary = {}
var tools := PopupPanel.new()
var tools_button := Button.new()
var guide_flight := Label.new()
var guide_mode_hint := Label.new()
var work_area := Rect2()
var layout_size := Vector2.ZERO
var reference: Dictionary = {}
var custom_reference: Dictionary = {}
var reference_editing := false
var reference_drawing := false
var reference_a := Vector2.ZERO
var reference_b := Vector2.ZERO
var reference_button := Button.new()
var reference_tool := OptionButton.new()
var reference_reset := Button.new()
var guide_steps: Array[Dictionary] = AirplaneGuide.steps()
var guide_step := 0
var guide_panel := PanelContainer.new()
var guide_title := Label.new()
var guide_text := Label.new()
var guide_previous := Button.new()
var guide_next := Button.new()
var guide_button := Button.new()
var flight_view: Node3D
var flight_button := Button.new()
var inspect_view := false
var animation_paused := false
var slow_motion := false
var reverse_flip := false
var unfold_after_flip := false
var settle_tween: Tween
@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	paper_material.vertex_color_use_as_albedo = true
	paper_material.vertex_color_is_srgb = true
	paper_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	paper_material.roughness = 0.95
	paper_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge_material.vertex_color_use_as_albedo = true
	paper_mesh.material_override = paper_material
	edge_mesh.material_override = edge_material
	add_child(paper_mesh)
	add_child(edge_mesh)
	get_window().content_scale_size = Vector2i.ZERO
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build_ui()
	get_window().focus_exited.connect(_focus_lost)
	_refresh()

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	canvas.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_guides)
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Malgun Gothic", "Noto Sans CJK KR"])
	theme.default_font = font
	theme.default_font_size = 14
	overlay.theme = theme
	var style := StyleBoxFlat.new()
	style.bg_color = Color("182a30")
	style.set_content_margin_all(8)
	style.set_corner_radius_all(8)
	overlay.add_child(toolbar)
	toolbar.add_theme_stylebox_override("panel", style)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 5)
	row.add_theme_constant_override("v_separation", 4)
	toolbar.add_child(row)
	if park_mode:
		var leave := Button.new()
		leave.text = "수정 취소 · 공원으로"
		leave.focus_mode = Control.FOCUS_NONE
		leave.pressed.connect(func() -> void:
			if state == State.IDLE: park_cancelled.emit()
		)
		row.add_child(leave)
	mode_one.text = "1 잡아끌기"
	mode_two.text = "2 선 긋기"
	for button in [mode_one, mode_two]:
		button.toggle_mode = true
	mode_one.pressed.connect(func() -> void: _set_mode(1))
	mode_two.pressed.connect(func() -> void: _set_mode(2))
	layer_toggle.text = "연결부 [3]"
	layer_toggle.tooltip_text = "위쪽에서 잡은 면과 이어진 부분을 함께 접습니다."
	layer_toggle.toggled.connect(_set_single_layer)
	flip_button.text = "뒤집기 [F]"
	flip_button.pressed.connect(_flip_paper)
	undo_button.text = "되돌리기 [Z]"
	undo_button.pressed.connect(_undo)
	unfold_button.text = "펼치기 [U]"
	unfold_button.pressed.connect(_unfold)
	guide_button.text = "가이드 [G]"
	guide_button.pressed.connect(_toggle_guide)
	flight_button.text = "접기 마치고 보관 [B]" if park_mode else "날려보기 [B]"
	flight_button.pressed.connect(_open_flight)
	parts_button.text = "비행 부위 지정"
	parts_button.pressed.connect(_open_parts)
	preset_button.text = "내 도면 [P]"
	preset_button.pressed.connect(_show_presets)
	tools_button.text = "도구…"
	tools_button.pressed.connect(func() -> void: tools.popup_centered(Vector2i(mini(600, int(get_viewport().get_visible_rect().size.x) - 32), 0)))
	for button in [mode_one, mode_two, layer_toggle, flip_button, undo_button, unfold_button, guide_button, parts_button, reset_button, preset_button, tools_button]:
		button.focus_mode = Control.FOCUS_NONE
		row.add_child(button)
	overlay.add_child(tools)
	tools.theme = theme
	tools.about_to_popup.connect(func() -> void: Audio.play_sfx("open"))
	tools.popup_hide.connect(func() -> void: Audio.play_sfx("close"))
	tools.add_theme_stylebox_override("panel", style)
	var extra := VBoxContainer.new()
	extra.add_theme_constant_override("separation", 8)
	tools.add_child(extra)
	var extra_row := HFlowContainer.new()
	extra.add_child(extra_row)
	Audio.add_button(extra_row)
	reset_button.text = "새 종이 [R]"
	reset_button.pressed.connect(_open_paper_picker)
	reference_button.text = "기준 편집 [4]"
	reference_button.toggle_mode = true
	reference_button.pressed.connect(_toggle_reference_edit)
	reference_tool.add_item("기준점", 0)
	reference_tool.add_item("기준선", 1)
	reference_tool.item_selected.connect(func(_index: int) -> void:
		if not reference_editing:
			_toggle_reference_edit()
		tools.hide()
	)
	reference_reset.text = "기본 중심으로"
	reference_reset.pressed.connect(_reset_reference)
	view_button.text = "옆에서 보기 [V]"
	view_button.pressed.connect(_toggle_view)
	pause_button.text = "정지 / 재생 [Space]"
	pause_button.pressed.connect(_toggle_pause)
	slow_toggle.text = "느리게"
	slow_toggle.toggled.connect(_set_slow_motion)
	confirm_toggle.text = "추가 클릭으로 확정 [C]"
	confirm_toggle.button_pressed = click_to_confirm
	confirm_toggle.toggled.connect(_set_confirmation)
	dump_button.text = "상태 덤프 [Ctrl+Shift+D]"
	dump_button.pressed.connect(_dump_state)
	dump_folder_button.text = "덤프 다운로드" if OS.has_feature("web") else "덤프 폴더"
	dump_folder_button.pressed.connect(_open_dump_folder)
	for button in [reference_button, reference_tool, reference_reset, view_button, pause_button, slow_toggle, confirm_toggle, dump_button, dump_folder_button]:
		button.focus_mode = Control.FOCUS_NONE
		extra_row.add_child(button)
	for button in [reference_button, reference_reset, view_button]:
		button.pressed.connect(func() -> void: tools.hide())
	var close_tools := Button.new()
	close_tools.text = "닫기"
	close_tools.focus_mode = Control.FOCUS_NONE
	close_tools.pressed.connect(func() -> void: tools.hide())
	extra.add_child(close_tools)
	overlay.add_child(action_bar)
	action_bar.add_theme_stylebox_override("panel", style)
	action_bar.add_child(footer)
	footer.add_theme_constant_override("separation", 4)
	counter.add_theme_font_size_override("font_size", 13)
	counter.max_lines_visible = 1
	counter.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(counter)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 12)
	status.max_lines_visible = 2
	footer.add_child(status)
	dump_notice.add_theme_font_size_override("font_size", 12)
	dump_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dump_notice.max_lines_visible = 3
	dump_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dump_notice)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(spacer)
	footer.add_child(flight_button)
	flight_button.focus_mode = Control.FOCUS_NONE
	PlayUI.primary(flight_button)
	_build_airplane_guide()
	parts_editor.source = self
	parts_editor.add_theme_stylebox_override("panel", style)
	overlay.add_child(parts_editor)
	_build_presets_ui(style)
	picker.source = self
	overlay.add_child(picker)
func _process(_delta: float) -> void:
	if flight_view != null:
		return
	_layout_workspace()
	_fit_view()
	pointer = _paper_position(get_viewport().get_mouse_position())
	hover = Paper.edge_near(faces, pointer, _pixel_radius(16)) if state == State.IDLE and not inspect_view else {}
	var hovered_control := get_viewport().gui_get_hovered_control()
	var on_ui := hovered_control != null and hovered_control != overlay
	_update_line_hover(pointer, Input.is_physical_key_pressed(KEY_SHIFT), on_ui)

	var cursor := Input.CURSOR_ARROW
	if not on_ui:
		if reference_editing:
			cursor = Input.CURSOR_CROSS
		elif state == State.DRAGGING:
			cursor = Input.CURSOR_DRAG
		elif state == State.PENDING or not hover.is_empty():
			cursor = Input.CURSOR_POINTING_HAND
		elif mode == 2 and not line_ready:
			cursor = Input.CURSOR_CROSS
	Input.set_default_cursor_shape(cursor)
	overlay.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if picker.visible: return
	if parts_editor.visible:
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE: parts_editor.hide()
		return
	if preset_shade.visible:
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			_hide_presets()
		return
	if flight_view != null:
		return
	if reference_drawing and event is InputEventKey and event.physical_keycode != KEY_ESCAPE:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: _set_mode(1)
			KEY_2: _set_mode(2)
			KEY_C: _set_confirmation(not click_to_confirm)
			KEY_3: _set_single_layer(not single_layer)
			KEY_4: _toggle_reference_edit()
			KEY_F: _flip_paper()
			KEY_U: _unfold()
			KEY_V: _toggle_view()
			KEY_SPACE: _toggle_pause()
			KEY_D:
				if event.ctrl_pressed and event.shift_pressed and not event.alt_pressed:
					_dump_state()
			KEY_G: _toggle_guide()
			KEY_P: _show_presets()
			KEY_B:
				get_viewport().set_input_as_handled()
				_open_flight()
			KEY_Z: _undo()
			KEY_R: _open_paper_picker()
			KEY_ESCAPE: _cancel()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_cancel()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press(_paper_position(event.position), event.shift_pressed)
			else:
				_release(_paper_position(event.position), event.shift_pressed)
	elif event is InputEventMouseMotion:
		_motion(_paper_position(event.position), event.shift_pressed)

# Release must still reach the drag when the mouse ends over a toolbar button.
func _input(event: InputEvent) -> void:
	if picker.visible and event is InputEventKey:
		get_viewport().set_input_as_handled()
		if event.pressed and event.physical_keycode == KEY_ESCAPE: picker.hide()
		return
	if preset_shade.visible and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_hide_presets()
		return
	if event is InputEventKey and event.physical_keycode == KEY_SHIFT and not event.echo:
		if state == State.DRAGGING or state == State.DRAWING or reference_drawing:
			_motion(last_drag_point, event.pressed)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if state == State.DRAGGING or state == State.DRAWING or reference_drawing:
			_release(_paper_position(event.position), event.shift_pressed)
			get_viewport().set_input_as_handled()

func _update_line_hover(point: Vector2, freehand: bool, on_ui: bool) -> void:
	line_hover = Vector2.INF
	line_hover_snapped = false
	if state == State.IDLE and mode == 2 and not line_ready and not inspect_view and not on_ui and not reference_editing:
		line_hover = _line_start_preview(point, freehand)
		line_hover_snapped = line_hover.distance_to(point) > Paper.EPS

func _line_start_preview(point: Vector2, freehand: bool) -> Vector2:
	return point if freehand else Paper.snap(faces, point, _pixel_radius(SNAP_RADIUS_PX), true, _snap_reference())

func _snap_point(point: Vector2, freehand: bool) -> Vector2:
	snap_marker = Vector2.INF
	if freehand:
		return point
	var snapped := _line_start_preview(point, freehand)
	if point.distance_to(snapped) > Paper.EPS:
		snap_marker = snapped
	return snapped

func _line_end_preview(point: Vector2, freehand: bool) -> Vector2:
	snap_marker = Vector2.INF
	if freehand: return point
	var candidate := Paper.snap_candidate(faces, point, _pixel_radius(SNAP_RADIUS_PX), true, _snap_reference())
	var snapped: Vector2 = candidate.point
	# Exact guide anchors still win, even when they do not move the cursor.
	if not candidate.snapped:
		var offset := point - line_a
		if offset.length_squared() > Paper.EPS * Paper.EPS:
			snapped = line_a + Vector2.from_angle(snappedf(offset.angle(), PI / 12.0)) * offset.length()
	if snapped.distance_to(point) > Paper.EPS: snap_marker = snapped
	return snapped

func _press(point: Vector2, freehand: bool = false) -> void:
	last_drag_point = point
	if reference_editing and not inspect_view:
		if state != State.IDLE:
			return
		if not reference_drawing:
			reference_a = point if freehand else Paper.snap(faces, point, _pixel_radius(SNAP_RADIUS_PX))
			reference_b = reference_a
			reference_drawing = true
		return
	if inspect_view:
		return
	last_drag_point = point
	if _animating():
		return
	if state == State.PENDING:
		if Paper.contains(Paper.folded(fold_plan), point):
			_commit()
		return
	if state != State.IDLE:
		return
	if mode == 2 and not line_ready:
		line_a = _snap_point(point, freehand)
		line_b = line_a
		state = State.DRAWING
	else:
		var selected := Paper.edge_near(faces, point, _pixel_radius(16))
		if selected.is_empty():
			status.text = "종이의 가장자리를 잡아 주세요."
			return
		var grabbed_face: Array[Dictionary] = [faces[selected.layer]]
		grab = selected.point if freehand else Paper.snap(grabbed_face, selected.point, _pixel_radius(SNAP_RADIUS_PX), false)
		grabbed_layer = selected.layer if single_layer else -1
		fold_plan = {}
		fold_angle = 0.0
		if mode == 2:
			fold_plan = Paper.plan(faces, line_a, line_b, grab, grabbed_layer)
			if fold_plan.is_empty():
				status.text = "이 선으로는 접을 수 없습니다. 접기선에서 떨어진 가장자리를 잡거나 선을 다시 그려 주세요."
				return
		state = State.DRAGGING
	_refresh_ui()

func _motion(point: Vector2, freehand: bool = false) -> void:
	last_drag_point = point
	if reference_drawing:
		reference_b = point if freehand else Paper.snap(faces, point, _pixel_radius(SNAP_RADIUS_PX))
		return
	if state == State.DRAWING:
		line_b = _line_end_preview(point, freehand)
	elif state == State.DRAGGING:
		var target := _snap_point(point, freehand)
		if mode == 1:
			var distance := grab.distance_to(target)
			if distance < _pixel_radius(4):
				fold_plan = {}
			else:
				line_a = (grab + target) * 0.5
				line_b = line_a + (target - grab).orthogonal().normalized()
				fold_plan = Paper.plan(faces, line_a, line_b, grab, grabbed_layer)
				fold_angle = lerpf(0.2, PI - 0.12, clampf(distance / 0.035, 0.0, 1.0))
		elif not fold_plan.is_empty():
			var initial_distance: float = (grab - fold_plan.origin).dot(fold_plan.normal)
			var target_distance: float = (target - fold_plan.origin).dot(fold_plan.normal)
			fold_angle = acos(clampf(target_distance / initial_distance, -1.0, 1.0))
		_refresh_mesh()
		_refresh_ui()

func _release(point: Vector2, freehand: bool = false) -> void:
	if reference_drawing:
		_finish_reference(point, freehand)
		return
	if state == State.DRAWING:
		_motion(point, freehand)
		var valid := _valid_line(line_a, line_b)
		state = State.IDLE
		line_ready = valid
		_refresh_ui()
		if not valid:
			status.text = "종이를 가로지르는 선을 드래그해 주세요. 짧은 선은 방향대로 연장됩니다."
	elif state == State.DRAGGING:
		_motion(point, freehand)
		if fold_plan.is_empty():
			_cancel(false)
			status.text = "종이의 연결을 유지하며 접을 수 있는 위치로 끌어 주세요."
			return
		if not _can_commit():
			_cancel(false)
			status.text = "조금 더 반대쪽으로 넘긴 뒤 놓아 주세요. 우클릭 / Esc로 취소할 수 있습니다."
			return
		if fold_plan.stay.size() + fold_plan.move.size() > 2048:
			_cancel(false)
			status.text = "프로토타입의 면 수 한계에 도달했습니다. 되돌리거나 새 종이로 시작해 주세요."
			return
		if click_to_confirm:
			state = State.PENDING
			fold_angle = PI - 0.10
			_refresh()
		else:
			_commit()

func _valid_line(a: Vector2, b: Vector2) -> bool:
	if a.distance_to(b) < _pixel_radius(8):
		return false
	var direction := (b - a).normalized().orthogonal()
	return not Paper.plan(faces, a, b, a + direction).is_empty()

func _commit() -> void:
	if fold_plan.is_empty() or _animating():
		return
	state = State.SETTLING
	_refresh_ui()
	animation_paused = false
	settle_tween = create_tween()
	settle_tween.set_speed_scale(0.2 if slow_motion else 1.0)
	settle_tween.tween_method(_animate_angle, fold_angle, PI, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	settle_tween.tween_callback(_finish_commit)

func _animate_angle(value: float) -> void:
	fold_angle = value
	_refresh_mesh()
	_refresh_ui()

func _finish_commit() -> void:
	_remember("fold", fold_plan)
	faces = Paper.folded(fold_plan)
	fold_count += 1
	Audio.play_sfx("fold")
	fold_plan = {}
	line_ready = false
	state = State.IDLE
	_refresh()

func _cancel(clear_line: bool = true) -> void:
	reference_drawing = false
	reference_editing = false
	if _animating():
		settle_tween.kill()
		animation_paused = false
		flip_angle = 0.0
		unfold_after_flip = false
		paper_mesh.transform = Transform3D.IDENTITY
		edge_mesh.transform = Transform3D.IDENTITY
	fold_plan = {}
	state = State.IDLE
	if clear_line:
		line_ready = false
	_refresh()

func _set_mode(value: int) -> void:
	if state != State.IDLE:
		_refresh_ui()
		return
	mode = value
	reference_editing = false
	line_ready = false
	_refresh_ui()

func _set_confirmation(value: bool) -> void:
	if state != State.IDLE:
		_refresh_ui()
		return
	click_to_confirm = value
	_refresh_ui()

func _set_single_layer(value: bool) -> void:
	if state != State.IDLE:
		_refresh_ui()
		return
	single_layer = value
	_refresh_ui()

func _remember(kind: String, plan: Dictionary = {}) -> void:
	history.append({"faces": faces.duplicate(true), "fold_count": fold_count, "kind": kind, "single_layer": single_layer, "plan": plan.duplicate(true)})

func _flip_paper(reverse: bool = false, then_unfold: bool = false) -> void:
	if state != State.IDLE:
		return
	line_ready = false
	snap_marker = Vector2.INF
	reverse_flip = reverse
	unfold_after_flip = then_unfold
	state = State.FLIPPING
	_refresh_ui()
	animation_paused = false
	settle_tween = create_tween()
	settle_tween.set_speed_scale(0.2 if slow_motion else 1.0)
	settle_tween.tween_method(_animate_flip, 0.0, PI, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	settle_tween.tween_callback(_finish_flip)

func _animate_flip(value: float) -> void:
	flip_angle = value
	var center_x := Paper.flip_center(faces)
	var radius := 0.0
	for face in faces:
		for point in face.points:
			radius = maxf(radius, absf(point.x - center_x))
	var pivot := Vector3(center_x, PAPER_Y, 0.0)
	var basis := Basis(Vector3.BACK, value)
	var position := pivot - basis * pivot + Vector3.UP * radius * sin(value)
	var pose := Transform3D(basis, position)
	paper_mesh.transform = pose
	edge_mesh.transform = pose
	_refresh_mesh()
	_refresh_ui()

func _finish_flip() -> void:
	Audio.play_sfx("unfold")
	if reverse_flip:
		var previous: Dictionary = history.pop_back()
		faces = previous.faces
		fold_count = previous.fold_count
	else:
		_remember("flip")
		faces = Paper.flipped(faces)
	paper_mesh.transform = Transform3D.IDENTITY
	edge_mesh.transform = Transform3D.IDENTITY
	flip_angle = 0.0
	state = State.IDLE
	_refresh()
	if unfold_after_flip:
		call_deferred("_unfold")

func _animating() -> bool:
	return state in [State.SETTLING, State.FLIPPING, State.UNFOLDING]

func _unfold() -> void:
	if state != State.IDLE:
		return
	var found_fold := false
	for previous in history:
		if previous.kind == "fold":
			found_fold = true
			break
	if not found_fold:
		status.text = "펼칠 접기가 없습니다."
		return
	line_ready = false
	if history[-1].kind == "flip":
		_flip_paper(true, true)
		return
	fold_plan = history[-1].plan.duplicate(true)
	fold_angle = PI
	state = State.UNFOLDING
	_refresh()
	animation_paused = false
	settle_tween = create_tween()
	settle_tween.set_speed_scale(0.2 if slow_motion else 1.0)
	settle_tween.tween_method(_animate_angle, PI, 0.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	settle_tween.tween_callback(_finish_unfold)

func _finish_unfold() -> void:
	Audio.play_sfx("unfold")
	var previous: Dictionary = history.pop_back()
	faces = previous.faces
	fold_count = previous.fold_count
	fold_plan = {}
	fold_angle = 0.0
	state = State.IDLE
	_refresh()

func _toggle_view() -> void:
	if state in [State.DRAWING, State.DRAGGING, State.PENDING]:
		return
	inspect_view = not inspect_view
	if inspect_view:
		camera.position = Vector3(0, 0.3, 0.3)
		camera.size = 0.5
		camera.look_at(Vector3.ZERO)
	else:
		camera.position = Vector3(0, 1, 0)
		camera.size = 0.38
		camera.rotation_degrees = Vector3(-90, 0, 0)
	camera.reset_physics_interpolation()
	_refresh_ui()

func _toggle_pause() -> void:
	if not _animating() or settle_tween == null or not settle_tween.is_valid():
		return
	animation_paused = not animation_paused
	if animation_paused:
		settle_tween.pause()
	else:
		settle_tween.play()
	_refresh_ui()

func _set_slow_motion(enabled: bool) -> void:
	slow_motion = enabled
	if _animating() and settle_tween != null and settle_tween.is_valid():
		settle_tween.set_speed_scale(0.2 if slow_motion else 1.0)

func _undo() -> void:
	if _animating():
		return
	if state != State.IDLE or line_ready:
		_cancel()
		return
	if history.is_empty():
		return
	var previous: Dictionary = history.pop_back()
	faces = previous.faces
	fold_count = previous.fold_count
	_refresh()

func _reset_paper(stock: Dictionary = {}) -> void:
	if _animating():
		return
	dump_notice.text = ""
	paper_stock = Stock.option(0) if stock.is_empty() else stock.duplicate(true)
	faces = Paper.rectangle(paper_stock.size)
	custom_reference = {}
	flight_parts = {}
	parts_editor.hide()
	reference_editing = false
	reference_drawing = false
	history.clear()
	fold_count = 0
	line_ready = false
	fold_plan = {}
	state = State.IDLE
	_refresh()

func _focus_lost() -> void:
	if state == State.DRAWING or state == State.DRAGGING or reference_drawing:
		_cancel(false)

func _paper_position(screen: Vector2) -> Vector2:
	var origin := camera.project_ray_origin(screen)
	var ray := camera.project_ray_normal(screen)
	var hit := origin + ray * ((PAPER_Y - origin.y) / ray.y)
	return Vector2(hit.x, hit.z)

func _screen(point: Vector2, height: float = PAPER_Y) -> Vector2:
	return camera.unproject_position(Vector3(point.x, height, point.y))

func _pixel_radius(pixels: float) -> float:
	return _paper_position(Vector2.ZERO).distance_to(_paper_position(Vector2(pixels, 0)))

func _refresh() -> void:
	var size := Paper.square_size(faces)
	guide_steps.assign(AirplaneGuide.steps(size) if size > 0 else [{"action": "notice", "title": "정사각형용 가이드", "text": "이 가이드는 정사각형용입니다. 직사각형 종이는 원래 비율로 자유롭게 접어 보세요."}])
	_set_guide_step(guide_step)
	if parts_editor.visible and parts_editor.candidate.get("signature", "") != Parts.signature(faces, history): parts_editor.hide()
	reference = FoldReference.geometry(faces, custom_reference)
	_refresh_mesh()
	_refresh_ui()

func _refresh_ui() -> void:
	if state != State.IDLE or inspect_view or flight_view != null:
		reference_editing = false
		reference_drawing = false
	reference_button.set_pressed_no_signal(reference_editing)
	reference_button.disabled = state != State.IDLE or inspect_view
	reference_tool.disabled = state != State.IDLE or inspect_view or reference_drawing
	reference_reset.disabled = state != State.IDLE or reference_drawing
	mode_one.set_pressed_no_signal(mode == 1)
	mode_two.set_pressed_no_signal(mode == 2)
	confirm_toggle.set_pressed_no_signal(click_to_confirm)
	mode_one.disabled = state != State.IDLE
	mode_two.disabled = state != State.IDLE
	confirm_toggle.disabled = state != State.IDLE
	undo_button.disabled = _animating() or (history.is_empty() and state == State.IDLE and not line_ready)
	reset_button.disabled = _animating()
	reset_button.text = "새 종이 [R] · " + Stock.summary(paper_stock)
	layer_toggle.set_pressed_no_signal(single_layer)
	layer_toggle.disabled = state != State.IDLE
	flip_button.disabled = state != State.IDLE
	flight_button.disabled = state != State.IDLE
	parts_button.disabled = state != State.IDLE or reference_drawing
	parts_button.text = "비행 부위 · 확정" if Parts.valid(flight_parts, faces, history) else ("비행 부위 · 재확인" if not flight_parts.is_empty() else "비행 부위 · 추천")
	preset_button.disabled = state != State.IDLE or reference_drawing
	unfold_button.disabled = state != State.IDLE or fold_count == 0
	view_button.text = "탑뷰로 돌아가기 [V]" if inspect_view else "옆에서 보기 [V]"
	view_button.disabled = state in [State.DRAWING, State.DRAGGING, State.PENDING]
	pause_button.disabled = not _animating()
	pause_button.text = "계속 재생 [Space]" if animation_paused else "일시 정지 [Space]"
	counter.text = "%s · %d번 접음  ·  %s  ·  %s  ·  %s" % [Stock.summary(paper_stock), fold_count, "잡아끌기" if mode == 1 else "선 긋기", "위쪽 연결부" if single_layer else "겹친 층 전체", "클릭 확정" if click_to_confirm else "놓으면 확정"]
	if _animating():
		counter.text += "  ·  %.0f°" % rad_to_deg(flip_angle if state == State.FLIPPING else fold_angle)
	match state:
		State.IDLE:
			if mode == 1:
				status.text = "위쪽 가장자리를 잡으면 이어진 부분도 함께 접힙니다. Shift를 누르면 스냅을 해제합니다." if single_layer else "가장자리 어디든 잡고 반대쪽으로 끌어 보세요. 기준점·기준선·꼭짓점·변 중앙에 스냅됩니다. Shift를 누르면 자유롭게 조절합니다."
			elif line_ready:
				status.text = "접을 쪽의 가장자리를 잡고 선 너머로 넘기세요. 우클릭하면 선을 다시 그릴 수 있습니다."
			else:
				status.text = "종이를 가로질러 접기선을 그으세요. 선이 생기면 접을 쪽 가장자리를 잡습니다."
		State.DRAWING:
			status.text = "기준점·기준선 우선, 그 외에는 15° 단위로 선을 맞춥니다. Shift: 자유 각도 · 놓으면 접기선을 만듭니다."
		State.DRAGGING:
			status.text = "놓으면 접기가 확정됩니다. 우클릭 / Esc: 취소" if _can_commit() else "조금 더 반대쪽으로 넘기세요. 아직 놓으면 취소됩니다."
		State.PENDING:
			status.text = "접힌 면을 클릭하면 확정합니다. 우클릭 / Esc로 접기 전으로 돌아갑니다."
		State.FLIPPING:
			status.text = "종이를 뒤집는 중…"
		State.SETTLING:
			status.text = "접는 중…"
		State.UNFOLDING:
			status.text = "마지막 접기를 펼치는 중…"
	guide_mode_hint.text = "직사각형 · 자유 접기" if guide_steps[guide_step].action == "notice" else ("1 잡아끌기: 원 → 화살표 끝" if mode == 1 else "2 선 긋기: 점선을 먼저 그리고 원 → 화살표 끝")
	if animation_paused:
		status.text = "일시 정지 · V로 옆에서 보기 · Space로 계속 재생 · Esc로 취소"
	elif inspect_view and state == State.IDLE:
		status.text = "관찰 보기 · U 펼치기 / F 뒤집기 · 접으려면 V로 탑뷰에 돌아가세요."

func _vertex(point: Vector2, layer: int, moving: bool) -> Vector3:
	var height := PAPER_Y + layer * LAYER_GAP
	if not moving:
		return Vector3(point.x, height, point.y)
	var normal: Vector2 = fold_plan.normal
	var distance: float = (point - fold_plan.origin).dot(normal)
	var rotated := point + normal * distance * (cos(fold_angle) - 1.0)
	# Reverse the moving stack continuously as it turns over.
	var stack_position := lerpf(float(layer), float(fold_plan.stay.size() + fold_plan.move.size() - 1 - layer), (1.0 - cos(fold_angle)) * 0.5)
	height = PAPER_Y + stack_position * LAYER_GAP + absf(distance) * sin(fold_angle)
	return Vector3(rotated.x, height, rotated.y)

func _refresh_mesh() -> void:
	paper_material.albedo_texture = Stock.texture(paper_stock)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edges := ImmediateMesh.new()
	edges.surface_begin(Mesh.PRIMITIVE_LINES)
	if fold_plan.is_empty():
		_add_faces(surface, edges, faces, false)
	else:
		_add_faces(surface, edges, fold_plan.stay, false)
		_add_faces(surface, edges, fold_plan.move, true)
	paper_mesh.mesh = surface.commit()
	edges.surface_end()
	edge_mesh.mesh = edges

func _add_faces(surface: SurfaceTool, edges: ImmediateMesh, source: Array[Dictionary], moving: bool) -> void:
	for layer in source.size():
		var face := source[layer]
		var points: PackedVector2Array = face.points
		var front: bool = face.front
		var normal := Vector3.UP
		if moving:
			var n: Vector2 = fold_plan.normal
			normal = Vector3(-n.x * sin(fold_angle), cos(fold_angle), -n.y * sin(fold_angle))
		var visible_normal := paper_mesh.basis * normal
		if visible_normal.dot(camera.global_basis.z) < 0.0:
			front = not front
		var color := Stock.front(paper_stock) if front else Stock.back(paper_stock)
		if moving and state == State.DRAGGING:
			color = color.lerp(GUIDE, 0.3)
		for i in range(1, points.size() - 1):
			var triangle := [0, i, i + 1]
			var reverse := (points[i] - points[0]).cross(points[i + 1] - points[0]) < 0.0
			if moving and fold_angle > PI * 0.5:
				reverse = not reverse
			if reverse:
				triangle.reverse()
			for vertex in triangle:
				var point: Vector2 = points[vertex]
				surface.set_uv(face.paper[vertex] / paper_stock.size + Vector2(0.5, 0.5))
				surface.set_color(color)
				surface.set_normal(normal)
				surface.add_vertex(_vertex(point, layer, moving))
		for i in points.size():
			edges.surface_set_color(GUIDE if moving and state == State.DRAGGING else INK)
			edges.surface_add_vertex(_vertex(points[i], layer, moving) + Vector3.UP * 0.00001)
			edges.surface_add_vertex(_vertex(points[(i + 1) % points.size()], layer, moving) + Vector3.UP * 0.00001)

func _draw_guides() -> void:
	if parts_editor.visible and state == State.IDLE:
		var region_center := Vector2.ZERO
		var region_count := 0
		for i in faces.size():
			var role := Parts.role(i, faces, history, parts_editor.wings, parts_editor.grip)
			if role != parts_editor.highlight: continue
			var polygon := PackedVector2Array()
			var center := Vector2.ZERO
			for p in faces[i].points:
				var q := _screen(p)
				polygon.append(q)
				center += q
			center /= polygon.size()
			overlay.draw_colored_polygon(polygon, Color(Parts.COLORS[role], 0.3))
			polygon.append(polygon[0])
			overlay.draw_polyline(polygon, Parts.COLORS[role], 3, true)
			region_center += center
			region_count += 1
		if region_count > 0:
			var role: int = parts_editor.highlight
			overlay.draw_string(overlay.get_theme_default_font(), region_center / region_count + Vector2(8, -8), Parts.NAMES[role] + " · %d개 면" % region_count, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Parts.COLORS[role])
	if not inspect_view and state in [State.IDLE, State.DRAWING, State.DRAGGING, State.PENDING] and not reference.is_empty():
		for segment in reference.segments:
			overlay.draw_dashed_line(_screen(segment[0]), _screen(segment[1]), Color(0.49, 0.88, 0.82, 0.4), 1.0, 6.0)
		for center in reference.centers:
			overlay.draw_circle(_screen(center), 4.0, GUIDE, false, 1.5, true)
	if reference_editing and not inspect_view:
		var preview := pointer if Input.is_physical_key_pressed(KEY_SHIFT) else Paper.snap(faces, pointer, _pixel_radius(SNAP_RADIUS_PX))
		if reference_drawing:
			preview = reference_b
			if reference_tool.selected == 1:
				overlay.draw_dashed_line(_screen(reference_a), _screen(reference_b), GUIDE, 2, 6)
		overlay.draw_circle(_screen(preview), 8, GUIDE, false, 2, true)
		return
	if guide_panel.visible and state == State.IDLE and not inspect_view:
		var step := guide_steps[guide_step]
		if step.action == "fold":
			var yellow := Color("f0d182")
			overlay.draw_dashed_line(_screen(step.a), _screen(step.b), yellow, 2.0, 7.0)
			overlay.draw_circle(_screen(step.grab), 7.0, yellow, false, 2.0, true)
			overlay.draw_circle(_screen(step.target), 4.0, yellow)
			_draw_arrow(_screen(step.grab), _screen(step.target), yellow)
	if state == State.IDLE and mode == 2 and not line_ready and line_hover != Vector2.INF:
		var screen := _screen(line_hover)
		overlay.draw_circle(screen, 10.0 if line_hover_snapped else 6.0, GUIDE, false, 2.0, true)
		overlay.draw_circle(screen, 2.0, GUIDE)
	if state == State.IDLE and single_layer and not hover.is_empty():
		var outline := PackedVector2Array()
		for point in faces[hover.layer].points:
			outline.append(_screen(point))
		outline.append(outline[0])
		overlay.draw_polyline(outline, GUIDE, 2.0, true)
	if state == State.DRAWING or line_ready or (state == State.DRAGGING and not fold_plan.is_empty()):
		var direction := (line_b - line_a).normalized()
		if direction.length_squared() > 0.0:
			var normal := direction.orthogonal()
			var low := INF
			var high := -INF
			for face in faces:
				var points: PackedVector2Array = face.points
				for i in points.size():
					var p := points[i]
					var q := points[(i + 1) % points.size()]
					var dp := (p - line_a).dot(normal)
					var dq := (q - line_a).dot(normal)
					if absf(dp) < Paper.EPS:
						var along := (p - line_a).dot(direction)
						low = minf(low, along)
						high = maxf(high, along)
					if dp * dq < 0.0:
						var along := (p.lerp(q, dp / (dp - dq)) - line_a).dot(direction)
						low = minf(low, along)
						high = maxf(high, along)
			if low < high:
				overlay.draw_dashed_line(_screen(line_a + direction * low), _screen(line_a + direction * high), GUIDE, 2.0, 7.0)
			elif state == State.DRAWING:
				overlay.draw_line(_screen(line_a), _screen(line_b), GUIDE, 2.0, true)
	if state == State.IDLE and not hover.is_empty() and not (mode == 2 and not line_ready):
		overlay.draw_circle(_screen(hover.point), 7.0, GUIDE, false, 2.0, true)
	if state == State.DRAGGING:
		var ready := _can_commit()
		overlay.draw_circle(_screen(pointer), 9.0, READY_COLOR if ready else WAIT_COLOR, false, 3.0, true)

	if (state == State.DRAGGING or state == State.DRAWING) and snap_marker != Vector2.INF:
		overlay.draw_circle(_screen(snap_marker), 10.0, GUIDE, false, 2.0, true)

func _snapshot() -> Dictionary:
	var posed_faces: Array[Dictionary] = []
	if fold_plan.is_empty():
		_append_posed_faces(posed_faces, faces, false)
	else:
		_append_posed_faces(posed_faces, fold_plan.stay, false)
		_append_posed_faces(posed_faces, fold_plan.move, true)
	return {
		"format": "pap-fold-dump", "version": 1, "paper_stock": paper_stock.duplicate(true), "flight_parts": flight_parts.duplicate(true), "reference": {"definition": custom_reference.duplicate(true), "geometry": reference.duplicate(true), "editing": reference_editing, "drawing": reference_drawing, "tool": reference_tool.selected, "a": reference_a, "b": reference_b}, "flight": null if flight_view == null else flight_view.snapshot(), "guide": {"visible": guide_panel.visible, "step": guide_step},
		"captured_at": Time.get_datetime_string_from_system(),
		"engine": Engine.get_version_info(),
		"controls": {"mode": mode, "single_layer": single_layer, "click_to_confirm": click_to_confirm, "inspect_view": inspect_view, "slow_motion": slow_motion},
		"interaction": {"state": State.keys()[state], "fold_count": fold_count, "line_ready": line_ready, "line_a": line_a, "line_b": line_b, "grab": grab, "pointer": pointer, "last_drag_point": last_drag_point, "grabbed_layer": grabbed_layer, "snap_marker": null if snap_marker == Vector2.INF else snap_marker},
		"animation": {"fold_angle_radians": fold_angle, "flip_angle_radians": flip_angle, "paused": animation_paused, "reverse_flip": reverse_flip, "unfold_after_flip": unfold_after_flip},
		"camera": {"position": camera.position, "rotation": camera.rotation, "size": camera.size},
		"render": {"paper_transform": paper_mesh.transform, "edge_transform": edge_mesh.transform, "posed_faces": posed_faces},
		"faces": faces.duplicate(true), "fold_plan": fold_plan.duplicate(true), "history": history.duplicate(true)
	}

func _append_posed_faces(output: Array[Dictionary], source: Array[Dictionary], moving: bool) -> void:
	for layer in source.size():
		var vertices: Array[Vector3] = []
		for point in source[layer].points:
			vertices.append(paper_mesh.transform * _vertex(point, layer, moving))
		output.append({"world_vertices": vertices, "paper": source[layer].paper, "seams": source[layer].seams, "front": source[layer].front, "moving": moving, "layer": layer})

func _dump_state(path_override: String = "") -> String:
	if OS.has_feature("web") and path_override.is_empty():
		var filename := "pap_%s.json" % Time.get_datetime_string_from_system().replace(":", "-")
		JavaScriptBridge.download_buffer(JSON.stringify(Dump.encode(_snapshot()), "  ", true, true).to_utf8_buffer(), filename, "application/json")
		dump_notice.text = "덤프 다운로드를 요청했습니다: " + filename
		return filename
	var folder := "user://dumps"
	var path := path_override
	if path.is_empty():
		var error := DirAccess.make_dir_recursive_absolute(folder)
		if error != OK:
			dump_notice.text = "덤프 폴더를 만들지 못했습니다: %s" % error_string(error)
			return ""
		var stamp := Time.get_datetime_string_from_system().replace(":", "-")
		path = "%s/pap_%s_%s.json" % [folder, stamp, Time.get_ticks_usec()]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		dump_notice.text = "덤프 저장 실패: %s" % error_string(FileAccess.get_open_error())
		return ""
	file.store_string(JSON.stringify(Dump.encode(_snapshot()), "  "))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		dump_notice.text = "덤프 쓰기 실패: %s" % error_string(write_error)
		return ""
	var absolute := ProjectSettings.globalize_path(path)
	dump_notice.text = "저장됨: %s · 덤프 폴더 버튼에서 JSON 파일을 전달해 주세요." % path.get_file()
	print("PAP dump saved: ", absolute)
	return absolute

func _open_dump_folder() -> void:
	if OS.has_feature("web"):
		_dump_state()
		return
	DirAccess.make_dir_recursive_absolute("user://dumps")
	var error := OS.shell_open(ProjectSettings.globalize_path("user://dumps"))
	if error != OK:
		dump_notice.text = "폴더 열기 실패: %s" % error_string(error)
func _build_airplane_guide() -> void:
	overlay.add_child(guide_panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("182a30")
	style.set_content_margin_all(10)
	style.set_corner_radius_all(8)
	guide_panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	guide_panel.add_child(column)
	guide_title.add_theme_font_size_override("font_size", 15)
	guide_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(guide_title)
	guide_mode_hint.add_theme_font_size_override("font_size", 12)
	guide_mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(guide_mode_hint)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	guide_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guide_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scroll.add_child(guide_text)
	var row := HBoxContainer.new()
	column.add_child(row)
	guide_previous.text = "이전"
	guide_next.text = "다음"
	for button in [guide_previous, guide_next]:
		button.focus_mode = Control.FOCUS_NONE
		row.add_child(button)
	guide_previous.pressed.connect(func() -> void: _set_guide_step(guide_step - 1))
	guide_next.pressed.connect(func() -> void: _set_guide_step(guide_step + 1))
	guide_flight.text = "준비되면 하단의 날려보기를 누르세요."
	guide_flight.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide_flight.focus_mode = Control.FOCUS_NONE
	column.add_child(guide_flight)
	guide_panel.visible = false
	_set_guide_step(0)
func _toggle_guide() -> void:
	guide_panel.visible = not guide_panel.visible

func _set_guide_step(index: int) -> void:
	guide_step = clampi(index, 0, guide_steps.size() - 1)
	var step := guide_steps[guide_step]
	guide_title.text = "%d / %d  %s" % [guide_step + 1, guide_steps.size(), step.title]
	guide_text.text = step.text
	guide_previous.disabled = guide_step == 0
	guide_next.disabled = guide_step == guide_steps.size() - 1
	guide_flight.visible = guide_step == guide_steps.size() - 1
func _open_flight() -> void:
	if park_mode:
		if state == State.IDLE and not reference_drawing and not picker.visible and preset_pending.is_empty(): park_stored.emit()
		return
	if state != State.IDLE or flight_view != null:
		return
	line_ready = false
	tools.hide()
	parts_editor.hide()
	get_window().content_scale_size = Vector2i.ZERO
	flight_view = FlightTest.new()
	flight_view.configure(faces, history, self)
	flight_view.closed.connect(_close_flight)
	overlay.visible = false
	paper_mesh.visible = false
	edge_mesh.visible = false
	$Ground.visible = false
	$Ground/CollisionShape3D.set_deferred("disabled", true)
	add_child(flight_view)

func _close_flight() -> void:
	if flight_view == null:
		return
	flight_session = flight_view.session_state()
	flight_view.queue_free()
	flight_view = null
	get_window().content_scale_size = Vector2i.ZERO
	overlay.visible = true
	paper_mesh.visible = true
	edge_mesh.visible = true
	$Ground.visible = true
	$Ground/CollisionShape3D.set_deferred("disabled", false)
	camera.make_current()
	camera.reset_physics_interpolation()
	_refresh()
func _toggle_reference_edit() -> void:
	if state != State.IDLE or inspect_view or flight_view != null:
		return
	reference_editing = not reference_editing
	reference_drawing = false
	line_ready = false
	_refresh_ui()
	if reference_editing:
		status.text = "기준점은 원하는 위치를 클릭하거나 드래그하세요. 기준선은 두 위치를 드래그하세요. Shift: 스냅 해제 · Esc: 취소"

func _reset_reference() -> void:
	if state != State.IDLE or reference_drawing:
		return
	custom_reference = {}
	reference_editing = false
	_refresh()

func _finish_reference(point: Vector2, freehand: bool) -> void:
	_motion(point, freehand)
	var definition: Dictionary
	if reference_tool.selected == 0:
		definition = FoldReference.point_definition(faces, reference_b)
	elif reference_a.distance_to(reference_b) >= _pixel_radius(8):
		definition = FoldReference.line_definition(faces, reference_a, reference_b)
	reference_drawing = false
	if definition.is_empty():
		status.text = "종이 위에 기준점을 놓거나 종이를 가로지르는 기준선을 그려 주세요."
		return
	custom_reference = definition
	reference_editing = false
	_refresh()
func _can_commit() -> bool:
	return not fold_plan.is_empty() and fold_angle >= COMMIT_ANGLE

func _draw_arrow(start: Vector2, finish: Vector2, color: Color) -> void:
	if start.distance_to(finish) < 12:
		return
	var direction := (finish - start).normalized()
	var side := direction.orthogonal() * 5
	var tip := finish - direction * 7
	overlay.draw_line(start + direction * 8, tip, color, 2, true)
	overlay.draw_colored_polygon(PackedVector2Array([tip, tip - direction * 10 + side, tip - direction * 10 - side]), color)

func _gesture_active() -> bool:
	return state in [State.DRAWING, State.DRAGGING, State.PENDING] or reference_drawing

func _layout_workspace() -> void:
	dump_notice.visible = not dump_notice.text.is_empty()
	var viewport := get_viewport().get_visible_rect().size
	if viewport != layout_size and layout_size != Vector2.ZERO and _gesture_active():
		_cancel(false)
		status.text = "창 크기가 바뀌었습니다. 종이를 다시 잡아 주세요."
	layout_size = viewport
	preset_panel.size = Vector2(minf(500, viewport.x - 28), minf(420, viewport.y - 28))
	preset_panel.position = (viewport - preset_panel.size) * 0.5
	toolbar.position = Vector2(10, 8)
	toolbar.size = Vector2(viewport.x - 20, 0)
	action_bar.size = Vector2(minf(700, viewport.x - 200), 122)
	action_bar.position = Vector2((viewport.x - 184 - action_bar.size.x) * 0.5, viewport.y - 134)
	action_bar.visible = not parts_editor.visible
	dump_notice.position = Vector2(action_bar.position.x + action_bar.size.x + 12, action_bar.position.y + 8)
	dump_notice.size = Vector2(viewport.x - dump_notice.position.x - 12, 100)
	var top := toolbar.position.y + toolbar.size.y + 12
	var bottom := action_bar.position.y - 12
	var width := viewport.x - 28
	if guide_panel.visible:
		var guide_width := minf(280, viewport.x * 0.34)
		guide_panel.position = Vector2(viewport.x - guide_width - 14, top)
		guide_panel.size = Vector2(guide_width, maxf(100, minf(280, bottom - top)))
		width -= guide_width + 12
	if parts_editor.visible:
		var parts_width := minf(420, viewport.x * 0.6)
		parts_editor.position = Vector2(viewport.x - parts_width - 12, 12)
		parts_editor.size = Vector2(parts_width, viewport.y - 24)
		width -= parts_width + 12
	work_area = Rect2(14, top, maxf(40, width), maxf(40, bottom - top))

# Keep projection fixed while a pointer gesture is active; fitting then must not move its target.
func _fit_view() -> void:
	if _gesture_active() or work_area.size.x <= 0 or work_area.size.y <= 0:
		return
	var points := PackedVector3Array()
	for face in faces:
		for p in face.points:
			var position := Vector3(p.x, PAPER_Y, p.y)
			points.append(position)
			if state == State.FLIPPING:
				points.append(paper_mesh.transform * position)
	if not fold_plan.is_empty():
		for moving in [false, true]:
			var source: Array[Dictionary] = fold_plan.move if moving else fold_plan.stay
			for layer in source.size():
				for p in source[layer].points:
					points.append(paper_mesh.transform * _vertex(p, layer, moving))
	if guide_panel.visible and guide_steps[guide_step].action == "fold":
		var step := guide_steps[guide_step]
		for p in [step.a, step.b, step.grab, step.target]:
			points.append(Vector3(p.x, PAPER_Y, p.y))
	if points.is_empty():
		return
	var low := Vector2(INF, INF)
	var high := -low
	for p in points:
		var local := camera.basis.inverse() * p
		var screen_plane := Vector2(local.x, -local.y)
		low = low.min(screen_plane)
		high = high.max(screen_plane)
	var extent := (high - low).max(Vector2(0.05, 0.05)) + Vector2(0.055, 0.055)
	var viewport := get_viewport().get_visible_rect().size
	camera.size = maxf(extent.y * viewport.y / work_area.size.y, extent.x * viewport.y / work_area.size.x)
	var unit := camera.size / viewport.y
	var center := (low + high) * 0.5
	var shift := work_area.get_center() - viewport * 0.5
	var distance := maxf(0.6, camera.position.dot(camera.basis.z))
	camera.position = camera.basis.x * (center.x - shift.x * unit) + camera.basis.y * (-center.y + shift.y * unit) + camera.basis.z * distance
	camera.reset_physics_interpolation()
func _snap_reference() -> Dictionary:
	if not guide_panel.visible or guide_steps[guide_step].action != "fold":
		return reference
	var candidates: Dictionary = reference.duplicate(true)
	var step := guide_steps[guide_step]
	for anchor in [step.a, step.b, step.grab, step.target]:
		candidates.centers.append(anchor)
	return candidates
func _build_presets_ui(style: StyleBoxFlat) -> void:
	overlay.add_child(preset_shade)
	preset_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preset_shade.color = Color(0.03, 0.05, 0.07, 0.8)
	preset_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	preset_shade.add_child(preset_panel)
	preset_panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	preset_panel.add_child(column)
	var title := Label.new()
	title.text = "내 도면"
	title.add_theme_font_size_override("font_size", 18)
	column.add_child(title)
	preset_name.placeholder_text = "이름 (예: 첫 종이비행기)"
	preset_name.max_length = 64
	preset_name.text_submitted.connect(func(_text: String) -> void: _request_preset_save())
	column.add_child(preset_name)
	preset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preset_list.custom_minimum_size.y = 64
	preset_list.item_selected.connect(_preset_selected)
	preset_list.item_activated.connect(func(_index: int) -> void: _request_preset_load())
	column.add_child(preset_list)
	preset_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preset_notice.max_lines_visible = 2
	column.add_child(preset_notice)
	var row := HBoxContainer.new()
	column.add_child(row)
	preset_save.text = "현재 도면 저장"
	preset_save.pressed.connect(_request_preset_save)
	preset_load.text = "선택 도면 불러오기"
	preset_load.pressed.connect(_request_preset_load)
	var close := Button.new()
	close.text = "계속 접기"
	close.pressed.connect(_hide_presets)
	for button in [preset_save, preset_load]:
		button.focus_mode = Control.FOCUS_NONE
		row.add_child(button)
	var exits := HBoxContainer.new()
	column.add_child(exits)
	exits.add_child(close)
	preset_fly.text = "접기 마치고 보관" if park_mode else "날려보기"
	preset_fly.focus_mode = Control.FOCUS_NONE
	preset_fly.pressed.connect(func() -> void:
		if not preset_pending.is_empty() or not pending_stock.is_empty(): return
		_hide_presets()
		_open_flight()
	)
	exits.add_child(preset_fly)
	PlayUI.primary(preset_fly)
	var confirmation := HBoxContainer.new()
	column.add_child(confirmation)
	preset_confirm.pressed.connect(_confirm_preset)
	preset_cancel.text = "취소"
	preset_cancel.pressed.connect(func() -> void: _set_preset_pending({}))
	for button in [preset_confirm, preset_cancel]:
		button.focus_mode = Control.FOCUS_NONE
		confirmation.add_child(button)
	preset_shade.hide()
	pending_stock = {}
	_set_preset_pending({})

func _show_presets() -> void:
	if state != State.IDLE or reference_drawing or flight_view != null: return
	_cancel()
	tools.hide()
	preset_notice.text = "현재 모양·접기 이력·기준점과 기준선을 저장합니다."
	_refresh_preset_list()
	_set_preset_pending({})
	preset_shade.show()
	Audio.play_sfx("open")

func _hide_presets() -> void:
	if preset_shade.visible: Audio.play_sfx("close")
	preset_shade.hide()
	pending_stock = {}
	_set_preset_pending({})
	get_viewport().gui_release_focus()

func _refresh_preset_list(selected_name: String = "") -> void:
	preset_entries = preset_store.list_presets()
	if not preset_store.list_errors.is_empty():
		preset_notice.text = "읽지 못한 도면 파일 %d개가 있습니다. 원본 파일은 유지됩니다." % preset_store.list_errors.size()
	preset_list.clear()
	var selected := 0
	for i in preset_entries.size():
		preset_list.add_item(preset_entries[i].name)
		if preset_entries[i].name == selected_name: selected = i
	if not preset_entries.is_empty():
		preset_list.select(selected)
		_preset_selected(selected)
	preset_load.disabled = preset_entries.is_empty() or not preset_pending.is_empty()

func _preset_selected(index: int) -> void:
	if preset_pending.is_empty() and index >= 0 and index < preset_entries.size():
		preset_name.text = preset_entries[index].name

func _set_preset_pending(value: Dictionary) -> void:
	preset_pending = value
	preset_confirm.visible = not value.is_empty()
	preset_cancel.visible = not value.is_empty()
	preset_save.disabled = not value.is_empty()
	preset_load.disabled = not value.is_empty() or preset_entries.is_empty()
	preset_name.editable = value.is_empty()
	preset_fly.disabled = not value.is_empty() or not pending_stock.is_empty()
	if value.is_empty(): return
	preset_confirm.text = "덮어쓰기" if value.kind == "save" else "불러오기"
	preset_notice.text = "‘%s’을 덮어쓸까요?" % value.name if value.kind == "save" else "현재 종이를 ‘%s’으로 바꿉니다. 계속할까요?" % value.name

func _preset_state() -> Dictionary:
	return {"faces": faces.duplicate(true), "history": history.duplicate(true), "fold_count": fold_count, "reference": custom_reference.duplicate(true), "flight_parts": flight_parts.duplicate(true), "paper_stock": paper_stock.duplicate(true)}

func _request_preset_save() -> void:
	if state != State.IDLE or reference_drawing or not preset_pending.is_empty(): return
	var name := preset_name.text.strip_edges()
	if FileAccess.file_exists(preset_store.path_for(name)):
		_set_preset_pending({"kind": "save", "name": name})
	else:
		_save_preset(name, false)

func _save_preset(name: String, overwrite: bool) -> void:
	var result: Dictionary = preset_store.save_preset(name, _preset_state(), overwrite)
	_set_preset_pending({})
	if not result.ok:
		preset_notice.text = "저장 실패: " + result.error
		Audio.play_sfx("error")
		return
	Audio.play_sfx("save")
	_refresh_preset_list(result.name)
	preset_notice.text = "저장됨: " + result.name
	var next_stock := pending_stock.duplicate(true)
	_hide_presets()
	if not next_stock.is_empty(): _reset_paper(next_stock)
	dump_notice.text = "내 도면 저장됨: " + result.name

func _request_preset_load() -> void:
	if state != State.IDLE or not preset_pending.is_empty(): return
	var selected := preset_list.get_selected_items()
	if selected.is_empty(): return
	var result: Dictionary = preset_store.load_preset(preset_entries[selected[0]].path)
	if not result.ok:
		preset_notice.text = "불러오기 실패: " + result.error
		return
	_set_preset_pending({"kind": "load", "name": result.name, "sheet": result.sheet})

func _confirm_preset() -> void:
	if preset_pending.is_empty() or state != State.IDLE or flight_view != null: return
	var pending: Dictionary = preset_pending
	if pending.kind == "save":
		_save_preset(pending.name, true)
		return
	var sheet: Dictionary = pending.sheet
	_cancel()
	paper_stock = sheet.paper_stock.duplicate(true)
	faces = sheet.faces.duplicate(true)
	history.assign(sheet.history.duplicate(true))
	fold_count = sheet.fold_count
	custom_reference = sheet.reference.duplicate(true)
	flight_parts = sheet.get("flight_parts", {}).duplicate(true)
	parts_editor.hide()
	grabbed_layer = -1
	snap_marker = Vector2.INF
	fold_angle = 0
	guide_panel.hide()
	reference_tool.select(1 if custom_reference.get("kind") == "line" else 0)
	if inspect_view: _toggle_view()
	_refresh()
	_hide_presets()
	dump_notice.text = "내 도면 불러옴: " + pending.name
func _open_parts() -> void:
	if state != State.IDLE or flight_view != null: return
	_cancel()
	guide_panel.hide()
	tools.hide()
	parts_editor.open()

func _open_paper_picker() -> void:
	if state != State.IDLE or reference_drawing or flight_view != null or preset_shade.visible: return
	parts_editor.hide()
	tools.hide()
	picker.open()

func _save_then_start(stock: Dictionary) -> void:
	pending_stock = stock.duplicate(true)
	_show_presets()
	preset_notice.text = "현재 도면을 저장하면 선택한 새 종이로 시작합니다. 취소하면 현재 접기를 유지합니다."

func restore_sheet(sheet: Dictionary) -> void:
	faces.assign(sheet.faces.duplicate(true))
	history.assign(sheet.history.duplicate(true))
	fold_count = sheet.fold_count
	custom_reference = sheet.get("reference", {}).duplicate(true)
	flight_parts = sheet.get("flight_parts", {}).duplicate(true)
	paper_stock = Stock.read(sheet.get("paper_stock"), faces)
	flight_session = sheet.get("flight_session", {}).duplicate(true)
	_refresh()
