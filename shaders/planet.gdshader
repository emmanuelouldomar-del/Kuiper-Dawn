// Terre procédurale : océans, continents, glaces, nuages, liseré atmosphérique
shader_type spatial;
varying vec3 lp;
float hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float noise(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { float a = 0.5; float s = 0.0; for (int i = 0; i < 6; i++) { s += a * noise(p); p *= 2.03; a *= 0.5; } return s; }
void vertex() { lp = VERTEX; }
void fragment() {
	vec3 p = normalize(lp);
	float c = fbm(p * 2.4 + vec3(1.7));
	float land = smoothstep(0.5, 0.53, c);
	float lat = abs(p.y);
	vec3 lc = mix(vec3(0.10, 0.20, 0.07), vec3(0.42, 0.33, 0.2), smoothstep(0.45, 0.65, fbm(p * 6.0)));
	vec3 col = mix(vec3(0.015, 0.05, 0.17), lc, land);
	col = mix(col, vec3(0.9), smoothstep(0.82, 0.9, lat + 0.05 * fbm(p * 8.0)));
	float cl = smoothstep(0.52, 0.72, fbm(p * 4.5 + vec3(3.1, 0.2, 5.0)));
	col = mix(col, vec3(0.97), cl * 0.9);
	ALBEDO = col;
	ROUGHNESS = mix(0.3, 0.95, max(land, cl));
	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION = vec3(0.25, 0.5, 1.0) * fr * 0.5;
}
