// Camouflage à trois tons pour les véhicules : taches de bruit 3D dans le repère du modèle (elles suivent le char),
// grain fin et légère usure qui fait varier la rugosité. Les couleurs viennent du camp (battle.gd).
shader_type spatial;

uniform vec3 c1 : source_color = vec3(0.24, 0.28, 0.15);
uniform vec3 c2 : source_color = vec3(0.16, 0.19, 0.10);
uniform vec3 c3 : source_color = vec3(0.35, 0.34, 0.23);
uniform float scale = 0.42;
uniform float tone = 0.55;     // assombrit : sous le soleil du jeu, les teintes ressortent bien plus claires

varying vec3 lp;

float h(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float n(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h(i), h(i + vec3(1, 0, 0)), f.x), mix(h(i + vec3(0, 1, 0)), h(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h(i + vec3(0, 0, 1)), h(i + vec3(1, 0, 1)), f.x), mix(h(i + vec3(0, 1, 1)), h(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec3 p = lp * scale;
	float a = n(p) * 0.65 + n(p * 2.3) * 0.35;
	float b = n(p * 1.3 + 7.1) * 0.65 + n(p * 2.9 + 3.3) * 0.35;
	vec3 col = c1;
	col = mix(col, c2, smoothstep(0.53, 0.56, a));
	col = mix(col, c3, smoothstep(0.6, 0.63, b));
	float g = n(lp * 9.0) * 0.6 + n(lp * 23.0) * 0.4;
	col *= (0.88 + 0.22 * g) * tone;
	ALBEDO = col;
	ROUGHNESS = 0.62 + 0.3 * g;
	METALLIC = 0.18;
}
