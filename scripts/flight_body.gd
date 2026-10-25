extends RigidBody3D

const Model := preload("res://scripts/flight_model.gd")
var panels: Array[Dictionary] = []

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var basis := state.transform.basis
	var linear := basis.inverse() * state.linear_velocity
	var angular := basis.inverse() * state.angular_velocity
	for panel in panels:
		var load := Model.aerodynamic_load(linear, angular, panel)
		if load.force.is_finite() and load.torque.is_finite():
			state.apply_central_force(basis * load.force)
			state.apply_torque(basis * load.torque)
