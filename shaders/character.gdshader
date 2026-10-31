shader_type spatial;
render_mode depth_prepass_alpha;
uniform sampler2D skin_texture : source_color, filter_nearest;
uniform bool clear_held = false;
uniform vec3 held_world = vec3(0.0);
uniform float clearance_radius = 0.1;

void fragment() {
	ALBEDO = texture(skin_texture, UV).rgb;
	ROUGHNESS = 1.0;
	ALPHA = 1.0;
	if (clear_held) {
		vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 to_paper = held_world - CAMERA_POSITION_WORLD;
		float paper_depth = length(to_paper);
		vec3 ray = to_paper / max(paper_depth, 0.001);
		float depth = dot(world - CAMERA_POSITION_WORLD, ray);
		float distance_to_ray = length(world - CAMERA_POSITION_WORLD - ray * depth);
		// Only the character fragments actually in front of the paper fade.
		if (depth > 0.0 && depth < paper_depth - 0.015) {
			ALPHA = mix(0.12, 1.0, smoothstep(clearance_radius * 0.8, clearance_radius, distance_to_ray));
		}
	}
}
