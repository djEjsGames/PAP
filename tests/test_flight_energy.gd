extends "res://tests/diagnostics/flight_energy.gd"

var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	var dump: Dictionary = Dump.decode(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/flight_energy_wind.json")))
	var output := "res://build/energy_regression"
	DirAccess.make_dir_recursive_absolute(output)
	var results: Array[Dictionary] = []
	var faces: Array[Dictionary] = []
	var history: Array[Dictionary] = []
	faces.assign(dump.faces)
	history.assign(dump.history)
	var frame := Model.launch_frame(faces, history)
	for shape in ["dump", "asymmetric"]:
		var current: Dictionary = dump.duplicate(true)
		if shape == "asymmetric":
			var posed := Model.pose(faces, history, Vector2(75, 105))
			for face in posed:
				for i in face.points.size(): face.points[i] = frame * face.points[i]
				face.normal = frame * face.normal
			current.flight.posed = posed
			current.flight.panels = Model.panels(posed, Model.properties(posed).center)
		var posed: Array[Dictionary] = []
		posed.assign(current.flight.posed)
		var props := Model.properties(posed)
		check_loads(current.flight.panels, shape)
		var shape_output: String = output.path_join(shape)
		DirAccess.make_dir_recursive_absolute(shape_output)
		for hz in [240, 480, 960]:
			for weather in ["calm", "dump", "cross"]:
				var result := await simulate(current, props, hz, weather, "production", shape_output)
				result.shape = shape
				results.append(result)
				var label := "%s %s %dHz" % [shape, weather, hz]
				check(is_finite(result.energy_final) and is_finite(result.energy_max), label + ": energy must remain finite")
				check(result.max_power <= 0.000001, label + ": full aerodynamic force and torque must not supply energy")
				check(result.energy_max <= result.energy_initial + 0.001, label + ": no numerical energy runaway above 1mJ tolerance")
				check(result.cap_time < 0, label + ": must not reach the engine angular velocity cap")
				check(result.reason == "landing", label + ": must land within the 12 second trial")
	var file := FileAccess.open(output.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(Dump.encode({"checks": checks, "failures": failures, "results": results}), "  ", true, true))
	file.close()
	print("PAP energy: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check_loads(panels: Array, shape: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261026
	var states := [{"linear": Vector3.ZERO, "angular": Vector3.ZERO}, {"linear": Vector3.ZERO, "angular": Vector3(0, 0, 40)}, {"linear": Vector3(-1.8456078, 0.408391, -2.3749857), "angular": Vector3(30.043602, 26.423882, 28.49259)}]
	for i in 1000:
		states.append({"linear": Vector3(rng.randf_range(-8, 8), rng.randf_range(-8, 8), rng.randf_range(-8, 8)), "angular": Vector3(rng.randf_range(-40, 40), rng.randf_range(-40, 40), rng.randf_range(-40, 40))})
	for state in states:
		var power := 0.0
		for panel in panels:
			var load := Model.aerodynamic_load(state.linear, state.angular, panel)
			check(load.force.is_finite() and load.torque.is_finite(), shape + ": finite load including zero velocity")
			power += load.force.dot(state.linear) + load.torque.dot(state.angular)
			var inverted: Dictionary = panel.duplicate(true)
			inverted.normal = -panel.normal
			var reverse := Model.aerodynamic_load(state.linear, state.angular, inverted)
			check(load.force.distance_to(reverse.force) <= 0.000001 and load.torque.distance_to(reverse.torque) <= 0.00000001, shape + ": face winding must preserve full load")
		check(power <= 0.000001, shape + ": translational and rotational power must be non-positive")
