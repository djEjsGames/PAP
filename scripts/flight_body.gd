extends RigidBody3D

const Model := preload("res://scripts/flight_model.gd")
var wind_velocity := Vector3.ZERO
var panels: Array[Dictionary] = []
var track_ground := false
var ground_time := 0.0
var first_ground_contact: Dictionary = {}

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if track_ground:
		ground_time += state.step
		if first_ground_contact.is_empty():
			for i in state.get_contact_count():
				var collider := state.get_contact_collider_object(i)
				if collider is Node and collider.get_meta("pap_ground", false):
					first_ground_contact = {"position":state.get_contact_collider_position(i), "time_s":ground_time}
					break
	var basis := state.transform.basis
	var linear := basis.inverse() * (state.linear_velocity - wind_velocity)
	var angular := basis.inverse() * state.angular_velocity
	for panel in panels:
		var load := Model.aerodynamic_load(linear, angular, panel)
		if load.force.is_finite() and load.torque.is_finite():
			state.apply_central_force(basis * load.force)
			state.apply_torque(basis * load.torque)
