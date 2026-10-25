extends SceneTree

const Model := preload("res://scripts/flight_model.gd")
const Body := preload("res://scripts/flight_body.gd")
const CHORD := 0.051
const SPAN := 0.15
const PAPER_MASS := 0.00059
const OUTPUT := "res://build/research_flight"
var failures := 0
var checks := 0
var coefficient_checks_finished := false

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _plate() -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(-CHORD / 2, 0, -SPAN / 2), Vector3(CHORD / 2, 0, -SPAN / 2),
		Vector3(CHORD / 2, 0, SPAN / 2), Vector3(-CHORD / 2, 0, SPAN / 2)
	])

func _coefficient_checks() -> void:
	var zero := Model.aerodynamic_coefficients(0)
	var broadside := Model.aerodynamic_coefficients(PI / 2)
	check(zero.x == 0 and absf(zero.y - 0.1) < 0.002, "Li 2022: edgewise lift is zero and skin drag is near 0.1")
	check(absf(zero.z - 0.3) < 0.002, "Li 2022: low-angle pressure centre is near 0.3 chord ahead of mid-chord")
	check(absf(broadside.x) < 0.000001 and absf(broadside.y - 1.9) < 0.000001 and absf(broadside.z) < 0.000001, "Li 2022: broadside drag is 1.9 and the pressure centre returns to mid-chord")
	var positive := Model.aerodynamic_coefficients(deg_to_rad(7))
	var negative := Model.aerodynamic_coefficients(deg_to_rad(-7))
	check(positive.x > 0 and positive.x == -negative.x and positive.y == negative.y and positive.z == negative.z, "Lift changes sign while drag and pressure offset are even in attack angle")
	check(positive.z < zero.z and positive.z > 0.2, "Pressure centre must move aft as attack angle grows")
	var points := _plate()
	var surface: Array[Dictionary] = [{"points": points, "normal": Vector3.UP}]
	var properties := Model.properties(surface)
	check(absf(properties.inertia.z - properties.mass * CHORD * CHORD / 12.0) < properties.inertia.z * 0.0001, "Material integration must match exact rectangular-plate pitch inertia")
	check(absf(properties.inertia.x - properties.mass * SPAN * SPAN / 12.0) < properties.inertia.x * 0.0001, "Material integration must match exact rectangular-plate roll inertia")
	var one := Model.panels(surface, Vector3.ZERO)
	var split := Model.panels([
		{"points": PackedVector3Array([points[0], points[1], points[2]]), "normal": Vector3.UP},
		{"points": PackedVector3Array([points[0], points[2], points[3]]), "normal": Vector3.UP}
	], Vector3.ZERO)
	check(one.size() == 1 and split.size() == 1, "Coplanar triangles must share a physical aerodynamic surface")
	var velocity := Vector3(2, -0.2, 0)
	var load := Model.aerodynamic_load(velocity, Vector3.ZERO, one[0])
	var split_load := Model.aerodynamic_load(velocity, Vector3.ZERO, split[0])
	check(load.force.distance_to(split_load.force) < 0.0000001 and load.torque.distance_to(split_load.torque) < 0.0000001, "Triangulating the same plate must not change its aerodynamic force or moment")
	var triangle := Model.panels([{"points": PackedVector3Array([Vector3(CHORD / 2, 0, 0), Vector3(-CHORD / 2, 0, -SPAN / 2), Vector3(-CHORD / 2, 0, SPAN / 2)]), "normal": Vector3.UP}], Vector3.ZERO)
	var mean_chord := Model._surface_moments(triangle[0], Vector3.RIGHT).x
	check(absf(mean_chord - CHORD * 2.0 / 3.0) < CHORD * 0.01, "Triangular wings must use their mean aerodynamic chord rather than bounding-box chord")
	var inverted := one[0].duplicate(true)
	inverted.normal = Vector3.DOWN
	var inverted_load := Model.aerodynamic_load(velocity, Vector3.ZERO, inverted)
	check(load.force.distance_to(inverted_load.force) < 0.0000001 and load.torque.distance_to(inverted_load.torque) < 0.0000001, "Reversing a sheet normal must preserve force and pressure moment")
	check(load.force.dot(velocity) <= 0, "Translational drag must remove energy")
	var spin := Vector3(0, 0, 4)
	var spinning := Model.aerodynamic_load(Vector3.ZERO, spin, one[0])
	check(spinning.torque.dot(spin) < 0, "Pure-rotation aerodynamic drag must oppose rotation")
	coefficient_checks_finished = true

func _run() -> void:
	_coefficient_checks()
	check(coefficient_checks_finished, "Coefficient and geometry checks must finish without script errors")
	check(Engine.physics_ticks_per_second >= 240, "Thin-plate dynamics require the project's 240 Hz physics step")
	var error := DirAccess.make_dir_recursive_absolute(OUTPUT)
	check(error == OK, "Research output directory must be writable")
	var csv := FileAccess.open(OUTPUT + "/trajectories.csv", FileAccess.WRITE)
	check(csv != null, "Research trajectory output must open")
	if csv == null:
		quit(1)
		return
	csv.store_line("physics_hz,com_fraction,time_s,x_m,y_m,angle_deg,speed_m_s,omega_rad_s,alpha_deg")
	var results: Array[Dictionary] = []
	for fraction in [0.0, 0.08, 0.14, 0.24, 0.31]:
		results.append(await _trial(fraction, csv))
	check(results[0].mean_spin_rad_s > 1 and results[1].mean_spin_rad_s > 1, "Centred and weakly front-weighted plates must retain unsteady rotating flight")
	check(results[2].mean_spin_rad_s > 1, "Intermediate front weighting must still produce unsteady flight")
	check(results[3].mean_spin_rad_s < 0.2 and results[3].mean_alpha_deg > 3 and results[3].mean_alpha_deg < 12, "The 0.24-chord fixture must settle into low-angle gliding")
	check(results[3].glide_ratio > 3 and results[3].glide_ratio < 4.5, "Stable gliding must have a descent ratio near the paper's 3-4 regime")
	check(results[4].mean_spin_rad_s < 0.2 and results[4].mean_alpha_deg < 1 and results[4].glide_ratio < 0.2, "The 0.31-chord fixture must settle into an edgewise dive")
	var original_ticks := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = original_ticks * 2
	var refined := await _trial(0.24, csv)
	Engine.physics_ticks_per_second = original_ticks
	csv.close()
	check(absf(refined.glide_ratio - results[3].glide_ratio) < 0.1 and absf(refined.mean_alpha_deg - results[3].mean_alpha_deg) < 0.2, "Stable gliding must converge when the physics step is halved")
	var summary := FileAccess.open(OUTPUT + "/summary.json", FileAccess.WRITE)
	check(summary != null, "Research summary output must open")
	if summary != null:
		summary.store_string(JSON.stringify({
			"source": "https://doi.org/10.1017/jfm.2022.89", "chord_m": CHORD,
			"span_m": SPAN, "bare_paper_mass_kg": PAPER_MASS, "air_density_kg_m3": Model.AIR_DENSITY,
			"physics_hz": Engine.physics_ticks_per_second, "duration_s": 10,
			"initial_speed_m_s": 2, "initial_height_m": 5, "longitudinal_only": true,
			"note": "Qualitative 3D rigid-body adaptation: no added-fluid-mass terms; front edge ballast represents experimental tape, not a player feature.",
			"results": results, "refined_glider": refined, "checks": checks, "failures": failures
		}, "  "))
		summary.close()
	print("PAP research: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _trial(fraction: float, csv: FileAccess) -> Dictionary:
	# Front-edge tape produces the selected CoM while retaining the measured bare-paper mass.
	var mass := PAPER_MASS / (1.0 - 2.0 * fraction)
	var added := mass - PAPER_MASS
	var cm := fraction * CHORD
	var pitch_inertia := PAPER_MASS * (CHORD * CHORD / 12.0 + cm * cm) + added * pow(CHORD / 2.0 - cm, 2)
	var body := Body.new()
	body.freeze = true
	body.mass = mass
	body.inertia = Vector3(mass * SPAN * SPAN / 12.0, mass * SPAN * SPAN / 12.0 + pitch_inertia, pitch_inertia)
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = Vector3.ZERO
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0
	body.angular_damp = 0
	body.can_sleep = false
	# The paper studies longitudinal motion with fins; these locks isolate that reference plane.
	body.axis_lock_angular_x = true
	body.axis_lock_angular_y = true
	body.axis_lock_linear_z = true
	body.collision_mask = 0
	body.panels = Model.panels([{"points": _plate(), "normal": Vector3.UP}], Vector3(cm, 0, 0))
	root.add_child(body)
	await physics_frame
	body.position = Vector3(0, 5, 0)
	body.freeze = false
	body.linear_velocity = Vector3(2, 0, 0)
	check(is_equal_approx(body.gravity_scale, 1.0), "Reference flight must use normal gravity")
	var spin := 0.0
	var alpha := 0.0
	var velocity := Vector3.ZERO
	var samples := 0
	var valid := true
	var maximum_speed := 0.0
	var ticks := Engine.physics_ticks_per_second
	for frame in ticks * 10:
		await physics_frame
		valid = body.position.is_finite() and body.linear_velocity.is_finite() and body.angular_velocity.is_finite()
		if not valid:
			break
		maximum_speed = maxf(maximum_speed, body.linear_velocity.length())
		var attack := absf(asin(clampf(-body.linear_velocity.normalized().dot(body.basis * Vector3.UP), -1, 1)))
		if frame % 8 == 0:
			csv.store_line("%d,%.2f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f" % [ticks, fraction, float(frame + 1) / ticks, body.position.x, body.position.y, rad_to_deg(body.basis.get_euler().z), body.linear_velocity.length(), body.angular_velocity.z, rad_to_deg(attack)])
		if frame >= ticks * 8:
			spin += absf(body.angular_velocity.z)
			alpha += attack
			velocity += body.linear_velocity
			samples += 1
	check(valid and maximum_speed < 20 and samples > 0, "Reference dynamics must remain finite without runaway speed")
	var result := {"com_fraction": fraction, "total_mass_g": mass * 1000,
		"mean_spin_rad_s": spin / maxi(samples, 1), "mean_alpha_deg": rad_to_deg(alpha / maxi(samples, 1)),
		"glide_ratio": absf(velocity.x) / maxf(absf(velocity.y), 0.000001),
		"maximum_speed_m_s": maximum_speed}
	print("Research plate: ", JSON.stringify(result))
	root.remove_child(body)
	body.queue_free()
	return result
