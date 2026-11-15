// Sol de l'astéroïde : ROCHE OCRE À FACETTES (d'après l'image de référence de l'utilisateur du 2026-11-15).
// Chaque triangle est éclairé à plat (normale de facette) avec une légère variation de teinte par facette ;
// teintes beige-ocre, plaques plus claires, fonds de cratère et pentes plus sombres, ombres violettes.
// Le relief géométrique vient du maillage cube-sphère à sommets décalés (main.gd, mailles d'environ 6 m).
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

float tri(vec3 p, vec3 n, float s) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(noise_tex, p.yz * s).r * w.x + texture(noise_tex, p.xz * s).r * w.y + texture(noise_tex, p.xy * s).r * w.z;
}

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

// grandes facettes (vues de loin) : cellules de Voronoï 3D de ~30 m, chacune avec une inclinaison constante
vec4 macro_cell(vec3 p) {
	vec3 ip = floor(p);
	vec3 fp = fract(p);
	float best = 9.0;
	vec3 id = vec3(0.0);
	for (int z = -1; z <= 1; z++) for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
		vec3 g = vec3(float(x), float(y), float(z));
		vec3 o = vec3(hash3(ip + g), hash3(ip + g + 19.1), hash3(ip + g + 47.7));
		vec3 r = g + o - fp;
		float d = dot(r, r);
		if (d < best) {
			best = d;
			id = ip + g;
		}
	}
	return vec4(id, best);
}

void fragment() {
	// normale de facette (constante sur le triangle), orientée comme la normale lissée
	vec3 fn = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(fn, NORMAL) < 0.0) {
		fn = -fn;
	}
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(fn, 0.0)).xyz);
	vec3 n = normalize(wnrm);
	float slope = UV2.y;
	float cr = UV2.x;
	// grandes facettes : chaque cellule incline la normale d'un angle constant (mosaïque) ; cellules de ~30 m de près,
	// de ~110 m de loin (sinon, vues de l'orbite, elles feraient un marbrage)
	float px = length(fwidth(wpos));
	float far_f = smoothstep(0.5, 2.5, px);
	vec4 mc = macro_cell(wpos / 30.0);
	vec4 mc2 = macro_cell(wpos / 110.0 + 50.0);
	vec3 rt1 = vec3(hash3(mc.xyz + 3.1), hash3(mc.xyz + 7.7), hash3(mc.xyz + 11.3)) * 2.0 - 1.0;
	vec3 rt2 = vec3(hash3(mc2.xyz + 3.1), hash3(mc2.xyz + 7.7), hash3(mc2.xyz + 11.3)) * 2.0 - 1.0;
	vec3 rt = mix(rt1, rt2, far_f);
	rt -= n * dot(n, rt);
	// de loin, les petites facettes font moins d'un pixel : on passe en douceur à la normale lisse (pas de scintillement)
	float near_f = 1.0 - smoothstep(0.6, 2.5, px);
	vec3 wb = normalize(mix(n, wn, near_f));
	vec3 wf = normalize(wb + rt * 0.17);
	// teintes (linéaires) : beige ocre peu saturé, plaques claires, ocre sombre
	vec3 base = vec3(0.205, 0.158, 0.118);
	vec3 light_c = vec3(0.29, 0.232, 0.178);
	vec3 dark_c = vec3(0.125, 0.096, 0.078);
	// plaques claires larges et douces
	float big = tri(wpos, n, 0.0007) * 0.75 + tri(wpos + 17.0, n, 0.0019) * 0.25;
	vec3 col = mix(base, light_c, smoothstep(0.48, 0.66, big));
	col = mix(col, dark_c, (1.0 - smoothstep(0.22, 0.38, big)) * 0.12);
	// variation de teinte par facette et par grande facette
	float fv = hash3(floor(wn * 61.0) + 0.5);
	float cv = mix(hash3(mc.xyz + 23.9), hash3(mc2.xyz + 23.9), far_f);
	col *= (1.0 + (fv - 0.5) * 0.14 * near_f) * (0.94 + cv * 0.12);
	// cratères : fond plus sombre, rebord plus clair ; pentes plus sombres
	col = mix(col, dark_c, clamp(-cr, 0.0, 1.0) * 0.32);
	col = mix(col, light_c * 1.05, clamp(cr, 0.0, 1.0) * 0.22);
	col = mix(col, dark_c * 1.1, smoothstep(0.3, 0.55, slope) * 0.3);
	// chemins de la base et vers le camp pirate : régolithe tassé plus clair
	vec2 q = UV;
	if (q.x < 0.5e6) {
		float zz = q.y;
		float cx = 20.0 + 26.0 * sin(zz / 70.0) + 10.0 * sin(zz / 23.0);
		float inz = smoothstep(100.0, 130.0, zz) * smoothstep(720.0, 680.0, zz);
		float dp = abs(q.x - cx) - 9.0 + (1.0 - inz) * 100.0;
		float dr = abs(length(q) - 128.0) - 5.0;
		float path = 1.0 - smoothstep(-2.0, 2.0, min(dp, dr));
		col = mix(col, light_c * 1.12, path * 0.6);
	}
	ALBEDO = col * tint;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
	// ombres violettes : légère lueur violette qui ne se voit que là où le soleil n'éclaire pas
	EMISSION = col * vec3(0.38, 0.26, 0.62) * 0.22;
	NORMAL = normalize((VIEW_MATRIX * vec4(wf, 0.0)).xyz);
}
