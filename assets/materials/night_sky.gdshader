shader_type sky;
// Dunkler Nachthimmel: Horizont-Dunst, wenige Sterne, duenne Wolkenschleier und
// eine Mondscheibe in Richtung der ersten DirectionalLight3D (Moonlight).

uniform vec3 zenith_color : source_color = vec3(0.008, 0.014, 0.036);
uniform vec3 horizon_color : source_color = vec3(0.075, 0.095, 0.155);
uniform vec3 ground_color : source_color = vec3(0.02, 0.026, 0.04);
uniform float star_strength = 0.2;
uniform float cloud_amount : hint_range(0.0, 1.0) = 0.55;
uniform float moon_size = 0.032;
uniform vec3 moon_color : source_color = vec3(0.72, 0.84, 1.0);

float h31(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x),
			mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void sky() {
	vec3 d = EYEDIR;
	float h = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(horizon_color, zenith_color, pow(h, 0.42));
	if (d.y < 0.0) {
		col = mix(horizon_color * 0.8, ground_color, smoothstep(0.0, 0.3, -d.y));
	}

	// Sterne
	vec3 sp = d * 180.0;
	vec3 id = floor(sp);
	float r = h31(id);
	float dd = length(fract(sp) - 0.5);
	float star = step(0.992, r) * smoothstep(0.32, 0.0, dd);
	star *= smoothstep(0.05, 0.35, d.y);
	col += vec3(0.65, 0.75, 1.0) * star * star_strength * (0.4 + 0.6 * h31(id + 7.0));

	// Wolkenschleier (fbm auf Himmelsebene projiziert)
	if (d.y > 0.02) {
		vec2 cp = d.xz / (d.y + 0.28) * 1.7 + vec2(TIME * 0.004, 0.0);
		float n = vnoise(cp) * 0.55 + vnoise(cp * 2.3 + 3.0) * 0.3 + vnoise(cp * 5.1 + 9.0) * 0.15;
		float cloud = smoothstep(0.5, 0.85, n) * smoothstep(0.02, 0.25, d.y) * cloud_amount;
		col = mix(col, horizon_color * 1.6 + vec3(0.01, 0.012, 0.02), cloud * 0.6);
	}

	// Mond
	if (LIGHT0_ENABLED) {
		float m = dot(d, LIGHT0_DIRECTION);
		float disc = smoothstep(cos(moon_size * 1.15), cos(moon_size), m);
		float halo = pow(max(m, 0.0), 160.0) * 0.12 + pow(max(m, 0.0), 24.0) * 0.015;
		col += moon_color * (disc * 0.5 + halo * 0.3);
	}
	COLOR = col;
}
