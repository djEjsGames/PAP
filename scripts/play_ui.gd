extends RefCounted

static func primary(button: Button) -> void:
	button.custom_minimum_size.y = 32
	button.add_theme_color_override("font_color", Color("142b30"))
	button.add_theme_color_override("font_hover_color", Color("142b30"))
	button.add_theme_color_override("font_pressed_color", Color("142b30"))
	for entry in [["normal", "7de1d2"], ["hover", "a3f0e4"], ["pressed", "55baaf"], ["disabled", "344d56"]]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(entry[1])
		style.set_corner_radius_all(6)
		style.set_content_margin_all(6)
		button.add_theme_stylebox_override(entry[0], style)
