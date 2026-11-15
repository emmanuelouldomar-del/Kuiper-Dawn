// Ciel : nébuleuse colorée (violet, rose, bleu) en bande, champ d'étoiles de plusieurs tailles.
shader_type sky;

uniform vec3 neb_a : source_color = vec3(0.55, 0.18, 0.75);
uniform vec3 neb_b : source_color = vec3(0.95, 0.35, 0.6);
uniform vec3 neb_c : source_color = vec3(0.15, 0.35, 0.95);
uniform float neb_power = 2.2;
uniform vec3 band_axis = vec3(0.35, 0.85, 0.4);

float hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

float fbm(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += vnoise(p) * a;
		p = p * 2.03 + 11.7;
		a *= 0.5;
	}
	return s;
}

float stars(vec3 d, float scale, float th) {
	vec3 p = d * scale;
	vec3 i = floor(p);
	float h = hash(i);
	if (h < th) {
		return 0.0;
	}
	vec3 c = i + 0.5 + (vec3(hash(i + 3.1), hash(i + 7.7), hash(i + 1.3)) - 0.5) * 0.6;
	float r = length(p - c);
	return smoothstep(0.12, 0.0, r) * (h - th) / (1.0 - th);
}

void sky() {
	vec3 d = EYEDIR;
	// bande de la nébuleuse (plan galactique incliné)
	float band = exp(-pow(dot(d, normalize(band_axis)) / 0.55, 2.0));
	float n1 = fbm(d * 2.2 + 5.0);
	float n2 = fbm(d * 4.5 - 3.0);
	float clouds = smoothstep(0.32, 0.8, n1 * 0.7 + n2 * 0.45) * band;
	vec3 neb = mix(neb_a, neb_b, smoothstep(0.4, 0.7, n2));
	neb = mix(neb, neb_c, smoothstep(0.55, 0.8, fbm(d * 3.1 + 21.0)));
	vec3 col = neb * clouds * clouds * 0.9 * neb_power;
	// filaments sombres de poussière
	col *= 1.0 - 0.6 * smoothstep(0.55, 0.7, fbm(d * 6.0 + 40.0)) * band;
	// fond très sombre bleuté
	col += vec3(0.004, 0.005, 0.012);
	// étoiles
	float s = stars(d, 180.0, 0.985) * 1.6 + stars(d, 420.0, 0.975) * 0.8 + stars(d, 60.0, 0.993) * 3.0;
	col += vec3(0.85, 0.9, 1.0) * s * (1.0 + band * 1.5);
	COLOR = col;
}
