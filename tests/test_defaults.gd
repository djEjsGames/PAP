extends SceneTree
const Stock := preload("res://scripts/paper_stock.gd")
const Paper := preload("res://scripts/paper_geometry.gd")
const Guide := preload("res://scripts/airplane_guide.gd")
const Model := preload("res://scripts/flight_model.gd")
const Dump := preload("res://scripts/paper_dump.gd")
const Presets := preload("res://scripts/paper_presets.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func layout() -> void:
	for i in 4: await process_frame

func capture(name: String) -> void:
	await layout()
	if "--screenshots" not in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/previews")
	root.get_texture().get_image().save_png("res://build/previews/defaults_" + name + ".png")

func folded_sheet(size: float) -> Dictionary:
	var faces := Paper.square(size)
	var history: Array[Dictionary] = []
	var count := 0
	for step in Guide.steps(size):
		if step.action == "unfold":
			faces = history.pop_back().faces
			count -= 1
		elif step.action == "flip":
			history.append({"kind": "flip", "faces": faces.duplicate(true), "fold_count": count, "single_layer": false})
			faces = Paper.flipped(faces)
		else:
			var layer := int(Paper.edge_near(faces, step.grab, 0.00001).layer) if step.single_layer else -1
			var plan := Paper.plan(faces, step.a, step.b, step.grab, layer)
			check(not plan.is_empty(), "Guide fold must work at size " + str(size))
			if plan.is_empty(): return {}
			history.append({"kind": "fold", "faces": faces.duplicate(true), "fold_count": count, "single_layer": step.single_layer, "plan": plan})
			faces = Paper.folded(plan)
			count += 1
	return {"faces": faces, "history": history, "fold_count": count, "reference": {}}

func run() -> void:
	check(is_equal_approx(Paper.total_area(Paper.square()), 0.0225), "New default must be a 15cm square")
	check(is_equal_approx(Paper.total_area(Paper.square(0.2)), 0.04), "Explicit legacy square must remain 20cm")
	var folder := "res://build/defaults_presets"
	var store := Presets.new(folder)
	var old: Dictionary = Dump.decode(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/flight_energy_wind.json")))
	check(is_equal_approx(old.flight.trials[-1].launch_transform.origin.y, 1.5), "Historical dump must retain its original 1.5m launch")
	var posed: Array[Dictionary] = []
	posed.assign(old.flight.posed)
	check(is_equal_approx(Model.properties(posed).mass, 0.0032), "Historical geometry must retain 3.2g at 80gsm")
	for size in [0.15, 0.2]:
		var state := folded_sheet(size)
		check(not state.is_empty(), "Guide must generate a complete sheet")
		if state.is_empty(): quit(1); return
		check(Presets._validate_state(state).is_empty(), "Both supported sizes must pass history and material validation")
		var saved := store.save_preset("size_" + str(size), state, true)
		check(saved.ok, "Saving either size must succeed")
		if not saved.ok: quit(1); return
		var loaded := store.load_preset(saved.path)
		check(loaded.ok and loaded.sheet.faces == state.faces and loaded.sheet.history == state.history, "Loading must preserve exact coordinates and history without rescaling")
		check(is_equal_approx(Paper.square_size(loaded.sheet.faces), size), "Material coordinates must retain original dimensions")
		var model := Model.pose(loaded.sheet.faces, loaded.sheet.history, Vector2(90, 90))
		check(is_equal_approx(Model.properties(model).area, size * size), "Deployed area must match stored size")
		check(is_equal_approx(Model.properties(model).mass, size * size * 0.08), "80gsm mass must be 1.8g or legacy 3.2g")
		for window in [Vector2i(1280, 720), Vector2i(640, 360)]:
			root.size = window
			var app: Node = load("res://scenes/main.tscn").instantiate()
			root.add_child(app)
			await layout()
			check(is_equal_approx(Paper.square_size(app.faces), 0.15), "New scenes must start at 15cm")
			if size == 0.15: await capture("15_new_" + str(window.x))
			app.faces.assign(loaded.sheet.faces)
			app.history.assign(loaded.sheet.history)
			app.fold_count = loaded.sheet.fold_count
			if Stock.read(app.paper_stock, app.faces).is_empty(): app.paper_stock = Stock.legacy(app.faces)
			app._refresh()
			check(app.guide_steps[0].grab.is_equal_approx(Vector2(size * 0.5, 0)), "Visible guide must use loaded sheet dimensions")
			check(Dump.validate(app._snapshot()).valid, "Dump validation must accept either actual size")
			if size == 0.15: await capture("15_folded_" + str(window.x))
			app._open_parts()
			await layout()
			check(not app.parts_editor.confirm.disabled, "15cm and legacy 20cm must support valid wing/grip selection")
			app.parts_editor.confirm.pressed.emit()
			await layout()
			var flight: Node = app.flight_view
			check(flight != null and flight.ready_to_launch, "Either size must enter flight through the existing primary action")
			check(is_equal_approx(flight.body.mass, size * size * 0.08), "Runtime mass must match the actual stored sheet")
			check(flight.body.center_of_mass == Vector3.ZERO and is_equal_approx((flight.body.global_transform * flight.body.center_of_mass).y, 1.7), "Launch must place the rebased centre of mass 1.7m above ground")
			if size == 0.15: await capture("15_ready_" + str(window.x))
			flight.launch()
			check(is_equal_approx(flight.launched.launch_transform.origin.y, 1.7), "New launch record must use 1.7m")
			flight.reset_trial()
			check(is_equal_approx(flight.body.position.y, 1.7), "Retry must retain 1.7m launch height")
			app._close_flight()
			app._open_flight()
			check(is_equal_approx(app.flight_view.body.position.y, 1.7), "Folding roundtrip must retain 1.7m launch height")
			app._close_flight()
			app._reset_paper()
			check(is_equal_approx(Paper.total_area(app.faces), 0.0225), "New paper after a legacy load must return to 15cm")
			root.remove_child(app)
			app.queue_free()
			await layout()
	for filename in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder.path_join(filename))
	DirAccess.remove_absolute(folder)
	print("PAP defaults: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

const OWN_ID := 2
const FOUND_ID := 1

func buy_fixture(park: Node) -> void:
	check(park.coins == 100 and park.stored_count() == 0 and park.items.size() == 1, "New park has 100 coins, no free sheet, one discovery")
	check(park.buy_paper(0) == OWN_ID and park.coins == 90, "Legacy regression fixture buys one real sheet")
