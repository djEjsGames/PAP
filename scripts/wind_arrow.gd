extends Control

const SPIN_PER_MPS := PI # Half a turn per second for every 1 m/s.
var view := SubViewport.new()
var heading := Node3D.new()
var rotor := Node3D.new()
var phase := 0.0
var angular_speed := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.size = Vector2i(128, 128)
	view.transparent_bg = true
	view.own_world_3d = true
	view.gui_disable_input = true
	view.msaa_3d = Viewport.MSAA_2X
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(view)
	var image := TextureRect.new()
	image.texture = view.get_texture()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image)
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.3
	camera.position = Vector3(0, 0, 3)
	view.add_child(camera)
	camera.make_current()
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.55
	view.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -35, 0)
	view.add_child(light)
	view.add_child(heading)
	heading.add_child(rotor)
	rotor.scale.z = 0.18 # A thin blade exposes the axial roll through its changing silhouette.
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.15
	shaft.bottom_radius = 0.15
	shaft.height = 1
	shaft.radial_segments = 6
	_add_mesh(shaft, Vector3(0, -0.3, 0), Color("55baaf"))
	var tip := CylinderMesh.new()
	tip.top_radius = 0
	tip.bottom_radius = 0.33
	tip.height = 0.6
	tip.radial_segments = 4
	_add_mesh(tip, Vector3(0, 0.5, 0), Color("9af2df"))
	# A bright ridge makes roll visible even when the cylindrical shaft faces the camera.
	var ridge := BoxMesh.new()
	ridge.size = Vector3(0.045, 0.85, 0.018)
	_add_mesh(ridge, Vector3(0, -0.3, 0.155), Color("fff4d5"))
	hide()

func _add_mesh(geometry: Mesh, position: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = geometry
	mesh.position = position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1
	mesh.material_override = material
	rotor.add_child(mesh)

func update_wind(direction: Vector3, speed: float, delta: float) -> void:
	visible = speed >= 0.001 and direction.length_squared() > 0.001
	angular_speed = maxf(0, speed) * SPIN_PER_MPS if visible else 0
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
	if not visible: return
	phase = fposmod(phase + angular_speed * delta, TAU)
	heading.basis = Basis(Quaternion(Vector3.UP, direction.normalized()))
	rotor.rotation.y = phase
