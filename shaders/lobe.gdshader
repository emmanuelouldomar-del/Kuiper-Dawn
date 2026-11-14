shader_type spatial;
// second lobe (astéroïde binaire) : sphère à part, texture projetée sur 3 axes (aucun étirement)
uniform sampler2D amap : filter_linear, repeat_enable;
uniform float tile = 512.0;
uniform float big = 5.7;
uniform vec3 tint = vec3(1.0);
uniform float rad = 100.0;
varying vec3 wpos;
varying vec3 wn;

float tri(vec3 p, vec3 w, float s, vec2 o) {
	return texture(amap, p.yz / s + o).r * w.x + texture(amap, p.xz / s + o).r * w.y + texture(amap, p.xy / s + o).r * w.z;
}

void vertex() {
	vec3 n = normalize(VERTEX);
	// légères ondulations, sans détail fin
	float b = textureLod(amap, n.xz * 0.35 + n.y * 0.2 + vec2(0.13, 0.57), 0.0).r;
	VERTEX = n * (1.0 + 0.05 * (b - 0.5));
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(n, 0.0)).xyz);
}

void fragment() {
	vec3 w = pow(abs(wn), vec3(4.0));
	w /= (w.x + w.y + w.z);
	float a2 = tri(wpos, w, tile * big, vec2(0.37, 0.11));
	float a3 = tri(wpos, w, tile * big * 0.6, vec2(0.71, 0.29));
	vec3 ocre = vec3(0.42, 0.22, 0.11);
	vec3 clair = vec3(0.45, 0.25, 0.13);
	vec3 col = mix(ocre, clair, smoothstep(0.5, 0.56, a2 + 0.45) * 0.6);
	ALBEDO = col * tint;
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
}
