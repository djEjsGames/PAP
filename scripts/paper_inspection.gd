extends Control

signal decided(action: String)
signal dump_requested
const Stock := preload("res://scripts/paper_stock.gd")
const Parts := preload("res://scripts/flight_parts.gd")
const Model := preload("res://scripts/flight_model.gd")
const Visual := preload("res://scripts/aircraft_visual.gd")
const Presets := preload("res://scripts/paper_presets.gd")
const PlayUI := preload("res://scripts/play_ui.gd")
var data: Dictionary
var from_world := false
var faces: Array[Dictionary] = []
var history: Array[Dictionary] = []
var binding: Dictionary = {}
var can_deploy := false
var deployed := false
var rotation_angles := Vector2.ZERO
var zoom := 1.0
var dragging := false
var view := SubViewport.new()
var stage := Node3D.new()
var model := MeshInstance3D.new()
var camera := Camera3D.new()
var surface := SubViewportContainer.new()
var toggle := Button.new()
var explanation := Label.new()
var action_buttons: Array[Button] = []
var radius := 0.1
var done := false
var preset_store := Presets.new()
var save_panel := PopupPanel.new()
var save_name := LineEdit.new()
var save_notice := Label.new()
var reference_button: Button
var save_button: Button

func configure(item: Dictionary, world_source: bool) -> void:
	data = item.duplicate(true)
	data.erase("flight")
	data.erase("marker")
	from_world = world_source
	faces.assign(item.sheet.faces.duplicate(true))
	history.assign(item.sheet.history.duplicate(true))
	if Parts.valid(item.sheet.flight_parts, faces, history): binding = item.sheet.flight_parts.duplicate(true)
	can_deploy = Model.wing_folds(history, binding).size() == 2 and Model.is_joined(Model.pose(faces, history, Vector2(90, 90), binding))
	deployed = can_deploy

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color("102126")
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 12)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	surface.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	surface.stretch = true
	surface.mouse_filter = Control.MOUSE_FILTER_STOP
	surface.gui_input.connect(_view_input)
	row.add_child(surface)
	view.size = Vector2i(640, 480)
	view.own_world_3d = true
	view.gui_disable_input = true
	surface.add_child(view)
	view.add_child(stage)
	stage.add_child(model)
	camera.fov = 42
	camera.near = 0.005
	camera.far = 20
	view.add_child(camera)
	camera.make_current()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("263e48")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.55
	view.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -35, 0)
	view.add_child(light)
	var action_column := VBoxContainer.new()
	action_column.custom_minimum_size.x = 240
	action_column.add_theme_constant_override("separation", 8)
	row.add_child(action_column)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_column.add_child(scroll)
	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 8)
	scroll.add_child(controls)
	var title := Label.new()
	title.text = data.name
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 20)
	controls.add_child(title)
	var stats := Label.new()
	stats.text = Stock.summary(data.sheet.paper_stock) + "\n한 장 %.2fg · 접기 %d회" % [Stock.mass(data.sheet.paper_stock) * 1000, data.sheet.fold_count]
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(stats)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(explanation)
	toggle.text = "접힌 모습 / 펼친 모습"
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.disabled = not can_deploy
	toggle.pressed.connect(func() -> void:
		deployed = not deployed
		_rebuild()
	)
	controls.add_child(toggle)
	_button(controls, "시점 초기화", reset_view)
	reference_button = _button(controls, "내 도면으로 남기기", _show_save)
	Audio.add_button(controls)
	_build_save_panel()
	if from_world:
		var store := _button(action_column, "보관하기", func() -> void: _decide("store"))
		PlayUI.primary(store)
		action_buttons.append(store)
		action_buttons.append(_button(action_column, "다시 놓기 [Esc]", func() -> void: _decide("cancel")))
		var clear := _button(action_column, "정리하기 · 발견물 기록", func() -> void: _decide("clear"))
		clear.add_theme_color_override("font_color", Color("ffb5a6"))
		clear.tooltip_text = "같은 발견물을 정리한 기록으로 남깁니다. 보수는 없습니다."
		action_buttons.append(clear)
	else:
		action_buttons.append(_button(action_column, "보관함으로 [Esc]", func() -> void: _decide("cancel")))
	var help := Label.new()
	help.text = "왼쪽 드래그: 회전 · 휠: 확대"
	help.add_theme_font_size_override("font_size", 18)
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_child(help)
	help.position = Vector2(10, 10)
	_rebuild()
	get_window().focus_exited.connect(func() -> void: dragging = false)

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 36
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _rebuild() -> void:
	var posed := Model.pose(faces, history, Vector2(90, 90) if deployed else Vector2.ZERO, binding)
	assert(Model.is_joined(posed), "Observation must preserve connected paper")
	var basis := Model.launch_frame(faces, history, binding)
	var display: Array[Dictionary] = []
	for face in posed:
		var points := PackedVector3Array()
		for point in face.points: points.append(basis * point)
		display.append({"points": points, "paper": face.paper, "seams": face.seams, "normal": basis * face.normal, "layer_sign": face.layer_sign})
	var properties := Model.properties(display)
	var visual := Visual.build(display, properties.center, data.sheet.paper_stock)
	model.mesh = visual.mesh
	model.material_override = visual.material
	radius = 0
	for face in display:
		for point in face.points: radius = maxf(radius, (point - properties.center).length())
	explanation.text = ("확정 날개" if not binding.is_empty() else "접기 이력의 추천 축") + (" · 90° 펼친 모습" if deployed else " · 접힌 모습") if can_deploy else "날개 축 없음 · 접힌 모습"
	_update_camera()

func reset_view() -> void:
	rotation_angles = Vector2.ZERO
	zoom = 1
	_update_camera()

func _process(_delta: float) -> void:
	_update_camera()

func _update_camera() -> void:
	stage.basis = Basis.from_euler(Vector3(rotation_angles.y, rotation_angles.x, 0))
	var aspect := maxf(0.1, float(view.size.x) / maxf(1, view.size.y))
	var half_angle := minf(deg_to_rad(camera.fov * 0.5), atan(tan(deg_to_rad(camera.fov * 0.5)) * aspect))
	var distance := maxf(0.05, radius / sin(half_angle) * 1.25 * zoom)
	camera.position = Vector3(0.7, 0.4, 1).normalized() * distance
	camera.look_at(Vector3.ZERO)

func _view_input(event: InputEvent) -> void:
	if done: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT: dragging = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom = clampf(zoom * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.9), 0.35, 3)
			_update_camera()
		accept_event()

func _input(event: InputEvent) -> void:
	if done: return
	if event is InputEventKey:
		if save_panel.visible:
			if event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
				save_panel.hide()
				get_viewport().set_input_as_handled()
			return
		if event.pressed and not event.echo and event.physical_keycode == KEY_D and event.ctrl_pressed and event.shift_pressed:
			get_viewport().set_input_as_handled()
			dump_requested.emit()
			return
		get_viewport().set_input_as_handled()
		if event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE: _decide("cancel")
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = false
	elif event is InputEventMouseMotion and dragging:
		rotation_angles += event.relative * 0.01
		_update_camera()
		get_viewport().set_input_as_handled()

func _decide(action: String) -> void:
	if done: return
	done = true
	dragging = false
	decided.emit(action)

func _build_save_panel() -> void:
	add_child(save_panel)
	save_panel.theme = theme
	save_panel.window_input.connect(_save_input)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 12)
	save_panel.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var label := Label.new()
	label.text = "실물과 별개인 도면으로 저장"
	column.add_child(label)
	column.add_child(save_name)
	save_name.custom_minimum_size.x = 320
	save_name.max_length = 64
	save_name.text_submitted.connect(func(_text: String) -> void: _save_diagram())
	save_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(save_notice)
	save_button = _button(column, "도면 저장", _save_diagram)
	_button(column, "취소", save_panel.hide)

func _show_save() -> void:
	if done: return
	save_name.text = data.name
	save_notice.text = "기체 보관·정리와 독립적으로 저장합니다."
	save_panel.popup_centered(Vector2i(mini(450, int(get_viewport().get_visible_rect().size.x) - 24), 0))
	save_name.grab_focus()
	save_name.select_all()

func _save_diagram() -> void:
	if not save_panel.visible or done: return
	var result := preset_store.save_preset(save_name.text, data.sheet)
	if not result.ok:
		save_notice.text = result.error
		Audio.play_sfx("error")
		return
	Audio.play_sfx("save")
	save_panel.hide()
	explanation.text = "내 도면 저장됨 · " + result.name

func snapshot() -> Dictionary:
	var actions: Array[Dictionary] = []
	for button in action_buttons: actions.append(_rect(button))
	var name_rect := _rect(save_name)
	var save_rect := _rect(save_button)
	name_rect.position += Vector2(save_panel.position)
	save_rect.position += Vector2(save_panel.position)
	return {"item_id": data.id, "from_world": from_world, "deployed": deployed, "can_deploy": can_deploy, "rotation": rotation_angles, "zoom": zoom, "surface": _rect(surface), "toggle": _rect(toggle), "reference": _rect(reference_button), "actions": actions, "save_dialog": save_panel.visible, "save_name": name_rect, "save_button": save_rect}

func _rect(control: Control) -> Dictionary:
	return {"position": control.global_position, "size": control.size}

func _save_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_D and event.ctrl_pressed and event.shift_pressed:
		save_panel.set_input_as_handled()
		dump_requested.emit()
