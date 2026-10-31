extends "res://tests/test_defaults.gd"

func run() -> void:
	for size in [Vector2i(1280, 720), Vector2i(640, 360)]:
		root.size = size
		var park: Node = load("res://scenes/park.tscn").instantiate()
		root.add_child(park)
		buy_fixture(park)
		await layout()
		park.player.position = Vector3(4, 0.01, 1)
		park.items[OWN_ID].sheet = folded_sheet(0.15)
		park.items[OWN_ID].sheet.paper_stock = Stock.option(0)
		park.items[OWN_ID].sheet.flight_parts = {}
		park.selected_id = OWN_ID
		park._take_selected()
		park.prepare_throw()
		await layout()
		var flight: Node = park.active_flight
		check(not park.character.visible, "Preparation hides avatar")
		flight._advance_gauge()
		await layout()
		check(flight.gauge_stage == 1 and not park.character.visible, "Gauge keeps avatar hidden")
		flight._cancel_gauge()
		flight.launch_power = 50
		flight.launch()
		await layout()
		check(flight.released and not park.character.visible, "Close flight viewing keeps avatar out of the aircraft camera")
		for i in 1800:
			if flight.landed: break
			await physics_frame
		await layout()
		check(flight.landed and not flight.launch_button.disabled, "Actual landing enables primary return")
		check(not flight.gauge_track.visible and not flight.gauge_cancel.visible and not flight.gauge_label.text.contains("↑↓"), "Landing removes obsolete gauge instructions")
		check(flight.launch_button.text.contains("B / Esc"), "Landing shows exit keys")
		await capture("controls_landed_" + str(size.x))
		flight.results_panel.show()
		flight._escape()
		check(not flight.results_panel.visible and park.active_flight == flight, "Escape first closes results")
		var body: RigidBody3D = flight.body
		var id: int = flight.item_id
		flight.launch_button.pressed.emit()
		await layout()
		check(park.active_flight == null and park.items[id].flight.body == body and not body.freeze and park.held_id == -1, "Primary return preserves same world body without pickup")
		check(park.character.visible, "Return restores avatar")
		park.queue_free()
		await layout()
	print("PAP park controls: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
