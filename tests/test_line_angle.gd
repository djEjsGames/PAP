extends "res://tests/test_defaults.gd"
const Reference := preload("res://scripts/fold_reference.gd")

func run() -> void:
	for window in [Vector2i(1280, 720), Vector2i(640, 360)]:
		root.size = window
		var app: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(app)
		await layout()
		for index in 4:
			var stock := Stock.option(index)
			app._reset_paper(stock)
			app._set_mode(2)
			for degrees in [7.0, 17.0, 38.0, 89.0, 103.0, 149.0, -17.0, -179.0]:
				app._press(Vector2.ZERO)
				var raw: Vector2 = Vector2.from_angle(deg_to_rad(degrees)) * stock.size.length() * 3
				app._motion(raw)
				var expected: Vector2 = Vector2.from_angle(snappedf(deg_to_rad(degrees), PI / 12)) * raw.length()
				check(app.line_b.is_equal_approx(expected), "Unanchored crease direction must snap in all quadrants at 15 degrees")
				check(is_equal_approx(app.line_b.distance_to(app.line_a), raw.length()), "Angular snapping must preserve drag length")
				var shift := InputEventKey.new()
				shift.physical_keycode = KEY_SHIFT
				shift.pressed = true
				app._input(shift)
				check(app.line_b == raw and app.snap_marker == Vector2.INF, "Shift without pointer motion must release both angle and point snapping")
				shift.pressed = false
				app._input(shift)
				check(app.line_b.is_equal_approx(expected), "Releasing Shift must restore angular snap from raw pointer")
				app._release(raw)
				check(app.line_ready, "Release must keep the displayed snapped crease")
				app._cancel()
			app._press(Vector2.ZERO)
			var preview: Vector2 = Vector2.from_angle(deg_to_rad(32)) * stock.size.length()
			app._motion(preview)
			await capture("line_15_" + stock.id + "_" + str(window.x))
			app._cancel()
			app._press(Vector2.ZERO)
			app._release(Vector2.ZERO)
			check(not app.line_ready, "A zero-length stroke must remain invalid")
		app._reset_paper()
		app._set_mode(2)
		app.guide_panel.show()
		app._set_guide_step(4)
		await layout()
		var step: Dictionary = app.guide_steps[4]
		app._press(step.a)
		app._motion(step.b)
		check(app.line_b == step.b, "An exact guide endpoint must win over 15 degree quantization")
		check(Paper.snap_candidate(app.faces, step.b, app._pixel_radius(28), true, app._snap_reference()).snapped, "Exact anchors must report a snap even with zero displacement")
		app._cancel()
		app.guide_panel.hide()
		app._press(Vector2(0.01, 0.02), true)
		var midpoint := Vector2(0.075, 0)
		app._motion(midpoint)
		check(app.line_b == midpoint, "Exact edge midpoint must retain its precise non-15-degree alignment")
		app._cancel()
		app._press(Vector2.ZERO, true)
		var unsnapped := Vector2(0.055, 0.031)
		app._motion(unsnapped, true)
		check(app.line_b == unsnapped, "Shift/freehand must preserve arbitrary angles and exact guide positions")
		app._cancel()
		app.preset_store = Presets.new("res://build/old_stock_angle_" + str(window.x))
		for index in [2, 3]:
			var old := Stock.option(index)
			old.size = Vector2(0.15, 0.15)
			old.name = "신문지" if index == 2 else "얇은 도화지"
			old.description = "같은 크기에서 더 가벼움" if index == 2 else "같은 크기에서 더 무거움"
			var state := folded_sheet(0.15)
			state.paper_stock = old
			var result: Dictionary = app.preset_store.save_preset("old_" + str(index), state, true)
			check(result.ok, "Old 15cm newspaper/drawing profiles must remain saveable")
			if not result.ok: quit(1); return
			var loaded: Dictionary = app.preset_store.load_preset(result.path)
			check(loaded.ok and loaded.sheet.paper_stock == old and loaded.sheet.faces == state.faces, "Old stored profiles must not resize or change grammage")
			app._set_preset_pending({"kind": "load", "name": old.name, "sheet": loaded.sheet})
			app._confirm_preset()
			app._open_flight()
			check(is_equal_approx(app.flight_view.body.mass, 0.0225 * old.gsm / 1000), "Old 15cm profiles must retain original runtime mass")
			app._close_flight()
		for filename in DirAccess.get_files_at(app.preset_store.folder): DirAccess.remove_absolute(app.preset_store.folder.path_join(filename))
		DirAccess.remove_absolute(app.preset_store.folder)
		root.remove_child(app)
		app.queue_free()
		await layout()
	check(Stock.option(2).size.is_equal_approx(Vector2(0.391, 0.545)), "New newsprint uses the selected domestic broadsheet page")
	check(Stock.option(3).size.is_equal_approx(Vector2(0.394, 0.545)), "New drawing paper uses 4-jeol dimensions")
	check(is_equal_approx(Stock.mass(Stock.option(2)), 0.009589275) and is_equal_approx(Stock.mass(Stock.option(3)), 0.0257676), "Larger sheets must use real area-based mass")
	print("PAP line/size: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
