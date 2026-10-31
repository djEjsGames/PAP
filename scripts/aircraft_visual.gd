extends RefCounted
const Model := preload("res://scripts/flight_model.gd")
const Parts := preload("res://scripts/flight_parts.gd")
const Stock := preload("res://scripts/paper_stock.gd")
const PaperToon := preload("res://shaders/paper_toon.gdshader")

static func build(posed: Array[Dictionary], center: Vector3, paper_stock: Dictionary) -> Dictionary:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_custom_format(0, SurfaceTool.CUSTOM_RG_FLOAT)
	var collision_points := PackedVector3Array()
	# Display spacing only: physical vertices, seams and collision remain unchanged.
	var stack_depth := minf(0.000025 * (posed.size() - 1), 0.0006)
	for face_index in posed.size():
		var face: Dictionary = posed[face_index]
		var layer_offset: float = (float(face_index) / maxi(1, posed.size() - 1) - 0.5) * stack_depth * face.layer_sign
		for i in range(1, face.points.size() - 1):
			var triangle := [face.points[0] - center, face.points[i] - center, face.points[i + 1] - center]
			var boundary_mask := Color(1, 1 if i + 1 == face.points.size() - 1 else 0, 1 if i == 1 else 0)
			for vertex_index in 3:
				var point: Vector3 = triangle[vertex_index]
				tool.set_color(boundary_mask)
				tool.set_uv([Vector2(1, 0), Vector2(0, 1), Vector2.ZERO][vertex_index])
				tool.set_uv2(Vector2(layer_offset, 0))
				var material_point: Vector2 = face.paper[[0, i, i + 1][vertex_index]] / paper_stock.size + Vector2(0.5, 0.5)
				tool.set_custom(0, Color(material_point.x, material_point.y, 0, 0))
				tool.set_normal(face.normal)
				tool.add_vertex(point)
				collision_points.append(point + face.normal * 0.0001)
				collision_points.append(point - face.normal * 0.0001)
	var geometry := tool.commit()
	var material := ShaderMaterial.new()
	material.shader = PaperToon
	if paper_stock.id not in ["origami", "legacy"]:
		material.set_shader_parameter("front_color", Stock.front(paper_stock))
		material.set_shader_parameter("back_color", Stock.back(paper_stock))
	var texture := Stock.texture(paper_stock)
	material.set_shader_parameter("use_pattern", texture != null)
	if texture != null: material.set_shader_parameter("paper_pattern", texture)
	return {"mesh": geometry, "material": material, "collision": collision_points}

static func grip_offset(posed: Array[Dictionary], faces: Array[Dictionary], history: Array[Dictionary], binding: Dictionary, center: Vector3) -> Vector3:
	var grip := int(binding.grip) if not binding.is_empty() else -1
	if grip < 0:
		var wings := Model.wing_folds(history)
		if wings.size() == 2:
			for i in faces.size():
				if Parts.role(i, faces, history, wings, -1) < 0:
					grip = i
					break
	# The character targets the pinch between the thumb and index finger.
	return Model.properties([posed[grip]]).center - center if grip >= 0 else Vector3.ZERO
