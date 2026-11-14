// Panache de moteur fusée (additif), s'estompe vers le bas
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 col : source_color = vec4(1.0, 0.85, 0.55, 1.0);
uniform float power = 6.0;
void fragment() {
	float t = UV.y;
	float edge = pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.5);
	float a = pow(1.0 - t, 1.6) * edge;
	ALBEDO = col.rgb * power * a;
	ALPHA = a;
}
