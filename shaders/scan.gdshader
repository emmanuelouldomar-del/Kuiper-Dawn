// Voile d'écran cathodique : lignes de balayage, bords assombris, légère lueur verte.
shader_type canvas_item;

uniform float spacing = 3.0;

void fragment() {
	float l = mod(FRAGCOORD.y, spacing) < 1.0 ? 0.12 : 0.0;
	vec2 d = UV - 0.5;
	float v = smoothstep(0.35, 0.75, length(d * vec2(1.0, 1.15)));
	COLOR = vec4(0.0, 0.04, 0.01, clamp(l + v * 0.55, 0.0, 0.85));
}
