// Post-traitement : 10 styles graphiques appliqués à l'image rendue
shader_type canvas_item;
uniform int mode = 0;
uniform vec2 res = vec2(1600.0, 900.0);
uniform sampler2D src : filter_linear;

float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }
vec3 sat(vec3 c, float s) { return mix(vec3(lum(c)), c, s); }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y); }

float L(sampler2D t, vec2 uv) { return lum(textureLod(t, uv, 0.0).rgb); }
float sobel(sampler2D t, vec2 uv, vec2 px) {
	float tl = L(t, uv + px * vec2(-1, -1)); float tc = L(t, uv + px * vec2(0, -1)); float tr = L(t, uv + px * vec2(1, -1));
	float ml = L(t, uv + px * vec2(-1, 0)); float mr = L(t, uv + px * vec2(1, 0));
	float bl = L(t, uv + px * vec2(-1, 1)); float bc = L(t, uv + px * vec2(0, 1)); float br = L(t, uv + px * vec2(1, 1));
	float gx = -tl - 2.0 * ml - bl + tr + 2.0 * mr + br;
	float gy = -tl - 2.0 * tc - tr + bl + 2.0 * bc + br;
	return sqrt(gx * gx + gy * gy);
}
vec3 kuwahara(sampler2D t, vec2 uv, vec2 px) {
	vec3 m[4]; vec3 s[4];
	for (int k = 0; k < 4; k++) { m[k] = vec3(0.0); s[k] = vec3(0.0); }
	for (int j = 0; j <= 3; j++) {
		for (int i = 0; i <= 3; i++) {
			vec3 a = textureLod(t, uv + px * vec2(float(-i), float(-j)), 0.0).rgb; m[0] += a; s[0] += a * a;
			vec3 b = textureLod(t, uv + px * vec2(float(i), float(-j)), 0.0).rgb; m[1] += b; s[1] += b * b;
			vec3 c = textureLod(t, uv + px * vec2(float(-i), float(j)), 0.0).rgb; m[2] += c; s[2] += c * c;
			vec3 d = textureLod(t, uv + px * vec2(float(i), float(j)), 0.0).rgb; m[3] += d; s[3] += d * d;
		}
	}
	float best = 1e9; vec3 res_c = vec3(0.0);
	for (int k = 0; k < 4; k++) {
		vec3 mm = m[k] / 16.0; vec3 vv = abs(s[k] / 16.0 - mm * mm);
		float v = vv.r + vv.g + vv.b;
		if (v < best) { best = v; res_c = mm; }
	}
	return res_c;
}
float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0)); int y = int(mod(p.y, 4.0));
	int idx = x + y * 4;
	float m[16] = float[](0., 8., 2., 10., 12., 4., 14., 6., 3., 11., 1., 9., 15., 7., 13., 5.);
	return m[idx] / 16.0 - 0.5;
}

void fragment() {
	vec2 uv = UV;
	vec2 px = 1.0 / res;
	vec3 c = textureLod(src, uv, 0.0).rgb;
	vec2 fc = uv * res;
	float vig = smoothstep(1.15, 0.35, length((uv - 0.5) * vec2(1.25, 1.0)));
	if (mode == 1) {
		// bande dessinée / cel-shading
		float l = lum(c);
		float q = floor(l * 4.0 + 0.5) / 4.0 + 0.12;
		c = sat(c, 1.25) * (q / max(l, 0.02));
		float e = sobel(src, uv, px * 1.5);
		float hatch = step(0.5, fract((fc.x + fc.y) / 7.0));
		if (l < 0.18) { c *= mix(1.0, 0.55, hatch); }
		c = mix(c, vec3(0.04, 0.02, 0.05), smoothstep(0.24, 0.42, e));
	} else if (mode == 2) {
		// stratégie temps réel (couleurs vives, contours fins)
		c = sat(c, 1.45) * vec3(1.08, 1.02, 0.9);
		c = (c - 0.5) * 1.12 + 0.52;
		float e = sobel(src, uv, px);
		c = mix(c, c * 0.35, smoothstep(0.15, 0.4, e) * 0.6);
	} else if (mode == 3) {
		// apocalypse rouge
		float l = lum(c);
		vec3 g = mix(vec3(l) * vec3(1.15, 0.5, 0.38), c * vec3(1.35, 0.62, 0.45), 0.45);
		g = (g - 0.45) * 1.25 + 0.45;
		g += vec3(0.08, 0.015, 0.0);
		g *= mix(0.45, 1.0, vig);
		g += (hash(fc + vec2(TIME)) - 0.5) * 0.06;
		c = g;
	} else if (mode == 4) {
		// pixel art 16 bits
		float B = 4.0;
		vec2 cell = floor(fc / B);
		vec2 uq = (cell * B + B * 0.5) / res;
		c = textureLod(src, uq, 0.0).rgb;
		c = sat(c, 1.35);
		float lv = 6.0;
		c = floor(c * lv + 0.5 + bayer4(cell) * 0.45) / lv;
		float e = sobel(src, uq, px * B);
		c = mix(c, vec3(0.06, 0.05, 0.1), smoothstep(0.2, 0.45, e));
	} else if (mode == 5) {
		// plan technique
		float e = sobel(src, uv, px * 1.5);
		vec3 bg = vec3(0.06, 0.19, 0.42);
		float gx = step(fract(fc.x / 40.0), 0.025) + step(fract(fc.y / 40.0), 0.025);
		float gs = step(fract(fc.x / 8.0), 0.13) + step(fract(fc.y / 8.0), 0.13);
		bg += vec3(0.09, 0.14, 0.2) * min(gx, 1.0) + vec3(0.025, 0.04, 0.06) * min(gs, 1.0);
		float e2 = sobel(src, uv, px * 3.0);
		float line = smoothstep(0.3, 0.55, e) * smoothstep(0.25, 0.5, e2);
		c = mix(bg, vec3(0.86, 0.94, 1.0), line);
	} else if (mode == 6) {
		// néon synthwave
		float e = sobel(src, uv, px);
		float eg = 0.0;
		for (int k = 1; k <= 4; k++) { eg += sobel(src, uv, px * float(k) * 1.5); }
		vec3 nc = mix(vec3(0.0, 1.0, 0.95), vec3(1.0, 0.1, 0.8), clamp(uv.y * 1.2 - 0.1 + 0.15 * sin(uv.x * 7.0), 0.0, 1.0));
		vec3 base = c * vec3(0.12, 0.08, 0.22);
		c = base + nc * smoothstep(0.05, 0.22, e) * 1.3 + nc * eg * 0.12 + max(c - 0.75, 0.0) * 1.5;
		c += vec3(0.08, 0.0, 0.12) * (1.0 - uv.y);
	} else if (mode == 7) {
		// aquarelle
		vec3 k = kuwahara(src, uv, px * 1.6);
		k = sat(k, 0.9) * 1.02 + 0.02;
		float paper = vnoise(fc / 3.0) * 0.5 + vnoise(fc / 17.0) * 0.5;
		float e = sobel(src, uv, px * 2.0);
		k *= 1.0 - smoothstep(0.15, 0.6, e) * 0.35;
		k = mix(k, vec3(0.96, 0.93, 0.86), 0.06 + paper * 0.06);
		k *= 0.92 + paper * 0.12;
		c = k;
	} else if (mode == 8) {
		// noir, rouge seul conservé
		float l = smoothstep(0.06, 0.55, lum(c));
		float red = smoothstep(0.08, 0.25, c.r - max(c.g, c.b));
		float e = sobel(src, uv, px);
		vec3 g = vec3(l);
		g = mix(g, vec3(0.0), smoothstep(0.15, 0.35, e));
		g = mix(g, vec3(0.9, 0.06, 0.04) * (0.6 + l), red);
		g *= mix(0.3, 1.0, vig);
		g += (hash(fc + vec2(TIME * 3.0)) - 0.5) * 0.08;
		c = g;
	} else if (mode == 9) {
		// low-poly pastel
		float l = lum(c);
		float q = floor(l * 5.0 + 0.5) / 5.0;
		vec3 p0 = vec3(0.36, 0.33, 0.55); vec3 p1 = vec3(0.62, 0.55, 0.78); vec3 p2 = vec3(0.95, 0.72, 0.72); vec3 p3 = vec3(1.0, 0.93, 0.8);
		vec3 grad = q < 0.33 ? mix(p0, p1, q / 0.33) : (q < 0.66 ? mix(p1, p2, (q - 0.33) / 0.33) : mix(p2, p3, (q - 0.66) / 0.34));
		c = mix(grad, sat(c, 1.2) * 1.1, 0.25);
		float e = sobel(src, uv, px);
		c = mix(c, vec3(0.32, 0.26, 0.48), smoothstep(0.15, 0.4, e) * 0.7);
	} else if (mode == 12) {
		// minimaliste & géométrique : aplats doux pastel, aucun trait, léger halo, fond dégradé
		vec3 g = vec3(0.0);
		for (int i = 0; i < 8; i++) {
			float an = float(i) * 0.785398;
			vec2 o = vec2(cos(an), sin(an)) * px * 7.0;
			g += max(textureLod(src, uv + o, 1.0).rgb - 0.5, vec3(0.0));
		}
		float sk = 1.0 - smoothstep(0.004, 0.035, lum(c));
		c = sat(c, 1.0) * 0.92 + vec3(0.01, 0.012, 0.02);
		c += g * 0.05;
		vec3 bg = mix(vec3(0.09, 0.2, 0.24), vec3(0.03, 0.06, 0.1), uv.y);
		c = mix(c, bg + c * 0.6, sk);
		c *= mix(0.8, 1.0, vig);
	} else if (mode == 11) {
		// anime années 80 façon Venus Wars : aplats doux, traits bruns fins, teinte sépia poussiéreuse
		float l = lum(c);
		float b1 = smoothstep(0.10, 0.14, l);
		float b2 = smoothstep(0.42, 0.47, l);
		vec3 hue = c / max(l, 0.02);
		hue = mix(vec3(1.0), hue, 0.75);
		float lv = mix(mix(0.07, 0.24, b1), 0.5, b2);
		c = hue * lv;
		c = mix(c * vec3(0.8, 0.82, 1.0), c, b1);
		c *= mix(vec3(1.0), vec3(1.08, 1.0, 0.86), b2);
		c = sat(c, 0.85) * vec3(1.04, 0.98, 0.92) + vec3(0.02, 0.015, 0.01);
		float e = sobel(src, uv, px * 1.2);
		c = mix(c, vec3(0.13, 0.08, 0.05), smoothstep(0.45, 0.75, e) * 0.75);
		c *= mix(0.72, 1.0, vig);
		c += (hash(fc + vec2(floor(TIME * 12.0))) - 0.5) * 0.03;
	} else if (mode == 10) {
		// réaliste cinéma : aberration chromatique légère, vignette, grain fin
		vec2 d = (uv - 0.5) * px * 3.0;
		c = vec3(textureLod(src, uv + d, 0.0).r, c.g, textureLod(src, uv - d, 0.0).b);
		c = (c - 0.5) * 1.08 + 0.5;
		c *= mix(0.6, 1.0, vig);
		c += (hash(fc + vec2(TIME)) - 0.5) * 0.025;
	}
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
