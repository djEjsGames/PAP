shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 front_color : source_color = vec4(0.98, 0.57, 0.32, 1.0);
uniform vec4 back_color : source_color = vec4(1.0, 0.91, 0.71, 1.0);
uniform vec4 ink_color : source_color = vec4(0.12, 0.16, 0.20, 1.0);
uniform float line_width : hint_range(0.0, 4.0) = 1.25;
varying vec3 world_normal;
varying vec3 world_position;

void vertex() {
	// Carry the folded layer order along each face's deployed normal, for either viewing side.
	VERTEX += NORMAL * UV2.x;
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 normal = normalize(world_normal);
	if (dot(normal, CAMERA_POSITION_WORLD - world_position) < 0.0) {
		normal = -normal;
	}
	float light = dot(normal, normalize(vec3(-0.45, 0.8, 0.55)));
	float band = 0.48 + 0.25 * step(0.15, light) + 0.27 * step(0.65, light);
	vec3 paper_color = FRONT_FACING ? front_color.rgb : back_color.rgb;
	vec3 barycentric = vec3(UV, 1.0 - UV.x - UV.y);
	vec3 distance_px = barycentric / max(fwidth(barycentric), vec3(0.00001));
	// COLOR marks polygon boundaries; internal fan diagonals receive no ink.
	distance_px = mix(vec3(10000.0), distance_px, COLOR.rgb);
	float edge = min(distance_px.x, min(distance_px.y, distance_px.z));
	float fill = smoothstep(line_width - 0.5, line_width + 0.5, edge);
	ALBEDO = mix(ink_color.rgb, paper_color * band, fill);
}