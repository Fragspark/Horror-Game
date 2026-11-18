shader_type spatial;
// Fensterglas fuer das Wohnhaus: fast durchsichtig, unshaded (kein Specular,
// keine Spiegelung von Innenlampen, siehe Fix vom 17.11.), aber mit Schmutz an
// Raendern/Ecken und fleckigen Schlieren, damit Scheiben nachts nicht wie
// unsichtbare Loecher wirken. Schmutz DUNKELT ab, leuchtet also nie.
render_mode unshaded, blend_mix, cull_back, depth_draw_opaque;

uniform vec4 glass_color : source_color = vec4(0.72, 0.8, 0.9, 1.0);
uniform vec4 dirt_color : source_color = vec4(0.035, 0.045, 0.055, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.07;
uniform float grime_alpha : hint_range(0.0, 1.0) = 0.12;
uniform float edge_width : hint_range(0.02, 0.5) = 0.11;
uniform float noise_scale = 3.2;

varying vec3 wp;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h21(i);
	float b = h21(i + vec2(1.0, 0.0));
	float c = h21(i + vec2(0.0, 1.0));
	float d = h21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Position in der Scheibenebene (funktioniert fuer x- und z-gerichtete Scheiben)
	vec2 p = vec2(wp.x + wp.z, wp.y) * noise_scale;
	float n = vnoise(p) * 0.6 + vnoise(p * 2.7 + 7.0) * 0.4;
	float edge_d = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float edge = 1.0 - smoothstep(0.0, edge_width, edge_d);
	// unten staerker verschmutzt (Regenrinnsale / Staub)
	float bottom = 1.0 - smoothstep(0.0, 0.35, UV.y);
	float streak = smoothstep(0.62, 0.95, vnoise(vec2(p.x * 2.2, p.y * 0.25)));
	float grime = clamp(edge * (0.35 + n) + bottom * 0.35 * n + streak * 0.35, 0.0, 1.0);
	ALBEDO = mix(glass_color.rgb, dirt_color.rgb, grime);
	ALPHA = base_alpha + grime * grime_alpha;
}
