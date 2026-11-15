// Sol de l'astéroïde : roche grise en aplats (façon Planetary Annihilation), pailletée d'éclats orange et rouges
// Le relief vient du maillage cube-sphère (main.gd) ; ce shader ne fait que la couleur et l'ombrage en aplats.
// UV = coordonnées à plat (m) autour de la base (1e6 loin de la base) ; UV2.x = ombrage des cratères (-1 fond, +1 rebord) ;
// UV2.y = pente du relief seul (1 - normale · normale de la forme lisse).
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform vec3 center = vec3(0.0);
uniform vec3 tint = vec3(1.0);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// bruit projeté sur les 3 axes (pas d'étirement sur la sphère)
float tri(vec3 p, vec3 n, float s) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(noise_tex, p.yz * s).r * w.x + texture(noise_tex, p.xz * s).r * w.y + texture(noise_tex, p.xy * s).r * w.z;
}

vec3 hash3(vec3 p) {
	// hachage sans sinus (précis même loin de l'origine)
	vec3 p3 = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// bande claire bordée d'un liseré foncé, à partir d'une distance signée (m) : chemins de la base
vec3 trail(vec3 col, float d, vec3 inside, vec3 edge, float amount) {
	float aa = max(fwidth(d), 0.02);
	col = mix(col, inside, (1.0 - smoothstep(-aa, aa, d)) * amount);
	col = mix(col, edge, (1.0 - smoothstep(0.35 - aa, 0.35 + aa, abs(d))) * amount * 0.85);
	return col;
}

void fragment() {
	vec3 n = normalize(wnrm);
	// pente du relief seul (cratères, plateaux, crêtes), mesurée par rapport à la forme lisse de l'astéroïde
	float slope = UV2.y;

	// gris d'astéroïde, plusieurs nuances (teintes en linéaire)
	vec3 grey = vec3(0.148, 0.150, 0.156);
	vec3 grey_d = vec3(0.086, 0.088, 0.094);
	vec3 grey_l = vec3(0.26, 0.262, 0.266);
	vec3 grey_w = vec3(0.17, 0.162, 0.152);   // gris chaud
	vec3 grey_c = vec3(0.118, 0.124, 0.135);  // gris froid
	vec3 edge = vec3(0.035, 0.034, 0.036);
	vec3 rock = vec3(0.062, 0.062, 0.068);
	vec3 rock_d = vec3(0.038, 0.038, 0.043);

	// grandes plaques de gris plus ou moins foncé, chaud ou froid
	float big = tri(wpos, n, 0.004);
	vec3 col = mix(grey, grey_d, smoothstep(0.45, 0.62, big) * 0.6);
	float hue = tri(wpos + vec3(113.0, 57.0, -41.0), n, 0.0025);
	col = mix(col, grey_w, smoothstep(0.55, 0.7, hue) * 0.6);
	col = mix(col, grey_c, smoothstep(0.42, 0.3, hue) * 0.6);

	// cratères : fond plus sombre, rebord plus clair
	float cr = UV2.x;
	col = mix(col, grey_d * 0.85, clamp(-cr, 0.0, 1.0) * 0.5);
	col = mix(col, grey_l, clamp(cr, 0.0, 1.0) * 0.45);

	// zones de régolithe plus clair
	float gv = tri(wpos + vec3(37.0, 11.0, 5.0), n, 0.011);
	col = mix(col, grey_l * 0.85, smoothstep(0.66, 0.69, gv) * 0.5);

	// chemins autour de la base et vers le camp pirate (coordonnées à plat) : régolithe tassé clair
	vec2 q = UV;
	float near = 1.0 - step(0.5e6, q.x);
	if (near > 0.5) {
		float zz = q.y;
		float cx = 20.0 + 26.0 * sin(zz / 70.0) + 10.0 * sin(zz / 23.0);
		float inz = smoothstep(100.0, 130.0, zz) * smoothstep(720.0, 680.0, zz);
		float dp = abs(q.x - cx) - 11.0 + (1.0 - inz) * 100.0;
		float dr = abs(length(q) - 128.0) - 6.0;
		col = trail(col, min(dp, dr), grey_l, edge, near);
	}

	// petits cailloux sombres semés sur le sol
	float sp = tri(wpos, n, 0.3);
	col = mix(col, edge, smoothstep(0.74, 0.78, sp) * 0.6);

	// falaises et pentes fortes : roche sombre à nu, en strates
	float cliff = smoothstep(0.32, 0.45, slope);
	// strates anticrénelées (pas de moiré vu de loin)
	float sv = length(wpos - center) * 0.18 + tri(wpos, n, 0.02) * 0.6;
	float sw = max(fwidth(sv), 1e-4);
	float strata = mix(smoothstep(0.5 - sw, 0.5 + sw, fract(sv)), 0.5, smoothstep(0.25, 0.5, sw));
	col = mix(col, mix(rock, rock_d, strata * 0.6), cliff);

	// paillettes : très petits éclats orange et rouges semés dans le gris, plus denses par plaques, et léger voile rouille.
	// Discret : de loin, les éclats (plus petits qu'un pixel) sont remplacés par leur teinte moyenne, sans scintillement.
	float px = length(vec2(length(dFdx(wpos)), length(dFdy(wpos)))) * 0.7;
	vec3 orange = vec3(0.62, 0.16, 0.02);
	vec3 red = vec3(0.45, 0.03, 0.015);
	float patch = smoothstep(0.35, 0.7, tri(wpos + vec3(53.0, -17.0, 8.0), n, 0.008));
	// voile rouille, très léger, comme un brossage
	float rust = smoothstep(0.5, 0.8, tri(wpos + vec3(-29.0, 41.0, 13.0), n, 0.02)) * (0.4 + 0.6 * patch);
	col = mix(col, vec3(0.2, 0.085, 0.045), rust * 0.06);
	float cs = 0.16;                                   // taille d'un éclat (m)
	float dens = mix(0.006, 0.035, patch);              // part des cellules qui portent un éclat
	vec3 h = hash3(floor(wpos / cs));
	float fleck = step(1.0 - dens, h.x);
	vec3 fc = mix(orange, red, h.y);
	float near_f = 1.0 - smoothstep(cs * 0.5, cs * 1.5, px);
	col = mix(col, fc, fleck * near_f * 0.6);
	// de loin : teinte moyenne des éclats
	col = mix(col, mix(orange, red, 0.5), dens * 0.12 * (1.0 - near_f));

	ALBEDO = col * tint;
	ROUGHNESS = 1.0;
	// petit éclat lumineux des paillettes, discret
	EMISSION = fc * fleck * near_f * 0.06;
}

// éclairage en aplats (3 tons), façon dessin animé
void light() {
	float d = dot(NORMAL, LIGHT);
	float b = smoothstep(-0.02, 0.06, d) * 0.62 + smoothstep(0.42, 0.5, d) * 0.38;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * b / PI;
}
