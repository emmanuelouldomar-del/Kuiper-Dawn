extends SceneTree
# Netteté : agrandissement Lanczos x4, puis filtre de Kuwahara (zones aplaties, contours francs), puis masque flou léger.
var vp1: SubViewport
var vp2: SubViewport
var out_path := ""
var frames := 0

const KUWA := """
shader_type canvas_item;
uniform sampler2D src : filter_linear;
uniform int R = 3;
void fragment() {
	vec2 px = 1.0 / vec2(textureSize(src, 0));
	vec3 m[4]; vec3 s[4];
	for (int q = 0; q < 4; q++) { m[q] = vec3(0.0); s[q] = vec3(0.0); }
	ivec2 o[4] = ivec2[](ivec2(-1,-1), ivec2(1,-1), ivec2(-1,1), ivec2(1,1));
	float n = float((R + 1) * (R + 1));
	for (int q = 0; q < 4; q++) {
		for (int j = 0; j <= R; j++) for (int i = 0; i <= R; i++) {
			vec3 c = texture(src, UV + vec2(float(i * o[q].x), float(j * o[q].y)) * px).rgb;
			m[q] += c; s[q] += c * c;
		}
	}
	float best = 1e9; vec3 res = vec3(0.0);
	for (int q = 0; q < 4; q++) {
		vec3 mu = m[q] / n;
		vec3 v = abs(s[q] / n - mu * mu);
		float sv = v.r + v.g + v.b;
		if (sv < best) { best = sv; res = mu; }
	}
	COLOR = vec4(res, 1.0);
}
"""
const USM := """
shader_type canvas_item;
uniform sampler2D src : filter_linear;
uniform float amt = 0.6;
void fragment() {
	vec2 px = 1.0 / vec2(textureSize(src, 0));
	vec3 c = texture(src, UV).rgb;
	vec3 b = vec3(0.0); float w = 0.0;
	for (int j = -3; j <= 3; j++) for (int i = -3; i <= 3; i++) {
		float g = exp(-float(i * i + j * j) / 4.5);
		b += texture(src, UV + vec2(float(i), float(j)) * px).rgb * g; w += g;
	}
	b /= w;
	COLOR = vec4(clamp(c + (c - b) * amt, 0.0, 1.0), 1.0);
}
"""

func make_pass(tex: Texture2D, size: Vector2i, code: String, params := {}) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.size = Vector2(size)
	var sh := Shader.new()
	sh.code = code
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("src", tex)
	for k in params:
		mat.set_shader_parameter(k, params[k])
	tr.material = mat
	vp.add_child(tr)
	return vp

func _init():
	var a := OS.get_cmdline_user_args()
	var im := Image.load_from_file(a[0])
	im.convert(Image.FORMAT_RGB8)
	var k := int(a[2])
	im.resize(im.get_width() * k, im.get_height() * k, Image.INTERPOLATE_LANCZOS)
	out_path = a[1]
	var t0 := ImageTexture.create_from_image(im)
	vp1 = make_pass(t0, im.get_size(), KUWA, {"R": int(a[3])})
	vp2 = make_pass(vp1.get_texture(), im.get_size(), USM, {"amt": float(a[4])})

func _process(_d):
	frames += 1
	if frames == 5:
		var img := vp2.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.save_png(out_path)
		print("OK ", img.get_size())
		quit()
	return false
