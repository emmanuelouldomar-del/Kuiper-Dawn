// Style low-poly « game-ready » : chaque triangle est éclairé à plat (normale du triangle calculée
// à partir des dérivées écran), couleurs unies, émission optionnelle, couleur de sommet optionnelle (unités).
shader_type spatial;
render_mode specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float metallic = 0.0;
uniform float roughness = 0.8;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform bool use_vertex_color = false;

varying vec3 vcol;

void vertex() {
	vcol = COLOR.rgb;
}

void fragment() {
	// facette : normale du triangle, tournée vers la caméra
	vec3 fn = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(fn, VIEW) < 0.0) {
		fn = -fn;
	}
	NORMAL = fn;
	vec3 c = albedo.rgb;
	if (use_vertex_color) {
		c *= pow(vcol, vec3(2.2));
	}
	ALBEDO = c;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	EMISSION = emission.rgb * emission_energy;
}

// flat shading : deux tons tranchés, ombre bleutée (comme le sol)
void light() {
	float d = dot(NORMAL, LIGHT);
	float lit = step(0.08, d) * ATTENUATION;
	vec3 sh = vec3(0.34, 0.40, 0.70) * 0.45;
	DIFFUSE_LIGHT += mix(sh, vec3(1.0), lit) * LIGHT_COLOR * (0.35 + 0.65 * lit) / PI;
}
