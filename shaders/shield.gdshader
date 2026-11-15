// Bouclier du centre de commandement (réacteur à hélium-3) : dôme d'énergie additif, trame hexagonale,
// lisière lumineuse (Fresnel), anneaux d'impact, montée depuis le sol à l'activation.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 col = vec3(0.25, 0.72, 1.0);
uniform float act = 1.0;      // activation 0 → 1 (le dôme monte depuis le sol)
uniform float energy = 1.0;   // énergie du bouclier 0 → 1 (0 : effondré)
uniform vec4 hits[8];         // xyz : direction de l'impact depuis le centre, w : âge (s)

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

// distance au bord d'une cellule hexagonale (0 au bord)
float hex_edge(vec2 p) {
	const vec2 s = vec2(1.0, 1.7320508);
	vec4 hc = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
	vec4 h = vec4(p - hc.xy * s, p - (hc.zw + 0.5) * s);
	vec2 q = dot(h.xy, h.xy) < dot(h.zw, h.zw) ? h.xy : h.zw;
	q = abs(q);
	return 0.5 - max(dot(q, s * 0.5), q.x);
}

void fragment() {
	vec3 d = normalize(lp);
	// sous le sol (moitié basse) : rien
	if (d.y < -0.35) {
		discard;
	}
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.5);
	// trame hexagonale projetée depuis le haut du dôme
	vec2 hp = d.xz / (1.0 + max(d.y, 0.0)) * 26.0;
	float he = hex_edge(hp);
	float hw = fwidth(he) * 1.2;
	float hexl = 1.0 - smoothstep(0.0, max(hw, 0.015), he);
	// impacts : éclair et anneau qui s'élargit
	float ring = 0.0;
	for (int i = 0; i < 8; i++) {
		float a = hits[i].w;
		if (a < 1.6) {
			float dd = acos(clamp(dot(d, normalize(hits[i].xyz)), -1.0, 1.0));
			ring += exp(-pow((dd - a * 0.22) / 0.025, 2.0)) * (1.0 - a / 1.6);
			ring += exp(-dd * 40.0) * max(0.0, 1.0 - a * 3.0) * 2.0;
		}
	}
	// activation : le dôme monte depuis le sol, avec un front lumineux
	float h01 = clamp(d.y * 1.2 + 0.35, 0.0, 1.0);
	float shown = 1.0 - smoothstep(act - 0.02, act + 0.02, h01);
	float front = exp(-pow((h01 - act) / 0.03, 2.0)) * step(act, 0.999);
	float e = mix(0.25, 1.0, energy) * step(0.001, energy + ring);
	float I = (0.015 + fres * 0.35 + hexl * (0.05 + fres * 0.25)) * e * shown + front * 1.5 + ring * 0.9;
	ALBEDO = col * I;
}
