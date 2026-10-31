extends "res://tests/test_park.gd"

var sounds: Dictionary = {}

func heard(event: String) -> void:
	sounds[event] = sounds.get(event, 0) + 1

func count(event: String) -> int:
	return sounds.get(event, 0)

func click_at(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await layout()

func run() -> void:
	var audio: Node = root.get_node("Audio")
	audio.sfx_played.connect(heard)
	check(audio.voices.size() == 8 and audio.streams.size() == 15, "One audio service owns bounded SFX voices and all event streams")
	for event in audio.streams:
		for clip in audio.streams[event]: check(clip != null and clip.get_length() > 0, "Every shipped sound decodes")
	var music: AudioStreamPlayer = audio.music
	var music_id := music.get_instance_id()
	var music_position := music.get_playback_position()
	check(music.stream != null and music.stream.loop, "Shared music is a real looping stream")
	var settings_path: String = audio.settings_path
	var old_volumes: Dictionary = audio.volumes.duplicate()
	var old_muted: Dictionary = audio.muted.duplicate()
	audio.settings_path = "res://build/audio_settings_test.cfg"
	audio.set_volume("Music", 0.25)
	audio.set_volume("SFX", 0.65)
	audio.set_muted("Music", true)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")) and not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "Music and SFX mute independently")
	var config := ConfigFile.new()
	check(config.load(audio.settings_path) == OK and config.get_value("Music", "muted") and is_equal_approx(config.get_value("SFX", "volume"), 0.65), "Only audio settings persist")
	for bus in old_volumes:
		audio.set_volume(bus, old_volumes[bus])
		audio.set_muted(bus, old_muted[bus])
	audio.settings_path = settings_path
	for size in [Vector2i(1280, 720), Vector2i(640, 360)]:
		root.size = size
		var park: Node = load("res://scenes/park.tscn").instantiate()
		root.add_child(park)
		await layout()
		check(audio.music.get_instance_id() == music_id, "New parks and discovered bodies never duplicate music")
		park.selected_id = 1
		park._take_selected()
		var takes := count("take")
		park.player.position = Vector3(4, 0.01, 1)
		park.prepare_throw()
		await layout()
		var flight: Node = park.active_flight
		var pitch: float = park.view_angles.y
		await tap(KEY_UP)
		await layout()
		check(absf(flight.aim.y - rad_to_deg(pitch) - 1) < 0.001 and absf(park.view_angles.y - deg_to_rad(flight.aim.y)) < 0.00001, "Up key updates persistent park target rather than temporary HUD text")
		flight.elevation_up.pressed.emit()
		await layout()
		check(flight.elevation_value.get_theme_font_size("font_size") >= 28 and flight.elevation_value.text.contains("°") and flight.elevation_hint.text.contains("↑↓"), "Large elevation readout names its actual controls")
		var frame := Rect2(Vector2.ZERO, Vector2(size))
		for control in [flight.elevation_value, flight.elevation_up, flight.elevation_down, flight.elevation_hint, flight.gauge_panel, flight.wind_hud]:
			check(frame.encloses(control.get_global_rect()), "Throw and wind HUD fit the viewport")
		check(not flight.gauge_panel.get_global_rect().intersects(flight.wind_hud.get_global_rect()), "Wind and throw controls do not overlap")
		await capture("hud_ready_" + str(size.x))
		flight.camera_dragging = true
		flight._toggle_results()
		await layout()
		check(flight.results_overlay.visible and not flight.camera_dragging and flight.results_panel.get_parent() == flight.results_overlay and flight.results_overlay.z_index > flight.topbar.z_index, "Opening results cancels dragging and uses the front modal layer")
		check(frame.encloses(flight.results_panel.get_global_rect()), "Results panel and its close control fit")
		var aim: Vector2 = flight.aim
		var camera_angles: Vector2 = flight.camera_angles
		await click_at(flight.adjust_button.get_global_rect().get_center())
		await tap(KEY_UP)
		await tap(KEY_SPACE)
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		wheel.position = Vector2(6, 6)
		Input.parse_input_event(wheel)
		await layout()
		check(flight.results_panel.visible and not flight.adjust_panel.visible and flight.gauge_stage == 0 and flight.aim == aim and flight.camera_angles == camera_angles, "Modal blocks underlying clicks, elevation, camera and launch input")
		await capture("hud_results_" + str(size.x))
		await tap(KEY_ESCAPE)
		check(not flight.results_panel.visible and park.active_flight == flight, "First Escape only closes results")
		var gauge_count := count("gauge")
		await tap(KEY_SPACE)
		check(flight.gauge_stage == 1 and count("gauge") == gauge_count + 1 and flight.elevation_up.disabled, "Gauge starts once and locks elevation")
		key(KEY_SPACE, true, true)
		await process_frame
		key(KEY_SPACE, false)
		check(flight.gauge_stage == 1 and count("gauge") == gauge_count + 1, "Held key repeat cannot advance or sound twice")
		await tap(KEY_SPACE)
		check(flight.gauge_stage == 2, "Second fresh input chooses power")
		flight.gauge_returning = true
		flight.gauge_cursor = 0
		var throws := count("throw")
		var impacts := count("impact")
		await tap(KEY_SPACE)
		check(flight.released and count("throw") == throws + 1 and count("impact") == impacts + 1, "Actual release plays throw and timing once")
		flight.launch()
		check(count("throw") == throws + 1, "Duplicate release is silent")
		flight._toggle_results()
		var landings := count("land")
		for i in 2400:
			if flight.landed: break
			await physics_frame
		await layout()
		check(flight.landed and flight.results_panel.visible and flight.trials.size() == 1 and count("land") == landings + 1, "Physics continues under results and first landing records and sounds once")
		flight._finish("착지")
		check(flight.trials.size() == 1 and count("land") == landings + 1, "Repeated landing cannot duplicate record or sound")
		await capture("hud_landed_results_" + str(size.x))
		await tap(KEY_ESCAPE)
		await capture("hud_landed_" + str(size.x))
		await tap(KEY_B)
		check(count("land") == landings + 1 and count("take") == takes, "View exit is not landing or automatic pickup")
		park.player.position = flight.body.position
		var recoveries := count("recover")
		park.recover_item(1)
		park.recover_item(1)
		await layout()
		check(count("recover") == recoveries + 1 and park.items[1].state == "hand" and park.held_id == 1, "Successful recovery sounds once and returns the same item to hand")
		check(audio.music.get_instance_id() == music_id, "Scene round trips retain one music player")
		park.queue_free()
		await layout()
	var folding: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(folding)
	await layout()
	folding.fold_plan = Paper.plan(folding.faces, Vector2.ZERO, Vector2.UP, Vector2(0.05, 0))
	var folds := count("fold")
	folding._finish_commit()
	check(count("fold") == folds + 1 and folding.fold_count == 1, "Only committed geometry plays folding sound")
	folding.preset_store = Presets.new("res://build/hud_audio_presets")
	var saves := count("save")
	folding._save_preset("audio", true)
	check(count("save") == saves + 1, "Successful diagram save plays confirmation")
	folding._save_preset("", false)
	check(count("save") == saves + 1 and count("error") > 0, "Failed save never plays success")
	folding.queue_free()
	await layout()
	var walker: Node = load("res://scenes/park.tscn").instantiate()
	root.add_child(walker)
	await layout()
	walker.player.position = Vector3(4, 0.01, 1)
	for i in 8: await physics_frame
	var steps := count("step")
	key(KEY_W)
	for i in 120: await physics_frame
	key(KEY_W, false)
	check(count("step") > steps, "Grounded actual walking plays spaced footsteps")
	steps = count("step")
	for i in 120: await physics_frame
	check(count("step") == steps, "Standing still does not play footsteps")
	walker._box(walker.player.position + Vector3(0.5, 1, 0), Vector3(0.2, 2, 4), Color.WHITE)
	key(KEY_D)
	for i in 100: await physics_frame
	steps = count("step")
	for i in 120: await physics_frame
	check(count("step") == steps, "Pushing against a blocking wall does not play footsteps")
	key(KEY_D, false)
	walker._toggle_inventory()
	steps = count("step")
	key(KEY_W)
	for i in 120: await physics_frame
	key(KEY_W, false)
	check(count("step") == steps, "Open inventory suppresses walking sounds")
	walker.queue_free()
	await layout()
	var blocked_park: Node = load("res://scenes/park.tscn").instantiate()
	root.add_child(blocked_park)
	await layout()
	blocked_park._take_selected()
	blocked_park.player.position = Vector3(4, 0.01, 1)
	blocked_park.prepare_throw()
	await layout()
	var blocked_flight: Node = blocked_park.active_flight
	blocked_flight._advance_gauge()
	await process_frame
	blocked_flight._advance_gauge()
	blocked_flight.gauge_returning = true
	blocked_flight.gauge_cursor = 0
	blocked_park._box(blocked_flight.body.position, Vector3(0.5, 0.5, 0.5), Color.WHITE)
	await physics_frame
	var before_throw := count("throw")
	var before_impact := count("impact")
	var before_error := count("error")
	blocked_flight._commit_impact(false)
	check(not blocked_flight.released and count("throw") == before_throw and count("impact") == before_impact and count("error") == before_error + 1, "Blocked timing input plays failure without release or timing success")
	blocked_park.queue_free()
	await layout()
	if AudioServer.get_driver_name() != "Dummy": check(music.playing and music.get_playback_position() > music_position, "Shared BGM keeps advancing through all scene round trips")
	print("PAP HUD/audio: %d checks, %d failures" % [checks, failures])
	await audio.stop_all()
	quit(1 if failures else 0)
