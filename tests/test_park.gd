extends "res://tests/test_defaults.gd"

func key(code: Key, pressed: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)

func tap(code: Key) -> void:
	key(code)
	await process_frame
	key(code, false)
	await process_frame

func invariant(park: Node) -> void:
	var hands := 0
	var workers := 0
	for id in park.items:
		var item: Dictionary = park.items[id]
		check(item.state in ["stored", "hand", "work", "flying", "world"], "Each physical item has one supported state")
		if item.state == "hand":
			hands += 1
			check(park.held_id == id and item.flight == null, "Hand ownership is exclusive")
		if item.state == "work": workers += 1
		if item.state in ["stored", "work"]: check(item.flight == null, "Stored/work item has no world duplicate")
		if item.state in ["world", "flying"]: check(item.flight != null and is_instance_valid(item.flight), "World item retains its one physics body")
	check(hands <= 1 and workers <= 1, "Only one item can be held or edited")

func run() -> void:
	for window in [Vector2i(1280, 720), Vector2i(640, 360)]:
		root.size = window
		var park: Node = load("res://scenes/park.tscn").instantiate()
		root.add_child(park)
		await layout()
		check(park.items.size() == 2 and park.stored_count() == 1, "Start has one basic sheet and one fixed discovery")
		check(Presets._validate_state(park.items[2].sheet).is_empty(), "Fixed found plane has valid connected history")
		await capture("park_start_" + str(window.x))
		var initial: Vector3 = park.player.position
		key(KEY_W)
		for frame in 75: await physics_frame
		key(KEY_W, false)
		await layout()
		check(park.player.position.z < initial.z - 0.6, "WASD moves toward workbench")
		check(park.bench_target, "One nearby workbench action becomes highlighted")
		var player_position: Vector3 = park.player.position
		var player_view: Vector2 = park.view_angles
		await capture("park_bench_" + str(window.x))
		await tap(KEY_E)
		await layout()
		check(park.editor != null and park.items[1].state == "work", "E opens folding at bench")
		var original: Dictionary = park.items[1].sheet.duplicate(true)
		park.editor._reset_paper(Stock.option(2))
		park.finish_edit(false)
		await layout()
		check(park.items[1].sheet == original and park.items[1].state == "stored", "Cancel never overwrites physical sheet")
		check(park.player.position.distance_to(player_position) < 0.01 and park.view_angles == player_view, "Editor returns to original location/view")
		park.open_editor(1)
		await layout()
		var sheet := folded_sheet(0.15)
		sheet.paper_stock = Stock.option(0)
		sheet.flight_parts = {}
		park.editor.restore_sheet(sheet)
		await capture("park_folding_" + str(window.x))
		park.editor.flight_button.pressed.emit()
		park.finish_edit(true)
		await layout()
		check(park.editor == null and park.items.size() == 2 and park.items[1].state == "stored", "Store/double input updates one item")
		check(park.items[1].sheet.faces == sheet.faces and park.items[1].sheet.history == sheet.history, "Store preserves exact material and history")
		await tap(KEY_TAB)
		await layout()
		await capture("park_inventory_" + str(window.x))
		check(park.inventory.visible and park.inventory_ids.size() == 1, "Physical inventory lists only owned items")
		park.take_button.pressed.emit()
		check(park.held_id == 1 and park.items[1].state == "hand", "Taking transfers same item to hand")
		invariant(park)
		park.prepare_throw()
		await layout()
		var flight: Node = park.active_flight
		check(flight != null and flight.ready_to_launch, "Hand enters world throw preparation")
		check(is_equal_approx(flight.body.mass, 0.0018), "World body uses actual paper mass")
		await tap(KEY_SPACE)
		check(flight.gauge_stage == 1, "Space begins gauge once")
		key(KEY_SPACE, true, true)
		await process_frame
		check(flight.gauge_stage == 1, "Held key cannot lock or launch twice")
		key(KEY_SPACE, false)
		var locked: Vector3 = park.player.position
		key(KEY_W)
		for frame in 10: await physics_frame
		key(KEY_W, false)
		check(park.player.position == locked, "Gauge locks movement")
		await tap(KEY_ESCAPE)
		check(flight.gauge_stage == 0 and park.held_id == 1, "Gauge cancellation does not consume item")
		await tap(KEY_B)
		await layout()
		check(park.active_flight == null and park.held_id == 1, "Leaving preparation keeps same held item")
		# Two positions/yaws/elevations, with real landing and recovery between throws.
		for index in 2:
			park.player.position = Vector3(3 + index * 2, 0.01, 1 + index)
			park.view_angles = Vector2(0.65 if index == 0 else -0.8, deg_to_rad(15 if index == 0 else -10))
			await layout()
			var origin: Vector3 = park.launch_position()
			var standing: Vector3 = park.player.position
			park.prepare_throw()
			await layout()
			flight = park.active_flight
			flight.angles = Vector2(75, 100)
			flight._rebuild()
			await layout()
			var old_basis: Basis = flight.body.global_basis
			var global_rotation := Basis(Vector3.RIGHT, deg_to_rad(12))
			flight.gizmo.selected_axis = 0
			flight._set_attitude(global_rotation * old_basis)
			flight.dragging = true
			flight._process(0)
			check(flight.dragging and flight.gizmo.selected_axis == 0, "Preparation frame does not interrupt an axis drag")
			flight.dragging = false
			flight.gizmo.end_drag()
			check(flight.body.get_global_transform_interpolated().origin.distance_to(flight.body.global_position) < 0.001, "World preview rendering follows the actual frozen physics body")
			check(flight.body.global_basis.is_equal_approx(global_rotation * old_basis), "Editor-style axis rotation uses world axis even with launch yaw")
			await capture("park_aim_%d_%d" % [index, window.x])
			await tap(KEY_SPACE)
			flight.launch_power = 65
			await tap(KEY_SPACE)
			check(flight.gauge_stage == 2 and not flight.gauge_returning and not flight.released, "Power lock continues to outward end")
			flight._process((1.0 - flight.gauge_cursor) / flight.POWER_SPEED + 0.01)
			check(flight.gauge_returning and not flight.released, "Cursor returns without premature release")
			flight.gauge_cursor = 0
			await tap(KEY_SPACE)
			check(flight.released and park.held_id == -1 and park.items[1].state == "flying", "Throw transfers the same physical item to world")
			check(flight.launched.launch_transform.origin.distance_to(origin) < 0.01, "Launch COM is current standing position plus 1.7m")
			var expected: Vector3 = Basis(Vector3.UP, park.view_angles.x) * Vector3(0, sin(park.view_angles.y), -cos(park.view_angles.y)) * (8.16 * flight.launched.launch_power / 100.0)
			check(flight.launched.launch_velocity.distance_to(expected) < 0.03, "World launch follows captured yaw and pitch")
			check(flight.launched.origin_width_px == 20 and absf(flight.launched.elevation_deviation) < 0.01, "Origin area and elevation-only timing rules are preserved")
			await capture("park_flight_%d_%d" % [index, window.x])
			await tap(KEY_B)
			await layout()
			check(park.active_flight == null and flight.running and not flight.body.freeze, "Viewing exit returns camera without stopping world physics")
			check(park.player.position.distance_to(standing) < 0.01, "Player remains at throw position")
			flight.elapsed = 13
			flight._physics_process(0)
			check(not flight.body.freeze and flight.running, "Independent test timeout does not freeze world flight")
			await capture("park_exit_%d_%d" % [index, window.x])
			for frame in 5000:
				await physics_frame
				if flight.landed: break
			check(flight.landed and park.items[1].state == "world", "Actual physics lands and enables recovery")
			check(park.items[1].marker != null and park.trials.size() == index + 1, "Landing marker and record are retained")
			park.player.position = flight.body.position + Vector3(0.4, 0, 0.4)
			await layout()
			await capture("park_recover_%d_%d" % [index, window.x])
			park.recover_item(1)
			park.recover_item(1)
			await layout()
			check(park.items[1].state == "hand" and park.held_id == 1 and park.items[1].flight == null and park.items.size() == 2, "Repeated recovery returns the same physical item directly to hand")
			check(park.items[1].sheet.faces == sheet.faces and park.items[1].sheet.history == sheet.history, "Flight and recovery preserve original material/history")
			check(park.items[1].flight_session.angles == Vector2(75, 100), "Wing settings survive recovery")
			invariant(park)
			park.selected_id = 1
			park._take_selected()
		# Wall and initial-shape overlap guard.
		park.player.position = Vector3(-6.6, 0, -8)
		park.view_angles = Vector2(PI / 2, 0)
		await layout()
		park.prepare_throw()
		await layout()
		flight = park.active_flight
		await tap(KEY_SPACE)
		check(flight.gauge_stage == 0 and park.held_id == 1, "Near wall blocks throw without consuming aircraft")
		park.exit_flight()
		await layout()
		# Editing remains transactional and cannot overwrite an independent blueprint.
		park.player.position = BENCH_position()
		park.open_editor(1)
		await layout()
		park.editor._reset_paper(Stock.option(3))
		park.finish_edit(false)
		await layout()
		check(park.items[1].sheet.paper_stock.id == "origami" and park.items[1].flight_session.angles == Vector2(75, 100), "Cancelled later editing preserves stock and wing settings")
		# An elevated floor must move the launch height with the standing ground.
		park._box(Vector3(6, 0.5, 3), Vector3(2, 1, 2), Color.GRAY)
		park.player.position = Vector3(6, 1.01, 3)
		park.view_angles = Vector2.ZERO
		await layout()
		park.prepare_throw()
		await layout()
		check(is_equal_approx(park.active_flight.launch_origin.y, 2.7), "Raised ground uses ground + 1.7m rather than fixed world height")
		park.exit_flight()
		await layout()
		# Storing a replacement sheet updates the same item, not a saved blueprint.
		park.player.position = BENCH_position()
		park.open_editor(1)
		await layout()
		park.editor.preset_store = Presets.new("res://build/park_test_presets")
		park.editor._save_preset("Park original", true)
		park.editor._reset_paper(Stock.option(3))
		park.finish_edit(true)
		await layout()
		check(park.items[1].sheet.paper_stock.id == "board" and park.items.size() == 2, "New stock updates same physical ID without adding a duplicate")
		var blueprint := Presets.new("res://build/park_test_presets").load_preset(Presets.new("res://build/park_test_presets").path_for("Park original"))
		check(blueprint.ok and blueprint.sheet.paper_stock.id == "origami" and blueprint.sheet.faces == sheet.faces, "Editing physical item never overwrites independently saved blueprint")
		park._take_selected()
		park.player.position = Vector3(5, 0.01, 1)
		park.prepare_throw()
		await layout()
		check(is_equal_approx(park.active_flight.body.mass, 0.0257676), "World throw uses full 4절 size and mass")
		flight = park.active_flight
		flight.launch()
		check(park.items[1].state == "flying", "Recovery guard starts from actual world ownership")
		park.restore_failed_flight(flight)
		check(park.active_flight == null and park.items[1].state == "stored" and park.items[1].flight == null and park.items.size() == 2, "Numerical failure returns the same physical item safely")
		park.restore_failed_flight(flight)
		check(park.items.size() == 2 and park.trials.size() == 3, "Repeated error recovery cannot duplicate aircraft or error record")
		invariant(park)
		park.queue_free()
		await layout()
	print("PAP park: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func BENCH_position() -> Vector3:
	return Vector3(0, 0.01, -1)
