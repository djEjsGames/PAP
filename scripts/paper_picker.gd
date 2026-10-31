extends ColorRect
const Stock := preload("res://scripts/paper_stock.gd")
const PlayUI := preload("res://scripts/play_ui.gd")
var source: Node
var panel := PanelContainer.new()
var selected := 0
var cards: Array[Button] = []
var titles: Array[Label] = []
var warning := Label.new()
var start := Button.new()
var save_start := Button.new()

func _ready() -> void:
	color = Color(0.03, 0.05, 0.07, 0.85)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("182a30")
	style.set_content_margin_all(10)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var title := Label.new()
	title.text = "새 종이 · 다른 조건으로 접어보기"
	title.add_theme_font_size_override("font_size", 18)
	column.add_child(title)
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.max_lines_visible = 2
	column.add_child(warning)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(grid)
	var sample_scale := 0.0
	for stock in Stock.OPTIONS: sample_scale = maxf(sample_scale, maxf(stock.size.x, stock.size.y))
	for i in 4:
		var stock := Stock.option(i)
		var card := Button.new()
		card.focus_mode = Control.FOCUS_NONE
		card.custom_minimum_size = Vector2(0, 102)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.tooltip_text = stock.description
		card.pressed.connect(func() -> void: choose(i))
		grid.add_child(card)
		cards.append(card)
		card.draw.connect(func() -> void:
			if selected != i: return
			var origin := Vector2(card.size.x - 23, 9)
			card.draw_line(origin + Vector2(0, 5), origin + Vector2(4, 9), Color("7de1d2"), 2, true)
			card.draw_line(origin + Vector2(4, 9), origin + Vector2(12, 0), Color("7de1d2"), 2, true)
		)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(row)
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 7
		row.offset_top = 5
		row.offset_right = -7
		row.offset_bottom = -5
		var sample := Control.new()
		sample.custom_minimum_size = Vector2(58, 70)
		sample.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(sample)
		sample.draw.connect(func() -> void:
			var extent: Vector2 = stock.size / sample_scale * 66
			var rect := Rect2((sample.size - extent) * 0.5, extent)
			sample.draw_rect(rect, Stock.front(stock))
			var texture := Stock.texture(stock)
			if texture != null: sample.draw_texture_rect(texture, rect, false, Stock.front(stock))
			sample.draw_rect(rect, Color("a1afb0"), false)
		)
		var info := VBoxContainer.new()
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(info)
		for text in [stock.name, "%s×%scm · %.2fg" % [String.num(stock.size.x * 100, 1).trim_suffix(".0"), String.num(stock.size.y * 100, 1).trim_suffix(".0"), Stock.mass(stock) * 1000], "%.0fg/m² · %s" % [stock.gsm, stock.description]]:
			var label := Label.new()
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.add_theme_font_size_override("font_size", 14 if info.get_child_count() < 2 else 11)
			info.add_child(label)
			label.text = text
			if info.get_child_count() == 1: titles.append(label)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	start.text = "이 종이로 시작"
	start.focus_mode = Control.FOCUS_NONE
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.pressed.connect(func() -> void:
		hide()
		source._reset_paper(Stock.option(selected))
	)
	actions.add_child(start)
	PlayUI.primary(start)
	save_start.text = "저장하고 시작"
	save_start.focus_mode = Control.FOCUS_NONE
	save_start.pressed.connect(func() -> void:
		hide()
		source._save_then_start(Stock.option(selected))
	)
	actions.add_child(save_start)
	var cancel := Button.new()
	cancel.text = "취소"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(hide)
	actions.add_child(cancel)
	hide()

func open() -> void:
	selected = 0
	for i in 4:
		if Stock.OPTIONS[i].id == source.paper_stock.id: selected = i
	warning.text = "카드는 비교만 합니다. 시작하면 현재 종이가 교체됩니다." if source.history.is_empty() else "시작하면 현재 접기가 교체됩니다. 남길 도면은 저장하고 시작하세요."
	choose(selected)
	show()

func choose(index: int) -> void:
	selected = index
	for i in 4:
		titles[i].text = ("선택 · " if i == selected else "") + Stock.OPTIONS[i].name
		var style := StyleBoxFlat.new()
		style.bg_color = Color("29464c") if i == selected else Color("22373e")
		style.border_color = Color("7de1d2") if i == selected else Color("657779")
		style.set_border_width_all(2 if i == selected else 1)
		style.set_corner_radius_all(6)
		cards[i].add_theme_stylebox_override("normal", style)
		cards[i].add_theme_stylebox_override("hover", style)
		cards[i].add_theme_stylebox_override("pressed", style)
		cards[i].queue_redraw()

func _process(_delta: float) -> void:
	if not visible: return
	var viewport := get_viewport_rect().size
	panel.size = Vector2(minf(680, viewport.x - 24), minf(430, viewport.y - 24))
	panel.position = (viewport - panel.size) * 0.5
