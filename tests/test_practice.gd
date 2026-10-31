extends "res://tests/test_park.gd"

var sounds: Dictionary = {}

func heard(event: String) -> void:
	sounds[event] = sounds.get(event, 0) + 1

func walk(park: Node, target: Vector3) -> void:
	park.view_angles.x = 0
	for i in 2400:
		var delta: Vector3 = target - park.player.position
		if Vector2(delta.x, delta.z).length() < 0.25: break
		park.move_keys.clear()
		if absf(delta.x) > 0.1: park.move_keys[KEY_D if delta.x > 0 else KEY_A] = true
		if absf(delta.z) > 0.1: park.move_keys[KEY_S if delta.z > 0 else KEY_W] = true
		await physics_frame
	park.move_keys.clear()
	await layout()
	check(Vector2(target.x - park.player.position.x, target.z - park.player.position.z).length() < 0.4, "Player physically walks to pickup/start without teleporting the aircraft")

func run() -> void:
	var audio: Node = root.get_node("Audio")
	audio.sfx_played.connect(heard)
	var measurements: Array = []
	for size in [Vector2i(1280, 720), Vector2i(640, 360)]:
		root.size = size
		var park: Node = load("res://scenes/park.tscn").instantiate()
		root.add_child(park)
		buy_fixture(park)
		await layout()
		var shape: String = JSON.stringify(Dump.encode(park.items[FOUND_ID].sheet))
		park.toggle_practice()
		check(not park.practice_active and park.items.size() == 2, "Far participation only guides the player and creates no item")
		# Setup position only; the repeated pickup/start loop below uses actual character physics.
		park.player.position = Vector3(2.5, 0.01, -1.6)
		await layout()
		park.recover_item(FOUND_ID)
		await layout()
		check(park.inspection != null and park.items[FOUND_ID].state == "inspecting", "Existing discovered plane still requires inspection and a processing choice")
		park.inspection.action_buttons[0].pressed.emit()
		await layout()
		await tap(KEY_TAB)
		park.take_button.pressed.emit()
		await layout()
		check(park.held_id == FOUND_ID and park.items.size() == 2, "Practice uses the same existing discovered aircraft")
		await walk(park, park.PRACTICE_START)
		await tap(KEY_T)
		check(park.practice_active and not park.practice_target().is_empty(), "Participation at the physical start line enables one target")
		await capture("practice_start_" + str(size.x))
		var previous_global := 0
		for attempt in 3:
			park.view_angles = Vector2(0, deg_to_rad(10))
			await tap(KEY_SPACE)
			await layout()
			var flight: Node = park.active_flight
			check(flight.trials.size() == attempt, "Same aircraft restores prior trial history")
			if attempt > 0: check(flight.previous_trail.mesh != null, "Previous world-space trajectory is restored in amber")
			flight._angle_changed(0, 110 if attempt == 1 else 90)
			flight.set_process(false)
			await tap(KEY_SPACE)
			flight.gauge_phase = (60.0 - 1) / 99
			flight._process(0)
			await tap(KEY_SPACE)
			flight._process((1 - flight.gauge_cursor) / flight.POWER_SPEED + 1.0 / flight.IMPACT_SPEED)
			check(flight.gauge_stage == 2 and flight.gauge_returning, "Three-input gauge still travels to the far end before returning")
			flight.gauge_cursor = 0
			var land_sounds: int = sounds.get("land", 0)
			await tap(KEY_SPACE)
			flight.set_process(true)
			await layout()
			check(flight.released and flight.launched.origin_width_px == 20 and is_equal_approx(flight.launch_origin.y, 1.7), "Actual release keeps gauge and physical launch height")
			check(flight.gauge_panel.size.y < 120 and not flight.elevation_value.get_parent().visible, "In-flight view collapses the large input controls")
			var frame := Rect2(Vector2.ZERO, Vector2(size))
			check(frame.encloses(flight.gauge_panel.get_global_rect()) and not flight.gauge_panel.get_global_rect().intersects(flight.wind_hud.get_global_rect()), "Compact viewing and wind controls fit both resolutions")
			if attempt == 0: await capture("practice_flight_" + str(size.x))
			for i in 3600:
				await physics_frame
				if flight.landed: break
			await layout()
			check(flight.landed and not flight.first_contact.is_empty(), "Real physics supplies a tagged ground contact before settling")
			if not flight.landed or flight.first_contact.is_empty(): quit(1); return
			var contact: Dictionary = flight.first_contact
			check(flight.contact_marker.mesh != null and Vector2(flight.contact_marker.position.x - contact.position.x, flight.contact_marker.position.z - contact.position.z).length() < 0.00001 and flight.contact_marker.position.y > contact.position.y, "A fixed world marker shows the actual first contact XZ above the surface")
			check(contact.time_s <= flight.elapsed and absf(contact.position.y) < 0.05, "Contact timestamp and collider world position refer to the actual floor")
			check(contact.success == (contact.error_m <= park.PRACTICE_RADIUS), "Practice uses first contact error and the launch-time radius")
			var record: Dictionary = flight.trials[-1]
			check(record.first_contact == contact and record.practice_target == contact.target and record.trajectory.size() > 2, "Trial freezes target, first contact and real trajectory")
			measurements.append({"window":size, "attempt":attempt, "record":record})
			previous_global += 1
			flight._finish("착지")
			check(park.trials.size() == previous_global, "Restoring or finishing twice never duplicates global trials")
			check(sounds.get("land", 0) == land_sounds + 1, "First contact and settling together play landing sound exactly once")
			flight._toggle_results()
			await layout()
			check(frame.encloses(flight.results_panel.get_global_rect()), "Three-trial comparison modal fits")
			if attempt > 0: check(flight.results.text.contains("날개") and flight.results.text.contains("바꾼 조건"), "Comparison identifies the one changed variable without causal advice")
			await capture("practice_results_%d_%d" % [attempt, size.x])
			await tap(KEY_ESCAPE)
			check(park.active_flight == flight and not flight.results_panel.visible, "Escape first closes only the comparison modal")
			await tap(KEY_B)
			var landed_position: Vector3 = flight.body.position
			await walk(park, landed_position)
			await tap(KEY_E)
			await layout()
			check(park.held_id == FOUND_ID and park.items[FOUND_ID].state == "hand" and park.items[FOUND_ID].flight == null, "Real E recovery puts the same item directly in hand")
			check(park.items.size() == 2 and JSON.stringify(Dump.encode(park.items[FOUND_ID].sheet)) == shape, "Repeated practice preserves material, history, ID and quantity")
			await walk(park, park.PRACTICE_START)
		check(park.items[FOUND_ID].flight_session.trials.size() == 3 and park.trials.size() == 3, "Exactly three item and global records survive the loop")
		var original_sheet: Dictionary = park.items[FOUND_ID].sheet
		park.items[FOUND_ID].sheet = park.items[OWN_ID].sheet.duplicate(true)
		park.prepare_throw()
		await layout()
		check(park.active_flight.trials.size() == 3 and park.active_flight.previous_trail.mesh == null and park.active_flight.results.text.contains("기체/용지/부위 변경 전"), "Changed geometry keeps labeled history without presenting its path as the same aircraft configuration")
		park.exit_flight()
		park.items[FOUND_ID].sheet = original_sheet
		await layout()
		# A first miss cannot become success by rolling into the target later.
		park.prepare_throw()
		await layout()
		var probe: Node = park.active_flight
		probe.launch()
		probe.body.freeze = true
		probe.set_physics_process(false)
		probe._record_first_contact(park.PRACTICE_CENTER + Vector3(2, 0, 0), 1)
		var marker_position: Vector3 = probe.contact_marker.position
		probe.body.position = park.PRACTICE_CENTER
		probe._record_first_contact(park.PRACTICE_CENTER, 2)
		check(not probe.first_contact.success and is_equal_approx(probe.first_contact.error_m, 2), "Rolling into the ring cannot replace the first miss")
		check(probe.contact_marker.position == marker_position, "First-contact marker never follows the rolling aircraft")
		park.practice_active = false
		check(not probe.first_contact.target.is_empty(), "Leaving practice cannot rewrite a launched target")
		await tap(KEY_B)
		# Own-item recovery safely stores a different already-held physical item.
		probe.landed = true
		park.items[FOUND_ID].state = "world"
		await walk(park, probe.body.position)
		park.selected_id = OWN_ID
		park._take_selected()
		park.recover_item(FOUND_ID)
		check(park.held_id == FOUND_ID and park.items[OWN_ID].state == "stored" and park.items.size() == 2, "Another held sheet is safely stored when recovering the same plane")
		park.prepare_throw()
		await layout()
		var fresh: Node = park.active_flight
		fresh._record_first_contact(park.PRACTICE_CENTER, 0)
		fresh._finish("착지")
		check(fresh.first_contact.is_empty() and park.trials.size() == 3, "Preparation and cancellation cannot create a target success or record")
		park.exit_flight()
		await layout()
		park.player.position = park.PRACTICE_START
		park.practice_active = true
		park.prepare_throw()
		await layout()
		fresh = park.active_flight
		fresh.launch()
		fresh.body.freeze = true
		fresh.set_physics_process(false)
		fresh._finish("착지")
		check(fresh.trials[-1].first_contact.is_empty() and fresh.results.text.contains("판정 불가"), "Missing ground observation is not replaced by the final stop")
		check(fresh.trials.size() == 3 and park.trials.size() == 4 and fresh.contact_marker.mesh == null, "Fourth record caps item history at three without inventing a new contact marker")
		park.exit_flight()
		await layout()
		park.player.position = park.PRACTICE_CENTER
		check(park.practice_target().is_empty(), "Outside the start area remains free throw even while practice is enabled")
		park.queue_free()
		await layout()
	var file := FileAccess.open("res://build/practice_measurements.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(Dump.encode(measurements), "\t"))
	print("PAP practice: %d checks, %d failures" % [checks, failures])
	await audio.stop_all()
	quit(1 if failures else 0)
