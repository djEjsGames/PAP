extends "res://tests/test_defaults.gd"
const Parts := preload("res://scripts/flight_parts.gd")
var camera_rows: Array[Dictionary] = []

func event_key(code: Key, pressed: bool = true, echo: bool = false) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = pressed
	e.echo = echo
	Input.parse_input_event(e)

func tap(code: Key) -> void:
	event_key(code)
	await process_frame
	event_key(code, false)
	await process_frame

func sheet_for(index: int) -> Dictionary:
	var stock := Stock.option(index)
	if index == 0:
		var sheet := folded_sheet(0.15)
		sheet.paper_stock = stock
		sheet.flight_parts = {}
		return sheet
	var faces := Paper.rectangle(stock.size)
	var plan := Paper.plan(faces, Vector2(0, -stock.size.y * 0.5), Vector2(0, stock.size.y * 0.5), Vector2(stock.size.x * 0.5, 0))
	var history: Array[Dictionary] = [{"kind":"fold", "faces":faces.duplicate(true), "fold_count":0, "single_layer":false, "plan":plan}]
	return {"faces":Paper.folded(plan), "history":history, "fold_count":1, "reference":{}, "flight_parts":{}, "paper_stock":stock}

func material_state(item: Dictionary) -> String:
	return JSON.stringify(Dump.encode({"sheet":item.sheet, "flight_session":item.flight_session}), "", true, true)

func measure(park: Node, flight: Node, size: Vector2i, stock: Dictionary, pitch: float, zoom: float) -> void:
	park.view_angles = Vector2(0.3, deg_to_rad(pitch))
	park.zoom = zoom
	await layout()
	var screen: Vector2 = flight.camera.unproject_position(flight.body.global_position)
	var safe_top: float = flight.metrics.position.y + flight.metrics.size.y + 12
	var safe_bottom: float = minf(flight.gauge_panel.position.y, flight.wind_hud.position.y) - 10
	check(absf(screen.y - (safe_top + safe_bottom) * 0.5) < 1, "COM stays centered in the aircraft area above the larger throw controls")
	check(is_equal_approx(flight.body.position.y, park.launch_position().y) and is_equal_approx(flight.body.mass, Stock.mass(stock)), "Framing does not change launch height or mass")
	var rect := Rect2(screen, Vector2.ZERO)
	for face in flight.posed:
		for point in face.points:
			var projected: Vector2 = flight.camera.unproject_position(flight.body.global_transform * (point - flight.properties.center))
			rect = rect.expand(projected)
	if zoom == 4:
		check(Rect2(Vector2.ZERO, Vector2(size)).encloses(rect), "Default shows the complete physical aircraft")
		check(not rect.intersects(flight.metrics.get_global_rect()) and not rect.intersects(flight.topbar.get_global_rect()) and not rect.intersects(flight.gauge_panel.get_global_rect()) and not rect.intersects(flight.wind_hud.get_global_rect()), "Default paper is clear of all top/bottom HUD")
		check(not park.character.visible and park.character.holding, "Preparation hides only the visual character")
		if stock.id == "origami" or pitch == 0:
			await capture("review_ready_%s_%d_%d" % [stock.id, int(pitch), size.x])
	camera_rows.append({"window":size, "stock":stock.id, "pitch":pitch, "zoom":zoom, "com_screen":screen, "y_fraction":screen.y/size.y, "bounds":rect, "hand_error":park.character.reach_error})

func run() -> void:
	for size in [Vector2i(1280,720), Vector2i(640,360)]:
		root.size = size
		var park: Node = load("res://scenes/park.tscn").instantiate()
		root.add_child(park)
		await layout()
		check(park.status.get_theme_font_size("font_size") >= 16 and park.hint.get_theme_font_size("font_size") >= 18, "HUD keeps readable font sizes in both windows")
		check(park.status_panel.visible and park.actions_panel.visible, "HUD separates state and stable bottom actions")
		check(park.character.motion == "idle" and park.character.skeleton.get_bone_count() > 30, "Imported skinned character starts in real idle")
		await capture("review_idle_" + str(size.x))
		park.move_keys[KEY_W] = true
		for i in 25: await physics_frame
		await layout()
		check(park.character.motion == "run", "Movement selects the supplied run clip")
		await capture("review_run_" + str(size.x))
		park.move_keys.clear()
		await layout()
		check(park.character.motion == "idle", "Stopping restores idle")
		for yaw in [0.0, PI * 0.5]:
			park.view_angles.x = yaw
			for key in [KEY_W, KEY_A, KEY_S, KEY_D]:
				park.move_keys[key] = true
				await physics_frame
				await physics_frame
				var input := Vector3(float(key == KEY_D) - float(key == KEY_A), 0, float(key == KEY_S) - float(key == KEY_W))
				var expected := Basis(Vector3.UP, yaw) * input
				check((-park.player.global_basis.z).dot(expected) > 0.999, "Body faces camera-relative movement intent")
				park.move_keys.clear()
			var facing: Basis = park.player.global_basis
			park.view_angles.x += 0.4
			await physics_frame
			await physics_frame
			check(park.player.global_basis.is_equal_approx(facing), "Idle camera rotation preserves body facing")
		park.player.position = Vector3(0,0.01,-1)
		await layout()
		await capture("review_bench_" + str(size.x))
		check(park.bench_target and park.hint.visible, "Bench has one readable contextual action")
		park.player.position = Vector3(3,0.01,1)
		for index in 4:
			park.items[1].sheet = sheet_for(index)
			park.items[1].flight_session = {}
			park.carried_id = -1
			park.selected_id = 1
			park._take_selected()
			await layout()
			check(park.character.reach_error < 0.03 and park.carried.visible, "Carried aircraft follows the real pinch point")
			if index == 0: await capture("review_hand_" + str(size.x))
			park.prepare_throw()
			await layout()
			var flight: Node = park.active_flight
			for pitch in [-10.0,0.0,15.0]:
				for zoom in [1.5,4.0,9.0]:
					await measure(park, flight, size, Stock.option(index), pitch, zoom)
			var before: Basis = flight.attitude
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			click.position = Vector2(size) * 0.5
			flight._unhandled_input(click)
			var motion := InputEventMouseMotion.new()
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT
			motion.relative = Vector2(40,20)
			flight._unhandled_input(motion)
			check(flight.attitude == before, "Ordinary drag still cannot rotate the aircraft in preparation")
			park.exit_flight()
			await layout()
			check(park.character.visible, "Preparation cancellation restores character")
			var immutable_before := material_state(park.items[1])
			park.open_inspection(1,false)
			await layout()
			check(park.inspection.model.mesh != null and park.inspection.can_deploy == (index == 0), "Every stock has real 3D preview without invented wings")
			check(material_state(park.items[1]) == immutable_before, "Every stock's observation preserves its original dimensions and pose settings")
			if index >= 2: await capture("review_inspect_" + Stock.option(index).id + "_" + str(size.x))
			park.finish_inspection("cancel")
			await layout()
		# Real found-object entry, local rotation, zoom, folded view, no mutation.
		park.player.position = park.items[2].flight.body.position + Vector3(0.4,0,0.4)
		park.view_angles = Vector2.ZERO
		await layout()
		var found_before := material_state(park.items[2])
		var original_transform: Transform3D = park.items[2].flight.body.transform
		park.recover_item(2)
		await layout()
		check(park.inspection != null and park.items[2].state == "inspecting" and park.stored_count() == 0, "Unknown discovery reserves its same ID for automatic inspection")
		var inspection: Node = park.inspection
		check(inspection.model.mesh != null and inspection.can_deploy and inspection.deployed, "Discovery defaults to a connected real 90-degree 3D preview")
		await capture("review_discovery_" + str(size.x))
		var player_position: Vector3 = park.player.position
		var camera_angles: Vector2 = park.view_angles
		for code in [KEY_W,KEY_SPACE,KEY_E,KEY_ENTER,KEY_TAB]:
			await tap(code)
		check(park.inspection == inspection and park.player.position == player_position and park.view_angles == camera_angles and park.active_flight == null, "Opening/held/action keys cannot move or process an inspected item")
		# Exercise the same handlers that real GUI pointer events use.
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		inspection._view_input(press)
		var drag := InputEventMouseMotion.new()
		drag.relative = Vector2(60,25)
		drag.button_mask = MOUSE_BUTTON_MASK_LEFT
		inspection._input(drag)
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		inspection._view_input(wheel)
		check(inspection.rotation_angles != Vector2.ZERO and inspection.zoom < 1, "Observation drag and wheel rotate/zoom the actual model")
		await capture("review_rotated_" + str(size.x))
		inspection.toggle.pressed.emit()
		await layout()
		check(not inspection.deployed and material_state(park.items[2]) == found_before, "Folded display never edits physical sheet/settings")
		await capture("review_folded_" + str(size.x))
		inspection.reset_view()
		check(inspection.rotation_angles == Vector2.ZERO and inspection.zoom == 1, "Reset restores the observation viewpoint")
		await tap(KEY_ESCAPE)
		check(park.inspection == null and park.items[2].state == "world" and park.items[2].flight.body.position.distance_to(original_transform.origin) < 0.01, "World Escape restores original state/location")
		await layout()
		park.recover_item(2)
		await layout()
		park.inspection.action_buttons[0].pressed.emit()
		park.finish_inspection("store")
		await layout()
		check(park.items.size() == 2 and park.items[2].state == "stored" and park.items[2].known and park.items[2].flight == null and material_state(park.items[2]) == found_before, "Store commits the same physical discovery once")
		# Inventory observation returns to the same owned state and open inventory.
		park._toggle_inventory()
		await layout()
		var owned_before := material_state(park.items[2])
		park.open_inspection(2,false)
		await layout()
		await tap(KEY_ESCAPE)
		await layout()
		check(park.inventory.visible and park.items[2].state == "stored" and material_state(park.items[2]) == owned_before, "Inventory Escape restores its original ownership and immutable settings")
		park.inventory.hide()
		park.selected_id = 2
		park._take_selected()
		var hand_before := material_state(park.items[2])
		park.open_inspection(2,false)
		await layout()
		await tap(KEY_ESCAPE)
		await layout()
		check(park.held_id == 2 and park.items[2].state == "hand" and material_state(park.items[2]) == hand_before, "Owned hand inspection returns the same hand item and original settings")
		# Valid explicit binding is used ahead of automatic recommendation.
		var wings := Model.wing_folds(park.items[2].sheet.history)
		var binding := {"signature":Parts.signature(park.items[2].sheet.faces,park.items[2].sheet.history), "wings":Array(wings), "grip":4}
		check(Parts.valid(binding,park.items[2].sheet.faces,park.items[2].sheet.history), "Test discovery has a valid explicit wing binding")
		park.items[2].sheet.flight_parts = binding
		park.open_inspection(2,false)
		await layout()
		check(park.inspection.binding == binding and park.inspection.deployed, "Inspection prioritizes a valid binding")
		park.finish_inspection("cancel")
		await layout()
		# Flat paper has no invented wing axes.
		park.items[1].sheet = {"faces":Paper.square(), "history":[], "fold_count":0, "reference":{}, "flight_parts":{}, "paper_stock":Stock.option(0)}
		park.open_inspection(1,false)
		await layout()
		check(not park.inspection.can_deploy and park.inspection.toggle.disabled, "No wing geometry is invented for an uncreased sheet")
		park.finish_inspection("cancel")
		await layout()
		# Another aircraft keeps simulating while a discovery is inspected.
		park.items[1].sheet = sheet_for(0)
		park.carried_id = -1
		park.selected_id = 1
		park._take_selected()
		park.player.position = Vector3(4,0.01,1)
		park.prepare_throw()
		await layout()
		var background: Node = park.active_flight
		background.launch()
		park.exit_flight()
		var id: int = park.add_item("정리 검토 기체", park._starter_plane())
		park.items[id].known = false
		park._spawn_found(id,park.player.position + Vector3(0.5,0.05,0))
		park.recover_item(id)
		await layout()
		var elapsed: float = background.elapsed
		for i in 20: await physics_frame
		check(background.elapsed > elapsed or background.landed, "Other world flight continues during inspection")
		var reference_before := material_state(park.items[id])
		park.inspection.preset_store = Presets.new("res://build/inspection_references")
		park.inspection._show_save()
		park.inspection.save_name.text = "Discovery " + str(size.x)
		await capture("review_reference_" + str(size.x))
		# Use a new name per test run while avoiding overwrite of any existing reference.
		var store: RefCounted = park.inspection.preset_store
		var path: String = store.path_for(park.inspection.save_name.text)
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
		park.inspection._save_diagram()
		check(FileAccess.file_exists(path) and material_state(park.items[id]) == reference_before and park.items[id].state == "inspecting", "Saving a reference creates no physical copy and does not decide processing")
		park.inspection.dragging = true
		root.focus_exited.emit()
		check(not park.inspection.dragging, "Focus loss ends observation dragging")
		park.inspection.action_buttons[2].pressed.emit()
		park.finish_inspection("clear")
		await layout()
		check(park.items[id].state == "cleared" and park.items[id].flight == null and park.cleaning_records.size() == 1, "Clear archives one distinct no-reward discovery record without duplication")
		var reference: Dictionary = store.load_preset(path)
		check(reference.ok and reference.sheet.faces == park.items[id].sheet.faces and material_state(park.items[id]) == reference_before, "Clearing discovery preserves its independently saved reference and original material")
		await capture("review_cleared_" + str(size.x))
		park.queue_free()
		await layout()
	var file := FileAccess.open("res://build/park_review_camera_measurements.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(Dump.encode(camera_rows),"\t"))
	file.close()
	print("PAP park review: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
