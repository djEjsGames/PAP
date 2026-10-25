extends SceneTree

const Paper := preload("res://scripts/paper_geometry.gd")
const Dump := preload("res://scripts/paper_dump.gd")
const FoldReference := preload("res://scripts/fold_reference.gd")
const Presets := preload("res://scripts/paper_presets.gd")
const AirplaneGuide := preload("res://scripts/airplane_guide.gd")
const FlightModel := preload("res://scripts/flight_model.gd")
var airplane_finished := false
var failures := 0
var checks := 0
var interactions_finished := false
var grip_orientation_finished := false
var presets_finished := false

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	_geometry_checks()
	_continuity_checks()
	_layer_obstruction_checks()
	_flip_short_edge_checks()
	await _interaction_checks()
	check(interactions_finished, "Interaction checks must finish without script errors")
	await _fold_ux_checks()
	await _small_guide_checks()
	await _reference_checks()
	await _preset_checks()
	check(presets_finished, "Preset checks must finish without runtime errors")
	await _review_checks()
	await _airplane_checks()
	await _user_launch_checks()
	await _grip_orientation_checks()
	await _surface_layer_checks()
	check(grip_orientation_finished, "Grip orientation checks must finish without runtime errors")
	check(airplane_finished, "Basic airplane guide must finish without runtime errors")
	print("PAP: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _geometry_checks() -> void:
	var square := Paper.square()
	check(is_equal_approx(Paper.total_area(square), 0.04), "Square area must be 20cm x 20cm")
	for point in [Vector2(0, -0.1), Vector2(0.1, 0), Vector2(0, 0.1), Vector2(-0.1, 0), Vector2(-0.1, -0.1)]:
		check(not Paper.edge_near(square, point, 0.005).is_empty(), "All four edges and corners must be grabbable")
	check(Paper.edge_near(square, Vector2.ZERO, 0.005).is_empty(), "Interior must not act as an edge")
	check(Paper.snap(square, Vector2(0.004, 0.003), 0.015).distance_to(Vector2.ZERO) < Paper.EPS, "The sheet center must be a snap anchor")
	check(Paper.snap(square, Vector2(0.003, 0.04), 0.015).distance_to(Vector2(0, 0.04)) < Paper.EPS, "Centerline snapping must align to the center while preserving free movement along it")
	check(Paper.reference_geometry(square).segments.size() == 2, "A square must expose its two material center axes")
	check(Paper.plan(square, Vector2.ZERO, Vector2.ZERO, Vector2.ONE).is_empty(), "Zero-length crease must be rejected")
	check(Paper.plan(square, Vector2(0.2, 0), Vector2(0.2, 1), Vector2.ZERO).is_empty(), "Outside crease must be rejected")
	check(Paper.plan(square, Vector2.ZERO, Vector2.UP, Vector2.ZERO).is_empty(), "Grab on crease must be rejected")
	var half_plan := Paper.plan(square, Vector2.ZERO, Vector2(0, 1), Vector2(0.1, 0))
	check(not half_plan.is_empty(), "Half fold must be valid")
	var half := Paper.folded(half_plan)
	check(half.size() == 2, "Half fold must preserve both layers")
	var turned_reference := Paper.reference_geometry(Paper.flipped(half))
	check(turned_reference.centers.size() == 1 and turned_reference.centers[0].distance_to(Vector2(-0.1, 0)) < Paper.EPS, "Center references must follow the original material after folding and flipping, not the silhouette midpoint")
	check(half[0].front and not half[1].front, "Moved layer must flip and land on top")
	check(is_equal_approx(Paper.total_area(half), 0.04), "Half fold must conserve sheet area")
	for face in half:
		for point in face.points:
			check(point.x <= Paper.EPS, "Half fold must reflect into the stationary side")
	var quarter_plan := Paper.plan(half, Vector2.ZERO, Vector2(1, 0), Vector2(-0.05, 0.1))
	check(quarter_plan.move.size() == 2 and quarter_plan.stay.size() == 2, "Second fold must split every stacked layer")
	var quarter := Paper.folded(quarter_plan)
	check(quarter.size() == 4, "Quarter fold must have four layers")
	check(quarter[2].front and not quarter[3].front, "Moving stack order must reverse")
	check(is_equal_approx(Paper.total_area(quarter), 0.04), "Repeated fold must conserve sheet area")
	var diagonal := Paper.folded(Paper.plan(square, Vector2(-0.1, -0.1), Vector2(0.1, 0.1), Vector2(0.1, -0.1)))
	check(diagonal.size() == 2, "Diagonal fold must keep two triangles without degenerate faces")
	check(is_equal_approx(Paper.total_area(diagonal), 0.04), "Diagonal fold must conserve sheet area")
	var random := RandomNumberGenerator.new()
	random.seed = 4817
	var current := square
	for i in 12:
		var center := Vector2.ZERO
		var count := 0
		for face in current:
			for point in face.points:
				center += point
				count += 1
		center /= count
		var angle := random.randf_range(0.0, TAU)
		var direction := Vector2.from_angle(angle)
		var next := Paper.plan(current, center, center + direction, center + direction.orthogonal())
		check(not next.is_empty(), "Repeated arbitrary crease should remain valid")
		if next.is_empty():
			break
		current = Paper.folded(next)
		check(absf(Paper.total_area(current) - 0.04) < 0.000001, "Arbitrary repeated folds must conserve area")
		check(Paper.is_continuous(current), "Arbitrary repeated folds must retain all material joins")
		for face in current:
			check(face.points.size() >= 3 and Paper.area(face.points) > Paper.MIN_AREA, "No degenerate face may survive clipping")
	check(square.size() == 1 and square[0].front, "Planning and folding must not mutate the source sheet")
	var top_plan := Paper.plan(half, Vector2(-0.05, 0), Vector2(-0.05, 1), Vector2(-0.1, 0), 1)
	check(top_plan.move.size() == 1, "Single-layer fold must move only the selected top face")
	var wing := Paper.folded(top_plan)
	check(wing[0] == half[0], "First wing must leave the opposite layer unchanged")
	check(is_equal_approx(Paper.total_area(wing), 0.04), "Single-layer fold must conserve paper area")
	var turned := Paper.flipped(wing)
	check(turned.size() == wing.size() and turned[-1].front == not wing[0].front, "Flipping must reverse stack order and exposed colors")
	check(is_equal_approx(Paper.total_area(turned), 0.04), "Flipping must conserve area")
	var twice := Paper.flipped(turned)
	for i in wing.size():
		check(wing[i].front == twice[i].front, "Double flip must restore orientation")
		for j in wing[i].points.size():
			check(wing[i].points[j].distance_to(twice[i].points[j]) < Paper.EPS, "Double flip must restore positions")

func _continuity_checks() -> void:
	var square := Paper.square()
	var half := Paper.folded(Paper.plan(square, Vector2.ZERO, Vector2(0, 1), Vector2(0.1, 0)))
	var quarter := Paper.folded(Paper.plan(half, Vector2.ZERO, Vector2(1, 0), Vector2(-0.05, 0.1)))
	var planned := Paper.plan(quarter, Vector2(-0.05, 0), Vector2(-0.05, 1), Vector2(-0.1, -0.05), 3)
	check(planned.move.size() == 4, "A connected lower panel must carry the middle layers that block its lift")
	check(Paper.is_continuous(quarter), "Quarter fold must be one joined sheet")
	var folded := Paper.folded(planned)
	check(Paper.is_continuous(folded), "Connected flap must remain joined after the fold")
	check(Paper.is_continuous(Paper.flipped(folded)), "Turning over a connected flap must retain every material seam")
	var source_area := 0.0
	for face in folded:
		source_area += Paper.area(face.paper)
		check(face.paper.size() == face.points.size() and face.seams.size() == face.points.size(), "Every split vertex and edge must keep its material identity")
	check(is_equal_approx(source_area, 0.04), "The original sheet must keep all its material area")
	var pieces: Array[Dictionary] = planned.stay.duplicate(true)
	pieces.append_array(planned.move)
	for link in Paper.connections(pieces):
		for angle in [0.0, PI / 3.0, PI * 0.7, PI]:
			for endpoints in [[link.p, link.other_p], [link.q, link.other_q]]:
				var p := _rotated_point(endpoints[0], link.a >= planned.stay.size(), planned, angle)
				var q := _rotated_point(endpoints[1], link.b >= planned.stay.size(), planned, angle)
				check(p.distance_to(q) < Paper.JOIN_EPS, "Material seams must remain joined throughout the drag, not only at 180 degrees")
	var old_behavior: Dictionary = planned.duplicate(true)
	old_behavior.stay.append(old_behavior.move.pop_back())
	check(not Paper.is_continuous(Paper.folded(old_behavior)), "Regression fixture must detect the former isolated-face tear despite unchanged total area")
	check(is_equal_approx(Paper.total_area(Paper.folded(old_behavior)), 0.04), "Area conservation alone must not be mistaken for an intact sheet")
	var broken := half.duplicate(true)
	var shifted: PackedVector2Array = broken[1].points
	for i in shifted.size():
		shifted[i] += Vector2(0.01, 0)
	broken[1].points = shifted
	check(not Paper.is_continuous(broken), "A detached layer must be detected even if its area is intact")
	check(Paper.plan(broken, Vector2(0, -0.05), Vector2(1, -0.05), Vector2(0, -0.1)).is_empty(), "A disconnected sheet must not be silently accepted for another fold")

func _layer_obstruction_checks() -> void:
	var fixture: Dictionary = Dump.decode(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/wing_layer_overlap.json")))
	var before: Array[Dictionary] = []
	before.assign(fixture.before)
	var old_plan: Dictionary = fixture.old_plan
	var blocked := Paper.layer_obstructions(before, old_plan)
	check(blocked.size() == 2, "User dump must reproduce two stationary upper panels blocking the wing")
	var blocked_area := 0.0
	for obstruction in blocked:
		blocked_area += obstruction.area_m2
	check(blocked_area > 0.002, "User wing was lifting through more than 20 square centimeters of upper paper")
	var origin: Vector2 = old_plan.origin
	var b: Vector2 = origin + old_plan.normal.orthogonal()
	var corrected := Paper.plan(before, origin, b, fixture.grab, fixture.selected_layer)
	check(not corrected.is_empty(), "The wing must remain foldable with the blocking layers included")
	if corrected.is_empty():
		return
	check(corrected.move.size() > old_plan.move.size(), "Corrected wing fold must carry the trapped upper parts")
	check(Paper.layer_obstructions(before, corrected).is_empty(), "No stationary upper panel may remain above a lifted part")
	var old_dump := {"format": "pap-fold-dump", "version": 1, "faces": Paper.folded(old_plan), "history": [{"kind": "fold", "faces": before, "plan": old_plan, "fold_count": 6}]}
	check(not Dump.validate(old_dump).valid, "Dump validation must reject the attached impossible wing despite preserved area and connectivity")
	old_dump.faces = Paper.folded(corrected)
	old_dump.history[0].plan = corrected
	check(Dump.validate(old_dump).valid, "Corrected wing history must pass layer-order validation")
	check(Paper.is_continuous(Paper.folded(corrected)), "Layer correction must keep the sheet joined")
	check(is_equal_approx(Paper.total_area(Paper.folded(corrected)), 0.04), "Layer correction must preserve all paper material")
	for seed in before.size():
		var candidate := Paper.plan(before, origin, b, fixture.grab, seed)
		if not candidate.is_empty():
			check(Paper.layer_obstructions(before, candidate).is_empty(), "Every accepted layer choice must respect vertical stacking")

func _flip_short_edge_checks() -> void:
	var fixture: Dictionary = Dump.decode(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/flip_short_edge.json")))
	var faces: Array[Dictionary] = []
	faces.assign(fixture.faces)
	var before: Array[Dictionary] = []
	before.assign(fixture.before_flip)
	check(Paper.is_continuous(before), "User's sheet must be joined before the final flip")
	for iteration in 4:
		check(Paper.is_continuous(faces), "Flipping must not mistake a sub-tolerance edge for a detached 10cm seam")
		check(Paper.connections(faces).size() == Paper.connections(before).size(), "Reversing face order must preserve material adjacency")
		faces = Paper.flipped(faces)
	var interaction: Dictionary = fixture.interaction
	var plan := Paper.plan(faces, interaction.line_a, interaction.line_b, interaction.grab, int(interaction.grabbed_layer))
	check(not plan.is_empty(), "The exact rejected wing drag from the user dump must be foldable")
	if plan.is_empty():
		return
	var folded := Paper.folded(plan)
	check(Paper.is_continuous(folded), "The recovered opposite wing must remain one sheet")
	check(is_equal_approx(Paper.total_area(folded), 0.04), "Recovering the opposite wing must preserve all paper material")
	check(Paper.layer_obstructions(faces, plan).is_empty(), "Recovering the wing must not lift through stationary upper layers")
	var pieces: Array[Dictionary] = plan.stay.duplicate(true)
	pieces.append_array(plan.move)
	for link in Paper.connections(pieces):
		for angle in [0.0, PI * 0.5, PI]:
			for pair in [[link.p, link.other_p], [link.q, link.other_q]]:
				check(_rotated_point(pair[0], link.a >= plan.stay.size(), plan, angle).distance_to(_rotated_point(pair[1], link.b >= plan.stay.size(), plan, angle)) < Paper.JOIN_EPS, "The recovered wing must retain its hinges throughout the fold")
func _rotated_point(point: Vector2, moving: bool, plan: Dictionary, angle: float) -> Vector3:
	if not moving:
		return Vector3(point.x, 0, point.y)
	var distance: float = (point - plan.origin).dot(plan.normal)
	var position: Vector2 = point + plan.normal * distance * (cos(angle) - 1.0)
	return Vector3(position.x, distance * sin(angle), position.y)

func key(app: Node, code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	app._unhandled_input(event)

func mouse(app: Node, point: Vector2, pressed: bool, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = app._screen(point)
	event.button_index = button
	event.pressed = pressed
	app._unhandled_input(event)

func motion(app: Node, point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = app._screen(point)
	app._unhandled_input(event)

func routed_mouse(app: Node, point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = root.get_final_transform() * app._screen(point)
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func routed_motion(app: Node, point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = root.get_final_transform() * app._screen(point)
	event.global_position = event.position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)
	await process_frame

func capture_preview(filename: String) -> void:
	if "--screenshots" not in OS.get_cmdline_user_args():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/previews")
	var ignore_file := FileAccess.open("res://build/.gdignore", FileAccess.WRITE)
	ignore_file.close()
	var image := root.get_texture().get_image()
	image.save_png("res://build/previews/" + filename + ".png")

func _interaction_checks() -> void:
	var app: Node = load("res://scenes/main.tscn").instantiate()
	check(app.get_script() != null, "Main scene script must load")
	if app.get_script() == null:
		app.free()
		return
	root.add_child(app)
	await process_frame
	await process_frame
	await process_frame
	await capture_preview("01_initial")
	check(app.mode == 1 and not app.click_to_confirm, "Initial mode must immediately commit on release")
	var near_midpoint := Vector2(-0.1, app._pixel_radius(20))
	app._press(near_midpoint)
	check(app.grab.distance_to(Vector2(-0.1, 0)) < Paper.EPS, "Grab must snap to edge midpoint within the stronger radius")
	app._cancel()
	app._press(near_midpoint, true)
	check(app.grab.distance_to(near_midpoint) < Paper.EPS, "Shift must bypass grab snapping")
	app._cancel()
	app._press(Vector2(-0.1, 0))
	var near_corner := Vector2(0.1, 0.1 - app._pixel_radius(20))
	app._motion(near_corner)
	check(app.snap_marker.distance_to(Vector2(0.1, 0.1)) < Paper.EPS, "Drag target must snap to a corner from 20 pixels away")
	app._motion(near_corner, true)
	check(app.snap_marker == Vector2.INF, "Shift must bypass target snapping")
	var shift := InputEventKey.new()
	shift.physical_keycode = KEY_SHIFT
	shift.pressed = false
	app._input(shift)
	check(app.snap_marker != Vector2.INF, "Releasing Shift without moving must restore snapping")
	shift.pressed = true
	app._input(shift)
	check(app.snap_marker == Vector2.INF, "Holding Shift without moving must release snapping")
	app._cancel()
	app._set_mode(2)
	app._update_line_hover(near_midpoint, false, false)
	check(app.line_hover.distance_to(Vector2(-0.1, 0)) < Paper.EPS and app.line_hover_snapped, "Line-mode hover must mark the snapped starting point before clicking")
	var free_preview: Vector2 = app._line_start_preview(near_midpoint, true)
	check(free_preview.distance_to(near_midpoint) < Paper.EPS, "Shift must release the line-mode starting point preview")
	app._update_line_hover(near_midpoint, true, false)
	check(app.line_hover.distance_to(near_midpoint) < Paper.EPS and not app.line_hover_snapped, "Shift must update the visible hover indicator as well as clicking")
	app._update_line_hover(near_midpoint, false, true)
	check(app.line_hover == Vector2.INF, "Line hover must not appear over toolbar controls")
	app._update_line_hover(near_midpoint, false, false)
	if "--screenshots" in OS.get_cmdline_user_args():
		app.set_process(false)
		app.overlay.queue_redraw()
		await capture_preview("12_line_hover_snap")
		app.set_process(true)
	app._press(near_midpoint)
	check(app.line_a.distance_to(app.line_hover) < Paper.EPS, "The visible line starting point must match the actual click")
	app._cancel()
	app._press(near_midpoint, true)
	app._motion(Vector2(0.1, near_midpoint.y), true)
	check(app.line_a.distance_to(near_midpoint) < Paper.EPS and app.snap_marker == Vector2.INF, "Shift must also bypass crease endpoint snapping")
	app._cancel()
	app._set_mode(1)
	key(app, KEY_C)
	mouse(app, Vector2(-0.1, 0), true)
	motion(app, Vector2(0.1, 0))
	check(not app.fold_plan.is_empty(), "Direct edge drag must produce a fold")
	mouse(app, Vector2(0.1, 0), false)
	await capture_preview("02_pending")
	check(app.state == app.State.PENDING and app.fold_count == 0, "Release must preview without committing")
	key(app, KEY_2)
	key(app, KEY_C)
	check(app.mode == 1 and app.click_to_confirm, "Mode and confirmation changes must be blocked during a fold")
	mouse(app, Vector2(0.2, 0.2), true)
	check(app.state == app.State.PENDING, "Click outside the folded paper must not commit")
	mouse(app, Vector2(0.05, 0), true)
	await create_timer(0.3).timeout
	check(app.fold_count == 1 and app.faces.size() == 2, "Clicking the preview must commit the fold")
	key(app, KEY_2)
	mouse(app, Vector2(-0.02, 0), true)
	motion(app, Vector2(0.12, 0))
	mouse(app, Vector2(0.12, 0), false)
	check(app.line_ready, "Drawing across the folded paper must set a crease")
	mouse(app, Vector2(0.05, 0.1), true)
	motion(app, Vector2(0.05, -0.05))
	await capture_preview("03_folding_layers")
	motion(app, Vector2(0.05, -0.1))
	mouse(app, Vector2(0.05, -0.1), false)
	check(app.state == app.State.PENDING, "Line mode must allow a second fold")
	mouse(app, Vector2(0.05, -0.05), true)
	await create_timer(0.3).timeout
	await capture_preview("04_repeated_fold")
	check(app.fold_count == 2 and app.faces.size() == 4, "Line mode must fold all overlapping layers")
	var before_connected: Array[Dictionary] = app.faces.duplicate(true)
	key(app, KEY_1)
	key(app, KEY_3)
	mouse(app, Vector2(0.1, -0.05), true)
	motion(app, Vector2(0, -0.05))
	check(app.fold_plan.move.size() == 4, "Top-side interaction must carry both joined and blocking layers")
	mouse(app, Vector2(0, -0.05), false)
	mouse(app, Vector2(0.025, -0.05), true)
	await create_timer(0.3).timeout
	check(app.fold_count == 3 and Paper.is_continuous(app.faces), "Top-side drag must finish as one intact sheet")
	await capture_preview("09_connected_flap")
	key(app, KEY_Z)
	check(app.faces == before_connected, "Undo must restore material coordinates and connections as well as the outline")
	key(app, KEY_3)
	key(app, KEY_Z)
	check(app.fold_count == 1 and app.faces.size() == 2, "Undo must restore exact previous layers")
	key(app, KEY_Z)
	check(app.fold_count == 0 and app.faces == Paper.square(), "Undo must restore the original sheet")
	key(app, KEY_1)
	key(app, KEY_C)
	mouse(app, Vector2(-0.1, 0), true)
	motion(app, Vector2(0.1, 0))
	mouse(app, Vector2(0.1, 0), false)
	await create_timer(0.3).timeout
	check(app.fold_count == 1 and app.state == app.State.IDLE, "Immediate mode must commit on release")
	key(app, KEY_R)
	check(app.fold_count == 0 and app.history.is_empty(), "Reset must clear the paper and undo history")
	mouse(app, Vector2(-0.1, 0), true)
	motion(app, Vector2(0, 0))
	mouse(app, Vector2.ZERO, true, MOUSE_BUTTON_RIGHT)
	check(app.state == app.State.IDLE and app.faces == Paper.square(), "Right click must cancel without mutating the sheet")
	key(app, KEY_2)
	mouse(app, Vector2(0.2, 0.2), true)
	mouse(app, Vector2(0.22, 0.2), false)
	check(not app.line_ready, "A line missing the paper must not be accepted")
	mouse(app, Vector2.ZERO, true)
	mouse(app, Vector2.ZERO, false)
	check(not app.line_ready, "A click without drawing must not make a crease")
	key(app, KEY_R)
	key(app, KEY_1)
	await routed_mouse(app, Vector2(-0.1, 0), true)
	await routed_motion(app, Vector2(0.1, 0))
	await routed_mouse(app, Vector2(0.1, 0), false)
	await create_timer(0.3).timeout
	check(app.fold_count == 1, "Godot input routing must deliver real mouse events to the fold controller")
	key(app, KEY_3)
	check(app.single_layer, "3 must enable top-layer selection independently of input mode")
	var before_wing: Array[Dictionary] = app.faces.duplicate(true)
	mouse(app, Vector2(0.1, 0), true)
	motion(app, Vector2(0, 0))
	mouse(app, Vector2(0, 0), false)
	await create_timer(0.3).timeout
	check(app.fold_count == 2 and app.faces.size() == 3, "First wing must fold one of the two overlapping layers")
	check(app.faces[0] == before_wing[0], "The other wing must remain unchanged")
	await capture_preview("06_first_wing")
	var before_flip: Array[Dictionary] = app.faces.duplicate(true)
	key(app, KEY_F)
	check(app.state == app.State.FLIPPING, "F must start turning the sheet over")
	key(app, KEY_1)
	key(app, KEY_3)
	check(app.single_layer, "Layer mode must not change during a flip")
	await create_timer(0.45).timeout
	check(app.fold_count == 2 and app.state == app.State.IDLE, "Flipping must not count as another fold")
	check(app.faces == Paper.flipped(before_flip), "Flipping must expose the opposite side")
	await capture_preview("07_flipped")
	mouse(app, Vector2(0.0, 0), true)
	motion(app, Vector2(0.1, 0))
	mouse(app, Vector2(0.1, 0), false)
	await create_timer(0.3).timeout
	check(app.fold_count == 3 and app.faces.size() == 4, "The opposite wing must fold independently after flipping")
	check(is_equal_approx(Paper.total_area(app.faces), 0.04), "Independent wings must preserve the whole sheet")
	await capture_preview("08_both_wings")
	key(app, KEY_Z)
	check(app.fold_count == 2 and app.faces == Paper.flipped(before_flip), "Undo must restore the opposite wing")
	key(app, KEY_Z)
	check(app.fold_count == 2 and app.faces == before_flip, "Undo must restore a flip without changing fold count")
	key(app, KEY_Z)
	check(app.fold_count == 1 and app.faces == before_wing, "Undo must restore the first wing")
	key(app, KEY_3)
	key(app, KEY_R)
	if "--screenshots" in OS.get_cmdline_user_args():
		root.size = Vector2i(640, 360)
		await process_frame
		await capture_preview("05_small_window")
	interactions_finished = true
	root.remove_child(app)
	app.queue_free()

func _review_checks() -> void:
	if "--screenshots" in OS.get_cmdline_user_args():
		root.size = Vector2i(1280, 720)
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	await process_frame
	key(app, KEY_U)
	check(app.state == app.State.IDLE and app.history.is_empty(), "Unfolding a fresh square must be a harmless no-op")
	mouse(app, Vector2(-0.1, 0), true)
	motion(app, Vector2(0.1, 0))
	mouse(app, Vector2(0.1, 0), false)
	await create_timer(0.3).timeout
	var folded: Array[Dictionary] = app.faces.duplicate(true)
	key(app, KEY_U)
	check(app.state == app.State.UNFOLDING, "U must animate the last crease open")
	await create_timer(0.18).timeout
	key(app, KEY_SPACE)
	var paused_angle: float = app.fold_angle
	check(paused_angle > 0.0 and paused_angle < PI, "Unfold must pass through intermediate angles")
	await create_timer(0.15).timeout
	check(is_equal_approx(app.fold_angle, paused_angle), "Paused unfold must not advance")
	key(app, KEY_V)
	check(app.inspect_view and app.animation_paused, "Side inspection must work without resuming the paused motion")
	await capture_preview("10_unfold_paused_side")
	var snapshot: Dictionary = app._snapshot()
	var encoded := JSON.stringify(Dump.encode(snapshot))
	var restored: Dictionary = Dump.decode(JSON.parse_string(encoded))
	check(Dump.validate(restored).valid, "Dump must round-trip the joined sheet through readable JSON")
	check(restored.animation.paused and restored.interaction.state == "UNFOLDING", "Dump must capture paused motion, not only committed geometry")
	check(is_equal_approx(restored.animation.fold_angle_radians, paused_angle), "Dump must retain the exact preview angle")
	check(restored.history.size() == app.history.size() and restored.fold_plan.origin is Vector2, "Dump must retain the fold history and native geometric types")
	check(restored.render.posed_faces[0].world_vertices[0] is Vector3 and restored.render.paper_transform == app.paper_mesh.transform, "Dump must include the displayed 3D pose and its transform")
	DirAccess.make_dir_recursive_absolute("res://build")
	var saved: String = app._dump_state("res://build/test_dump.json")
	check(not saved.is_empty() and FileAccess.file_exists(saved), "Dump button must write a shareable file")
	await check_dump_input(app, false)
	await check_dump_input(app, true)
	check(app.animation_paused and app.faces == folded, "Saving must not alter the current paper or pause state")
	var bad: Dictionary = restored.duplicate(true)
	var moved: PackedVector2Array = bad.faces[0].points
	for i in moved.size():
		moved[i] += Vector2(0.01, 0)
	bad.faces[0].points = moved
	check(not Dump.validate(bad).valid, "Dump validator must detect detached material even with unchanged area")
	key(app, KEY_SPACE)
	await create_timer(0.6).timeout
	check(app.faces == Paper.square() and app.fold_count == 0 and app.history.is_empty(), "Unfold must restore original material coordinates, order, and fold count")
	mouse(app, Vector2(-0.1, 0), true)
	check(app.state == app.State.IDLE, "Inspection view must not accidentally start folding")
	key(app, KEY_V)
	check(not app.inspect_view, "V must restore the top-down editing view")
	mouse(app, Vector2(-0.1, 0), true)
	motion(app, Vector2(0.1, 0))
	mouse(app, Vector2(0.1, 0), false)
	await create_timer(0.3).timeout
	key(app, KEY_U)
	await create_timer(0.1).timeout
	key(app, KEY_ESCAPE)
	check(app.faces == folded and app.fold_count == 1 and app.history.size() == 1, "Cancelling unfold must keep the folded sheet and its history intact")
	check(app.fold_plan.is_empty() and app.state == app.State.IDLE, "Cancelling unfold must clear the preview")
	app._set_slow_motion(true)
	key(app, KEY_F)
	await create_timer(0.25).timeout
	check(app.flip_angle < PI * 0.5, "Slow mode must allow detailed inspection of the flip")
	key(app, KEY_SPACE)
	key(app, KEY_V)
	await capture_preview("11_flip_paused_side")
	key(app, KEY_ESCAPE)
	check(app.faces == folded and app.history.size() == 1, "Cancelling a paused flip must not alter paper or history")
	check(app.paper_mesh.transform == Transform3D.IDENTITY and app.edge_mesh.transform == Transform3D.IDENTITY, "Cancelling flip must remove its temporary display transform")
	app._set_slow_motion(false)
	key(app, KEY_F)
	await create_timer(0.45).timeout
	check(app.faces == Paper.flipped(folded) and Paper.is_continuous(app.faces), "Flip must expose the opposite side without detaching material")
	key(app, KEY_U)
	await create_timer(1.05).timeout
	check(app.faces == Paper.square() and app.history.is_empty(), "Unfold after flip must first restore fold orientation and then open the crease")
	key(app, KEY_V)
	mouse(app, Vector2(-0.1, 0), true)
	motion(app, Vector2(0.1, 0))
	mouse(app, Vector2(0.1, 0), false)
	await create_timer(0.3).timeout
	key(app, KEY_2)
	mouse(app, Vector2(-0.02, 0), true)
	motion(app, Vector2(0.12, 0))
	mouse(app, Vector2(0.12, 0), false)
	mouse(app, Vector2(0.05, 0.1), true)
	motion(app, Vector2(0.05, -0.1))
	mouse(app, Vector2(0.05, -0.1), false)
	await create_timer(0.3).timeout
	check(app.fold_count == 2, "Unfold regression setup must contain two creases")
	key(app, KEY_U)
	await create_timer(0.6).timeout
	check(app.fold_count == 1 and Paper.is_continuous(app.faces), "First unfold must preserve the earlier crease")
	key(app, KEY_U)
	await create_timer(0.6).timeout
	check(app.faces == Paper.square() and app.fold_count == 0, "Repeated U must unfold all the way to the original sheet")
	root.remove_child(app)
	app.queue_free()
func _airplane_checks() -> void:
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	await process_frame
	var instructions := AirplaneGuide.steps()
	key(app, KEY_G)
	check(app.guide_panel.visible, "G must open the optional airplane guide without resetting the paper")
	await capture_preview("14_airplane_guide")
	for index in instructions.size():
		app._set_guide_step(index)
		check(app.guide_text.text == instructions[index].text, "On-screen guide and functional test must use the same step definition")
		var step: Dictionary = instructions[index]
		if step.action == "unfold":
			key(app, KEY_U)
			await create_timer(0.6).timeout
			check(app.faces == Paper.square(), "Center crease preparation must unfold back into one whole square")
		elif step.action == "flip":
			key(app, KEY_F)
			await create_timer(0.45).timeout
		else:
			var before: Array[Dictionary] = app.faces.duplicate(true)
			var previous_count: int = app.fold_count
			app._set_mode(2)
			app._set_single_layer(step.single_layer)
			app._press(step.a)
			app._motion(step.b)
			app._release(step.b)
			check(app.line_ready, "Airplane step %d must accept its crease" % (index + 1))
			app._press(step.grab)
			app._motion(step.target)
			check(not app.fold_plan.is_empty(), "Airplane step %d must grab a real edge and create a fold" % (index + 1))
			if app.fold_plan.is_empty():
				app.queue_free()
				return
			check(Paper.layer_obstructions(before, app.fold_plan).is_empty(), "Airplane step %d must not lift through another layer" % (index + 1))
			app._release(step.target)
			await create_timer(0.3).timeout
			check(app.fold_count == previous_count + 1, "Airplane step %d must commit once" % (index + 1))
		check(Paper.is_continuous(app.faces), "Airplane step %d must remain one joined sheet" % (index + 1))
		check(is_equal_approx(Paper.total_area(app.faces), 0.04), "Airplane step %d must preserve the 20cm square" % (index + 1))
	check(app.fold_count == 7, "Basic airplane must complete two corner folds, two taper folds, a body fold, and two wings")
	check(Dump.validate(app._snapshot()).valid, "The complete basic airplane history must pass material and layer-order validation")
	check(FlightModel.wing_folds(app.history).size() == 2, "Flight preparation must identify the two actual wing folds")
	var closed := FlightModel.pose(app.faces, app.history, Vector2.ZERO)
	for i in app.faces.size():
		for j in app.faces[i].points.size():
			var point: Vector2 = app.faces[i].points[j]
			check(closed[i].points[j].distance_to(Vector3(point.x, 0, point.y)) < 0.000005, "3D replay with closed wings must reproduce the actual folded paper")
	for angles in [Vector2(90, 90), Vector2(75, 105), Vector2(45, 60)]:
		var opened := FlightModel.pose(app.faces, app.history, angles)
		check(FlightModel.is_joined(opened), "Runtime seam validation must accept the opened basic airplane")
		var properties := FlightModel.properties(opened)
		check(is_equal_approx(properties.area, 0.04) and is_equal_approx(properties.mass, 0.0032), "Opening wings must preserve material area and real paper mass")
		for face in opened:
			for i in face.paper.size():
				for other in opened:
					for j in other.paper.size():
						var k: int = (j + 1) % other.paper.size()
						var q := Geometry2D.get_closest_point_to_segment(face.paper[i], other.paper[j], other.paper[k])
						if q.distance_to(face.paper[i]) > 0.0000001:
							continue
						var length: float = other.paper[j].distance_to(other.paper[k])
						if length < 0.00000001:
							continue
						var t: float = q.distance_to(other.paper[j]) / length
						check(face.points[i].distance_to(other.points[j].lerp(other.points[k], t)) < 0.00001, "Independent wing angles must never separate a material seam in 3D")
		var panels := FlightModel.panels(opened, properties.center)
		var area := 0.0
		for panel in panels:
			area += panel.area
		check(area > 0.001 and area <= 0.040001, "Aerodynamics must use exposed area without multiplying coincident folded layers")
	var velocity := Vector3(0, -0.5, -5)
	var force := FlightModel.aerodynamic_force(velocity, Vector3.UP, 0.01)
	check(force.y > 0 and force.dot(velocity) <= 0, "Lift must oppose downwash while aerodynamic drag removes energy")
	check(force.is_equal_approx(FlightModel.aerodynamic_force(velocity, Vector3.DOWN, 0.01)), "Force must not depend on polygon winding")
	await capture_preview("13_basic_airplane")
	await _flight_checks(app)
	airplane_finished = true
	root.remove_child(app)
	app.queue_free()
func _flight_checks(app: Node) -> void:
	var before: Array[Dictionary] = app.faces.duplicate(true)
	var previous_history: Array[Dictionary] = app.history.duplicate(true)
	key(app, KEY_B)
	await physics_frame
	await process_frame
	check(app.flight_view != null, "B must open the actual folded model in the flight test")
	var flight: Node = app.flight_view
	check(is_equal_approx(flight.body.mass, 0.0032) and flight.body.panels.size() > 0, "Flight must use measured paper mass and exposed panels")
	_check_grip_orientation(app.faces, app.history, flight.posed)
	var largest_area := 0.0
	var reference_normal := Vector3.ZERO
	for panel in flight.body.panels:
		if panel.area > largest_area:
			largest_area = panel.area
			reference_normal = panel.normal
	check(absf(reference_normal.dot(Vector3.UP)) > 0.9999, "The default 90-degree wing pose must not hide an extra pitch angle")
	check(app.faces == before and app.history == previous_history, "Preparing flight must not alter folding data")
	await _launch_controls_checks(flight)
	await capture_preview("15_flight_ready")
	flight.linked.button_pressed = false
	flight._angle_changed(0, 75)
	flight._angle_changed(1, 105)
	check(flight.angles == Vector2(75, 105), "Wing angles must be adjustable independently")
	check(app._snapshot().flight.angles == Vector2(75, 105), "State dump must include flight preparation angles")
	var flight_dump: Dictionary = Dump.decode(JSON.parse_string(JSON.stringify(Dump.encode(app._snapshot()))))
	check(flight_dump.flight.posed[0].points is PackedVector3Array and flight_dump.flight.angles == Vector2(75, 105), "Flight dump must preserve actual 3D wing geometry and angle settings")
	await check_dump_input(app, false)
	flight.linked.button_pressed = true
	flight._angle_changed(0, 90)
	for trial in 3:
		flight._angle_changed(0, 75 if trial == 1 else 90)
		flight.launch()
		check(flight.running and flight.body.position.distance_to(Vector3(0, 1.5, 0)) < 0.000001, "Each launch must reset the same position")
		var frames := 0
		while flight.running and frames < Engine.physics_ticks_per_second * 13:
			await physics_frame
			frames += 1
			if frames == 12 and trial == 0:
				await capture_preview("16_flying")
		check(not flight.running and flight.trials.size() == trial + 1, "Flight must end and record distance and airtime")
		check(flight.body.position.is_finite() and flight.trials[-1].reason != "수치 오류", "Flight integration must remain finite")
		check(flight.trials[-1].duration_s > 0.1 and flight.trials[-1].distance_m > 0.1, "The fixed launch must produce a measurable flight")
	check(absf(flight.trials[0].distance_m - flight.trials[2].distance_m) < 0.15, "Repeating the same launch settings should give comparable range")
	check(absf(flight.trials[0].distance_m - flight.trials[1].distance_m) > 0.001, "Changing only wing angle must affect the simulated flight")
	print("Flight comparison: ", flight.trials)
	await capture_preview("17_flight_results")
	await _physical_flight_checks(flight)
	app._close_flight()
	await process_frame
	check(app.flight_view == null and app.faces == before and app.history == previous_history, "Returning from flight must restore the exact editable sheet")
func _physical_flight_checks(flight: Node) -> void:
	flight.linked.button_pressed = true
	flight._angle_changed(0, 90)
	flight.aim_sliders[0].value = 0
	flight.aim_sliders[1].value = 3
	flight._reset_attitude()
	check(is_equal_approx(flight.body.gravity_scale, 1.0), "Research-based flights must use normal gravity")
	var ranges: Array[float] = []
	for power in [50.0, 100.0, 80.0, 80.0]:
		flight.power_slider.value = power
		flight.launch()
		var frames := 0
		while flight.running and frames < Engine.physics_ticks_per_second * 13:
			await physics_frame
			frames += 1
		check(not flight.running, "Physical flights must finish within the test limit")
		if flight.running:
			return
		var trial: Dictionary = flight.trials[-1]
		check(trial.reason == "착지", "Physical flights must end on real ground contact")
		ranges.append(trial.distance_m)
		if power == 80:
			var actual_range := Vector2(flight.body.position.x, flight.body.position.z).length()
			check(actual_range > 0.1 and is_finite(actual_range), "The basic plane must physically move and remain finite")
			check(absf(actual_range - float(trial.distance_m)) < 0.001, "Displayed range must match actual world travel")
	check(absf(ranges[0] - ranges[1]) > 0.01, "Throw power must still affect the physical trajectory")
	check(absf(ranges[2] - ranges[3]) < 0.15, "Repeating the physical flight must reproduce its range")
	print("Physical ranges (50%, 100%, 80%, 80%): ", ranges)
	await capture_preview("21_research_flight_results")

func check_dump_input(app: Node, button: bool) -> void:
	var folder := "user://dumps"
	DirAccess.make_dir_recursive_absolute(folder)
	var before := DirAccess.get_files_at(folder)
	if button:
		app.dump_button.pressed.emit()
	else:
		var event := InputEventKey.new()
		event.physical_keycode = KEY_D
		event.ctrl_pressed = true
		event.shift_pressed = true
		event.pressed = true
		Input.parse_input_event(event)
		await process_frame
		await process_frame
	var created: Array[String] = []
	for filename in DirAccess.get_files_at(folder):
		if not filename in before:
			created.append(filename)
	check(created.size() == 1, "Dump button/shortcut must save exactly one file to the default user folder")
	for filename in created:
		var path := folder.path_join(filename)
		var json: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		check(json is Dictionary, "Saved dump must contain readable JSON")
		if json is Dictionary:
			var restored: Dictionary = Dump.decode(json)
			check(Dump.validate(restored).valid, "Actual saved dump must preserve a valid sheet")
			check((restored.flight != null) == (app.flight_view != null), "Saved dump must include the active flight screen")
		DirAccess.remove_absolute(path)
func _launch_controls_checks(flight: Node) -> void:
	var initial: Basis = flight.body.basis
	await _axis_rotation_checks(flight)
	var direction: Vector3 = flight.launch_velocity().normalized()
	for power in [25.0, 75.0, 50.0]:
		flight.power_slider.value = power
		check(is_equal_approx(flight.launch_velocity().length(), power * 0.0816), "Throw power must determine initial speed")
		check(flight.body.basis.is_equal_approx(initial) and flight.launch_velocity().normalized().is_equal_approx(direction), "Power changes must preserve aircraft attitude and launch direction")
	flight.reset_trial()
	check(flight.launch_power == 50, "Resetting the launch position must preserve throw power")
	flight.aim_sliders[0].value = 90
	flight._aim_changed(0, -90)
	check(flight.aim.x == 0 and flight.aim_sliders[0].value == 0 and not flight.aim_sliders[0].editable, "Both the heading slider and legacy callback must preserve fixed forward heading")
	flight.aim_sliders[1].value = 25
	var velocity: Vector3 = flight.launch_velocity()
	check(flight.body.basis.is_equal_approx(initial), "Changing launch direction must not rotate the aircraft")
	check(is_zero_approx(velocity.x) and velocity.y > 1 and velocity.z < -3, "Elevation must change the vertical launch component while heading stays forward")
	await process_frame
	var position: Vector2 = flight.camera.unproject_position(flight.body.global_position)
	var press := InputEventMouseButton.new()
	press.position = position
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = position + Vector2(40, 20)
	motion.relative = Vector2(40, 20)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(motion)
	await process_frame
	check(not flight.body.basis.is_equal_approx(initial), "Dragging the preview must rotate the actual rigid body")
	var rotated: Basis = flight.body.basis
	motion.relative = Vector2(30, 0)
	motion.shift_pressed = true
	Input.parse_input_event(motion)
	await process_frame
	check(not flight.body.basis.is_equal_approx(rotated), "Shift-drag must allow rolling the aircraft")
	press.pressed = false
	Input.parse_input_event(press)
	await process_frame
	check(not flight.dragging, "Releasing the mouse must end preview rotation")
	rotated = flight.body.basis
	check(flight.launch_velocity().is_equal_approx(velocity), "Rotating the aircraft must preserve the chosen launch vector")
	flight._angle_changed(0, 80)
	check(flight.body.basis.is_equal_approx(rotated), "Changing wing shape must preserve the chosen attitude")
	flight.reset_trial()
	check(flight.body.basis.is_equal_approx(rotated) and flight.aim == Vector2(0, 25), "Returning to launch must preserve attitude and direction")
	var saved: Dictionary = Dump.decode(JSON.parse_string(JSON.stringify(Dump.encode(flight.snapshot()))))
	check(saved.launch_power == 50 and saved.launch_transform.basis.is_equal_approx(rotated) and saved.aim_degrees == Vector2(0, 25), "Dump must preserve the selected launch attitude and aim")
	flight.launch()
	check(flight.body.linear_velocity.is_equal_approx(velocity) and flight.body.basis.is_equal_approx(rotated), "Launching must use the previewed pose and direction")
	flight._rotate_preview(Vector2(100, 100), false)
	flight._aim_changed(0, 120)
	flight._power_changed(25)
	check(flight.launch_power == 50 and not flight.power_slider.editable, "Power must remain fixed during flight")
	check(flight.body.basis.is_equal_approx(rotated) and flight.aim.x == 0, "Preparation controls must not change a flying aircraft")
	flight._finish("조작 검사")
	check(flight.trials[-1].launch_power == 50 and flight.trials[-1].launch_transform.basis.is_equal_approx(rotated) and flight.trials[-1].launch_velocity.is_equal_approx(velocity), "Trial records must preserve their original launch settings")
	check(not flight.aim_sliders[0].editable and flight.aim_sliders[1].editable, "Landing must re-enable elevation without re-enabling heading")
	flight.aim.x = 73
	flight.aim_sliders[0].set_value_no_signal(73)
	check(is_zero_approx(flight.launch_velocity().x), "A stale heading value must not affect launch physics")
	flight.reset_trial()
	check(flight.aim == Vector2(0, 25) and flight.aim_sliders[0].value == 0 and not flight.aim_sliders[0].editable, "Retry must normalize stale heading state and keep its UI disabled")
	flight.trials.clear()
	flight.results.text = ""
	flight.aim_sliders[0].value = 0
	flight.aim_sliders[1].value = 3
	flight._reset_attitude()
	flight._angle_changed(0, 90)
	check(flight.body.basis.is_equal_approx(initial), "The attitude reset must restore the initial preview")

func _user_launch_checks() -> void:
	check(not FlightModel.is_joined([]), "Missing flight geometry must never be accepted for launch")
	var fixture: Dictionary = Dump.decode(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/user_completed_airplane.json")))
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	await process_frame
	app.faces.assign(fixture.faces)
	app.history.assign(fixture.history)
	app.fold_count = 8
	app._refresh()
	key(app, KEY_B)
	await physics_frame
	await process_frame
	var flight: Node = app.flight_view
	check(flight.ready_to_launch and flight.posed.size() == fixture.faces.size() and flight.body.panels.size() > 0, "The user's completed airplane must support preparing a flight")
	await _launch_controls_checks(flight)
	await capture_preview("18_user_launch_controls")
	for power in [25.0, 50.0, 75.0, 100.0]:
		flight.power_slider.value = power
		flight.launch()
		check(is_equal_approx(flight.body.linear_velocity.length(), power * 0.0816), "Actual launch must use the chosen power")
		var frames := 0
		while flight.running and frames < Engine.physics_ticks_per_second * 13:
			await physics_frame
			frames += 1
		check(not flight.running and flight.trials[-1].launch_power == power and flight.trials[-1].reason != "수치 오류", "Each power trial must complete with finite physics and its own setting")
	check(flight.trials[1].distance_m > flight.trials[0].distance_m, "The user's airplane must fly farther at 50% power than at 25% under identical launch conditions")
	print("Throw power comparison: ", flight.trials)
	await capture_preview("19_throw_power_comparison")
	app._close_flight()
	await process_frame
	root.remove_child(app)
	app.queue_free()
func _check_grip_orientation(faces: Array[Dictionary], history: Array[Dictionary], posed: Array[Dictionary]) -> void:
	var wings: Array[Dictionary] = []
	var grip: Array[Dictionary] = []
	for i in faces.size():
		var center := Vector2.ZERO
		for point in faces[i].paper:
			center += point
		center /= faces[i].paper.size()
		var is_wing := false
		for index in FlightModel.wing_folds(history):
			for part in history[index].plan.move:
				is_wing = is_wing or Paper._inside_convex(part.paper, center)
		if is_wing:
			wings.append(posed[i])
		else:
			grip.append(posed[i])
	check(not wings.is_empty() and not grip.is_empty(), "The airplane fixture must contain separate wings and a grip")
	var gap: Vector3 = FlightModel.properties(grip).center - FlightModel.properties(wings).center
	check(gap.y < -0.001, "The default launch pose must place the grip below the wings, including after paper flips")
	var largest := 0.0
	var normal := Vector3.ZERO
	for panel in FlightModel.panels(wings, Vector3.ZERO):
		if panel.area > largest:
			largest = panel.area
			normal = panel.normal
	check(absf(normal.dot(Vector3.UP)) > 0.9999, "The deployed wing plane must be horizontal in the default model frame")

func _grip_orientation_checks() -> void:
	root.size = Vector2i(1280, 720)
	for filename in ["grip_orientation", "user_completed_airplane"]:
		var fixture: Dictionary = Dump.decode(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + filename + ".json")))
		var faces: Array[Dictionary] = []
		faces.assign(fixture.faces)
		var history: Array[Dictionary] = []
		history.assign(fixture.history)
		for flips in 3:
			var flight: Node = load("res://scripts/flight_test.gd").new()
			flight.configure(faces, history, null)
			root.add_child(flight)
			await _wait_layout()
			check(flight.ready_to_launch and flight.angles == Vector2(90, 90), "Every paper orientation must start with deployed, connected wings")
			_check_grip_orientation(faces, history, flight.posed)
			if filename == "grip_orientation" and flips == 0:
				await capture_preview("22_grip_below_wings")
			var initial: Basis = flight.attitude
			var upside_down := Basis(Vector3.FORWARD, PI) * initial
			flight._set_attitude(upside_down)
			flight._angle_changed(0, 75)
			check(flight.attitude.is_equal_approx(upside_down), "Manual inverted attitudes must survive wing edits")
			flight._reset_attitude()
			check(flight.attitude.is_equal_approx(initial), "Reset must restore the default attitude")
			root.remove_child(flight)
			flight.queue_free()
			history.append({"kind": "flip", "faces": faces.duplicate(true), "fold_count": 8, "single_layer": false, "plan": {}})
			faces = Paper.flipped(faces)
	grip_orientation_finished = true

func _axis_rotation_checks(flight: Node) -> void:
	var initial: Basis = flight.attitude
	var aim: Vector2 = flight.aim
	for axis in 3:
		flight._set_attitude(initial)
		var points: PackedVector2Array = flight.gizmo.ring_points(axis)
		var start := -1
		for i in flight.gizmo.SEGMENTS:
			if points[i].x > 500 and points[i].y > 30 and points[i].y < 680 and flight.gizmo.pick_axis(points[i]) == axis:
				start = i
				break
		check(start >= 0, "Each X/Y/Z rotation ring must be independently selectable")
		if start < 0:
			continue
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.position = root.get_final_transform() * points[start]
		press.global_position = press.position
		press.pressed = true
		Input.parse_input_event(press)
		await process_frame
		check(flight.gizmo.selected_axis == axis, "Clicking a ring must select its own world axis")
		var motion := InputEventMouseMotion.new()
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		motion.position = root.get_final_transform() * points[(start + 12) % flight.gizmo.SEGMENTS]
		motion.global_position = motion.position
		Input.parse_input_event(motion)
		await process_frame
		var expected: Basis = Basis(flight.gizmo.AXES[axis], PI / 4) * initial
		check(flight.attitude.is_equal_approx(expected), "Ring dragging must rotate only the selected world axis by the pointer angle")
		motion.shift_pressed = true
		motion.position = root.get_final_transform() * points[(start + 9) % flight.gizmo.SEGMENTS]
		motion.global_position = motion.position
		Input.parse_input_event(motion)
		await process_frame
		expected = Basis(flight.gizmo.AXES[axis], deg_to_rad(30)) * initial
		check(flight.attitude.is_equal_approx(expected), "Shift-ring dragging must snap to 15 degree increments")
		press.pressed = false
		Input.parse_input_event(press)
		await process_frame
		check(flight.gizmo.selected_axis == -1 and not flight.dragging, "Mouse release must clear the active rotation axis")
		flight._set_attitude(initial)
		var euler := initial.get_euler()
		euler[axis] = deg_to_rad(45)
		flight.pose_fields[axis].value = 45
		check(flight.attitude.is_equal_approx(Basis.from_euler(euler)), "Numeric axis fields must apply precise Euler angles")
		check(flight.aim == aim, "Axis rotation must preserve the independent launch direction")
	flight._set_attitude(initial)
func _reference_checks() -> void:
	var square := Paper.square()
	var point := Vector2(0.03, 0.04)
	var definition := FoldReference.point_definition(square, point)
	var half := Paper.folded(Paper.plan(square, Vector2.ZERO, Vector2.UP, Vector2(0.1, 0)))
	check(FoldReference.geometry(half, definition).centers[0].distance_to(Vector2(-0.03, 0.04)) < Paper.EPS, "Custom reference points must follow the material through folding")
	var turned := Paper.flipped(half)
	check(FoldReference.geometry(turned, definition).centers[0].distance_to(Vector2(-0.07, 0.04)) < Paper.EPS, "Custom reference points must follow flipping")
	var selected_after_fold := FoldReference.point_definition(half, Vector2(-0.03, 0.04))
	check(selected_after_fold.point.distance_to(point) < Paper.EPS, "Picking a point on folded paper must select the exposed layer's material position")
	var guide := FoldReference.line_definition(square, Vector2(0.03, -0.02), Vector2(0.03, 0.02))
	var geometry := FoldReference.geometry(square, guide)
	check(geometry.centers.is_empty() and geometry.segments.size() == 1 and is_equal_approx(geometry.segments[0][0].distance_to(geometry.segments[0][1]), 0.2), "A short drawn reference line must extend to the paper edges")
	geometry = FoldReference.geometry(half, guide)
	check(geometry.segments.size() == 1 and absf(geometry.segments[0][0].x + 0.03) < Paper.EPS, "Reference lines must move with the folded material")
	var crossing := FoldReference.line_definition(square, Vector2(-0.02, 0.03), Vector2(0.02, 0.03))
	geometry = FoldReference.geometry(half, crossing)
	check(geometry.segments.size() == 2, "A reference line crossing a crease must split into attached segments")
	var on_folded := FoldReference.line_definition(half, Vector2(-0.05, -0.02), Vector2(-0.05, 0.02))
	check(FoldReference.geometry(square, on_folded).segments.size() == 2, "A guide drawn across stacked paper must preserve each layer when unfolded")
	check(FoldReference.point_definition(square, Vector2.ONE).is_empty(), "Outside points must not become paper reference points")
	check(FoldReference.line_definition(square, Vector2.ONE, Vector2(1, 2)).is_empty(), "Outside lines must not become paper guides")
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	await process_frame
	key(app, KEY_4)
	await routed_mouse(app, point, true)
	await routed_mouse(app, point, false)
	check(not app.reference_editing and app.custom_reference.kind == "point", "4 and clicking must set a custom snap point and return to folding")
	var nearby := point + Vector2(0.003, 0.002)
	check(app._line_start_preview(nearby, false).distance_to(point) < Paper.EPS, "Dragging and crease drawing must snap to the custom point")
	check(app._line_start_preview(nearby, true) == nearby, "Shift must bypass the custom reference")
	var off_center := Vector2(0.002, 0.003)
	check(app._line_start_preview(off_center, false) == off_center, "Custom references must replace the original center guides")
	var saved_definition: Dictionary = app.custom_reference.duplicate(true)
	key(app, KEY_4)
	app._press(Vector2(0.02, 0.02), true)
	app._motion(Vector2(0.07, 0.04), true)
	key(app, KEY_ESCAPE)
	check(app.custom_reference == saved_definition and not app.reference_drawing and app.fold_count == 0, "Cancelling reference editing must preserve the previous guide and paper")
	key(app, KEY_4)
	app._press(Vector2(0.02, 0.02), true)
	app._focus_lost()
	check(not app.reference_drawing and not app.reference_editing and app.custom_reference == saved_definition, "Losing focus must cancel reference editing without changing the guide")
	app.reference_tool.select(1)
	key(app, KEY_4)
	app._press(Vector2(0.03, -0.05), true)
	app._motion(Vector2(0.03, 0.07), true)
	app._release(Vector2(0.03, 0.07), true)
	check(app.custom_reference.kind == "line" and app.reference.segments.size() == 1, "Reference-line mode must create a guide without folding the paper")
	check(app._line_start_preview(Vector2(0.032, 0.02), false).distance_to(Vector2(0.03, 0.02)) < Paper.EPS, "Custom lines must attract the pointer to the nearest point on the line")
	await capture_preview("20_custom_reference_line")
	var restored: Dictionary = Dump.decode(JSON.parse_string(JSON.stringify(Dump.encode(app._snapshot()))))
	check(restored.reference.definition.kind == "line" and restored.reference.definition.segments[0] is PackedVector2Array, "Dumps must preserve material-space references and displayed geometry")
	app.faces = half
	app._refresh()
	check(absf(app.reference.segments[0][0].x + 0.03) < Paper.EPS, "Refreshing folded paper must update the custom reference")
	app.faces = turned
	app._refresh()
	check(absf(app.reference.segments[0][0].x + 0.07) < Paper.EPS, "Refreshing flipped paper must update the custom reference")
	app.faces = square
	app._refresh()
	check(absf(app.reference.segments[0][0].x - 0.03) < Paper.EPS, "Restoring paper history must restore the reference projection")
	app._reset_reference()
	check(app.custom_reference.is_empty() and app.reference.centers[0] == Vector2.ZERO and app.reference.segments.size() == 2, "Default-center reset must restore the original point and axes")
	app.custom_reference = definition
	app._reset_paper()
	check(app.custom_reference.is_empty(), "A new sheet must clear custom references")
	root.remove_child(app)
	app.queue_free()
func _assert_paper_work_area(app: Node, message: String) -> void:
	for face in app.faces:
		for point in face.points:
			var screen: Vector2 = app._screen(point)
			check(app.work_area.has_point(screen), message + ": paper must be inside the working area")
			check(not app.toolbar.get_global_rect().has_point(screen) and not app.footer.get_global_rect().has_point(screen), message + ": paper must not overlap toolbars")
			if app.guide_panel.visible:
				check(not app.guide_panel.get_global_rect().has_point(screen), message + ": paper must not overlap the guide")
			check(app._paper_position(screen).distance_to(point) < Paper.EPS, message + ": projection must round-trip")

func _wait_layout() -> void:
	for frame in 4:
		await process_frame

func _fold_ux_checks() -> void:
	for size in [Vector2i(1280, 720), Vector2i(640, 360)]:
		root.size = size
		var app: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(app)
		await _wait_layout()
		check(root.get_visible_rect().size == Vector2(size), "Folding UI must use physical window pixels for readable small-window text")
		check(app.mode_one.get_theme_font_size("font_size") >= 14, "Small-window controls must retain readable font size")
		check(not app.tools.visible and app.mode_one.is_visible_in_tree() and app.flight_button.is_visible_in_tree(), "Diagnostics must start folded away while essential actions remain visible")
		_assert_paper_work_area(app, "Initial " + str(size))
		key(app, KEY_G)
		await _wait_layout()
		_assert_paper_work_area(app, "Guide open " + str(size))
		for button in [app.mode_one, app.mode_two, app.layer_toggle, app.flip_button, app.undo_button, app.unfold_button, app.guide_button, app.flight_button, app.tools_button]:
			check(Rect2(Vector2.ZERO, Vector2(size)).encloses(button.get_global_rect()), "Every essential button must remain inside the supported window")
		await capture_preview("ux_01_guide_" + str(size.x))
		var camera_transform: Transform3D = app.camera.transform
		var camera_size: float = app.camera.size
		await routed_mouse(app, Vector2(0.1, 0), true)
		await routed_motion(app, Vector2(-0.05, 0))
		check(not app.fold_plan.is_empty(), "A visible edge must still be grabbable after guide-aware fitting")
		for displayed in app._snapshot().render.posed_faces:
			for vertex in displayed.world_vertices:
				check(app.work_area.has_point(app.camera.unproject_position(vertex)), "The current moving and stationary faces must remain visible during the guide drag")
		check(app.camera.transform == camera_transform and app.camera.size == camera_size, "Dragging must not refit or pan the camera under the cursor")
		check(app._paper_position(app._screen(Vector2(-0.05, 0))).distance_to(Vector2(-0.05, 0)) < Paper.EPS, "Dragging must preserve cursor-to-paper projection")
		await capture_preview("ux_02_moving_region_" + str(size.x))
		await routed_mouse(app, Vector2(-0.05, 0), false)
		await create_timer(0.3).timeout
		key(app, KEY_F)
		await create_timer(0.45).timeout
		await _wait_layout()
		_assert_paper_work_area(app, "After flip " + str(size))
		key(app, KEY_G)
		await _wait_layout()
		_assert_paper_work_area(app, "Guide closed " + str(size))
		var alternate := Vector2i(640, 360) if size.x == 1280 else Vector2i(1280, 720)
		root.size = alternate
		await _wait_layout()
		_assert_paper_work_area(app, "Resized existing window " + str(alternate))
		root.size = size
		await _wait_layout()
		app._reset_paper()
		await _wait_layout()
		key(app, KEY_2)
		app._press(Vector2(0, -0.1), true)
		app._motion(Vector2(0, 0.1), true)
		app._release(Vector2(0, 0.1), true)
		app._press(Vector2(0.1, 0), true)
		app._motion(Vector2(0.02, 0), true)
		check(not app._can_commit() and "아직" in app.status.text, "A shallow preview must warn that releasing cancels")
		await capture_preview("ux_03_not_ready_" + str(size.x))
		app._release(Vector2(0.02, 0), true)
		check(app.faces == Paper.square() and app.fold_count == 0 and "조금 더" in app.status.text, "Cancelling a shallow fold must preserve paper and explain the next action")
		app._press(Vector2(0.1, 0), true)
		app._motion(Vector2(-0.05, 0), true)
		check(app._can_commit() and "확정" in app.status.text, "An adequate preview must announce that release commits")
		await capture_preview("ux_04_ready_" + str(size.x))
		app._release(Vector2(-0.05, 0), true)
		await create_timer(0.3).timeout
		check(app.fold_count == 1, "Release-ready indication must agree with actual immediate commit")
		key(app, KEY_G)
		app._set_guide_step(9)
		await _wait_layout()
		check(app.guide_flight.visible and not app.guide_flight.disabled, "The final guide must expose flight without claiming automatic completion")
		await capture_preview("ux_05_last_guide_" + str(size.x))
		var before: Array[Dictionary] = app.faces.duplicate(true)
		app.guide_flight.pressed.emit()
		await physics_frame
		await process_frame
		check(app.flight_view != null and root.content_scale_size == Vector2i(1280, 720), "Guide flight action must reuse the existing scaled flight preparation UI")
		await capture_preview("ux_06_flight_" + str(size.x))
		app._close_flight()
		await _wait_layout()
		check(root.content_scale_size == Vector2i.ZERO and root.size == size and app.faces == before, "Returning from flight must restore folding layout scale and exact paper")
		_assert_paper_work_area(app, "Flight return " + str(size))
		await capture_preview("ux_07_return_" + str(size.x))
		app._reset_paper()
		var dump_key := InputEventKey.new()
		dump_key.physical_keycode = KEY_D
		dump_key.ctrl_pressed = true
		dump_key.shift_pressed = true
		dump_key.pressed = true
		var prior_files := DirAccess.get_files_at("user://dumps")
		Input.parse_input_event(dump_key)
		await _wait_layout()
		check(not app.tools.visible and app.dump_notice.is_visible_in_tree() and app.dump_notice.text.begins_with("저장됨"), "Shortcut save feedback must remain visible with diagnostics closed")
		for filename in DirAccess.get_files_at("user://dumps"):
			if not filename in prior_files:
				DirAccess.remove_absolute("user://dumps/" + filename)
		await capture_preview("ux_08_dump_notice_" + str(size.x))
		var failed: String = app._dump_state("res://build/nonexistent-dump-test-folder/fail.json")
		await _wait_layout()
		check(failed.is_empty() and app.dump_notice.is_visible_in_tree() and "실패" in app.dump_notice.text and not app.tools.visible, "Dump failures must remain visible with diagnostics closed")
		app.dump_notice.text = ""
		key(app, KEY_1)
		await _wait_layout()
		await routed_mouse(app, Vector2(-0.1, 0), true)
		await routed_motion(app, Vector2(0.1, 0))
		await routed_mouse(app, Vector2(0.1, 0), false)
		await create_timer(0.3).timeout
		check(app.fold_count == 1, "Actual mouse folding must still work after a flight round-trip")
		root.remove_child(app)
		app.queue_free()
	root.size = Vector2i(1280, 720)
	await _wait_layout()
func _small_guide_checks() -> void:
	root.size = Vector2i(640, 360)
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await _wait_layout()
	key(app, KEY_G)
	var instructions := AirplaneGuide.steps()
	for index in instructions.size():
		app._set_guide_step(index)
		await _wait_layout()
		var step: Dictionary = instructions[index]
		if step.action == "unfold":
			key(app, KEY_U)
			await create_timer(0.6).timeout
		elif step.action == "flip":
			key(app, KEY_F)
			await create_timer(0.45).timeout
		else:
			var count: int = app.fold_count
			app._set_mode(2)
			app._set_single_layer(step.single_layer)
			await routed_mouse(app, step.a, true)
			await routed_motion(app, step.b)
			await routed_mouse(app, step.b, false)
			check(app.line_ready, "Small-window guide must allow drawing crease at step " + str(index + 1))
			await routed_mouse(app, step.grab, true)
			await routed_motion(app, step.target)
			check(app._can_commit(), "Small-window guide must allow completing fold at step " + str(index + 1))
			await capture_preview("ux_small_step_" + str(index + 1))
			await routed_mouse(app, step.target, false)
			await create_timer(0.3).timeout
			check(app.fold_count == count + 1, "Small-window routed guide must commit once at step " + str(index + 1))
		await _wait_layout()
		_assert_paper_work_area(app, "Small guide step " + str(index + 1))
	check(app.fold_count == 7 and Dump.validate(app._snapshot()).valid, "The entire basic airplane must remain foldable and valid at minimum window size")
	await capture_preview("ux_09_completed_640")
	root.remove_child(app)
	app.queue_free()
	root.size = Vector2i(1280, 720)
	await _wait_layout()

func _surface_hit(flight: Node, point: Vector2, above: bool) -> Dictionary:
	var arrays: Array = flight.mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var offsets: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var order: Array[int] = []
	if arrays[Mesh.ARRAY_INDEX] == null or arrays[Mesh.ARRAY_INDEX].is_empty():
		for i in vertices.size(): order.append(i)
	else:
		for i in arrays[Mesh.ARRAY_INDEX]: order.append(i)
	var best := -INF if above else INF
	var hit: Dictionary = {}
	for i in range(0, order.size(), 3):
		var triangle: Array[Vector3] = []
		for j in 3:
			var index := order[i + j]
			triangle.append(flight.body.basis * (vertices[index] + normals[index] * offsets[index].x))
		var a := Vector2(triangle[0].x, triangle[0].z)
		var u := Vector2(triangle[1].x, triangle[1].z) - a
		var v := Vector2(triangle[2].x, triangle[2].z) - a
		var determinant := u.cross(v)
		if absf(determinant) < 0.0000000001: continue
		var relative := point - a
		var s := relative.cross(v) / determinant
		var t := u.cross(relative) / determinant
		if s < 0.0001 or t < 0.0001 or s + t > 0.9999: continue
		var height := triangle[0].y + s * (triangle[1].y - triangle[0].y) + t * (triangle[2].y - triangle[0].y)
		if (above and height > best) or (not above and height < best):
			best = height
			var normal: Vector3 = flight.body.basis * normals[order[i]]
			hit = {"height": height, "front": normal.y > 0 if above else normal.y < 0}
	return hit

func _check_surface_mesh(flight: Node) -> void:
	var arrays: Array = flight.mesh.mesh.surface_get_arrays(0)
	var offsets: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	check(offsets.size() == normals.size(), "Every render vertex must carry its deployed layer offset")
	for offset in offsets:
		check(absf(offset.x) <= 0.000301, "Visual stack separation must stay bounded without modifying physical paper")
	var closed := FlightModel.pose(flight.faces, flight.history, Vector2.ZERO)
	for i in flight.posed.size():
		check(flight.posed[i].layer_sign * closed[i].normal.y > 0.999, "Each posed face must preserve the original folded-layer up direction")
	check(FlightModel.is_joined(flight.posed), "Visual layer separation must leave actual material seams joined")

func _check_surface_pixels(flight: Node, image: Image, above: bool, symmetric: bool) -> int:
	var origin: Vector3 = -(flight.body.basis * flight.properties.center)
	var samples := 0
	for x in [0.005, 0.01, 0.02, 0.03]:
		for z in [-0.01, 0.01, 0.04, 0.075]:
			var pair: Array[Dictionary] = []
			for side in [-1, 1]:
				var point := Vector2(origin.x + side * x, origin.z + z)
				var hit := _surface_hit(flight, point, above)
				pair.append(hit)
				if hit.is_empty(): continue
				var world: Vector3 = flight.body.position + Vector3(point.x, hit.height, point.y)
				var screen: Vector2 = flight.camera.unproject_position(world)
				if screen.x < 490 or screen.x >= image.get_width() - 2 or screen.y < 2 or screen.y >= image.get_height() - 2: continue
				var pixel := Vector2i(screen.round())
				var ray: Vector3 = flight.camera.project_ray_origin(Vector2(pixel) + Vector2(0.5, 0.5))
				var sampled := _surface_hit(flight, Vector2(ray.x - flight.body.position.x, ray.z - flight.body.position.z), above)
				if sampled.is_empty(): continue
				hit = sampled
				var color := image.get_pixelv(pixel)
				if color.r < 0.4: continue # Avoid sampling the intentionally dark crease ink.
				var cream := color.b / maxf(color.r, 0.001) > 0.6
				check(cream == not hit.front, "GPU color must match the outer material side: %s point=%s color=%s hit=%s" % [flight.get_meta("surface_case"), point, color, hit])
				samples += 1
			if symmetric and not pair[0].is_empty() and not pair[1].is_empty():
				check(pair[0].front == pair[1].front, "A symmetric fold must expose matching material sides on mirrored wing samples")
	check(samples >= 2, "Surface color regression must sample actual visible paper")
	return samples

func _surface_layer_checks() -> void:
	root.size = Vector2i(1280, 720)
	var rendered := DisplayServer.get_name() != "headless"
	for filename in ["wing_surface_overlap", "user_completed_airplane", "grip_orientation"]:
		var fixture: Dictionary = Dump.decode(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + filename + ".json")))
		var faces: Array[Dictionary] = []
		faces.assign(fixture.faces)
		var history: Array[Dictionary] = []
		history.assign(fixture.history)
		for flip in 2:
			var flight: Node = load("res://scripts/flight_test.gd").new()
			flight.configure(faces, history, null)
			root.add_child(flight)
			await _wait_layout()
			check(flight.ready_to_launch and flight.angles == Vector2(90, 90) and not flight.aim_sliders[0].editable, "Surface rendering must preserve deployed wings and locked forward heading")
			_check_surface_mesh(flight)
			if filename == "wing_surface_overlap" and flip == 0:
				await capture_preview("surface_01_oblique")
			flight.set_process(false)
			flight.gizmo.visible = false
			for inverted in 2:
				flight._set_attitude(Basis.IDENTITY if inverted == 0 else Basis(Vector3.FORWARD, PI))
				flight.launch_arrow.visible = false
				flight.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
				flight.camera.size = 0.32
				flight.camera.h_offset = -0.1
				for above in [true, false]:
					var direction := Vector3.UP if above else Vector3.DOWN
					flight.camera.position = flight.body.position + direction * 0.5
					flight.camera.look_at(flight.body.position, Vector3.FORWARD)
					flight.camera.reset_physics_interpolation()
					if rendered:
						await process_frame
						await RenderingServer.frame_post_draw
						flight.set_meta("surface_case", filename + " flip=%d inverted=%d above=%s" % [flip, inverted, above])
						check(_check_surface_pixels(flight, root.get_texture().get_image(), above, filename == "wing_surface_overlap") >= 2, "GPU surface sampling must complete without a runtime error")
					if filename == "wing_surface_overlap" and flip == 0:
						await capture_preview("surface_02_" + ("top" if above else "bottom") + ("_inverted" if inverted else ""))
			flight._set_attitude(Basis(Vector3.FORWARD, PI))
			flight.linked.button_pressed = false
			var symmetric_pose: Array[Dictionary] = flight.posed.duplicate(true)
			flight._angle_changed(0, 70)
			flight._angle_changed(1, 100)
			var moved := false
			for i in flight.posed.size():
				for j in flight.posed[i].points.size():
					moved = moved or flight.posed[i].points[j].distance_to(symmetric_pose[i].points[j]) > 0.001
			check(moved and flight.angles == Vector2(70, 100), "Layer rendering must not force independently edited wings back into a symmetric shape")
			check(flight.attitude.is_equal_approx(Basis(Vector3.FORWARD, PI)), "Wing editing must preserve the player's manually inverted attitude")
			_check_surface_mesh(flight)
			if filename == "wing_surface_overlap" and flip == 0:
				await capture_preview("surface_03_asymmetric_angles")
			root.remove_child(flight)
			flight.queue_free()
			history.append({"kind": "flip", "faces": faces.duplicate(true), "single_layer": true})
			faces = Paper.flipped(faces)
func _preset_fixture_state(filename: String) -> Dictionary:
	var fixture: Dictionary = Dump.decode(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + filename + ".json")))
	var count := 0
	for entry in fixture.history:
		if entry.kind == "fold": count += 1
	return {"faces": fixture.faces, "history": fixture.history, "fold_count": count, "reference": FoldReference.line_definition(Paper.square(), Vector2(0, -0.1), Vector2(0, 0.1))}

func _write_preset_test(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Preset regression fixture must be writable")
	if file != null: file.store_string(text)

func _clean_preset_test(folder: String) -> void:
	check(ProjectSettings.globalize_path(folder).begins_with(ProjectSettings.globalize_path("res://build/")), "Preset tests may clean only their build folder")
	if not ProjectSettings.globalize_path(folder).begins_with(ProjectSettings.globalize_path("res://build/")): return
	for filename in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder.path_join(filename))
	DirAccess.remove_absolute(folder)

func _preset_checks() -> void:
	var folder := "res://build/preset_test_%s" % Time.get_ticks_usec()
	var store := Presets.new(folder)
	check(store.list_presets().is_empty(), "A fresh preset library must start empty")
	for filename in ["wing_surface_overlap", "user_completed_airplane", "grip_orientation"]:
		var state := _preset_fixture_state(filename)
		var name: String = "도면 / : " + filename
		var saved := store.save_preset(name, state)
		check(saved.ok, "A folded airplane and its history must save: " + str(saved))
		if not saved.ok: continue
		check(saved.path.get_base_dir() == folder, "Preset names must never become filesystem paths")
		var restored := Presets.new(folder).load_preset(saved.path)
		check(restored.ok, "A new library instance must read the saved sheet: " + str(restored.get("error", "")))
		if not restored.ok: continue
		check(restored.sheet.fold_count == state.fold_count and restored.sheet.faces == state.faces and restored.sheet.reference == state.reference, "Preset persistence must retain actual paper and material-space references")
		var original_faces: Array[Dictionary] = []
		var original_history: Array[Dictionary] = []
		original_faces.assign(state.faces)
		original_history.assign(state.history)
		var before := FlightModel.pose(original_faces, original_history, Vector2(90, 90))
		var after := FlightModel.pose(restored.sheet.faces, restored.sheet.history, Vector2(90, 90))
		check(FlightModel.is_joined(after) and before == after, "Loading a preset must reproduce the same deployed airplane")
		var old_text := FileAccess.get_file_as_string(saved.path)
		check(not store.save_preset(name, state).ok and FileAccess.get_file_as_string(saved.path) == old_text, "Unconfirmed duplicate saves must preserve the original file")
		var replacement: Dictionary = state.duplicate(true)
		replacement.reference = FoldReference.point_definition(Paper.square(), Vector2(0.02, 0.03))
		check(store.save_preset(name, replacement, true).ok, "Confirmed overwrite must atomically replace an existing preset")
		check(store.load_preset(saved.path).sheet.reference == replacement.reference, "Overwrite must persist the replacement data")
		var invalid: Dictionary = state.duplicate(true)
		invalid.fold_count += 1
		var prior := FileAccess.get_file_as_string(saved.path)
		check(not store.save_preset(name, invalid, true).ok and FileAccess.get_file_as_string(saved.path) == prior, "Validation failure must never overwrite a good preset")
	check(Presets.new(folder).list_presets().size() == 3, "Saved presets must remain discoverable after recreating the store")
	check(not store.save_preset("  ", {"faces": [], "history": [], "fold_count": 0}).ok, "Empty names must be rejected without writing")
	var valid_path := store.path_for("도면 / : wing_surface_overlap")
	var encoded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(valid_path))
	var bad_path := folder.path_join("corrupt.json")
	_write_preset_test(bad_path, "{broken")
	check(not store.load_preset(bad_path).ok, "Malformed JSON must fail gracefully")
	store.list_presets()
	check(not store.list_errors.is_empty(), "Unreadable preset files must be reported without removing them")
	var bad: Dictionary = encoded.duplicate(true)
	bad.sheet.history[0].plan.normal.x = "invalid"
	_write_preset_test(bad_path, JSON.stringify(bad))
	check(not store.load_preset(bad_path).ok, "Malformed vector tags must be rejected before native decoding")
	bad = encoded.duplicate(true)
	bad.sheet.history[0].erase("plan")
	_write_preset_test(bad_path, JSON.stringify(bad))
	check(not store.load_preset(bad_path).ok, "Missing history fields must not crash replay")
	bad = encoded.duplicate(true)
	bad.sheet.faces[0].seams["values"] = ["invalid"]
	_write_preset_test(bad_path, JSON.stringify(bad))
	check(not store.load_preset(bad_path).ok, "Invalid seam values must be rejected")
	bad = encoded.duplicate(true)
	bad.version = 99
	_write_preset_test(bad_path, JSON.stringify(bad))
	check(not store.load_preset(bad_path).ok, "Unsupported preset versions must be rejected")
	for size in [Vector2i(1280, 720), Vector2i(640, 360)]:
		root.size = size
		var ui_folder := folder.path_join("ui_" + str(size.x))
		var app: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(app)
		await _wait_layout()
		app.preset_store = Presets.new(ui_folder)
		var state := _preset_fixture_state("wing_surface_overlap")
		app.faces.assign(state.faces)
		app.history.assign(state.history)
		app.fold_count = state.fold_count
		app.custom_reference = state.reference
		app._refresh()
		key(app, KEY_P)
		await _wait_layout()
		check(app.preset_shade.visible and Rect2(Vector2.ZERO, Vector2(size)).encloses(app.preset_panel.get_global_rect()), "Preset UI must fit the supported window")
		app.preset_name.text = "첫 종이비행기"
		app.preset_save.pressed.emit()
		var path: String = app.preset_store.path_for("첫 종이비행기")
		check(FileAccess.file_exists(path), "The save UI must persist the current diagram")
		await capture_preview("preset_01_saved_" + str(size.x))
		var prior := FileAccess.get_file_as_string(path)
		app.custom_reference = FoldReference.point_definition(Paper.square(), Vector2(0.02, 0.03))
		app._request_preset_save()
		check(app.preset_pending.get("kind") == "save" and FileAccess.get_file_as_string(path) == prior, "Duplicate UI save must wait for overwrite confirmation")
		app.preset_cancel.pressed.emit()
		check(FileAccess.get_file_as_string(path) == prior, "Cancelling overwrite must preserve the saved diagram")
		app._request_preset_save()
		app.preset_confirm.pressed.emit()
		check(app.preset_store.load_preset(path).sheet.reference.kind == "point", "Confirming overwrite must save the changed reference")
		app._hide_presets()
		root.remove_child(app)
		app.queue_free()
		app = load("res://scenes/main.tscn").instantiate()
		root.add_child(app)
		await _wait_layout()
		app.preset_store = Presets.new(ui_folder)
		key(app, KEY_P)
		app._request_preset_load()
		check(app.preset_pending.get("kind") == "load" and app.faces == Paper.square(), "Loading must not replace the current sheet before confirmation")
		await capture_preview("preset_02_load_confirmation_" + str(size.x))
		app.preset_cancel.pressed.emit()
		check(app.faces == Paper.square(), "Cancelling load must preserve the current work")
		app._request_preset_load()
		app.preset_confirm.pressed.emit()
		await _wait_layout()
		check(app.faces == state.faces and app.fold_count == state.fold_count and app.custom_reference.kind == "point" and not app.preset_shade.visible, "Loading must restore the exact folded sheet after recreating the scene")
		app._open_flight()
		await physics_frame
		await process_frame
		check(app.flight_view.ready_to_launch and app.flight_view.posed.size() == app.faces.size(), "A loaded diagram must remain usable for flight preparation")
		app._close_flight()
		await _wait_layout()
		var last_plan: Dictionary = app.history[-1].plan.duplicate(true)
		app._undo()
		check(app.fold_count == state.fold_count - 1 and Paper.is_continuous(app.faces), "Loaded native history must support undo")
		app.fold_plan = last_plan
		app.fold_angle = PI
		app._commit()
		await create_timer(0.3).timeout
		check(app.fold_count == state.fold_count and Paper.is_continuous(app.faces), "A loaded diagram must support continuing and committing another fold")
		app._unfold()
		await create_timer(0.65).timeout
		check(app.fold_count == state.fold_count - 1 and Paper.is_continuous(app.faces), "Loaded history must support animated unfolding")
		var current: Array[Dictionary] = app.faces.duplicate(true)
		_write_preset_test(ui_folder.path_join("invalid.json"), JSON.stringify({"format": "pap-fold-preset", "version": 1, "name": "손상된 도면", "sheet": {}}))
		app._show_presets()
		app._refresh_preset_list("손상된 도면")
		app._request_preset_load()
		check(app.faces == current and app.preset_pending.is_empty() and "실패" in app.preset_notice.text, "Invalid preset loads must report an error without modifying current paper")
		app._hide_presets()
		root.remove_child(app)
		app.queue_free()
		_clean_preset_test(ui_folder)
	_clean_preset_test(folder)
	root.size = Vector2i(1280, 720)
	await _wait_layout()
	presets_finished = true
