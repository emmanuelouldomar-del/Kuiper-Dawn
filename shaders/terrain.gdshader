// Régolithe : hauteur et albédo lus dans une tuile 512 m (2 échelles), courbure de l'astéroïde
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D hmap : filter_linear, repeat_enable;
uniform sampler2D amap : filter_linear, repeat_enable;
uniform sampler2D detail_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_a : filter_linear_mipmap, repeat_enable;
uniform float tile = 512.0;
uniform float big = 5.7;
uniform float bigh = 4.0;
uniform float Rc = 10000.0;
uniform float flat_r0 = 150.0;
uniform float flat_r1 = 320.0;
uniform bool outer = false;
uniform float hole = 590.0;
uniform float vlod = 0.0;
uniform float sink = 0.0;
uniform vec3 ell = vec3(1.0);
uniform vec3 lobe_c = vec3(0.0);
uniform float lobe_r = 0.0;
uniform vec4 blobs[16];
uniform float bwid[16];
uniform float pole = 1.0;
uniform float th0 = 0.3;
varying vec3 vnorm;
varying float mrel;
// grand relief : cratères géants, canyons, falaises
uniform vec4 gcr[10];
uniform float gcd[10];
uniform vec4 cyn[4];
uniform vec4 cyc[4];
uniform float cyd[4];
uniform vec4 scp[3];
uniform float sch[3];
uniform vec3 tint = vec3(1.0);
varying vec3 wp;

float H(vec2 p, float lod) {
	float h1 = textureLod(hmap, p / tile, lod).r;
	float h2 = textureLod(hmap, p / (tile * big) + vec2(0.37, 0.11), lod).r;
	float m = smoothstep(flat_r0, flat_r1, length(p));
	// couloir du champ de bataille, aplani
	float mc = max(smoothstep(95.0, 175.0, abs(p.x - 20.0)), max(smoothstep(560.0, 650.0, p.y), smoothstep(120.0, 60.0, p.y)));
	return (h2 * bigh * 0.3) * min(mix(0.12, 1.0, m), mix(0.22, 1.0, mc));
}

float shape_raw(vec3 d) {
	float e = 1.0 / sqrt(dot(d * d, 1.0 / (ell * ell)));
	if (lobe_r > 0.0) {
		float dc = dot(d, lobe_c);
		float disc = dc * dc - dot(lobe_c, lobe_c) + lobe_r * lobe_r;
		if (disc > 0.0) {
			float tb = dc + sqrt(disc);
			float k = 0.12;
			float m = max(e, tb);
			e = m + k * log(exp((e - m) / k) + exp((tb - m) / k));
		}
	}
	float b = 0.0;
	for (int i = 0; i < 16; i++) {
		b += blobs[i].w * exp((dot(d, blobs[i].xyz) - 1.0) / bwid[i]);
	}
	return e * (1.0 + b);
}

float rad_at(vec3 d) {
	float th = acos(clamp(d.y, -1.0, 1.0));
	if (th <= th0) {
		return Rc;
	}
	float m = smoothstep(th0, th0 + 0.6, th);
	return Rc * (1.0 + (shape_raw(d) / pole - 1.0) * m);
}

float relief_m(vec3 d) {
	float off = 0.0;
	for (int i = 0; i < 10; i++) {
		if (gcd[i] > 0.0) {
			float t = acos(clamp(dot(d, gcr[i].xyz), -1.0, 1.0)) / gcr[i].w;
			if (t < 3.0) {
				float D = gcd[i];
				float bowl = t < 1.0 ? (t * t - 1.0) * D : 0.0;
				off += bowl + 0.24 * D * exp(-pow((t - 1.0) / 0.2, 2.0));
			}
		}
	}
	for (int i = 0; i < 4; i++) {
		if (cyd[i] > 0.0) {
			float sd = asin(clamp(dot(d, cyn[i].xyz), -1.0, 1.0));
			vec3 side = cross(cyn[i].xyz, cyc[i].xyz);
			sd += 0.35 * cyn[i].w * sin(dot(d, side) * 22.0 + float(i) * 1.7);
			float ma = smoothstep(cyc[i].w - 0.04, cyc[i].w + 0.04, dot(d, cyc[i].xyz));
			off -= cyd[i] * (1.0 - smoothstep(0.5 * cyn[i].w, cyn[i].w, abs(sd))) * ma;
		}
	}
	for (int i = 0; i < 3; i++) {
		off += sch[i] * smoothstep(-0.006, 0.006, dot(d, scp[i].xyz) - scp[i].w);
	}
	return off;
}

float relief_mask(vec2 q) {
	float mb = smoothstep(240.0, 330.0, length(q));
	float mc = max(smoothstep(110.0, 180.0, abs(q.x - 20.0)), max(smoothstep(580.0, 660.0, q.y), smoothstep(110.0, 40.0, q.y)));
	return mb * mc;
}

vec3 mapq(vec2 q, float lod) {
	float r = length(q);
	vec3 dir = vec3(0.0, 1.0, 0.0);
	if (r > 0.001) {
		float th = min(r / Rc, 3.14159);
		float s = sin(th);
		dir = vec3(s * q.x / r, cos(th), s * q.y / r);
	}
	return dir * (rad_at(dir) + relief_m(dir) * relief_mask(q) + H(q, lod) - sink) - vec3(0.0, Rc, 0.0);
}

void vertex() {
	// le plan est enroulé sur une sphère de rayon Rc (projection azimutale équidistante)
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 q = w.xz;
	float h = H(q, vlod);
	vec3 P = mapq(q, vlod);
	VERTEX = P;
	vnorm = vec3(0.0, 1.0, 0.0);
	mrel = relief_mask(q);
	{
		float e = 3.0;
		vec3 px = mapq(q + vec2(e, 0.0), vlod);
		vec3 pz = mapq(q + vec2(0.0, e), vlod);
		vnorm = normalize(cross(pz - P, px - P));
	}
	wp = vec3(q.x, h, q.y);
}

void fragment() {
	if (outer && max(abs(wp.x), abs(wp.z)) < hole) {
		discard;
	}
	float rr = length(wp.xz);
	if (rr > 3.13 * Rc) {
		discard;
	}
	float e = 2.0;
	float lod = outer ? 3.0 : 2.0;
	float hx = H(wp.xz + vec2(e, 0.0), lod) - H(wp.xz - vec2(e, 0.0), lod);
	float hz = H(wp.xz + vec2(0.0, e), lod) - H(wp.xz - vec2(0.0, e), lod);
	vec3 nf = normalize(vec3(-hx / (2.0 * e), 1.0, -hz / (2.0 * e)));
	vec3 n = nf;
	if (rr > 0.001) {
		float th = rr / Rc;
		vec2 er = wp.xz / rr;
		vec3 dir = vec3(sin(th) * er.x, cos(th), sin(th) * er.y);
		vec3 t1 = vec3(cos(th) * er.x, -sin(th), cos(th) * er.y);
		vec3 et = vec3(-er.y, 0.0, er.x);
		n = normalize(dot(nf.xz, er) * t1 + dot(nf.xz, vec2(-er.y, er.x)) * et + nf.y * dir);
	}
	if (false) {
		n = normalize(vnorm);
	} else if (mrel > 0.001) {
		n = normalize(mix(n, normalize(vnorm), mrel));
	}
	// pente forte (falaises, parois de canyon) : roche sombre à nu
	vec3 radial = vec3(0.0, 1.0, 0.0);
	if (rr > 0.001) {
		float thr = min(rr / Rc, 3.14159);
		radial = vec3(sin(thr) * wp.x / rr, cos(thr), sin(thr) * wp.z / rr);
	}
	// de loin : relief fin lissé (aplats propres, pas de grésillement)
	float fdn = smoothstep(500.0, 1800.0, -VERTEX.z);
	n = normalize(mix(n, normalize(vnorm), 0.9 + fdn * 0.1));
	float slope = 1.0 - dot(n, radial);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	NORMAL = normalize(mix(NORMAL, normalize((VIEW_MATRIX * vec4(normalize(vnorm), 0.0)).xyz), smoothstep(700.0, 2600.0, -VERTEX.z)));
	// style anime années 80 (Venus Wars) : sol ocre simple, deux tons seulement
	float a2 = texture(amap, wp.xz / (tile * big) + vec2(0.37, 0.11)).r;
	float fd = smoothstep(700.0, 2600.0, -VERTEX.z);
	// sable en grandes plaques nettes : orangé, clair, plus foncé (dunes)
	// style minimaliste : un abricot pastel uni, une seule nuance très douce
	vec3 ocre = vec3(0.42, 0.22, 0.11);
	vec3 clair = vec3(0.45, 0.25, 0.13);
	vec3 col = mix(ocre, clair, smoothstep(0.5, 0.56, a2 + 0.45) * 0.6);
	col = mix(col, ocre * 0.85, smoothstep(0.25, 0.5, slope));
	// chemins de sable clair : de la base vers le camp pirate, et autour de la base
	float zz = wp.z;
	float cx = 20.0 + 26.0 * sin(zz / 70.0) + 10.0 * sin(zz / 23.0);
	float onp = smoothstep(14.0, 10.0, abs(wp.x - cx)) * smoothstep(110.0, 140.0, zz) * smoothstep(700.0, 660.0, zz);
	float ring = smoothstep(9.0, 5.0, abs(length(wp.xz) - 128.0));
	col = mix(col, vec3(0.52, 0.34, 0.2), max(onp, ring) * 0.85);
	ALBEDO = col * tint;
	NORMAL_MAP = texture(detail_n, wp.xz / 3.0).rgb;
	NORMAL_MAP_DEPTH = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
}
