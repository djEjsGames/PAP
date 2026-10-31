extends PanelContainer
const PlayUI := preload("res://scripts/play_ui.gd")
const Parts := preload("res://scripts/flight_parts.gd")
const Model := preload("res://scripts/flight_model.gd")
var source: Node
var selectors: Array[OptionButton] = []
var wings: Array[int] = []
var grip := -1
var highlight := 0
var notice := Label.new()
var preview := Control.new()
var confirm := Button.new()
var candidate: Dictionary = {}
var continue_button := Button.new()
var close_button := Button.new()

func _ready() -> void:
	var column := VBoxContainer.new()
	add_child(column)
	var title := Label.new()
	title.text = "색으로 표시된 날개와 손잡이를 확인하세요"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)
	var roles := HBoxContainer.new()
	column.add_child(roles)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	for i in 3:
		var label := Button.new()
		label.focus_mode = Control.FOCUS_NONE
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.pressed.connect(func() -> void: _highlight(i))
		label.text = Parts.NAMES[i]
		label.modulate = Parts.COLORS[i]
		roles.add_child(label)
		var select := OptionButton.new()
		select.fit_to_longest_item = false
		select.focus_mode = Control.FOCUS_NONE
		select.item_selected.connect(func(index: int) -> void: _choose(i, index))
		selectors.append(select)
		content.add_child(select)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(notice)
	preview.custom_minimum_size.y = 100
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.draw.connect(_draw_preview)
	content.add_child(preview)
	confirm.text = "확정하고 보관" if source.park_mode else "확정하고 날려보기"
	confirm.focus_mode = Control.FOCUS_NONE
	confirm.pressed.connect(func() -> void:
		if confirm.disabled: return
		_confirm()
		hide()
		source._open_flight()
	)
	column.add_child(confirm)
	PlayUI.primary(confirm)
	var exits := HBoxContainer.new()
	column.add_child(exits)
	continue_button.text = "확정하고 계속 접기"
	continue_button.focus_mode = Control.FOCUS_NONE
	continue_button.pressed.connect(func() -> void:
		if confirm.disabled: return
		_confirm()
		hide()
	)
	exits.add_child(continue_button)
	close_button.text = "계속 접기"
	close_button.tooltip_text = "확정하지 않고 닫기 · 미확정도 자유 비행 가능"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(hide)
	exits.add_child(close_button)
	hide()

func open() -> void:
	show()
	wings = Model.wing_folds(source.history)
	if Parts.valid(source.flight_parts, source.faces, source.history):
		wings = Model.wing_folds(source.history, source.flight_parts)
	while wings.size() < 2: wings.append(-1)
	for i in 2:
		selectors[i].clear()
		for index in source.history.size():
			if source.history[index].kind == "fold":
				selectors[i].add_item("접기 %d · 기존 연결부" % (index + 1), index)
		selectors[i].select(selectors[i].get_item_index(wings[i]))
	selectors[2].clear()
	for index in source.faces.size(): selectors[2].add_item("면 %d · 재료 기준" % (index + 1), index)
	grip = int(source.flight_parts.grip) if Parts.valid(source.flight_parts, source.faces, source.history) else -1
	if grip < 0:
		for i in source.faces.size():
			if Parts.role(i, source.faces, source.history, wings, -1) < 0:
				grip = i
				break
	selectors[2].select(grip)
	_highlight(0)
	_update()

func _choose(role: int, index: int) -> void:
	_highlight(role)
	if role < 2: wings[role] = selectors[role].get_item_id(index)
	else: grip = index
	_update()

func _update() -> void:
	candidate = {"signature": Parts.signature(source.faces, source.history), "wings": Array(wings), "grip": grip}
	var valid := Parts.valid(candidate, source.faces, source.history)
	if valid: valid = Model.is_joined(Model.pose(source.faces, source.history, Vector2(90, 90), candidate))
	confirm.disabled = not valid
	continue_button.disabled = not valid
	notice.text = "90° 펼침 미리보기 · 손잡이는 아래 기준" if valid else "서로 다른 연결된 날개 두 개와, 날개 밖 손잡이 면을 선택하세요."
	if valid:
		if candidate == source.flight_parts: notice.text = "확정 · " + notice.text
		else: notice.text = ("추천 / 미확정 · " if source.flight_parts.is_empty() else "변경 후보 / 미확정 · ") + notice.text
	preview.queue_redraw()
	source.overlay.queue_redraw()

func _confirm() -> void:
	if confirm.disabled: return
	source.flight_parts = candidate.duplicate(true)
	source._refresh_ui()
	notice.text = "확정됨 · 선택한 두 축과 손잡이를 비행에 사용합니다."

func _draw_preview() -> void:
	if confirm.disabled: return
	var posed := Model.pose(source.faces, source.history, Vector2(90, 90), candidate)
	var basis := Model.launch_frame(source.faces, source.history, candidate)
	var polygons: Array[PackedVector2Array] = []
	var low := Vector2(INF, INF)
	var high := -low
	for face in posed:
		var points := PackedVector2Array()
		for p in face.points:
			var v: Vector3 = basis * p
			var q := Vector2(v.x + v.z * 0.4, -v.y + v.z * 0.45)
			points.append(q)
			low = low.min(q)
			high = high.max(q)
		polygons.append(points)
	var scale := minf((preview.size.x - 12) / maxf(high.x - low.x, 0.01), 80 / maxf(high.y - low.y, 0.01))
	for index in polygons.size():
		var points := PackedVector2Array()
		for p in polygons[index]: points.append((p - (low + high) * 0.5) * scale + preview.size * 0.5)
		var role := Parts.role(index, source.faces, source.history, wings, grip)
		var color: Color = Parts.COLORS[role] if role >= 0 else Color("71828a")
		var hull := Geometry2D.convex_hull(points)
		if hull.size() > 3:
			hull.remove_at(hull.size() - 1)
			if absf(_area(hull)) > 0.1: preview.draw_colored_polygon(hull, Color(color, 0.35))
		points.append(points[0])
		preview.draw_polyline(points, color, 1.5, true)

func _area(points: PackedVector2Array) -> float:
	var area := 0.0
	for i in points.size(): area += points[i].cross(points[(i + 1) % points.size()])
	return area * 0.5

func _highlight(role: int) -> void:
	highlight = role
	for i in selectors.size(): selectors[i].visible = i == role
	source.overlay.queue_redraw()
