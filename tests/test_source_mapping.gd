extends "res://tests/test_overlap_validation.gd"

func transformed(points: PackedVector2Array, scale: float, offset: Vector2, reverse: bool, start: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in points.size(): result.append(points[(i + start) % points.size()] * scale + offset)
	if reverse: result.reverse()
	return result

func run() -> void:
	var sliver := PackedVector2Array([Vector2(0, -0.075), Vector2(0.00000000745, 0.00000000745), Vector2(0.00000000186, 0.00000000745)])
	check(absf(Paper._convex_overlap_area(sliver, sliver) - Paper.area(sliver)) < 1e-16, "Sub-resolution material sliver keeps its actual clipping constraints")
	check(Paper._crease_separates(sliver, PackedVector2Array([Vector2(0, -0.075), Vector2(-0.00000000745, 0.00000000745), Vector2(0.00000000186, 0.00000000745)]), Vector2(0.00000000186, 0), Vector2.RIGHT), "Known hinge distinguishes two roundoff-width boundary fragments")
	check(not Paper._crease_separates(rect(-0.001, 0, 0.002, 0.1), rect(0, 0, 0.001, 0.1), Vector2.ZERO, Vector2.RIGHT), "Known hinge cannot excuse real overlap across the hinge")
	check(not Paper._crease_separates(sliver, sliver, Vector2.ZERO, Vector2.ZERO), "Invalid zero axis cannot excuse overlap")
	var snapshot: Dictionary = Dump.decode(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/a4_source_mapping.json")))
	var original := encoded(snapshot)
	var sheet := state_from(snapshot)
	var original_sheet := encoded(sheet)
	for filename in ["user_completed_airplane", "grip_orientation"]:
		var legacy: Dictionary = Dump.decode(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + filename + ".json")))
		for entry in legacy.history:
			if entry.kind != "fold": continue
			var legacy_before: Array[Dictionary] = []
			legacy_before.assign(entry.faces)
			for group in ["move", "stay"]:
				for fragment in entry.plan[group]:
					check(Paper._material_source(legacy_before, fragment) >= 0, "Even legacy roundoff-width material fragments keep a source")
	check(Dump.validate(snapshot).valid and Presets._validate_state(sheet).is_empty(), "New original dump and storage validation pass")
	check(encoded(snapshot) == original and encoded(sheet) == original_sheet, "Validation preserves all original data")
	var seventh: Dictionary = {}
	for entry in sheet.history:
		if entry.kind != "fold": continue
		var before: Array[Dictionary] = []
		before.assign(entry.faces)
		for group in ["move", "stay"]:
			for part in entry.plan[group]:
				check(Paper._material_source(before, part) >= 0, "Every historical part resolves a real material source")
		if entry.fold_count == 5:
			check(Paper._material_source(before, entry.plan.move[6]) == 6, "Sixth-fold move[6] restores source 6")
		elif entry.fold_count == 6:
			seventh = entry
			check(Paper._material_source(before, entry.plan.move[9]) == 41 and Paper._material_source(before, entry.plan.stay[41]) == 41, "Seventh-fold moving and fixed fragments restore source 41")
		elif entry.fold_count == 7:
			check(Paper._material_source(before, entry.plan.stay[22]) == 22, "Eighth-fold stay[22] restores source 22")
	var source: PackedVector2Array = seventh.faces[41].paper
	var part: PackedVector2Array = seventh.plan.move[9].paper
	check(absf(Paper.overlap_area(source, source) - Paper.area(source)) < 1e-12, "Original failing source self-overlap equals its area")
	# Vary the almost duplicate edge, rather than pinning a passing length threshold.
	var short_edge := 0
	for i in source.size():
		if source[i].distance_to(source[(i + 1) % source.size()]) < source[short_edge].distance_to(source[(short_edge + 1) % source.size()]): short_edge = i
	for edge_scale in [0.125, 1.0, 8.0]:
		var varied := source.duplicate()
		var next := (short_edge + 1) % source.size()
		varied[next] = source[short_edge] + (source[next] - source[short_edge]) * edge_scale
		for scale in [0.25, 1.0, 4.0]:
			for offset in [Vector2.ZERO, Vector2(0.3, -0.4), Vector2(-0.5, 0.25)]:
				for reverse in [false, true]:
					for start in source.size():
						var boundary := transformed(varied, scale, offset, reverse, start)
						var contained := transformed(part, scale, offset, not reverse, start % part.size())
						var tolerance := maxf(1e-12, Paper.area(boundary) * 0.000002)
						check(absf(Paper.overlap_area(boundary, boundary) - Paper.area(boundary)) <= tolerance, "Self-overlap survives short-edge, position, scale and ordering changes")
						check(absf(Paper.overlap_area(contained, boundary) - Paper.area(contained)) <= tolerance, "Contained fragment keeps its overlap")
						var candidates: Array[Dictionary] = [{"paper":rect(10, 10, 0.1, 0.1)}, {"paper":boundary}]
						check(Paper._material_source(candidates, {"paper":contained}) == 1, "Contained fragment maps to the real source")
	var before: Array[Dictionary] = []
	before.assign(seventh.faces)
	var broken_plan: Dictionary = seventh.plan.duplicate(true)
	var unknown: PackedVector2Array = broken_plan.move[9].paper.duplicate()
	for i in unknown.size(): unknown[i] += Vector2(10, 10)
	broken_plan.move[9].paper = unknown
	var failures_by_kind := Paper.layer_obstructions(before, broken_plan)
	check(failures_by_kind.size() == 1 and failures_by_kind[0].get("kind") == "source_mapping", "Unknown source is one mapping error, never a bottom layer")
	var failed_snapshot: Dictionary = snapshot.duplicate(true)
	failed_snapshot.history = [{"kind":"fold", "faces":before, "plan":broken_plan, "fold_count":6}]
	var report := Dump.validate(failed_snapshot)
	check(not report.valid and report.historical_source_errors.size() == 1 and report.historical_layer_obstructions.is_empty(), "Unknown source rejects validation without invented penetration")
	check(";".join(report.errors).contains("7번째 접기에서 조각의 원본 종이 층"), "Mapping failure is explained separately in Korean")
	broken_plan = seventh.plan.duplicate(true)
	unknown = broken_plan.stay[41].paper.duplicate()
	for i in unknown.size(): unknown[i] += Vector2(10, 10)
	broken_plan.stay[41].paper = unknown
	failures_by_kind = Paper.layer_obstructions(before, broken_plan)
	check(failures_by_kind.size() == 1 and failures_by_kind[0].get("kind") == "source_mapping" and failures_by_kind[0].part_group == "stay", "Unknown fixed source also fails explicitly without layer ordering")
	var store := Presets.new("res://build/source_mapping_presets")
	var saved := store.save_preset("original_195916", sheet, true)
	check(saved.ok, "New original sheet saves")
	if not saved.ok: quit(1); return
	var loaded := store.load_preset(saved.path)
	check(loaded.ok and encoded(loaded.sheet) == original_sheet, "New original sheet round-trips unchanged")
	var park: Node = load("res://scenes/park.tscn").instantiate()
	root.add_child(park)
	await layout()
	park.items[1].sheet = sheet.duplicate(true)
	park.player.position = park.BENCH
	park.open_editor(1)
	await layout()
	var editor: Node = park.editor
	check(editor != null and encoded(editor._preset_state()) == original_sheet, "Workbench opens exact new sheet")
	var history_before := encoded(editor.history)
	var damaged: PackedVector2Array = editor.faces[0].points.duplicate()
	damaged[0] += Vector2(0.01, 0)
	editor.faces[0].points = damaged
	var failed_before := encoded(editor._preset_state())
	park.finish_edit(true)
	check(park.editor == editor and encoded(editor._preset_state()) == failed_before and encoded(editor.history) == history_before, "Failed workbench storage retains edited paper and undo history")
	editor.restore_sheet(sheet)
	park.finish_edit(true)
	await layout()
	check(park.editor == null and park.items[1].state == "stored" and encoded(park.items[1].sheet) == original_sheet, "Workbench stores exact new original sheet")
	park.selected_id = 1
	park._take_selected()
	await layout()
	check(park.held_id == 1 and encoded(park.items[1].sheet) == original_sheet, "Retrieval keeps same physical sheet with original history and parts")
	park.queue_free()
	await layout()
	print("PAP source mapping: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
