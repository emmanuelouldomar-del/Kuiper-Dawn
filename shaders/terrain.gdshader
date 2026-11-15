// Sol de l'astéroïde : RÉGOLITHE GRIS SEMI-RÉALISTE (d'après les images de référence de l'utilisateur).
// Poussière grise à grain fin, plaques plus sombres ou plus claires, fonds de cratère sombres, rebords clairs,
// roche nue sombre sur les pentes ; relief de détail par perturbation de la normale (bruit projeté sur 3 axes).
// Éclairage PBR standard de Godot. Le relief géométrique vient du maillage cube-sphère (main.gd).
// UV = coordonnées à plat (m) autour de la base (1e6 loin) ; UV2.x = ombrage des cratères (-1 fond, +1 rebord) ;
// UV2.y = pente du relief seul.
shader_type spatial;
render_mode cull_disabled;

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

// bruit fractal (plusieurs octaves)
float fbm(vec3 p, vec3 n, float s) {
	return tri(p, n, s) * 0.5 + tri(p + 17.3, n, s * 2.17) * 0.3 + tri(p - 9.1, n, s * 4.6) * 0.2;
}

void fragment() {
	vec3 n = normalize(wnrm);
	float slope = UV2.y;
	float cr = UV2.x;
	// teintes (linéaires) : gris de régolithe légèrement brun, poussière claire, roche sombre bleutée
	vec3 dust = vec3(0.115, 0.108, 0.100);
	vec3 dust_l = vec3(0.19, 0.18, 0.168);
	vec3 dust_d = vec3(0.062, 0.058, 0.056);
	vec3 rock = vec3(0.045, 0.046, 0.052);
	// grandes plaques, puis grain moyen et fin
	float big = fbm(wpos, n, 0.006);
	float mid = fbm(wpos + 31.0, n, 0.05);
	float fine = tri(wpos * 1.0 + 7.0, n, 0.6);
	vec3 col = mix(mix(dust_d, dust, 0.45), dust, smoothstep(0.25, 0.7, big));
	col = mix(col, dust_l, smoothstep(0.6, 0.85, mid) * 0.25);
	col *= 0.9 + fine * 0.2;
	// cratères : fond sombre, rebord éclairci (éjectas)
	col = mix(col, dust_d * 0.8, clamp(-cr, 0.0, 1.0) * 0.55);
	col = mix(col, dust_l * 1.1, clamp(cr, 0.0, 1.0) * 0.5);
	// éjectas : traînées claires autour des grands cratères
	col += dust_l * 0.25 * smoothstep(0.7, 0.95, tri(wpos + 53.0, n, 0.012)) * (1.0 - smoothstep(0.2, 0.4, slope));
	// pentes : roche nue sombre, striée
	float cliff = smoothstep(0.28, 0.48, slope);
	col = mix(col, rock * (0.8 + fine * 0.5), cliff);
	// chemins de la base et vers le camp pirate : régolithe tassé plus clair, bords doux
	vec2 q = UV;
	if (q.x < 0.5e6) {
		float zz = q.y;
		float cx = 20.0 + 26.0 * sin(zz / 70.0) + 10.0 * sin(zz / 23.0);
		float inz = smoothstep(100.0, 130.0, zz) * smoothstep(720.0, 680.0, zz);
		float dp = abs(q.x - cx) - 9.0 + (1.0 - inz) * 100.0;
		float dr = abs(length(q) - 128.0) - 5.0;
		float path = 1.0 - smoothstep(-2.0, 2.0, min(dp, dr));
		col = mix(col, dust_l * (0.85 + fine * 0.2), path * 0.7);
	}
	ALBEDO = col * tint;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
	// relief de détail : perturbation de la normale par le gradient du bruit
	float e = 0.35;
	vec3 t1 = normalize(cross(n, abs(n.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec3 t2 = cross(n, t1);
	float h0 = fbm(wpos, n, 0.09);
	float hx = fbm(wpos + t1 * e, n, 0.09);
	float hy = fbm(wpos + t2 * e, n, 0.09);
	vec3 bn = normalize(n - (t1 * (hx - h0) + t2 * (hy - h0)) * (2.2 / e) * 0.35);
	NORMAL = normalize((VIEW_MATRIX * vec4(bn, 0.0)).xyz);
}
