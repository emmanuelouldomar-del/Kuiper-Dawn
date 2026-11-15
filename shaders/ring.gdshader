// Anneaux de la géante gazeuse : profil radial (couleur + transparence) lu dans une texture 1D.
shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never, shadows_disabled;

uniform sampler2D prof : source_color, filter_linear, repeat_disable;

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	vec4 c = texture(prof, vec2(clamp(r, 0.0, 1.0), 0.5));
	ALBEDO = c.rgb * 0.75;
	ALPHA = c.a * step(r, 1.0);
}
