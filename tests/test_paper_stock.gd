extends "res://tests/test_defaults.gd"

func run() -> void:
	var base := Model.properties(Model.pose(Paper.square(), [], Vector2.ZERO), 0.08)
	var wind_load := Model.aerodynamic_load(Vector3(0, -0.5, -4), Vector3.ZERO, Model.panels(Model.pose(Paper.square(), [], Vector2.ZERO), Vector3.ZERO)[0])
	for index in [2, 3]:
		var stock := Stock.option(index)
		var props := Model.properties(Model.pose(Paper.square(), [], Vector2.ZERO), stock.gsm / 1000.0)
		check(is_equal_approx(props.mass / base.mass, stock.gsm / 80.0), "Grammage must scale actual mass")
		check(props.inertia.is_equal_approx(base.inertia * (stock.gsm / 80.0)), "Grammage must scale actual inertia")
		check((wind_load.force / props.mass).is_equal_approx(wind_load.force / base.mass * (80.0 / stock.gsm)), "Equal aerodynamic load must produce inverse-mass acceleration, not a distance bonus")
	for window in [Vector2i(1280, 720), Vector2i(640, 360)]:
		root.size = window
		var app: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(app)
		await layout()
		check(app.paper_stock.id == "origami" and not app.picker.visible, "First start must provide default paper without a selection gate")
		app.preset_store = Presets.new("res://build/stock_presets_" + str(window.x))
		var frame := Rect2(Vector2.ZERO, Vector2(window))
		for index in 4:
			var before: Dictionary = app._preset_state().duplicate(true)
			var session: Dictionary = app.flight_session.duplicate(true)
			app.line_ready = true
			app.line_a = Vector2(0, -0.02)
			app.line_b = Vector2(0, 0.02)
			app._open_paper_picker()
			app.picker.cards[index].pressed.emit()
			await capture("stock_picker_" + str(index) + "_" + str(window.x))
			check(app._preset_state() == before and app.flight_session == session, "Card comparison must not alter paper, parts or flight context")
			check(frame.encloses(app.picker.panel.get_global_rect()), "Picker must fit the viewport")
			for control in app.picker.cards + [app.picker.start, app.picker.save_start]:
				check(frame.encloses(control.get_global_rect()), "All four cards and completion buttons must be visible")
			var escape := InputEventKey.new()
			escape.physical_keycode = KEY_ESCAPE
			escape.pressed = true
			Input.parse_input_event(escape)
			await layout()
			escape.pressed = false
			Input.parse_input_event(escape)
			await layout()
			check(not app.picker.visible and app.line_ready and app.line_a == Vector2(0, -0.02) and app._preset_state() == before, "Escape must cancel selection without replacing work")
			app._open_paper_picker()
			app.picker.choose(index)
			app.picker.start.pressed.emit()
			await layout()
			var stock := Stock.option(index)
			check(app.paper_stock == stock and app.history.is_empty(), "Only start confirmation must replace paper and physical stock")
			check(Paper.material_size(app.faces).is_equal_approx(stock.size), "Actual geometry must preserve selected aspect and dimensions")
			check(is_equal_approx(Paper.total_area(app.faces), stock.size.x * stock.size.y), "Actual material area must match selected sheet")
			await capture("stock_new_" + stock.id + "_" + str(window.x))
			var state := {}
			if stock.size.x != stock.size.y:
				check(app.guide_steps.size() == 1 and app.guide_steps[0].action == "notice", "A4 must allow free folding and identify square-only guide without stretching it")
				app._toggle_guide()
				await capture("stock_rect_guide_" + stock.id + "_" + str(window.x))
				app._set_mode(1)
				app._press(Vector2(stock.size.x * 0.5, 0), true)
				app._motion(Vector2(-stock.size.x * 0.5, 0), true)
				app._release(Vector2(-stock.size.x * 0.5, 0), true)
				await create_timer(0.3).timeout
				check(app.fold_count == 1, "A4 free folding must commit through the normal controller")
				state = app._preset_state()
			else:
				state = folded_sheet(0.15)
			app.faces.assign(state.faces)
			app.history.assign(state.history)
			app.fold_count = state.fold_count
			app._refresh()
			var saved: Dictionary = app.preset_store.save_preset(stock.id, app._preset_state(), true)
			check(saved.ok, "Every paper must save through existing persistence")
			if not saved.ok: quit(1); return
			var restored: Dictionary = app.preset_store.load_preset(saved.path)
			check(restored.ok and restored.sheet.paper_stock == stock and restored.sheet.faces == app.faces, "Preset must retain physical stock and exact coordinates")
			var invalid: Dictionary = restored.sheet.duplicate(true)
			invalid.paper_stock.gsm += 1
			check(not app.preset_store.save_preset("invalid", invalid).ok, "Inconsistent paper metadata must be rejected")
			app._set_preset_pending({"kind": "load", "name": stock.id, "sheet": restored.sheet})
			app._confirm_preset()
			check(app.paper_stock == stock, "Load UI must restore stock without the picker overwriting it")
			check(Dump.validate(Dump.decode(Dump.encode(app._snapshot()))).valid, "Dump must validate dimensions, metadata and folded material")
			app._open_parts()
			await layout()
			if stock.size.x == stock.size.y:
				check(not app.parts_editor.confirm.disabled, "Every square material must support wing/grip confirmation")
				app.parts_editor.confirm.pressed.emit()
			else:
				app._open_flight()
			await layout()
			var flight: Node = app.flight_view
			check(flight.ready_to_launch and flight.paper_stock == stock, "Selected paper must reach flight without another required choice")
			check(is_equal_approx(flight.body.mass, Stock.mass(stock)), "Runtime mass must use selected grammage")
			check(is_equal_approx(flight.body.position.y, 1.7), "Every new flight must use 1.7m centre-of-mass height")
			for face in flight.posed:
				for point in face.points:
					var screen: Vector2 = flight.camera.unproject_position(flight.body.global_transform * (point - flight.properties.center))
					check(screen.y < flight.gauge_panel.position.y + 1, "Default preview must keep large sheets above the lower action controls")
			await capture("stock_ready_" + stock.id + "_" + str(window.x))
			flight.launch()
			for i in 3000:
				if not flight.running: break
				await physics_frame
			check(not flight.running and not flight.trials.is_empty() and flight.trials[-1].reason != "수치 오류", "Every paper flight must complete with finite physics")
			var record: Dictionary = flight.trials[-1].duplicate(true)
			check(record.paper_stock == stock and is_equal_approx(record.mass_kg, Stock.mass(stock)), "Flight records must retain launch paper and mass")
			flight.reset_trial()
			check(flight.paper_stock == stock and is_equal_approx(flight.body.position.y, 1.7), "Retry must retain paper and launch height")
			app._close_flight()
			app._open_flight()
			check(app.flight_view.paper_stock == stock and app.flight_view.trials[-1] == record, "Roundtrip must preserve stock and immutable past records")
			app._close_flight()
			if index < 3:
				app._open_paper_picker()
				app.picker.choose(index + 1)
				app.picker.hide()
				check(app.flight_session.trials[-1] == record and app.paper_stock == stock, "Comparing another stock must never rewrite a completed flight")
		var current: Dictionary = app._preset_state().duplicate(true)
		app._save_then_start(Stock.option(0))
		app.preset_name.text = ""
		app._request_preset_save()
		check(app._preset_state() == current and not app.pending_stock.is_empty(), "Save failure must keep the current sheet and defer stock replacement")
		app.preset_fly.pressed.emit()
		check(app.flight_view == null, "Save-and-start cannot be bypassed by the disabled fly callback")
		app._hide_presets()
		check(app._preset_state() == current and app.pending_stock.is_empty(), "Cancelling save-and-start must preserve the original sheet")
		app._save_then_start(Stock.option(2))
		app.preset_name.text = "before_new_stock"
		app._request_preset_save()
		check(app.paper_stock.id == "news" and app.history.is_empty() and not app.preset_shade.visible, "Successful save-and-start must create only the selected stock")
		var old: Dictionary = app.preset_store.load_preset(app.preset_store.path_for("before_new_stock"))
		check(old.ok and old.sheet.paper_stock == current.paper_stock and old.sheet.faces == current.faces, "Save-and-start must save the old work, not the new blank sheet")
		for filename in DirAccess.get_files_at(app.preset_store.folder): DirAccess.remove_absolute(app.preset_store.folder.path_join(filename))
		DirAccess.remove_absolute(app.preset_store.folder)
		root.remove_child(app)
		app.queue_free()
		await layout()
	print("PAP stock: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
