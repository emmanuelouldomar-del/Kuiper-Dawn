// Décor (rochers, cailloux) : roche semi-réaliste, couleur de sommet, facettes nettes, éclairage PBR standard.
shader_type spatial;
render_mode cull_disabled;

uniform vec4 base : source_color = vec4(1.0);

void fragment() {
	vec3 fn = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(fn, VIEW) < 0.0) {
		fn = -fn;
	}
	NORMAL = fn;
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * base.rgb;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
}
