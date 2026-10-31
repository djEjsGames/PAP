extends Node3D

const MODEL := preload("res://assets/characters/kenney/characterMedium.fbx")
const SKIN := preload("res://assets/characters/kenney/skaterMaleA.png")
const IDLE := preload("res://assets/characters/kenney/idle.fbx")
const RUN := preload("res://assets/characters/kenney/run.fbx")
static var clips: AnimationLibrary
var model: Node3D
var skeleton: Skeleton3D
var animator := AnimationPlayer.new()
var moving := false
var holding := false
var preparing := false
var hand_target := Vector3.ZERO
var upper := -1
var forearm := -1
var hand := -1
var index_finger := -1
var thumb := -1
var motion := ""
var reach_error := 0.0
var material := ShaderMaterial.new()

func _ready() -> void:
	process_priority = 10
	model = MODEL.instantiate()
	model.rotation.y = PI
	# The imported FBX is 3.765m tall; keep one metre-based 2.0m character.
	model.scale = Vector3.ONE * (2.0 / 3.7647)
	add_child(model)
	skeleton = model.get_node("Root/Skeleton3D")
	material.shader = preload("res://shaders/character.gdshader")
	material.set_shader_parameter("skin_texture", SKIN)
	for mesh in model.find_children("*", "MeshInstance3D"): mesh.material_override = material
	upper = skeleton.find_bone("RightArm")
	forearm = skeleton.find_bone("RightForeArm")
	hand = skeleton.find_bone("RightHand")
	index_finger = skeleton.find_bone("RightHandIndex3_end")
	thumb = skeleton.find_bone("RightHandThumb2_end")
	_build_clips()
	model.add_child(animator)
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animator.add_animation_library("", clips)
	_update_pose(0)

static func _build_clips() -> void:
	if clips != null: return
	clips = AnimationLibrary.new()
	for entry in [[IDLE, "Idle", "idle"], [RUN, "Run", "run"]]:
		var source: Node = entry[0].instantiate()
		var rig: Skeleton3D = source.get_node("Root/Skeleton3D")
		var player: AnimationPlayer = source.get_node("AnimationPlayer")
		var clip: Animation
		for name in player.get_animation_list():
			if name.ends_with("|" + entry[1]): clip = player.get_animation(name).duplicate(true)
		assert(clip != null, "Use the supplied idle/run clips")
		# Immutable tracks differ between FBX rest poses; fill them from that clip's own rig.
		for i in rig.get_bone_count():
			var path := NodePath("Root/Skeleton3D:" + rig.get_bone_name(i))
			var rest := rig.get_bone_rest(i)
			for pair in [[Animation.TYPE_POSITION_3D, rest.origin], [Animation.TYPE_ROTATION_3D, rest.basis.get_rotation_quaternion()], [Animation.TYPE_SCALE_3D, rest.basis.get_scale()]]:
				if clip.find_track(path, pair[0]) >= 0: continue
				var track := clip.add_track(pair[0])
				clip.track_set_path(track, path)
				clip.track_insert_key(track, 0, pair[1])
		clip.loop_mode = Animation.LOOP_LINEAR
		clips.add_animation(entry[2], clip)
		source.free()

func _process(delta: float) -> void:
	_update_pose(delta)

func _update_pose(delta: float) -> void:
	var next := "run" if moving else "idle"
	if motion != next:
		motion = next
		animator.play(motion, 0.12)
	animator.speed_scale = 1.25 if moving else 1.0
	animator.advance(delta)
	# Match the cartoon hands to a metre-scale paper prop while keeping the imported skin and rig.
	for name in ["LeftHand", "RightHand"]:
		var index := skeleton.find_bone(name)
		skeleton.set_bone_pose_scale(index, Vector3.ONE * 0.60)
	skeleton.force_update_all_bone_transforms()
	if not holding: return
	# The preparation lean clears the paper without moving the feet or the launch point.
	var axis := (skeleton.global_basis.inverse() * (global_basis * Vector3(0.35, 0, -0.94))).normalized()
	for pair in [["Spine", 0.60 if preparing else 0.08]]:
		var index := skeleton.find_bone(pair[0])
		var pose := skeleton.get_bone_global_pose(index)
		pose.basis = Basis(axis, pair[1]) * pose.basis
		skeleton.set_bone_global_pose(index, pose)
		skeleton.force_update_all_bone_transforms()
	if preparing:
		var shoulder := skeleton.find_bone("RightShoulder")
		var pose := skeleton.get_bone_global_pose(shoulder)
		pose.origin += skeleton.global_basis.inverse() * (global_basis * Vector3(-0.12, 0.18, -0.04))
		skeleton.set_bone_global_pose(shoulder, pose)
		skeleton.force_update_all_bone_transforms()
	var target := skeleton.to_local(hand_target)
	for iteration in 24:
		_aim_fingers_up()
		for index in [forearm, upper]:
			var pose := skeleton.get_bone_global_pose(index)
			var tip := (skeleton.get_bone_global_pose(index_finger).origin + skeleton.get_bone_global_pose(thumb).origin) * 0.5
			var from := tip - pose.origin
			var to := target - pose.origin
			if from.length_squared() < 0.000000001 or to.length_squared() < 0.000000001: continue
			pose.basis = Basis(Quaternion(from.normalized(), to.normalized())) * pose.basis
			skeleton.set_bone_global_pose(index, pose)
			skeleton.force_update_all_bone_transforms()
	_aim_fingers_up()
	reach_error = hand_position().distance_to(hand_target)

func hand_position() -> Vector3:
	return skeleton.to_global((skeleton.get_bone_global_pose(index_finger).origin + skeleton.get_bone_global_pose(thumb).origin) * 0.5)

func _aim_fingers_up() -> void:
	var pose := skeleton.get_bone_global_pose(hand)
	var pinch := (skeleton.get_bone_global_pose(index_finger).origin + skeleton.get_bone_global_pose(thumb).origin) * 0.5
	var direction := pinch - pose.origin
	if direction.length_squared() < 0.000000001: return
	var up := (skeleton.global_basis.inverse() * Vector3.UP).normalized()
	pose.basis = Basis(Quaternion(direction.normalized(), up)) * pose.basis
	skeleton.set_bone_global_pose(hand, pose)
	skeleton.force_update_all_bone_transforms()
