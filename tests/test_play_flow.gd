extends SceneTree
const Dump := preload("res://scripts/paper_dump.gd")
const Stock := preload("res://scripts/paper_stock.gd")
const Paper := preload("res://scripts/paper_geometry.gd")
const Parts := preload("res://scripts/flight_parts.gd")
const Presets := preload("res://scripts/paper_presets.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func layout() -> void:
	for i in 4: await process_frame

func capture(name: String) -> void:
	await layout()
	if "--screenshots" not in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/previews")
	root.get_texture().get_image().save_png("res://build/previews/flow_" + name + ".png")

func click(button: Button) -> void:
	check(button.is_visible_in_tree() and not button.disabled, "Action must be visible and enabled")
	button.pressed.emit()
	await layout()

func run() -> void:
	for size in [Vector2i(1280, 720), Vector2i(640, 360)]:
		root.size = size
		var app: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(app)
		await layout()
		var frame := Rect2(Vector2.ZERO, Vector2(size))
		var fixture: Dictionary = Dump.decode(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/wing_surface_overlap.json")))
		var normalized := {"faces": fixture.faces, "history": fixture.history, "fold_count": 8, "reference": {}}
		normalized.fold_count = 0
		for step in fixture.history:
			if step.kind == "fold": normalized.fold_count += 1
		check(Presets._validate_state(normalized).is_empty(), "Fixture must normalize nested native arrays")
		app.faces.assign(normalized.faces)
		app.history.assign(normalized.history)
		app.fold_count = 0
		for step in app.history:
			if step.kind == "fold": app.fold_count += 1
		if Stock.read(app.paper_stock, app.faces).is_empty(): app.paper_stock = Stock.legacy(app.faces)
		app._refresh()
		await capture("01_folding_" + str(size.x))
		check(frame.encloses(app.flight_button.get_global_rect()), "Folding primary must fit")
		var primary_bottom: float = app.flight_button.get_global_rect().end.y
		await click(app.parts_button)
		check(app.parts_editor.visible, "Parts button must open optional role selection")
		for button in [app.parts_editor.confirm, app.parts_editor.continue_button, app.parts_editor.close_button]:
			check(frame.encloses(button.get_global_rect()), "All part completion actions must remain visible without scrolling")
		app.parts_editor._highlight(2)
		check(app.parts_editor.selectors[2].visible and not app.parts_editor.selectors[0].visible, "Role tab must expose only its candidate")
		await capture("02_parts_" + str(size.x))
		await click(app.parts_editor.confirm)
		check(app.flight_view != null and Parts.valid(app.flight_parts, app.faces, app.history), "One confirmation click must enter flight with explicit parts")
		if app.flight_view == null:
			app.queue_free()
			quit(1)
			return
		var flight: Node = app.flight_view
		check(flight.gauge_stage == 0 and not flight.running, "Entering preparation must not accidentally start a gauge")
		check(absf(flight.launch_button.get_global_rect().end.y - primary_bottom) <= 1, "Primary bottom must stay fixed between folding and flight")
		flight._aim_changed(1, 12)
		flight._set_wind(Vector3(-0.2, 0, 1.5))
		flight.linked.button_pressed = false
		flight._angle_changed(0, 75)
		flight._angle_changed(1, 105)
		flight._pose_axis_changed(2, 8)
		flight.camera_angles += Vector2(0.2, 0.1)
		flight.camera_zoom = 1.3
		await capture("03_preparation_" + str(size.x))
		var button_rect: Rect2 = flight.launch_button.get_global_rect()
		await click(flight.launch_button)
		check(flight.gauge_stage == 1 and not flight.running, "One main click must start exactly one gauge stage")
		flight.result_button.pressed.emit()
		check(flight.gauge_stage == 1 and not flight.results_panel.visible and flight.result_button.disabled, "Results cannot silently cancel a live gauge")
		flight._process(0.7)
		await capture("04_power_" + str(size.x))
		await click(flight.launch_button)
		check(flight.gauge_stage == 2 and not flight.running, "Strength click must not launch")
		check(not flight.gauge_returning and flight.launch_button.disabled, "Ascent selection must wait for the end before accepting impact")
		await capture("05_wait_" + str(size.x))
		flight._process(2.2)
		check(flight.gauge_returning and not flight.running, "Cursor must reach the end before returning")
		flight.gauge_cursor = 0
		await capture("06_origin_" + str(size.x))
		check(flight.launch_button.get_global_rect() == button_rect, "State labels must not move the primary action")
		flight.gauge_cursor = 0
		flight.launch_button.pressed.emit()
		check(flight.running, "Final timing input must perform the actual launch")
		var count: int = flight.trials.size()
		flight.launch_button.pressed.emit()
		check(flight.running and flight.trials.size() == count, "Duplicate input must not launch twice")
		await capture("07_flight_" + str(size.x))
		for i in 3000:
			if not flight.running: break
			await physics_frame
		check(not flight.running and flight.trials.size() == count + 1 and flight.trials[-1].reason == "착지", "Real physics must land and append exactly one result")
		check("다시 던지기" in flight.launch_button.text and "직전" in flight.gauge_label.text, "Landing must expose retry with nearby distance and duration")
		await capture("08_landing_" + str(size.x))
		var record: Dictionary = flight.trials[-1].duplicate(true)
		await click(flight.result_button)
		check(flight.results_panel.visible and flight.results.text.find("거리") < flight.results.text.find("강도"), "Results must prioritize distance and duration")
		for button in [flight.result_retry]:
			check(frame.encloses(button.get_global_rect()), "Result continuation must fit small windows")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_SPACE
		key.pressed = true
		Input.parse_input_event(key)
		await process_frame
		key.pressed = false
		Input.parse_input_event(key)
		await process_frame
		check(flight.gauge_stage == 0 and not flight.running, "Result popup must absorb ordinary launch keys")
		await capture("09_results_" + str(size.x))
		await click(flight.result_retry)
		check(flight.gauge_stage == 1 and not flight.results_panel.visible and not flight.running and flight.elapsed == 0, "Result retry must return to launch and start gauge in one click")
		await capture("10_retry_" + str(size.x))
		var saved: Dictionary = flight.session_state()
		var back := InputEventKey.new()
		back.physical_keycode = KEY_B
		back.pressed = true
		Input.parse_input_event(back)
		await layout()
		back.pressed = false
		Input.parse_input_event(back)
		await layout()
		check(app.flight_view == null, "B must return to folding without the same key reopening flight")
		await capture("11_back_to_folding_" + str(size.x))
		app._open_parts()
		await layout()
		await click(app.parts_editor.confirm)
		flight = app.flight_view
		check(flight.aim == saved.aim and flight.launch_power == saved.launch_power and flight.body.wind_velocity == saved.wind, "Role roundtrip must preserve elevation, power and exact wind")
		check(flight.attitude == saved.attitude and flight.angles == saved.angles, "Same aircraft roundtrip must preserve manual pose and wings")
		check(flight.camera_angles == saved.camera_angles and flight.camera_zoom == saved.camera_zoom, "Roundtrip must preserve camera and zoom")
		check(flight.gauge_stage == 0 and not flight.running and not flight.automatic_miss, "Gauge state and automatic launch cannot resume across screens")
		check(flight.trials[-1] == record, "Past trial conditions must remain unchanged")
		app._close_flight()
		app._undo()
		app._open_flight()
		await layout()
		flight = app.flight_view
		check(flight.aim == saved.aim and flight.body.wind_velocity == saved.wind and flight.trials[-1] == record, "Geometry changes must preserve global conditions and immutable records")
		check("기체 수정 전" in flight.results.text, "Old aircraft records must be identified after editing")
		check(flight.binding.is_empty() and "기체/부위 변경" in flight.gauge_label.text, "Stale binding must fall back with a visible pose reset reason")
		await capture("12_modified_" + str(size.x))
		app._close_flight()
		app.preset_store = Presets.new("res://build/flow_presets_" + str(size.x))
		app._show_presets()
		app.preset_name.text = "flow_" + str(Time.get_ticks_usec())
		await layout()
		await click(app.preset_save)
		check(not app.preset_shade.visible and "저장됨" in app.dump_notice.text, "Successful save must notify without blocking the next action")
		await capture("13_saved_" + str(size.x))
		check(absf(app.flight_button.get_global_rect().end.y - primary_bottom) <= 1, "Save notification must not displace the primary action")
		app._show_presets()
		app._request_preset_save()
		check(app.preset_pending.get("kind") == "save" and app.preset_fly.disabled, "Overwrite must still require explicit confirmation and disable fly exit")
		var pending: Dictionary = app.preset_pending.duplicate(true)
		app.preset_fly.pressed.emit()
		check(app.flight_view == null and app.preset_pending == pending, "Fly must not bypass data protection")
		app.preset_cancel.pressed.emit()
		app._hide_presets()
		for filename in DirAccess.get_files_at(app.preset_store.folder): DirAccess.remove_absolute(app.preset_store.folder.path_join(filename))
		DirAccess.remove_absolute(app.preset_store.folder)
		root.remove_child(app)
		app.queue_free()
		await layout()
	print("PAP flow: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
