extends "res://scripts/flight_test.gd"

var park: Node3D
var item_id := -1
var item: Dictionary
var watching := true
var released := false
var landed := false
var launch_origin := Vector3.ZERO
var launch_yaw := 0.0
var target_locked := false
var settled_time := 0.0
var first_contact: Dictionary = {}
var launch_target: Dictionary = {}
var previous_trail := MeshInstance3D.new()
var contact_marker := MeshInstance3D.new()

func _ready() -> void:
	super._ready()
	add_child(previous_trail)
	add_child(contact_marker)
	_draw_previous()

func configure_item(owner_park: Node3D, id: int, data: Dictionary) -> void:
	park = owner_park
	item_id = id
	item = data
	configure(data.sheet.faces, data.sheet.history, null)
	paper_stock = data.sheet.paper_stock.duplicate(true)
	if Parts.valid(data.sheet.flight_parts, faces, history): binding = data.sheet.flight_parts.duplicate(true)
	_read_target()

func _build_ground() -> void:
	pass

func _restore_session() -> void:
	var saved: Dictionary = item.get("flight_session", {})
	if saved.is_empty(): return
	if saved.get("sheet_signature") == sheet_signature and saved.get("binding") == binding:
		attitude = saved.attitude
		angles = saved.angles
	camera_angles = saved.camera_angles
	camera_zoom = saved.camera_zoom
	launch_power = saved.launch_power
	trials.assign(saved.get("trials", []).slice(-3).duplicate(true))
	_set_wind(saved.wind)

func _build_ui() -> void:
	super._build_ui()
	topbar.get_child(0).text = "공원 투척"
	elevation_help = "↑↓ / −+ : 고도각\n우클릭 드래그: 조준"
	hud.theme.default_font_size = 16
	launch_button.add_theme_font_size_override("font_size", 18)
	metrics.add_theme_stylebox_override("normal", park._hud_style())
	for child in topbar.get_children():
		if child is Button and child != adjust_button and child.name != "SoundSettings":
			child.hide()
	_button(topbar, "공원으로 [B]", func() -> void: closed.emit())
	result_retry.hide()
	var return_button: Button = result_retry.get_parent().get_child(1)
	return_button.text = "공원으로 돌아가기 [B]"
	PlayUI.primary(return_button)
	var backdrop := StyleBoxFlat.new()
	backdrop.bg_color = Color("182a30")
	backdrop.set_corner_radius_all(6)
	wind_hud.draw.disconnect(_draw_wind)
	wind_hud.draw.connect(func() -> void: wind_hud.draw_style_box(backdrop, Rect2(Vector2(-4, -4), wind_hud.size + Vector2(8, 8))))
	wind_hud.draw.connect(_draw_wind)

func _read_target() -> void:
	launch_origin = park.launch_position()
	launch_yaw = park.view_angles.x
	aim = Vector2(rad_to_deg(launch_yaw), rad_to_deg(park.view_angles.y))

func reset_trial() -> void:
	if released: return
	super.reset_trial()
	if body == null: return
	aim.x = rad_to_deg(launch_yaw)
	body.transform = Transform3D(Basis(Vector3.UP, launch_yaw) * attitude, launch_origin)
	body.reset_physics_interpolation()
	trajectory = PackedVector3Array([launch_origin])
	_draw_previous()
	_update_metrics()
	_update_launch_arrow()

func _advance_gauge() -> void:
	if watching and landed:
		closed.emit()
		return
	if released or not watching: return
	if gauge_stage == 0:
		_read_target()
		reset_trial()
		if not park.clear_launch(self):
			context_notice = "바로 앞이 막혀 있습니다. 열린 곳으로 이동하세요."
			Audio.play_sfx("error")
			return
		context_notice = ""
		target_locked = true
	super._advance_gauge()

func _cancel_gauge() -> void:
	super._cancel_gauge()
	target_locked = false

func _aim_changed(index: int, value: float) -> void:
	if index != 1 or released or gauge_stage != 0 or results_panel.visible: return
	park.view_angles.y = deg_to_rad(clampf(value, -70, 70))
	_read_target()
	reset_trial()

func launch_velocity() -> Vector3:
	var elevation := deg_to_rad(effective_elevation())
	return Basis(Vector3.UP, launch_yaw) * Vector3(0, sin(elevation), -cos(elevation)) * (MAX_LAUNCH_SPEED * launch_power / 100.0)

func launch(timing_error: float = 0, missed: bool = false) -> void:
	if released: return
	if not park.clear_launch(self):
		_cancel_gauge()
		context_notice = "발사 위치가 막혀 있습니다."
		Audio.play_sfx("error")
		return
	super.launch(timing_error, missed)
	if not running: return
	released = true
	launch_target = park.practice_target().duplicate(true)
	launched.practice_target = launch_target.duplicate(true)
	first_contact = {}
	_draw_contact_marker({})
	body.first_ground_contact = {}
	body.ground_time = 0
	body.track_ground = true
	launched.launch_transform = body.transform
	launched.target_aim_degrees = aim
	launched.aim_degrees = Vector2(aim.x, effective_elevation())
	trajectory = PackedVector3Array([launch_origin])
	park.release_item(self)

func _physics_process(delta: float) -> void:
	if not released or landed: return
	if not body.position.is_finite() or not body.linear_velocity.is_finite() or not body.angular_velocity.is_finite():
		park.restore_failed_flight(self)
		return
	elapsed += delta
	if first_contact.is_empty() and not body.first_ground_contact.is_empty():
		_record_first_contact(body.first_ground_contact.position, body.first_ground_contact.time_s)
	trail_timer += delta
	if trail_timer >= 0.05:
		trail_timer = 0
		trajectory.append(body.position)
		_draw_trail()
	_update_metrics()
	if body.get_contact_count() > 0 and body.linear_velocity.length() < 0.4:
		settled_time += delta
	else:
		settled_time = 0
	if settled_time >= 0.25:
		_finish("착지")

func _finish(reason: String) -> void:
	if not released or landed: return
	if reason != "착지":
		first_contact = {}
		_draw_contact_marker({})
	if reason == "착지" and first_contact.is_empty(): Audio.play_sfx("land")
	landed = true
	running = false
	var trial := launched.duplicate(true)
	trial.merge({"distance_m": Vector2(body.position.x - launch_origin.x, body.position.z - launch_origin.z).length(), "duration_s": elapsed, "reason": reason, "mass_kg": body.mass, "sheet_signature": sheet_signature}, true)
	trial.first_contact = first_contact.duplicate(true)
	trial.item_id = item_id
	trial.final_position = body.position
	trial.trajectory = trajectory.duplicate()
	trials.append(trial)
	if trials.size() > 3: trials.pop_front()
	_refresh_results()
	park.land_item(self)

func _record_first_contact(point: Vector3, time: float) -> void:
	if not released or not first_contact.is_empty() or not point.is_finite(): return
	first_contact = {"position":point, "time_s":time, "distance_m":Vector2(point.x - launch_origin.x, point.z - launch_origin.z).length(), "target":launch_target.duplicate(true)}
	if not launch_target.is_empty():
		var center: Vector3 = launch_target.center
		first_contact.error_m = Vector2(point.x - center.x, point.z - center.z).length()
		first_contact.success = first_contact.error_m <= launch_target.radius
	Audio.play_sfx("land")
	_draw_contact_marker(first_contact)

func _draw_contact_marker(contact: Dictionary) -> void:
	if contact_marker.get_parent() == null: return
	contact_marker.mesh = null
	if contact.is_empty(): return
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	var free_throw: bool = contact.get("target", {}).is_empty()
	if free_throw:
		for point in [Vector3(-0.08, 0, 0), Vector3(0.08, 0, 0), Vector3(0, 0, -0.08), Vector3(0, 0, 0.08)]: lines.surface_add_vertex(point)
	elif contact.get("success", false):
		for i in 24:
			for angle in [TAU * i / 24, TAU * (i + 1) / 24]: lines.surface_add_vertex(Vector3(cos(angle), 0, sin(angle)) * 0.09)
	else:
		for point in [Vector3(-0.08, 0, -0.08), Vector3(0.08, 0, 0.08), Vector3(-0.08, 0, 0.08), Vector3(0.08, 0, -0.08)]: lines.surface_add_vertex(point)
	lines.surface_end()
	contact_marker.mesh = lines
	contact_marker.position = contact.position + Vector3.UP * 0.006
	if not free_throw: contact_marker.position.y = maxf(contact_marker.position.y, contact.target.center.y + 0.006)
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = Color("8bcfff") if free_throw else (Color("86ffae") if contact.get("success", false) else Color("ff805a"))
	contact_marker.material_override = ink

func _contact_summary(contact: Dictionary) -> String:
	if contact.is_empty(): return "첫 지면 접촉 미측정 · 표적 판정 불가"
	if contact.get("target", {}).is_empty(): return "자유 투척 · 첫 접촉 %.2fm / %.2fs" % [contact.distance_m, contact.time_s]
	return "%s · 중심 오차 %.2fm · 첫 접촉 %.2fm / %.2fs" % ["성공 · 표적 안" if contact.success else "표적 밖", contact.error_m, contact.distance_m, contact.time_s]

func _same_aircraft(record: Dictionary) -> bool:
	return record.get("sheet_signature") == sheet_signature and record.get("paper_stock", {}) == paper_stock and record.get("flight_parts", {}) == binding

func _refresh_results() -> void:
	results.text = "같은 실물의 최근 3회 · 첫 접촉과 정지 거리는 별개\n첫 접촉: 초록○ 안 / 주홍X 밖 / 하늘+ 자유 투척\n" if not trials.is_empty() else "아직 비행 기록이 없습니다. 한 가지씩 바꿔 3회 비교해보세요."
	for i in range(trials.size() - 1, -1, -1):
		var record: Dictionary = trials[i]
		results.text += "\n%d. %s%s\n힘 %.0f%% · 목표 %.0f° → 실제 %.1f° · 날개 %.0f° / %.0f°\n정지확정 거리 %.2fm / %.2fs · 바람 %.1fm/s\n" % [i + 1, _contact_summary(record.get("first_contact", {})), " · 기체/용지/부위 변경 전" if not _same_aircraft(record) else "", record.launch_power, record.target_aim_degrees.y, record.aim_degrees.y, record.angles.x, record.angles.y, record.distance_m, record.duration_s, record.wind_velocity.length()]
		if i > 0:
			var previous: Dictionary = trials[i - 1]
			var changes := PackedStringArray()
			if record.launch_power != previous.launch_power: changes.append("힘")
			if record.target_aim_degrees != previous.target_aim_degrees: changes.append("목표각")
			if record.angles != previous.angles: changes.append("날개")
			if record.launch_transform.basis != previous.launch_transform.basis: changes.append("기체 자세")
			if record.launch_transform.origin.distance_to(previous.launch_transform.origin) > 0.05: changes.append("발사 위치")
			if record.wind_velocity != previous.wind_velocity: changes.append("바람")
			if not _same_aircraft(record) or not _same_aircraft(previous): changes.append("기체/용지/부위 · 참고 비교")
			results.text += "바꾼 조건: " + (", ".join(changes) if not changes.is_empty() else "없음") + "\n"
			var contact: Dictionary = record.get("first_contact", {})
			var before: Dictionary = previous.get("first_contact", {})
			if _same_aircraft(record) and _same_aircraft(previous) and contact.has("error_m") and before.has("error_m") and contact.target == before.target:
				results.text += "직전 대비 중심 오차 %+.2fm (−는 가까워짐)\n" % (contact.error_m - before.error_m)
	result_button.text = "결과 (%d)" % trials.size()

func _draw_previous() -> void:
	if previous_trail.get_parent() == null: return
	previous_trail.mesh = null
	_draw_contact_marker({})
	if trials.is_empty() or not _same_aircraft(trials[-1]): return
	_draw_contact_marker(trials[-1].get("first_contact", {}))
	var points: PackedVector3Array = trials[-1].get("trajectory", PackedVector3Array())
	if points.size() < 2: return
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in points: lines.surface_add_vertex(point)
	lines.surface_end()
	previous_trail.mesh = lines
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = Color("e7ab60")
	previous_trail.material_override = ink

func _layout_hud() -> void:
	super._layout_hud()
	elevation_value.get_parent().visible = not released
	wind_reset.get_parent().visible = not released
	if released:
		var size := get_viewport().get_visible_rect().size
		gauge_panel.size.y = 104
		gauge_panel.position.y = size.y - 116
		wind_hud.size.y = 70
		wind_hud.position.y = size.y - 116
		gauge_track.hide()
		gauge_cancel.hide()

func _process(delta: float) -> void:
	if body == null: return
	if not released and gauge_stage == 0 and not target_locked:
		_read_target()
		var preview_transform := Transform3D(Basis(Vector3.UP, launch_yaw) * attitude, launch_origin)
		if not body.transform.is_equal_approx(preview_transform):
			body.transform = preview_transform
			body.reset_physics_interpolation()
		_update_metrics()
		_update_launch_arrow()
	if watching:
		super._process(delta)
		if not released and gauge_stage == 0:
			gauge_label.text = ("4m 표적 연습" if not park.practice_target().is_empty() else ("자유 투척 · 연습은 시작선에서" if park.practice_active else "자유 투척")) + " · Space로 강도 선택"
			if adjust_panel.visible: elevation_hint.text = "↑↓ / −+ : 고도각\n우클릭: 시점만 회전"
		if released:
			launch_button.disabled = not landed
			launch_button.text = "공원으로 돌아가기 [B / Esc]" if landed else "비행 중 · B로 관람 종료"
			gauge_track.hide()
			gauge_cancel.hide()
			elevation_down.disabled = true
			elevation_up.disabled = true
			elevation_hint.text = "실제 발사 %+.1f°" % effective_elevation()
			if landed and not trials.is_empty():
				gauge_label.text = _contact_summary(first_contact)
			elif not first_contact.is_empty(): gauge_label.text = _contact_summary(first_contact) + " · 정지 대기"
			gauge_panel.tooltip_text = "B로 공원 복귀 · Esc는 열린 창을 먼저 닫습니다."
	else:
		hud.hide()
		results_overlay.hide()
		gizmo.hide()

func _update_camera() -> void:
	if not watching or body == null: return
	if released or adjust_panel.visible:
		camera.fov = 48
		follow_distance = maxf(1.2, preview_distance * 1.5)
		super._update_camera()
	else:
		camera.fov = 48
		# Look forward from behind and slightly above the paper without changing the throw target.
		var view_pitch := clampf(park.view_angles.y - deg_to_rad(15), deg_to_rad(-45), deg_to_rad(-12))
		camera.global_basis = Basis(Vector3.UP, park.view_angles.x) * Basis(Vector3.RIGHT, view_pitch)
		var viewport := get_viewport().get_visible_rect().size
		var top := metrics.position.y + metrics.size.y + 12
		var bottom := minf(gauge_panel.position.y, wind_hud.position.y) - 10
		var center_fraction := (top + bottom) * 0.5 / viewport.y
		var tangent := tan(deg_to_rad(camera.fov * 0.5))
		var horizontal := tangent * viewport.x / viewport.y
		var vertical_ratio := (center_fraction - 0.5) * 2 * tangent
		var left := 24.0 / viewport.x - 0.5
		var right := 0.5 - 24.0 / viewport.x
		var upper := 0.5 - top / viewport.y
		var lower := 0.5 - bottom / viewport.y
		var fit := 0.45
		# Fit the actual oriented vertices, rather than a sphere that hides small folded aircraft.
		for face in posed:
			for point in face.points:
				var relative: Vector3 = camera.global_basis.inverse() * (body.global_basis * (point - properties.center))
				fit = maxf(fit, relative.z + 0.04)
				fit = maxf(fit, (relative.x + right * 2 * horizontal * relative.z) / maxf(0.01, right * 2 * horizontal))
				fit = maxf(fit, (-relative.x - left * 2 * horizontal * relative.z) / (-left * 2 * horizontal))
				fit = maxf(fit, (relative.y + upper * 2 * tangent * relative.z) / maxf(0.01, upper * 2 * tangent + vertical_ratio))
				fit = maxf(fit, (-relative.y - lower * 2 * tangent * relative.z) / maxf(0.01, -vertical_ratio - lower * 2 * tangent))
		var distance := maxf(0.06, fit * clampf(park.zoom / 4.0, 0.375, 2.25))
		var up_shift := (center_fraction - 0.5) * 2 * tangent * distance
		# Keep the physical plane fixed; the arrow and target values show the actual throw direction.
		camera.global_position = body.global_position + camera.global_basis * Vector3(0, up_shift, distance)

func grip_position() -> Vector3:
	return body.global_transform * AircraftVisual.grip_offset(posed, faces, history, binding, properties.center)

func _update_metrics() -> void:
	if body == null: return
	var distance := Vector2(body.position.x - launch_origin.x, body.position.z - launch_origin.z).length()
	metrics.text = "%s · %.2fg · 거리 %.2fm / %.2fs%s" % [Stock.summary(paper_stock), body.mass * 1000, distance, elapsed, " · 이전 궤적: 주황" if previous_trail.mesh != null else ""]

func _update_launch_arrow() -> void:
	if not is_inside_tree(): return
	super._update_launch_arrow()
	launch_arrow.position = launch_origin - LAUNCH
	launch_arrow.visible = not released

func _input(event: InputEvent) -> void:
	if not watching: return
	if event is InputEventKey and not event.pressed: launch_keys.erase(event.physical_keycode)
	if results_panel.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_escape()
		return
	if event is InputEventMouseMotion and dragging:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			gizmo.update_drag(event.position, event.shift_pressed)
			get_viewport().set_input_as_handled()
		else:
			dragging = false
			gizmo.end_drag()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = false
		gizmo.end_drag()
	if event is InputEventKey and not event.pressed: launch_keys.erase(event.physical_keycode)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		camera_dragging = false
	if event is InputEventMouseMotion and camera_dragging:
		if released or adjust_panel.visible:
			camera_angles.x -= event.relative.x * 0.008
			camera_angles.y = clampf(camera_angles.y + event.relative.y * 0.008, -1.3, 1.3)
		elif gauge_stage == 0:
			park.rotate_view(event.relative)
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_escape()

func _unhandled_input(event: InputEvent) -> void:
	if not watching: return
	if results_panel.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_B: closed.emit()
		elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE: _escape()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.physical_keycode in [KEY_UP, KEY_DOWN]:
		_aim_changed(1, aim.y + (1 if event.physical_keycode == KEY_UP else -1))
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		if event.physical_keycode == KEY_D and event.ctrl_pressed and event.shift_pressed: park.dump_state()
		elif event.physical_keycode == KEY_B: closed.emit()
		elif event.physical_keycode in [KEY_SPACE, KEY_ENTER] and not results_panel.visible and not released:
			if not launch_keys.has(event.physical_keycode):
				launch_keys[event.physical_keycode] = true
				_advance_gauge()
		elif event.physical_keycode in [KEY_W, KEY_A, KEY_S, KEY_D] and not released and gauge_stage == 0 and not adjust_panel.visible and not results_panel.visible:
			park.move_keys[event.physical_keycode] = true
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			camera_dragging = gauge_stage == 0 or released
			get_viewport().set_input_as_handled()
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var factor := 0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.9
			if released or adjust_panel.visible: camera_zoom = clampf(camera_zoom * factor, 0.35, 8)
			elif gauge_stage == 0: park.zoom = clampf(park.zoom * factor, 1.5, 9)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT and adjust_panel.visible and not released and gauge_stage == 0:
			dragging = gizmo.begin_drag(event.position)
	elif event is InputEventMouseMotion and dragging:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT: gizmo.update_drag(event.position, event.shift_pressed)
		else: dragging = false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = false
		gizmo.end_drag()

func _escape() -> void:
	if results_panel.visible: _toggle_results()
	elif adjust_panel.visible: _toggle_adjust()
	elif gauge_stage != 0: _cancel_gauge()
	else: closed.emit()

func _set_attitude(value: Basis) -> void:
	if gizmo.selected_axis >= 0:
		value = Basis(Vector3.UP, launch_yaw).inverse() * value
	super._set_attitude(value)

func snapshot() -> Dictionary:
	var result := super.snapshot()
	result["launch_transform"] = launched.launch_transform if released else Transform3D(Basis(Vector3.UP, launch_yaw) * attitude, launch_origin)
	result["aim_degrees"] = Vector2(aim.x, effective_elevation())
	result["released"] = released
	result["landed"] = landed
	result["watching"] = watching
	result["first_contact"] = first_contact.duplicate(true)
	result["practice_target"] = launch_target.duplicate(true)
	return result
