// Décor (rochers, cailloux) : facettes nettes, même roche ocre que le sol (la couleur de sommet ne donne plus que
// la luminosité, la teinte est imposée), ombres violettes comme le terrain.
shader_type spatial;
render_mode cull_disabled;

uniform vec4 base : source_color = vec4(1.0);
uniform vec3 ochre = vec3(0.235, 0.18, 0.135);

void fragment() {
	vec3 fn = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(fn, VIEW) < 0.0) {
		fn = -fn;
	}
	NORMAL = fn;
	vec3 c = pow(COLOR.rgb, vec3(2.2)) * base.rgb;
	float l = dot(c, vec3(0.3, 0.55, 0.15));
	vec3 col = ochre * clamp(l * 6.0, 0.62, 1.4);
	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
	EMISSION = col * vec3(0.38, 0.26, 0.62) * 0.22;
}
