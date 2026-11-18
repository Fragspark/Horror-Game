shader_type spatial;
// Gras/Unkraut fuer MultiMesh: Vertex-Farben, beidseitig, leichtes Wiegen im Wind.
render_mode cull_disabled, depth_draw_opaque;

uniform float sway_amount = 0.09;
uniform float sway_speed = 0.9;
uniform float tint_boost = 1.0;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float h = max(VERTEX.y, 0.0);
	float ph = origin.x * 0.45 + origin.z * 0.31;
	float s = sin(TIME * sway_speed + ph) + 0.5 * sin(TIME * sway_speed * 2.3 + ph * 1.7);
	VERTEX.x += s * sway_amount * h * h;
	VERTEX.z += cos(TIME * sway_speed * 0.8 + ph) * sway_amount * 0.6 * h * h;
}

void fragment() {
	ALBEDO = COLOR.rgb * tint_boost;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
