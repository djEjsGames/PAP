extends "res://tests/test_defaults.gd"

func rect(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])

func state_from(snapshot: Dictionary) -> Dictionary:
	return {"faces":snapshot.faces.duplicate(true), "history":snapshot.history.duplicate(true), "fold_count":snapshot.interaction.fold_count, "paper_stock":snapshot.paper_stock.duplicate(true), "flight_parts":snapshot.flight_parts.duplicate(true), "reference":snapshot.reference.definition.duplicate(true)}

func encoded(value: Variant) -> String:
	# JSON numbers decode as floats; native validation normalizes fold counts to ints.
	return JSON.stringify(JSON.parse_string(JSON.stringify(Dump.encode(value), "", true, true)), "", true, true)

func run() -> void:
	var box := rect(0, 0, 1, 1)
	check(absf(Paper.overlap_area(box, rect(0.5, 0.5, 1, 1)) - 0.25) < 1e-12, "Known area remains exact")
	check(Paper.overlap_area(box, rect(1, 0, 1, 1)) == 0, "Shared edge is not overlap")
	check(Paper.overlap_area(box, rect(1, 1, 1, 1)) == 0, "Shared vertex is not overlap")
	box.reverse()
	check(absf(Paper.overlap_area(box, rect(0.5, 0.5, 1, 1)) - 0.25) < 1e-12, "Opposite winding has same area")
	check(Paper.overlap_area(rect(0.1, 0.1, 0.001, 0.001), rect(0.1009998, 0.1, 0.001, 0.001)) > Paper.MIN_OVERLAP_AREA, "Small real overlap above original area threshold remains detected")
	check(Paper.overlap_area(rect(0.1, 0.1, 0.00003, 0.00003), rect(0.1, 0.1, 0.00003, 0.00003)) > Paper.MIN_OVERLAP_AREA, "Tiny coincident faces remain real overlap")
	var duplicate_edge := PackedVector2Array([Vector2(0.1, 0.1), Vector2(0.2, 0.1), Vector2(0.2, 0.2), Vector2(0.1, 0.2), Vector2(0.100000005, 0.199999995)])
	check(absf(Paper.overlap_area(rect(0.12, 0.12, 0.02, 0.02), duplicate_edge) - 0.0004) < 1e-9, "Near-duplicate boundary vertex cannot erase real material overlap")
	for filename in ["wing_surface_overlap", "user_completed_airplane", "grip_orientation"]:
		var old: Dictionary = Dump.decode(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + filename + ".json")))
		var count := 0
		for entry in old.history:
			if entry.kind == "fold": count += 1
		check(Presets._validate_state({"faces":old.faces, "history":old.history, "fold_count":count, "reference":{}}).is_empty(), "Historical material source mapping remains valid: " + filename)
	var snapshot: Dictionary = Dump.decode(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/a4_boundary_contact.json")))
	var original := encoded(snapshot)
	check(Dump.validate(snapshot).valid, "Original A4 eight-fold dump passes without rewriting")
	var sheet := state_from(snapshot)
	var sheet_before := encoded(sheet)
	check(Presets._validate_state(sheet).is_empty(), "Original A4 passes storage validator")
	check(encoded(sheet) == sheet_before and encoded(snapshot) == original, "Validation preserves original geometry, history, stock and parts")
	for entry in sheet.history:
		if entry.kind != "fold" or entry.fold_count != 5: continue
		var before: Array[Dictionary] = []
		before.assign(entry.faces)
		var plan: Dictionary = entry.plan
		check(Paper.layer_obstructions(before, plan).is_empty(), "Recorded sixth fold is boundary contact")
		var generated := Paper.plan(before, plan.origin, plan.origin + plan.normal.orthogonal(), plan.origin + plan.normal * 0.01)
		check(not generated.is_empty() and Paper.layer_obstructions(before, generated).is_empty(), "Regenerated sixth fold agrees with saved validation")
		if not generated.is_empty():
			var prefix: Array[Dictionary] = []
			for previous in sheet.history:
				prefix.append(previous.duplicate(true))
				if previous == entry: break
			prefix[-1].plan = generated
			var regenerated_state := {"faces":Paper.folded(generated), "history":prefix, "fold_count":6, "paper_stock":sheet.paper_stock, "reference":{}, "flight_parts":{}}
			check(Presets._validate_state(regenerated_state).is_empty(), "Regenerated sixth-fold result passes complete storage validation")
	var store := Presets.new("res://build/overlap_validation_presets")
	var saved := store.save_preset("original_a4", sheet, true)
	check(saved.ok, "Original user sheet saves")
	if not saved.ok: quit(1); return
	var loaded := store.load_preset(saved.path)
	check(loaded.ok and encoded(loaded.sheet) == sheet_before, "Saved user sheet round-trips without changing any material data")
	var wing: Dictionary = Dump.decode(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/wing_layer_overlap.json")))
	var wing_before: Array[Dictionary] = []
	wing_before.assign(wing.before)
	var blocked := Paper.layer_obstructions(wing_before, wing.old_plan)
	check(blocked.size() == 2, "Real wing penetration still detects both upper layers")
	var invalid_report := Dump.validate({"format":"pap-fold-dump", "version":1, "faces":Paper.folded(wing.old_plan), "history":[{"kind":"fold", "faces":wing_before, "plan":wing.old_plan, "fold_count":6}]})
	check(not invalid_report.valid and invalid_report.historical_layer_obstructions.size() == 2, "Real penetration is rejected by dump validation")
	check(";".join(invalid_report.errors).contains("7번째 접기"), "Real failure identifies fold in Korean")
	for index in 4:
		var stock := Stock.option(index)
		for angle in [89.999, 90.0, 90.001]:
			var faces := Paper.rectangle(stock.size)
			var direction := Vector2.RIGHT.rotated(deg_to_rad(angle))
			var plan := Paper.plan(faces, Vector2.ZERO, direction, Vector2(stock.size.x * 0.4, 0))
			check(not plan.is_empty(), "All four stock sizes allow nearly vertical fold")
			if plan.is_empty(): continue
			check(Paper.layer_obstructions(faces, plan).is_empty(), "Fold boundary does not obstruct at any stock size")
			var history: Array[Dictionary] = [{"kind":"fold", "faces":faces, "fold_count":0, "single_layer":false, "plan":plan}]
			var state := {"faces":Paper.folded(plan), "history":history, "fold_count":1, "paper_stock":stock, "flight_parts":{}, "reference":{}}
			check(Presets._validate_state(state).is_empty() and Paper.is_continuous(state.faces), "Material area, connectivity and saved validation agree")
	# Exercise real workbench commit/retrieve and failure retention with the original sheet.
	var park: Node = load("res://scenes/park.tscn").instantiate()
	root.add_child(park)
	buy_fixture(park)
	await layout()
	park.items[OWN_ID].sheet = sheet.duplicate(true)
	park.player.position = park.BENCH
	park.open_editor(OWN_ID)
	await layout()
	check(park.editor != null and encoded(park.editor._preset_state()) == sheet_before, "Workbench opens exact original sheet")
	var editor: Node = park.editor
	var history_before := encoded(editor.history)
	var damaged: PackedVector2Array = editor.faces[0].points.duplicate()
	damaged[0] += Vector2(0.01, 0)
	editor.faces[0].points = damaged
	var failed_before := encoded(editor._preset_state())
	park.finish_edit(true)
	check(park.editor == editor and encoded(editor._preset_state()) == failed_before and encoded(editor.history) == history_before, "Failed storage preserves paper and undo history")
	check(editor.dump_notice.text.begins_with("보관 불가:"), "Workbench exposes validation failure")
	editor.restore_sheet(sheet)
	park.finish_edit(true)
	await layout()
	check(park.editor == null and park.items[OWN_ID].state == "stored" and encoded(park.items[OWN_ID].sheet) == sheet_before, "Workbench stores exact original sheet")
	park.selected_id = OWN_ID
	park._take_selected()
	await layout()
	check(park.held_id == OWN_ID and encoded(park.items[OWN_ID].sheet) == sheet_before, "Retrieval preserves same physical sheet and original undo data")
	park.queue_free()
	await layout()
	print("PAP overlap validation: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
