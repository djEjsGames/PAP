extends SceneTree
const Stock := preload("res://scripts/paper_stock.gd")
const Dump := preload("res://scripts/paper_dump.gd")
const Model := preload("res://scripts/flight_model.gd")

class TraceBody extends RigidBody3D:
	const Model := preload("res://scripts/flight_model.gd")
	var panels: Array[Dictionary] = []
	var wind := Vector3.ZERO
	var mode := "original"
	var csv: FileAccess
	var time := 0.0
	var initial_energy := -1.0
	var max_energy := 0.0
	var max_speed := 0.0
	var max_spin := 0.0
	var first_positive_power := -1.0
	var work := [0.0, 0.0, 0.0, 0.0]
	var positive_work := [0.0, 0.0, 0.0, 0.0]
	var samples: Array[Dictionary] = []
	var next_sample := 0.0
	var max_power := -INF
	var max_decomposition_error := 0.0
	var cap_time := -1.0

	func parts(linear: Vector3, angular: Vector3, panel: Dictionary, canonical: bool = false) -> Dictionary:
		var normal: Vector3 = panel.normal
		var velocity: Vector3 = linear + angular.cross(panel.position)
		var tangent := velocity - normal * velocity.dot(normal)
		if tangent.length_squared() < 0.00000001:
			tangent = angular.cross(normal)
			if canonical and tangent[tangent.abs().max_axis_index()] < 0: tangent = -tangent
		if tangent.length_squared() < 0.00000001: tangent = panel.points[1] - panel.points[0]
		tangent = tangent.normalized()
		var moments := Model._surface_moments(panel, tangent)
		var alpha := asin(clampf(-velocity.normalized().dot(normal), -1, 1))
		var coefficients := Model.aerodynamic_coefficients(alpha)
		var offset: Vector3 = tangent * (moments.x * coefficients.z)
		var force := Model.aerodynamic_force(velocity, normal, panel.area)
		var axis := tangent.cross(normal).normalized()
		var rotation := angular.dot(axis)
		var lift_direction := (normal - velocity.normalized() * velocity.normalized().dot(normal)).normalized()
		var rot_lift: Vector3 = lift_direction * (0.5 * Model.AIR_DENSITY * panel.area * moments.x * 1.1 * rotation * velocity.length())
		var rot_drag: Vector3 = -axis * (0.5 * Model.AIR_DENSITY * 1.9 * moments.y * rotation * absf(rotation))
		return {"base": force, "offset": offset, "rot_lift": rot_lift, "rot_drag": rot_drag}

	func legacy_load(linear: Vector3, angular: Vector3, panel: Dictionary) -> Dictionary:
		var c := parts(linear, angular, panel)
		return {"force": c.base + c.rot_lift, "torque": (panel.position + c.offset).cross(c.base) + c.rot_drag}

	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		var basis := state.transform.basis
		var linear := basis.inverse() * (state.linear_velocity - wind)
		var angular := basis.inverse() * state.angular_velocity
		var force := Vector3.ZERO
		var torque := Vector3.ZERO
		var powers := [0.0, 0.0, 0.0, 0.0]
		for panel in panels:
			var exact := Model.aerodynamic_load(linear, angular, panel) if mode == "production" else legacy_load(linear, angular, panel)
			var c := parts(linear, angular, panel, mode == "production")
			var applied_force: Vector3 = exact.force
			var applied_torque: Vector3 = exact.torque
			if mode == "no_cop": applied_torque -= c.offset.cross(c.base)
			elif mode == "no_rot_lift": applied_force -= c.rot_lift
			elif mode == "point_consistent":
				var point: Vector3 = panel.position + c.offset
				var base_force := Model.aerodynamic_force(linear + angular.cross(point), panel.normal, panel.area)
				applied_force = base_force + c.rot_lift
				applied_torque = point.cross(base_force) + panel.position.cross(c.rot_lift) + c.rot_drag
			powers[0] += c.base.dot(linear + angular.cross(panel.position))
			powers[1] += c.offset.cross(c.base).dot(angular)
			powers[2] += c.rot_lift.dot(linear)
			powers[3] += c.rot_drag.dot(angular)
			if mode in ["production", "point_consistent"]:
				var point: Vector3 = panel.position + c.offset
				var point_velocity: Vector3 = linear + angular.cross(point)
				powers[0] += Model.aerodynamic_force(point_velocity, panel.normal, panel.area).dot(point_velocity) - c.base.dot(linear + angular.cross(panel.position))
				powers[1] -= c.offset.cross(c.base).dot(angular)
				powers[2] += c.rot_lift.dot(angular.cross(panel.position))
			force += applied_force
			torque += applied_torque
		var power := force.dot(linear) + torque.dot(angular)
		if mode == "original": max_decomposition_error = maxf(max_decomposition_error, absf(power - (powers[0] + powers[1] + powers[2] + powers[3])))
		var translation := 0.5 * mass * linear.length_squared()
		var rotation_energy := 0.5 * state.angular_velocity.dot(state.inverse_inertia_tensor.inverse() * state.angular_velocity)
		var potential := mass * 9.8 * state.transform.origin.y
		var energy := translation + rotation_energy + potential
		if initial_energy < 0: initial_energy = energy
		max_energy = maxf(max_energy, energy)
		max_speed = maxf(max_speed, state.linear_velocity.length())
		max_spin = maxf(max_spin, angular.length())
		max_power = maxf(max_power, power)
		if power > 0.000001 and first_positive_power < 0: first_positive_power = time
		if angular.length() > 47.12 and cap_time < 0: cap_time = time
		var sample := {"t": time, "position": state.transform.origin, "velocity": state.linear_velocity, "omega": state.angular_velocity, "energy": energy, "translation": translation, "rotation": rotation_energy, "potential": potential, "force": basis * force, "torque": basis * torque, "power": power, "powers": powers.duplicate(), "work": work.duplicate()}
		if time >= next_sample:
			samples.append(sample)
			next_sample += 0.5
		var row := [time, state.transform.origin.x, state.transform.origin.y, state.transform.origin.z, state.linear_velocity.x, state.linear_velocity.y, state.linear_velocity.z, state.angular_velocity.x, state.angular_velocity.y, state.angular_velocity.z, energy, translation, rotation_energy, potential, force.x, force.y, force.z, torque.x, torque.y, torque.z, power, powers[0], powers[1], powers[2], powers[3]]
		var strings := PackedStringArray()
		for value in row: strings.append("%.12f" % value)
		csv.store_csv_line(strings)
		for i in 4:
			work[i] += powers[i] * state.step
			positive_work[i] += maxf(powers[i], 0) * state.step
		state.apply_central_force(basis * force)
		state.apply_torque(basis * torque)
		time += state.step

class Trial extends Node3D:
	signal finished
	var body: TraceBody
	var elapsed := 0.0
	var running := false
	var reason := ""
	func _physics_process(delta: float) -> void:
		if not running: return
		elapsed += delta
		if elapsed > 0.05 and body.get_contact_count() > 0: reason = "landing"
		elif elapsed >= 12: reason = "timeout"
		if not reason.is_empty():
			running = false
			body.freeze = true
			finished.emit()

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Pass a PAP dump path after --")
		quit(1)
		return
	var dump: Dictionary = Dump.decode(JSON.parse_string(FileAccess.get_file_as_string(args[0])))
	var output := "res://build/energy_diagnostic"
	DirAccess.make_dir_recursive_absolute(output)
	var posed: Array[Dictionary] = []
	posed.assign(dump.flight.posed)
	var material: Array[Dictionary] = []
	material.assign(dump.faces)
	var stock := Stock.read(dump.get("paper_stock", dump.flight.get("paper_stock")), material)
	if stock.is_empty():
		push_error("Invalid paper dimensions or grammage")
		quit(1)
		return
	var props := Model.properties(posed, stock.gsm / 1000.0)
	var physics_settings := {}
	for setting in ProjectSettings.get_property_list():
		if "jolt" in setting.name and "velocity" in setting.name: physics_settings[setting.name] = ProjectSettings.get_setting(setting.name)
	var metadata := {"mass": props.mass, "inertia": props.inertia, "center": props.center, "panels": [], "physics_settings": physics_settings, "launch": dump.flight.trials[-1]}
	for panel in dump.flight.panels: metadata.panels.append({"area": panel.area, "position": panel.position, "normal": panel.normal})
	var source_faces: Array[Dictionary] = []
	var source_history: Array[Dictionary] = []
	source_faces.assign(dump.faces)
	source_history.assign(dump.history)
	var rebuilt := Model.pose(source_faces, source_history, dump.flight.angles)
	var frame := Model.launch_frame(source_faces, source_history)
	var max_position_error := 0.0
	for i in rebuilt.size():
		for j in rebuilt[i].points.size(): max_position_error = maxf(max_position_error, (frame * rebuilt[i].points[j]).distance_to(posed[i].points[j]))
	metadata.rebuilt_pose_error = max_position_error
	metadata.joined = Model.is_joined(rebuilt)
	metadata.force_point_test = force_point_test(dump.flight.panels)
	var results: Array[Dictionary] = []
	for hz in [240, 480, 960]:
		for weather in ["calm", "dump"]:
			results.append(await simulate(dump, props, hz, weather, "original", output))
	for mode in ["no_cop", "no_rot_lift", "point_consistent"]:
		results.append(await simulate(dump, props, 240, "dump", mode, output))
	for hz in [480, 960]: results.append(await simulate(dump, props, hz, "dump", "point_consistent", output))
	results.append(await simulate(dump, props, 1920, "dump", "original", output))
	results.append(await simulate(dump, props, 1920, "dump", "point_consistent", output))
	results.append(await simulate(dump, props, 240, "dump", "original", output))
	var file := FileAccess.open(output.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(Dump.encode({"metadata": metadata, "results": results}), "  ", true, true))
	file.close()
	print("Energy diagnosis written: ", output)
	quit()

func simulate(dump: Dictionary, props: Dictionary, hz: int, weather: String, mode: String, output: String) -> Dictionary:
	Engine.physics_ticks_per_second = hz
	var arena := Trial.new()
	root.add_child(arena)
	var ground := StaticBody3D.new()
	ground.position.y = -0.1
	var ground_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 0.2, 100)
	ground_shape.shape = box
	ground.add_child(ground_shape)
	arena.add_child(ground)
	var body := TraceBody.new()
	body.freeze = true
	body.mass = props.mass
	body.inertia = Vector3(maxf(props.inertia.x, 0.00000001), maxf(props.inertia.y, 0.00000001), maxf(props.inertia.z, 0.00000001))
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = Vector3.ZERO
	body.collision_layer = 2
	body.collision_mask = 1
	body.contact_monitor = true
	body.max_contacts_reported = 8
	body.continuous_cd = true
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0
	body.angular_damp = 0
	body.panels.assign(dump.flight.panels)
	body.wind = dump.flight.wind_velocity if weather == "dump" else (Vector3(2, 0, 0) if weather == "cross" else Vector3.ZERO)
	body.mode = mode
	var vertices := PackedVector3Array()
	for face in dump.flight.posed:
		for i in range(1, face.points.size() - 1):
			for point in [face.points[0], face.points[i], face.points[i + 1]]:
				vertices.append(point - props.center + face.normal * 0.0001)
				vertices.append(point - props.center - face.normal * 0.0001)
	var collision := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	hull.points = vertices
	hull.margin = 0.0001
	collision.shape = hull
	body.add_child(collision)
	var name := "%s_%d_%s" % [weather, hz, mode]
	body.csv = FileAccess.open(output.path_join(name + ".csv"), FileAccess.WRITE)
	body.csv.store_line("t,x,y,z,vx,vy,vz,wx,wy,wz,energy,translation_ke,rotation_ke,potential,fx_local,fy_local,fz_local,tx_local,ty_local,tz_local,power,base_power,cop_power,rot_lift_power,rot_drag_power")
	arena.body = body
	arena.add_child(body)
	await physics_frame
	await physics_frame
	body.transform = dump.flight.trials[-1].launch_transform
	body.freeze = false
	body.sleeping = false
	body.linear_velocity = dump.flight.trials[-1].launch_velocity
	body.angular_velocity = Vector3.ZERO
	arena.running = true
	await arena.finished
	body.csv.close()
	var inverse: Basis = body.get_inverse_inertia_tensor()
	var relative: Vector3 = body.linear_velocity - body.wind
	var energy: float = 0.5 * body.mass * relative.length_squared() + 0.5 * body.angular_velocity.dot(inverse.inverse() * body.angular_velocity) + body.mass * 9.8 * body.position.y
	var result := {"name": name, "hz": hz, "weather": weather, "mode": mode, "duration": arena.elapsed, "reason": arena.reason, "position": body.position, "velocity": body.linear_velocity, "omega": body.angular_velocity, "energy_initial": body.initial_energy, "energy_final": energy, "energy_max": body.max_energy, "speed_max": body.max_speed, "spin_max": body.max_spin, "first_positive_power": body.first_positive_power, "cap_time": body.cap_time, "max_power": body.max_power, "work": body.work, "positive_work": body.positive_work, "decomposition_error": body.max_decomposition_error, "samples": body.samples}
	print(name, " t=", arena.elapsed, " E=", energy, " maxE=", body.max_energy, " speed=", body.linear_velocity.length(), " spin=", body.angular_velocity.length(), " work=", body.work)
	arena.queue_free()
	await process_frame
	return result

func force_point_test(panels: Array) -> Dictionary:
	var evaluator := TraceBody.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261026
	var positives := 0
	var fixed_positives := 0
	var worst := {"power": -INF}
	var fixed_max := -INF
	for i in 1000:
		var linear := Vector3(rng.randf_range(-8, 8), rng.randf_range(-8, 8), rng.randf_range(-8, 8))
		var angular := Vector3(rng.randf_range(-40, 40), rng.randf_range(-40, 40), rng.randf_range(-40, 40))
		var force := Vector3.ZERO
		var torque := Vector3.ZERO
		var fixed_force := Vector3.ZERO
		var fixed_torque := Vector3.ZERO
		for panel in panels:
			var old := evaluator.legacy_load(linear, angular, panel)
			force += old.force
			torque += old.torque
			var c := evaluator.parts(linear, angular, panel)
			var point: Vector3 = panel.position + c.offset
			var base := Model.aerodynamic_force(linear + angular.cross(point), panel.normal, panel.area)
			fixed_force += base + c.rot_lift
			fixed_torque += point.cross(base) + panel.position.cross(c.rot_lift) + c.rot_drag
		var power := force.dot(linear) + torque.dot(angular)
		var fixed_power := fixed_force.dot(linear) + fixed_torque.dot(angular)
		if power > 0.000001: positives += 1
		if fixed_power > 0.000001: fixed_positives += 1
		if power > worst.power: worst = {"power": power, "linear": linear, "angular": angular, "force": force, "torque": torque, "point_consistent_power": fixed_power}
		fixed_max = maxf(fixed_max, fixed_power)
	evaluator.free()
	return {"states": 1000, "positive_original": positives, "positive_point_consistent": fixed_positives, "max_point_consistent": fixed_max, "worst_original": worst}
