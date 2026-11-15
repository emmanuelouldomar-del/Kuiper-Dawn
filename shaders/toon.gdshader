// Décor (rochers, agaves, cactus, cailloux) : couleur de sommet × couleur de base, éclairage en aplats
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform vec4 base : source_color = vec4(1.0);

void fragment() {
	// couleurs de sommet en sRGB -> espace linéaire ; base est déjà convertie (source_color)
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * base.rgb;
	ROUGHNESS = 1.0;
}

void light() {
	float d = dot(NORMAL, LIGHT);
	float b = smoothstep(-0.02, 0.06, d) * 0.62 + smoothstep(0.42, 0.5, d) * 0.38;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * b / PI;
}
