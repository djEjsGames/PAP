extends "res://tests/test_park.gd"

func run() -> void:
	for size in [Vector2i(1280, 720), Vector2i(640, 360)]:
		root.size = size
		var park: Node = load("res://scenes/park.tscn").instantiate()
		root.add_child(park)
		await layout()
		check(park.items.size() == 1 and park.stored_count() == 0 and park.coins == 100 and park.selected_id == -1, "No free sheet or reserved ID; new wallet is 100")
		await capture("shop_start_" + str(size.x))
		await tap(KEY_TAB)
		check(park.inventory.visible and park.take_button.disabled, "Empty Tab inventory cannot invent a sheet")
		await tap(KEY_ESCAPE)
		park.player.position = park.SHOP + Vector3(0, 0.01, 1)
		await layout()
		await tap(KEY_E)
		check(park.shop.visible and park.shop_target, "Nearby E opens real paper stall")
		var origin: Vector3 = park.player.position
		var old_zoom: float = park.zoom
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		park._unhandled_input(wheel)
		check(park.zoom == old_zoom, "Shop blocks wheel camera input even when GUI passes wheel events")
		await tap(KEY_W)
		await tap(KEY_SPACE)
		await tap(KEY_TAB)
		key(KEY_E, true, true)
		key(KEY_E, false)
		await layout()
		check(park.shop.visible and not park.inventory.visible and park.active_flight == null and park.move_keys.is_empty() and park.player.position.distance_to(origin) < 0.03, "Shop blocks movement, throw, inventory and repeated interact")
		for index in 4: park.shop.choose(index)
		check(park.coins == 100 and park.items.size() == 1, "Selection is free")
		await capture("shop_compare_" + str(size.x))
		await tap(KEY_ESCAPE)
		check(not park.shop.visible and park.coins == 100 and park.items.size() == 1, "Cancel preserves balance and items")
		park.interact()
		var ids: Array[int] = []
		for index in 4:
			park.shop.choose(index)
			var before: int = park.coins
			park.shop.start.pressed.emit()
			var id: int = park.selected_id
			ids.append(id)
			check(park.coins == before - park.PRICES[index] and id == index + 2, "Purchase spends exact price and allocates unique physical ID")
			var sheet: Dictionary = park.items[id].sheet
			check(Stock.same(sheet.paper_stock, Stock.option(index)) and Presets._validate_state(sheet).is_empty(), "Purchased dimensions and density are valid without converting legacy material")
			check(sheet.history.is_typed() and sheet.history.get_typed_builtin() == TYPE_DICTIONARY and sheet.history.is_empty(), "Every purchased blank has typed empty history")
			key(KEY_ENTER, true, true)
			key(KEY_ENTER, false)
			check(park.coins == before - park.PRICES[index] and park.items.size() == index + 2, "Held key echo cannot repeat purchasing")
		check(park.coins == 25, "Four kinds cost 75 coins")
		park.shop.choose(3)
		check(park.buy_paper(3) == -1 and park.coins == 25 and park.items.size() == 5, "Insufficient purchase is atomic")
		check(park.buy_paper(-1) == -1 and park.buy_paper(4) == -1 and park.coins == 25, "Invalid stock preserves balance")
		await capture("shop_insufficient_" + str(size.x))
		await tap(KEY_ESCAPE)
		park.selected_id = ids[0]
		park.player.position = park.BENCH
		park.interact()
		await layout()
		check(park.editor != null and Stock.same(park.editor.locked_stock, Stock.option(0)), "Bought selection opens at workbench with fixed material")
		var editor: Node = park.editor
		for index in [1, 2, 3]:
			editor._reset_paper(Stock.option(index))
			check(Stock.same(editor.paper_stock, Stock.option(0)) and editor.history.is_empty(), "Reset cannot change purchased material")
		editor._open_paper_picker()
		check(not editor.picker.visible, "Park new-material picker directs to shop")
		var other: Dictionary = park.items[ids[1]].sheet
		editor.restore_sheet(other)
		check(Stock.same(editor.paper_stock, Stock.option(0)), "Dump/restore cannot change purchased material")
		editor._set_preset_pending({"kind":"load", "name":"other", "sheet":other})
		editor._confirm_preset()
		check(Stock.same(editor.paper_stock, Stock.option(0)), "Other-material preset is blocked")
		check(editor.preset_pending.is_empty() and not editor.preset_confirm.visible and not editor.preset_save.disabled and editor.preset_name.editable, "Rejected material restores preset confirmation controls")
		var folded := folded_sheet(0.15)
		folded.paper_stock = Stock.option(0)
		folded.flight_parts = {}
		editor._set_preset_pending({"kind":"load", "name":"same", "sheet":folded})
		editor._confirm_preset()
		check(editor.fold_count > 0, "Same-material folding data applies to the same sheet")
		editor.paper_stock = Stock.option(1)
		park.finish_edit(true)
		check(park.editor != null and park.items[ids[0]].sheet.history.is_empty(), "Final store rejects material bypass without destroying source")
		editor.paper_stock = Stock.option(0)
		park.finish_edit(true)
		await layout()
		check(park.editor == null and park.coins == 25 and park.selected_id == ids[0], "Fold and store retain bought ID without additional cost")
		await tap(KEY_TAB)
		park._take_selected()
		park.player.position = park.PRACTICE_START
		park.view_angles = Vector2(0, deg_to_rad(10))
		park.toggle_practice()
		park.prepare_throw()
		await layout()
		check(park.active_flight != null and park.active_flight.item_id == ids[0], "Purchased sheet enters real target throw")
		var flight: Node = park.active_flight
		flight.launch()
		for frame in 2400:
			await physics_frame
			if flight.landed: break
		check(flight.landed, "Purchased folded plane reaches actual physics landing")
		park.exit_flight()
		park.player.position = flight.body.position + Vector3(0.5, 0, 0.5)
		park.recover_item(ids[0])
		await layout()
		check(park.held_id == ids[0] and park.coins == 25 and park.items.size() == 5, "Recovery reuses purchased physical ID with no spending")
		park.shop.choose(0)
		park.buy_paper(0)
		park.shop.choose(2)
		park.buy_paper(2)
		check(park.coins == 0 and park.buy_paper(0) == -1 and park.coins == 0, "Exact depletion stays at zero on later attempts")
		invariant(park)
		park.queue_free()
		await layout()
	var extra: Node = load("res://scenes/park.tscn").instantiate()
	root.add_child(extra)
	buy_fixture(extra)
	extra._take_selected()
	var bought: int = extra.buy_paper(1)
	extra.shop.open()
	extra.shop.choose(1)
	await layout()
	var point: Vector2 = extra.shop.start.get_global_rect().get_center()
	for click in 2:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.position = point
		mouse.pressed = true
		Input.parse_input_event(mouse)
		await layout()
		check(extra.coins == 70 - click * 20, "Holding purchase mouse button does not buy repeatedly")
		mouse.pressed = false
		Input.parse_input_event(mouse)
		await layout()
	check(extra.coins == 30 and extra.owned_stock(1) == 3 and extra.items.size() == 5, "Two separate mouse clicks purchase exactly two more sheets")
	bought = extra.selected_id
	extra.shop.hide()
	extra.player.position = extra.BENCH
	extra.interact()
	await layout()
	check(extra.editing_id == bought and extra.held_id == OWN_ID and extra.items[OWN_ID].state == "hand", "Buying with a held plane edits selected purchase and preserves old hand item")
	extra.finish_edit(false)
	extra.items[OWN_ID].state = "cleared"
	extra.held_id = -1
	check(extra.owned_stock(0) == 0, "Cleared known paper is excluded from owned quantity")
	extra.queue_free()
	await layout()
	var lab: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(lab)
	await layout()
	lab._reset_paper(Stock.option(3))
	check(lab.paper_stock.id == "board", "Standalone laboratory retains free material choice")
	lab.queue_free()
	await layout()
	await root.get_node("Audio").stop_all()
	print("PAP shop: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
