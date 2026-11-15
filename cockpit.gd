## Kuiper Dawn — poste de pilotage en 3D (d'après l'image de référence de l'utilisateur) :
## salle sombre aux baies informatiques, moniteurs inclinés en arc autour du siège, tenus par des bras mécaniques,
## câbles, bureau et claviers, accoudoirs-consoles avec boule de commande, boutons et petits écrans.
## Les écrans de jeu (bridge.gd) sont rendus dans des SubViewport affichés sur les moniteurs ;
## un clic sur un moniteur le déploie en plein écran, un clic sur un bouton d'accoudoir déclenche son action.
extends Node

var cv: SubViewport          # monde 3D du cockpit, rendu à la taille de la fenêtre
var root: Node3D
var cam: Camera3D
var screens := {}            # id -> {vp, node, w, h}
var buttons := {}            # id -> {node, size, mat, col, lit}
var leds: Array = []
var t := 0.0
var cam_base := Transform3D()
var sway := Vector2.ZERO
const CAM_POS := Vector3(0, 1.2, 0.18)

var M := {}


func mat(col: Color, metal := 0.4, rough := 0.6, emis := 0.0) -> StandardMaterial3D:
	var k := "%s_%.2f_%.2f_%.2f" % [col.to_html(), metal, rough, emis]
	if M.has(k):
		return M[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	if emis > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emis
	M[k] = m
	return m


func box(par: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	par.add_child(mi)
	return mi


func cyl(par: Node3D, r: float, h: float, pos: Vector3, m: Material, rot := Vector3.ZERO, seg := 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	mi.mesh = c
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	par.add_child(mi)
	return mi


func sph(par: Node3D, r: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	mi.mesh = s
	mi.material_override = m
	mi.position = pos
	par.add_child(mi)
	return mi


func strut(par: Node3D, a: Vector3, b: Vector3, r: float, m: Material, seg := 10) -> MeshInstance3D:
	var d := b - a
	var L := d.length()
	if L < 0.001:
		return null
	var mi := cyl(par, r, L, (a + b) * 0.5, m, Vector3.ZERO, seg)
	var y := d / L
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	mi.basis = Basis(x, y, x.cross(y) * -1.0).orthonormalized()
	return mi


# câble qui pend entre deux points (chaînette)
func cable(par: Node3D, a: Vector3, b: Vector3, sag: float, r: float, m: Material) -> void:
	var n := 10
	var prev := a
	for i in range(1, n + 1):
		var k := float(i) / n
		var p := a.lerp(b, k) - Vector3(0, sag * 4.0 * k * (1.0 - k), 0)
		strut(par, prev, p, r, m, 6)
		prev = p


func setup(window_size: Vector2i) -> void:
	cv = SubViewport.new()
	cv.own_world_3d = true
	cv.size = window_size
	cv.msaa_3d = Viewport.MSAA_2X
	cv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(cv)
	root = Node3D.new()
	cv.add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("020306")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.4, 0.55)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.12, 0.16)
	env.fog_density = 0.09
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	cam = Camera3D.new()
	cam.fov = 78.0
	cam.near = 0.03
	cam.far = 40.0
	root.add_child(cam)
	cam.look_at_from_position(CAM_POS, Vector3(0, 1.28, -1.6))
	cam_base = cam.transform
	cam.current = true
	build_room()
	build_monitors()
	build_desk()
	build_armrests()


# ---------------------------------------------------------------- salle : baies informatiques, plafond, câbles
func build_room() -> void:
	var dark := mat(Color("0b0d10"), 0.5, 0.7)
	var rack := mat(Color("15181c"), 0.6, 0.5)
	var floor := mat(Color("08090b"), 0.3, 0.9)
	box(root, Vector3(12, 0.05, 12), Vector3(0, -0.02, -2), floor)
	box(root, Vector3(12, 0.05, 12), Vector3(0, 3.2, -2), dark)
	# baies informatiques au fond et sur les côtés, constellées de voyants
	var led_mm := MultiMesh.new()
	led_mm.transform_format = MultiMesh.TRANSFORM_3D
	led_mm.use_colors = true
	var lb := BoxMesh.new()
	lb.size = Vector3(0.02, 0.012, 0.01)
	led_mm.mesh = lb
	var led_x: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 240
	var spots: Array = []
	for i in 9:
		spots.append([Vector3(-2.4 + i * 0.6, 1.25, -3.0), 0.0])
	for i in 6:
		spots.append([Vector3(-2.7, 1.25, -2.4 + i * 0.62), PI / 2])
		spots.append([Vector3(2.7, 1.25, -2.4 + i * 0.62), -PI / 2])
	for s in spots:
		var g := Node3D.new()
		g.position = s[0]
		g.rotation.y = s[1]
		root.add_child(g)
		box(g, Vector3(0.56, 2.5, 0.5), Vector3.ZERO, rack)
		for k in 12:
			box(g, Vector3(0.5, 0.012, 0.02), Vector3(0, -1.1 + k * 0.19, 0.25), dark)
			for j in 5:
				if rng.randf() < 0.6:
					var col: Color = [Color("40e0ff"), Color("ff3ad0"), Color("5ff0a0"), Color("ffb347")][rng.randi() % 4]
					led_x.append([g.transform * Transform3D(Basis(), Vector3(-0.2 + j * 0.05, -1.05 + k * 0.19, 0.26)), col])
	led_mm.instance_count = led_x.size()
	for i in led_x.size():
		led_mm.set_instance_transform(i, led_x[i][0])
		led_mm.set_instance_color(i, led_x[i][1])
	var lm := StandardMaterial3D.new()
	lm.vertex_color_use_as_albedo = true
	lm.emission_enabled = true
	lm.emission_energy_multiplier = 3.0
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var lmi := MultiMeshInstance3D.new()
	lmi.multimesh = led_mm
	lmi.material_override = lm
	root.add_child(lmi)
	leds.append(lmi)
	# câbles qui pendent du plafond
	var cab := mat(Color("0d0f12"), 0.2, 0.8)
	var cab2 := mat(Color("1d2a33"), 0.2, 0.8)
	for i in 26:
		var a := Vector3(rng.randf_range(-2.6, 2.6), 3.15, rng.randf_range(-2.8, -0.2))
		var b := Vector3(rng.randf_range(-2.6, 2.6), 3.15, rng.randf_range(-2.8, -0.2))
		cable(root, a, b, rng.randf_range(0.3, 1.0), rng.randf_range(0.008, 0.02), cab if i % 3 else cab2)
	# lumières : cyan au centre, magenta à droite, vert à gauche
	for l in [[Vector3(0, 1.5, -1.1), Color("40d8ff"), 1.6, 3.0], [Vector3(1.1, 1.6, -0.9), Color("ff3ad0"), 1.2, 2.6], [Vector3(-1.1, 1.6, -0.9), Color("3dffb0"), 1.0, 2.6], [Vector3(0, 2.9, -0.5), Color("8fb4ff"), 0.4, 4.0]]:
		var o := OmniLight3D.new()
		o.position = l[0]
		o.light_color = l[1]
		o.light_energy = l[2]
		o.omni_range = l[3]
		root.add_child(o)


# ---------------------------------------------------------------- moniteurs en arc autour du siège
# id, angle autour du siège (°), hauteur, distance, largeur, hauteur (m), pixels/m, couleur du halo
const MON := [
	["center", 0.0, 1.3, 1.3, 1.3, 0.8, 1000.0, Color("40d8ff")],
	["sys", 0.0, 2.02, 1.32, 0.72, 0.34, 900.0, Color("40d8ff")],
	["left", -46.0, 1.32, 1.5, 0.8, 0.8, 1000.0, Color("3dffb0")],
	["lefttop", -40.0, 2.0, 1.55, 0.74, 0.44, 1100.0, Color("3dffb0")],
	["energy", -64.0, 0.98, 1.12, 0.4, 0.26, 900.0, Color("40d8ff")],
	["right2", 46.0, 1.32, 1.5, 0.8, 0.8, 1000.0, Color("ff3ad0")],
	["right", 40.0, 2.02, 1.55, 0.62, 0.44, 1000.0, Color("ff3ad0")],
	["alert", 64.0, 0.98, 1.12, 0.4, 0.26, 900.0, Color("ff3ad0")],
]


func build_monitors() -> void:
	var bez := mat(Color("101215"), 0.6, 0.5)
	var arm := mat(Color("1a1d21"), 0.7, 0.45)
	var joint := mat(Color("262a30"), 0.7, 0.4)
	for d in MON:
		var a := deg_to_rad(d[1])
		var pos := Vector3(sin(a) * d[3], d[2], CAM_POS.z - cos(a) * d[3])
		var node := Node3D.new()
		root.add_child(node)
		var eye := CAM_POS + Vector3(0, 0.05, 0)
		node.look_at_from_position(pos, pos + (pos - eye))
		var w: float = d[4]
		var h: float = d[5]
		box(node, Vector3(w + 0.07, h + 0.07, 0.05), Vector3(0, 0, -0.03), bez)
		box(node, Vector3(w * 0.5, h * 0.5, 0.06), Vector3(0, 0, -0.08), bez)
		var vp := SubViewport.new()
		vp.size = Vector2i(int(w * d[6]), int(h * d[6]))
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.transparent_bg = false
		add_child(vp)
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(w, h)
		q.mesh = qm
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.albedo_texture = vp.get_texture()
		sm.disable_fog = true
		sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		q.material_override = sm
		q.position.z = 0.0
		node.add_child(q)
		# voyant et halo du moniteur
		sph(node, 0.008, Vector3(w * 0.5 - 0.02, -h * 0.5 - 0.022, 0.0), mat(Color("5ff0a0"), 0, 0.5, 4.0))
		var o := OmniLight3D.new()
		o.light_color = d[7]
		o.light_energy = 0.35 if d[2] > 1.1 else 0.08
		o.omni_range = 0.9
		o.position = Vector3(0, 0, 0.25)
		node.add_child(o)
		# bras mécanique : du plafond (moniteurs hauts) ou du bureau (moniteurs bas) jusqu'au dos du moniteur
		var back := node.global_transform * Vector3(0, 0, -0.1)
		var anchor := Vector3(pos.x * 1.25, 3.15, pos.z - 0.3) if d[2] > 1.6 else Vector3(pos.x * 1.2, 0.0 if d[2] < 1.1 else 3.15, pos.z - 0.35)
		var mid := back.lerp(anchor, 0.5) + Vector3(0, 0, -0.25)
		strut(root, back, mid, 0.03, arm)
		strut(root, mid, anchor, 0.035, arm)
		sph(root, 0.05, mid, joint)
		sph(root, 0.04, back, joint)
		cable(root, back + Vector3(0.03, 0, 0), anchor + Vector3(0.1, 0, 0), 0.12, 0.008, mat(Color("0d0f12"), 0.2, 0.8))
		screens[d[0]] = {"vp": vp, "node": node, "w": w, "h": h}


# ---------------------------------------------------------------- bureau et claviers
func build_desk() -> void:
	var top := mat(Color("121418"), 0.5, 0.55)
	var key := mat(Color("23262c"), 0.3, 0.6)
	box(root, Vector3(1.9, 0.05, 0.55), Vector3(0, 0.78, -0.85), top)
	box(root, Vector3(1.9, 0.75, 0.04), Vector3(0, 0.4, -1.1), mat(Color("0b0c0f"), 0.4, 0.7))
	for s: float in [-1.0, 1.0]:
		var kb := Node3D.new()
		kb.position = Vector3(s * 0.26, 0.81, -0.78)
		kb.rotation = Vector3(0.08, -s * 0.12, 0)
		root.add_child(kb)
		box(kb, Vector3(0.42, 0.02, 0.15), Vector3.ZERO, mat(Color("15171b"), 0.4, 0.6))
		for r in 4:
			for k in 13:
				box(kb, Vector3(0.026, 0.012, 0.026), Vector3(-0.19 + k * 0.0315, 0.014, -0.05 + r * 0.032), key)
	# souris, outils, petit boîtier lumineux
	sph(root, 0.025, Vector3(0.62, 0.81, -0.78), mat(Color("1b1d21"), 0.4, 0.4))
	box(root, Vector3(0.18, 0.01, 0.02), Vector3(-0.6, 0.81, -0.95), mat(Color("4a4f57"), 0.8, 0.3), Vector3(0, 0.4, 0))
	box(root, Vector3(0.12, 0.012, 0.015), Vector3(-0.5, 0.81, -0.88), mat(Color("4a4f57"), 0.8, 0.3), Vector3(0, -0.3, 0))
	box(root, Vector3(0.22, 0.08, 0.14), Vector3(0, 0.84, -0.98), mat(Color("1b1d21"), 0.5, 0.5))
	for k in 4:
		sph(root, 0.008, Vector3(-0.06 + k * 0.04, 0.885, -0.92), mat([Color("40e0ff"), Color("ff3ad0"), Color("5ff0a0"), Color("ffb347")][k], 0, 0.5, 3.0))


# ---------------------------------------------------------------- accoudoirs-consoles : boule de commande, boutons, petits écrans
func build_armrests() -> void:
	var pad := mat(Color("1d2024"), 0.6, 0.45)
	var cush := mat(Color("2a2420"), 0.1, 0.85)
	var jean := mat(Color("2c3640"), 0.0, 0.9)
	# jambes du pilote, assise
	for s: float in [-1.0, 1.0]:
		strut(root, Vector3(s * 0.13, 0.62, 0.22), Vector3(s * 0.16, 0.6, -0.32), 0.075, jean, 12)
		strut(root, Vector3(s * 0.16, 0.6, -0.32), Vector3(s * 0.17, 0.05, -0.42), 0.06, jean, 12)
	box(root, Vector3(0.6, 0.12, 0.5), Vector3(0, 0.5, 0.2), cush)
	for s: float in [-1.0, 1.0]:
		var g := Node3D.new()
		g.position = Vector3(s * 0.48, 0.66, -0.05)
		root.add_child(g)
		box(g, Vector3(0.16, 0.1, 0.62), Vector3.ZERO, cush)
		# bras mécanique latéral qui tient la console
		strut(root, Vector3(s * 0.75, 0.0, 0.3), Vector3(s * 0.62, 0.62, -0.1), 0.05, mat(Color("1a1d21"), 0.7, 0.45))
		# console à l'avant de l'accoudoir
		var c := Node3D.new()
		c.position = Vector3(0, 0.07, -0.42)
		c.rotation.x = 0.25
		g.add_child(c)
		box(c, Vector3(0.3, 0.06, 0.26), Vector3.ZERO, pad)
		box(c, Vector3(0.31, 0.01, 0.27), Vector3(0, 0.032, 0), mat(Color("2c3036"), 0.6, 0.4))
		# petit écran incliné sur le côté extérieur (messages à gauche, pilote automatique à droite)
		var sid := "log" if s < 0.0 else "bot"
		var sn := Node3D.new()
		sn.position = Vector3(s * 0.26, 0.12, -0.36)
		g.add_child(sn)
		sn.look_at(sn.global_position + (sn.global_position - (CAM_POS + Vector3(0, 0.05, 0))))
		box(sn, Vector3(0.27, 0.15, 0.03), Vector3(0, 0, -0.02), pad)
		var vp := SubViewport.new()
		vp.size = Vector2i(500, 270)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.24, 0.13)
		q.mesh = qm
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.albedo_texture = vp.get_texture()
		sm.disable_fog = true
		q.material_override = sm
		sn.add_child(q)
		screens[sid] = {"vp": vp, "node": sn, "w": 0.24, "h": 0.13}
		if s < 0.0:
			# boule de commande et boutons de vitesse
			var tb := sph(c, 0.045, Vector3(-0.07, 0.045, 0.04), mat(Color("4a5260"), 0.5, 0.25))
			tb.scale = Vector3(1, 0.8, 1)
			cyl(c, 0.058, 0.02, Vector3(-0.07, 0.03, 0.04), mat(Color("15181c"), 0.6, 0.4), Vector3.ZERO, 24)
			var ids := ["pause", "x1", "x2", "x4", "x8"]
			var labels := ["II", "×1", "×2", "×4", "×8"]
			for k in 5:
				add_button(c, ids[k], labels[k], Vector3(0.025 + (k % 3) * 0.042, 0.04, -0.05 + (k / 3) * 0.045), Vector3(0.034, 0.016, 0.034), Color("ff3ad0"))
			add_button(c, "tab", "3D", Vector3(0.11, 0.04, 0.04), Vector3(0.034, 0.016, 0.034), Color("40e0ff"))
		else:
			add_button(c, "bot", "PILOTE AUTO", Vector3(0.0, 0.042, -0.04), Vector3(0.2, 0.02, 0.07), Color("ffb347"))
			for k in 6:
				add_button(c, "deco%d" % k, "", Vector3(-0.1 + k * 0.04, 0.038, 0.06), Vector3(0.026, 0.012, 0.026), [Color("40e0ff"), Color("ff3ad0"), Color("5ff0a0")][k % 3])


func add_button(par: Node3D, id: String, text: String, pos: Vector3, size: Vector3, col: Color) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = col.darkened(0.6)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.4
	var b := box(par, size, pos, m)
	if text != "":
		var l := Label3D.new()
		l.text = text
		l.font_size = 48
		l.pixel_size = 0.00042
		l.modulate = Color(1, 1, 1, 0.95)
		l.outline_size = 0
		l.rotation.x = -PI / 2
		l.position = Vector3(0, size.y * 0.5 + 0.002, 0)
		b.add_child(l)
	buttons[id] = {"node": b, "size": size, "mat": m, "lit": false}


func set_lit(id: String, on: bool) -> void:
	if not buttons.has(id):
		return
	var b: Dictionary = buttons[id]
	b.lit = on
	(b.mat as StandardMaterial3D).emission_energy_multiplier = 2.6 if on else 0.4


# ---------------------------------------------------------------- interaction
func resize(s: Vector2i) -> void:
	cv.size = s


# rayon de la caméra du cockpit ; renvoie {kind: "screen"/"button", id} ou {}
func pick(p: Vector2) -> Dictionary:
	var o := cam.project_ray_origin(p)
	var d := cam.project_ray_normal(p)
	var best := {}
	var bt := INF
	for id in screens:
		var s: Dictionary = screens[id]
		var inv: Transform3D = (s.node as Node3D).global_transform.affine_inverse()
		var lo := inv * o
		var ld := inv.basis * d
		if absf(ld.z) < 1e-5:
			continue
		var k := -lo.z / ld.z
		if k <= 0.0 or k >= bt:
			continue
		var hp := lo + ld * k
		if absf(hp.x) <= s.w * 0.5 and absf(hp.y) <= s.h * 0.5:
			bt = k
			best = {"kind": "screen", "id": id}
	for id in buttons:
		var b: Dictionary = buttons[id]
		var inv: Transform3D = (b.node as Node3D).global_transform.affine_inverse()
		var lo := inv * o
		var ld := (inv.basis * d)
		var hs: Vector3 = b.size * 0.5 + Vector3(0.004, 0.01, 0.004)
		var t0 := -INF
		var t1 := INF
		var ok := true
		for ax in 3:
			if absf(ld[ax]) < 1e-7:
				if absf(lo[ax]) > hs[ax]:
					ok = false
				continue
			var a1 := (-hs[ax] - lo[ax]) / ld[ax]
			var a2 := (hs[ax] - lo[ax]) / ld[ax]
			t0 = maxf(t0, minf(a1, a2))
			t1 = minf(t1, maxf(a1, a2))
		if ok and t1 >= t0 and t0 > 0.0 and t0 < bt:
			bt = t0
			best = {"kind": "button", "id": id}
	return best


# rectangle à l'écran (pixels de la fenêtre) occupé par un moniteur
func project_rect(id: String) -> Rect2:
	var s: Dictionary = screens[id]
	var n: Node3D = s.node
	var r := Rect2()
	var first := true
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var p := cam.unproject_position(n.global_transform * Vector3(c.x * s.w * 0.5, c.y * s.h * 0.5, 0))
		if first:
			r = Rect2(p, Vector2.ZERO)
			first = false
		else:
			r = r.expand(p)
	return r


func update(dt: float, mouse: Vector2, wsize: Vector2) -> void:
	t += dt
	# léger balancement de la tête qui suit la souris
	if wsize.x < 10.0 or wsize.y < 10.0:
		return
	var m := ((mouse / wsize - Vector2(0.5, 0.5)) * 2.0).clamp(Vector2(-1, -1), Vector2(1, 1))
	sway = sway.lerp(m, minf(1.0, dt * 3.0))
	cam.transform = cam_base * Transform3D(Basis(Vector3.UP, -sway.x * 0.05) * Basis(Vector3.RIGHT, -sway.y * 0.03), Vector3.ZERO)
	for k in 6:
		var id := "deco%d" % k
		if buttons.has(id):
			(buttons[id].mat as StandardMaterial3D).emission_energy_multiplier = 0.4 + 1.6 * (0.5 + 0.5 * sin(t * (1.3 + k * 0.7) + k))


