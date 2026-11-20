## Kuiper Dawn — passerelle de commandement (portée du remake « K-240 Remake ») :
## la partie se joue sur plusieurs écrans. À gauche, la gestion (colonie, construction, recherche) ;
## au centre, la vue principale 3D ; à droite, le radar tactique et les contacts ; en bas, la console.
## Tab : bascule vers la vue 3D plein écran et retour.
extends Control

var w  # main.gd
var C  # colony.gd

const CY := Color("5fd4ff")
const DIM := Color("7398b8")
const TXT := Color("d3eaff")
const OK := Color("5ff0a0")
const BAD := Color("ff5a5a")
const AMB := Color("ffb347")

var left: Panel
var center: Panel
var right: Panel
var head_lbl: Label
var tabs: TabContainer
var res_rows := {}
var lbl_energy: Label
var lbl_pop: Label
var bar_morale: ProgressBar
var lbl_morale: Label
var lbl_pol: Label
var lbl_tax: Label
var lbl_shield: Label
var sl_tax: HSlider
var bld_btn := {}
var lbl_sites: Label
var tech_btn := {}
var lbl_tech: Label
var radar: Control
var lbl_contacts: Label
var lbl_units: Label
var lbl_log: Label
var view_name := ""
var S  # strategy.gd
var rtree: Control
var rt_pos := {}
const NW := 136.0
const NH := 54.0
var unit_btn := {}
var lbl_queue: Label
var lbl_hangar: Label
var fleet_box: VBoxContainer
var fleet_sig := ""
var sat_btn: Button
var lbl_intel: Label
var lbl_combat: Label
var lbl_alert: Label
var lbl_bot: Label
var map: Control
var map_sel := ""
var end_shown := false
# poste de pilotage : décor, moniteurs, écran agrandi
var mons: Array = []          # moniteurs 2D (cadre, écran, bouton marche/arrêt)
var hw := {}                 # boutons physiques de la console
var console: Control
var room: Control
var room_vp: SubViewport
var room_view: TextureRect
var hint: Label
var th_ui: Theme
var deco := {}
var right2: Panel
var diplo: Panel
var Fx  # factions.gd
var Sv  # survival.gd
var lbl_surv: Label
var bar_health: ProgressBar
var lbl_earth: Label
var ship_btn: Button
var ark_btn: Button
var lbl_ark: Label
var sab_btn: Button
var diplo_box: VBoxContainer
var diplo_sig := ""
var market_open := ""
var sup_box: VBoxContainer
var sup_sig := ""
var ops_box: VBoxContainer
var ops_sig := ""
var lbl_diplo_log: Label
var tabs2: TabContainer
var dim: ColorRect
var focused: Control = null
var fz_t := 0.0
var fz_dir := 0.0
var build_side: ScrollContainer
const SIDE_W := 250.0
var sweep := 0.0
var t_ui := 0.0


func setup(world, colony) -> void:
	w = world
	C = colony
	S = world.strategy
	Fx = world.factions
	Sv = world.survival
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	th_ui = make_theme()
	# taille explicite : sous un CanvasLayer, les ancres ne suffisent pas
	position = Vector2.ZERO
	size = Vector2(get_viewport().size)
	get_viewport().size_changed.connect(func(): size = Vector2(get_viewport().size))
	theme = th_ui
	load_art()
	# fond : salle de commandement en 2D (murs de métal, rivets, bandeau de titre, console du bas)
	# fond en pixel art : dessiné dans un SubViewport à 1/PXR de la résolution, affiché en pixels nets
	room_vp = SubViewport.new()
	room_vp.transparent_bg = false
	room_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	room_vp.canvas_transform = Transform2D().scaled(Vector2.ONE / PXR)
	add_child(room_vp)
	room = Control.new()
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room.draw.connect(draw_room)
	room_vp.add_child(room)
	room_view = TextureRect.new()
	room_view.texture = room_vp.get_texture()
	room_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	room_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	room_view.stretch_mode = TextureRect.STRETCH_SCALE
	room_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	room_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(room_view)
	# écrans de jeu, chacun dans un moniteur à cadre (bouton marche/arrêt, voyant, molettes)
	left = screen_panel()
	center = screen_panel(true)
	right = screen_panel()
	right2 = screen_panel()
	diplo = screen_panel()
	for d in [[left, "left", "GESTION"], [center, "center", "VUE PRINCIPALE"], [right, "right", "RADAR"], [right2, "right2", "SPATIAL"], [diplo, "diplo", "DIPLOMATIE"]]:
		add_monitor(d[1], d[2], d[0], false)
	build_left()
	build_center()
	build_right()
	build_right2()
	build_diplo()
	build_ops()
	build_survival()
	# survie : l’onglet Survie (phase, objectifs, jauges) passe en premier
	var st := tabs.get_node_or_null("Survie")
	if st != null:
		tabs.move_child(st, 0)
		tabs.current_tab = 0
	build_small_screens()
	for m in mons:
		var p: Control = m.content
		var ov := Control.new()
		ov.set_anchors_preset(Control.PRESET_FULL_RECT)
		ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ov.draw.connect(func(): draw_corners(ov))
		p.add_child(ov)
	build_console()
	# écran agrandi : fond assombri sous le moniteur agrandi (le cadre du moniteur reste visible)
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			unfocus())
	add_child(dim)
	hint = lbl("Cliquez sur un moniteur pour l’agrandir · bouton ⏻ : marche / arrêt de l’écran", Color(0.6, 0.85, 1.0, 0.8), 13)
	add_child(hint)
	resized.connect(do_layout)
	do_layout()
	refresh()


# ---------------------------------------------------------------- moniteurs 2D
const BZ_SIDE := 14.0
const BZ_TOP := 14.0
const BZ_BOT := 30.0

const SCAN := preload("res://shaders/scan.gdshader")


# moniteur : cadre (Panel) + écran (contenu) ; les petits écrans ont un contenu de taille fixe mis à l'échelle
func add_monitor(id: String, title: String, content: Control, small: bool) -> Dictionary:
	var mon := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0) if art_tex != null else Color("4c4f57")
	sb.border_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(2)
	sb.border_width_top = 3
	sb.set_corner_radius_all(0)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 0 if art_tex != null else 10
	sb.shadow_offset = Vector2(0, 4)
	mon.add_theme_stylebox_override("panel", sb)
	mon.mouse_filter = Control.MOUSE_FILTER_STOP
	var vp: SubViewport = null
	var wp: Control = null
	if art_tex != null:
		# sur l'illustration : le moniteur est rendu dans sa propre texture, puis plaqué en perspective
		# sur le quadrilatère du moniteur de l'image (draw_warp) ; il ne redevient un Control à plat qu'une fois agrandi
		vp = SubViewport.new()
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.gui_disable_input = true
		add_child(vp)
		mon.theme = th_ui
		vp.add_child(mon)
		wp = Control.new()
		wp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wp.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(wp)
	else:
		add_child(mon)
	var holder := Control.new()
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	mon.add_child(holder)
	if content.get_parent() != null:
		content.reparent(holder, false)
	else:
		holder.add_child(content)
	# verre cathodique : lueur verte phosphore et lignes de balayage par-dessus le contenu
	content.modulate = Color(0.85, 1.0, 0.88)
	var scan := ColorRect.new()
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scm := ShaderMaterial.new()
	scm.shader = SCAN
	scan.material = scm
	holder.add_child(scan)
	# écran éteint
	var off := ColorRect.new()
	off.color = Color("05070a")
	off.visible = false
	off.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(off)
	var m := {"id": id, "title": title, "mon": mon, "holder": holder, "content": content, "off": off, "scan": scan, "small": small, "home": Rect2(), "on": true}
	mon.draw.connect(func(): draw_bezel(m))
	if vp != null:
		m.vp = vp
		m.warp = wp
		m.quad = PackedVector2Array()
		wp.draw.connect(func(): draw_warp(m))
	# bouton marche / arrêt
	var pw := Button.new()
	pw.text = "⏻"
	pw.focus_mode = Control.FOCUS_NONE
	pw.tooltip_text = "Marche / arrêt de l’écran"
	pw.add_theme_font_size_override("font_size", 13)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color("2a2f38")
	ps.border_color = Color("5a6270")
	ps.set_border_width_all(1)
	ps.set_corner_radius_all(9)
	pw.add_theme_stylebox_override("normal", ps)
	var ph: StyleBoxFlat = ps.duplicate()
	ph.bg_color = Color("3a4250")
	pw.add_theme_stylebox_override("hover", ph)
	pw.add_theme_stylebox_override("pressed", ph)
	pw.pressed.connect(func(): toggle_power(m))
	mon.add_child(pw)
	m.pw = pw
	# bouton réduire (visible en plein écran)
	var rd := Button.new()
	rd.text = "✕ RÉDUIRE (Échap)"
	rd.focus_mode = Control.FOCUS_NONE
	rd.add_theme_font_size_override("font_size", 11)
	var rs: StyleBoxFlat = ps.duplicate()
	rs.bg_color = Color("3a1a1a")
	rs.border_color = Color("ff6b5f")
	rd.add_theme_stylebox_override("normal", rs)
	rd.add_theme_stylebox_override("hover", rs)
	rd.add_theme_color_override("font_color", Color("ffd6d2"))
	rd.pressed.connect(unfocus)
	rd.visible = false
	mon.add_child(rd)
	m.rd = rd
	# clic sur un écran latéral : l'agrandir (l'écran principal se pilote directement, il s'agrandit avec ⛶)
	if id != "center" or art_tex != null:
		var c := Control.new()
		c.mouse_filter = Control.MOUSE_FILTER_STOP
		c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		c.tooltip_text = "Cliquer pour agrandir l’écran"
		c.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				focus_screen(m))
		holder.add_child(c)
		m.catcher = c
	mons.append(m)
	return m


func mon_of(p: Control) -> Dictionary:
	for m in mons:
		if m.content == p:
			return m
	return {}


func toggle_power(m: Dictionary) -> void:
	m.on = not m.on
	m.off.visible = not m.on
	m.content.visible = m.on
	if m.id == "center" and w != null:
		w.layout_screen()
	m.mon.queue_redraw()


# cadre : marque, voyant, molettes, grilles d'aération
func draw_bezel(m: Dictionary) -> void:
	var mon: Panel = m.mon
	var s := mon.size
	var f := get_theme_default_font()
	if m.get("bare", false):
		return
	# coque en relief : biseau éclairé en haut et à gauche, ombré en bas et à droite
	mon.draw_rect(Rect2(0, 0, s.x, s.y), Color("4c4f57"))
	mon.draw_rect(Rect2(0, 0, s.x, 3), Color("8a8e96"))
	mon.draw_rect(Rect2(0, 0, 3, s.y), Color("74787f"))
	mon.draw_rect(Rect2(0, s.y - 4, s.x, 4), Color("2a2c31"))
	mon.draw_rect(Rect2(s.x - 4, 0, 4, s.y), Color("33363c"))
	# bordure creusée autour de l'écran
	var scr := Rect2(BZ_SIDE, BZ_TOP, s.x - BZ_SIDE * 2, s.y - BZ_TOP - BZ_BOT)
	var rim := scr.grow(5)
	mon.draw_rect(rim, Color("1c1d22"))
	mon.draw_rect(Rect2(rim.position, Vector2(rim.size.x, 3)), Color("101115"))
	mon.draw_rect(Rect2(rim.position.x, rim.end.y - 2, rim.size.x, 2), Color("5c6068"))
	# halo vert de l'écran allumé
	if m.on:
		for k in 3:
			mon.draw_rect(scr.grow(6 + k * 3), Color(0.25, 1.0, 0.5, 0.035), false, 3.0)
	var y := s.y - BZ_BOT * 0.5
	# voyant marche / arrêt (avec halo)
	var led := Vector2(s.x - 50, y)
	mon.draw_circle(led, 6.0, Color(0.4, 1.0, 0.6, 0.18) if m.on else Color(1.0, 0.3, 0.3, 0.18))
	mon.draw_circle(led, 3.5, OK if m.on else BAD)
	if s.x < 240.0:
		return
	# plaque de marque
	var pl := Rect2(12, y - 7, 120, 14)
	mon.draw_rect(pl, Color("3a3d44"))
	mon.draw_rect(Rect2(pl.position.x, pl.end.y - 1, pl.size.x, 1), Color("6a6e76"))
	mon.draw_string(f, Vector2(18, y + 4), "K-240 · " + m.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("aab2be"))
	# molettes en relief
	for k in 2:
		var c := Vector2(s.x - 86 - k * 18, y)
		mon.draw_circle(c, 6.5, Color("26282d"))
		mon.draw_circle(c + Vector2(-0.5, -0.5), 5.5, Color("5a5e66"))
		mon.draw_line(c, c + Vector2(0, -5).rotated(0.6 + k * 1.3), Color("d0d6de"), 1.5)
	# grille d'aération
	var vx := s.x * 0.5 - 30
	for k in 6:
		mon.draw_rect(Rect2(vx + k * 10, y - 5, 4, 10), Color("1e2025"))
		mon.draw_rect(Rect2(vx + k * 10, y + 4, 4, 1), Color("6a6e76"))
	if not m.on:
		mon.draw_line(scr.position + Vector2(scr.size.x * 0.1, scr.size.y * 0.2), scr.position + Vector2(scr.size.x * 0.35, scr.size.y * 0.05), Color(1, 1, 1, 0.06), 6.0)


# place un moniteur dans un rectangle de l'écran
func place_mon(m: Dictionary, r: Rect2) -> void:
	var mon: Panel = m.mon
	mon.position = r.position
	mon.size = r.size
	# sur l'illustration : écran posé dans le moniteur de l'image, sans cadre ajouté (le cadre n'apparaît qu'en plein écran)
	var bare: bool = art_tex != null and focused != m.content
	m.bare = bare
	var inner := Rect2(Vector2.ZERO, r.size) if bare else Rect2(BZ_SIDE, BZ_TOP, r.size.x - BZ_SIDE * 2, r.size.y - BZ_TOP - BZ_BOT)
	var h: Control = m.holder
	h.position = inner.position
	h.size = inner.size
	var c: Control = m.content
	# taille de mise en page : celle du plein écran sur l'illustration (contenu réduit pour tenir dans le moniteur), sinon le moniteur
	var design: Vector2 = inner.size
	if art_tex != null:
		var V := size if size.x > 10 else Vector2(get_viewport().size)
		design = Vector2(V.x * 0.94 - BZ_SIDE * 2, V.y * 0.92 - BZ_TOP - BZ_BOT)
	# écran d'état : à sa place, rendu en HOME_W de large (texte lisible dans un petit moniteur) ;
	# en s'agrandissant, il passe progressivement à 1:1, avec les mêmes tailles de texte que les grands écrans
	if m.small:
		var t := ease(fz_t, -2.2) if focused == m.content else 0.0
		design *= lerpf(HOME_W / design.x, 1.0, t)
	if not design.is_equal_approx(inner.size):
		var k := minf(inner.size.x / design.x, inner.size.y / design.y)
		c.size = design
		c.scale = Vector2(k, k)
		c.position = (inner.size - design * k) * 0.5
	else:
		c.scale = Vector2.ONE
		c.position = Vector2.ZERO
		c.size = inner.size
	m.scan.position = Vector2.ZERO
	m.scan.size = inner.size
	m.off.position = Vector2.ZERO
	m.off.size = inner.size
	if m.has("catcher"):
		m.catcher.position = Vector2.ZERO
		m.catcher.size = inner.size
	m.pw.visible = not bare
	m.pw.position = Vector2(r.size.x - 38, r.size.y - BZ_BOT * 0.5 - 10)
	m.pw.size = Vector2(26, 20)
	m.rd.position = Vector2(r.size.x - 270, r.size.y - BZ_BOT * 0.5 - 10)
	m.rd.size = Vector2(150, 20)
	mon.queue_redraw()


# ---------------------------------------------------------------- disposition
func home_rects(V: Vector2) -> Dictionary:
	# les moniteurs sont encastrés dans le cockpit : verrière au-dessus, piliers sur les côtés, pupitre en bas
	var top := 66.0
	var bot := 172.0
	var gx := 26.0
	var W := V.x - gx * 2.0
	var H := V.y - top - bot
	var g := 10.0
	var lw := W * 0.25
	var cw := W * 0.48
	var rx := gx + lw + cw
	var rw := W - lw - cw
	var r := {}
	r.left = Rect2(gx, top, lw - g * 0.5, H * 0.6 - g * 0.5)
	r.diplo = Rect2(gx, top + H * 0.6 + g * 0.5, lw - g * 0.5, H * 0.4 - g * 0.5)
	r.center = Rect2(gx + lw + g * 0.5, top, cw - g, H * 0.74 - g * 0.5)
	var sy := top + H * 0.74 + g * 0.5
	var sh := H * 0.26 - g * 0.5
	var ids := ["sys", "energy", "alert", "log", "bot"]
	var sw := (cw - g) / ids.size()
	for i in ids.size():
		r[ids[i]] = Rect2(gx + lw + g * 0.5 + i * sw + (g * 0.25 if i > 0 else 0.0), sy, sw - g * 0.5, sh)
	r.right = Rect2(rx + g * 0.5, top, rw - g * 0.5, H * 0.45 - g * 0.5)
	r.right2 = Rect2(rx + g * 0.5, top + H * 0.45 + g * 0.5, rw - g * 0.5, H * 0.55 - g * 0.5)
	r.console = Rect2(16, V.y - 112, V.x - 32, 96)
	# illustration fournie (art/cockpit.png) : positions des écrans lues dans art/cockpit.json (fractions de l'image)
	if art_tex != null:
		var ir := art_rect(V)
		for id in art_map:
			var a: Array = art_map[id]
			if a.size() > 0 and a[0] is Array:
				var q := art_quad(id, V)
				var bb := Rect2(q[0], Vector2.ZERO)
				for p in q:
					bb = bb.expand(p)
				r[id] = bb
			else:
				r[id] = Rect2(ir.position + Vector2(a[0], a[1]) * ir.size, Vector2(a[2], a[3]) * ir.size)
	return r


# quadrilatère d'un moniteur de l'illustration (coins haut-gauche, haut-droit, bas-droit, bas-gauche), en pixels de la fenêtre
func art_quad(id: String, V: Vector2) -> PackedVector2Array:
	var ir := art_rect(V)
	var out := PackedVector2Array()
	var a: Array = art_map.get(id, [])
	if a.size() == 4 and a[0] is Array:
		for c in a:
			out.append(ir.position + Vector2(c[0], c[1]) * ir.size)
	else:
		var rr: Rect2 = Rect2(ir.position + Vector2(a[0], a[1]) * ir.size, Vector2(a[2], a[3]) * ir.size) if a.size() == 4 else Rect2()
		out = PackedVector2Array([rr.position, Vector2(rr.end.x, rr.position.y), rr.end, Vector2(rr.position.x, rr.end.y)])
	return out


# passage d'un moniteur entre la texture plaquée en perspective et le Control à plat (écran agrandi, interactif)
func set_flat(m: Dictionary, flat: bool) -> void:
	var mon: Panel = m.mon
	if flat and mon.get_parent() != self:
		mon.reparent(self, false)
		move_child(mon, -1)
		m.warp.visible = false
	elif not flat and mon.get_parent() != m.vp:
		mon.reparent(m.vp, false)
		m.warp.visible = true


# projection du carré unité sur un quadrilatère (homographie), pour une vraie perspective
func homography(q: PackedVector2Array) -> Array:
	var d1 := q[1] - q[2]
	var d2 := q[3] - q[2]
	var sg := q[0] - q[1] + q[2] - q[3]
	var den := d1.x * d2.y - d2.x * d1.y
	var g := 0.0
	var h := 0.0
	if absf(den) > 1e-6:
		g = (sg.x * d2.y - d2.x * sg.y) / den
		h = (d1.x * sg.y - sg.x * d1.y) / den
	var a := q[1] - q[0] + q[1] * g
	var b := q[3] - q[0] + q[3] * h
	return [a, b, q[0], g, h]


func hmap(H: Array, u: float, v: float) -> Vector2:
	return (H[0] * u + H[1] * v + H[2]) / (H[3] * u + H[4] * v + 1.0)


# l'écran rendu dans sa texture, plaqué sur le quadrilatère par une grille de petites mailles
func draw_warp(m: Dictionary) -> void:
	var q: PackedVector2Array = m.quad
	if q.size() != 4:
		return
	var tex: Texture2D = m.vp.get_texture()
	var H := homography(q)
	var N := 12
	var holo: bool = m.id in ["left", "diplo", "right", "right2", "kron"]
	var col := PackedColorArray([Color(1, 1, 1, 0.9 if holo and focused != m.content else 1.0)])
	for j in N:
		for i in N:
			var u0 := float(i) / N
			var u1 := float(i + 1) / N
			var v0 := float(j) / N
			var v1 := float(j + 1) / N
			var pts := PackedVector2Array([hmap(H, u0, v0), hmap(H, u1, v0), hmap(H, u1, v1), hmap(H, u0, v1)])
			var uvs := PackedVector2Array([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)])
			m.warp.draw_polygon(pts, col, uvs, tex)


func do_layout() -> void:
	var V := size
	if V.x < 10:
		V = Vector2(get_viewport().size)
	var R := home_rects(V)
	var pxr := 1.0 if art_tex != null else PXR
	room_vp.size = Vector2i(maxi(1, int(V.x / pxr)), maxi(1, int(V.y / pxr)))
	room_vp.canvas_transform = Transform2D().scaled(Vector2.ONE / pxr)
	room_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if art_tex != null else CanvasItem.TEXTURE_FILTER_NEAREST
	room.size = V
	var full := Rect2(V.x * 0.03, V.y * 0.04, V.x * 0.94, V.y * 0.92)
	for m in mons:
		var r: Rect2 = R[m.id]
		m.home = r
		if m.has("vp"):
			# illustration : moniteur plaqué en perspective ; agrandi, les coins glissent vers le plein écran
			var t := ease(fz_t, -2.2) if focused == m.content else 0.0
			var flat: bool = focused == m.content and fz_t >= 1.0
			set_flat(m, flat)
			if flat:
				place_mon(m, full)
				continue
			var q0 := art_quad(m.id, V)
			var fq := PackedVector2Array([full.position, Vector2(full.end.x, full.position.y), full.end, Vector2(full.position.x, full.end.y)])
			var q := PackedVector2Array()
			var bb := Rect2(q0[0].lerp(fq[0], t), Vector2.ZERO)
			for i in 4:
				q.append(q0[i].lerp(fq[i], t))
				bb = bb.expand(q[i])
			# texture juste assez grande pour le quadrilatère (texte net, pas de scintillement)
			var k := clampf(maxf(bb.size.x / full.size.x, bb.size.y / full.size.y) * 1.6, 0.12, 1.0)
			m.vp.size = Vector2i(maxi(8, int(full.size.x * k)), maxi(8, int(full.size.y * k)))
			m.vp.canvas_transform = Transform2D().scaled(Vector2(k, k))
			place_mon(m, Rect2(Vector2.ZERO, full.size))
			m.quad = q
			m.warp.queue_redraw()
			continue
		if focused == m.content:
			var t := ease(fz_t, -2.2)
			r = Rect2(r.position.lerp(full.position, t), r.size.lerp(full.size, t))
		place_mon(m, r)
	if console != null:
		console.position = R.console.position
		console.size = R.console.size
		if art_tex != null and hw.has("tab3d"):
			# console étroite sur l'illustration : vue 3D et pilote auto sur une seconde rangée
			var hb2: Control = console.get_child(0)
			hb2.position = Vector2(8, 4)
			for id in ["tab3d", "bot"]:
				var b: Button = hw[id]
				b.anchor_left = 0.0
				b.anchor_right = 0.0
				b.offset_top = 52
				b.offset_bottom = 92
			(hw["tab3d"] as Button).offset_left = 8
			(hw["tab3d"] as Button).offset_right = 148
			(hw["bot"] as Button).offset_left = 156
			(hw["bot"] as Button).offset_right = 346
	if hint != null:
		hint.position = Vector2(V.x * 0.3, V.y - 168.0)
		hint.visible = art_tex == null
	if map != null:
		map.position = Vector2(6, 34)
		map.size = center.size - Vector2(12, 34 + 40)
	if build_side != null:
		build_side.position = Vector2(6, 34)
		build_side.size = Vector2(SIDE_W, center.size.y - 34 - 40)
	room.queue_redraw()
	if w != null:
		w.layout_screen()


# zone de la vue 3D dans l'écran principal (repère de l'écran) : à droite du panneau Construire
func screen_rect_local() -> Rect2:
	var off := SIDE_W + 6.0 if build_side != null and build_side.visible else 0.0
	return Rect2(Vector2(6 + off, 34), center.size - Vector2(12 + off, 34 + 40))


# zone de la vue 3D à l'écran : la caméra se pilote directement dans l'écran principal (sauf si un autre écran est agrandi)
func screen_rect() -> Rect2:
	if focused != null and focused != center:
		return Rect2()
	# sur l'illustration, l'écran principal est petit : la caméra ne se pilote qu'une fois l'écran agrandi
	if art_tex != null and (focused != center or fz_t < 1.0):
		return Rect2()
	var m := mon_of(center)
	if not m.is_empty() and not m.on:
		return Rect2()
	var r := screen_rect_local()
	var xf := center.get_global_transform()
	return Rect2(xf * r.position, r.size * xf.get_scale())


# ---------------------------------------------------------------- console du bas : boutons physiques
func hw_btn(t: String, cb: Callable, col := Color("3a4250")) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	var n := StyleBoxFlat.new()
	n.bg_color = col
	n.border_color = col.lightened(0.25)
	n.set_border_width_all(1)
	n.border_width_top = 2
	n.set_corner_radius_all(6)
	n.shadow_color = Color(0, 0, 0, 0.7)
	n.shadow_size = 3
	n.shadow_offset = Vector2(0, 3)
	n.content_margin_left = 10
	n.content_margin_right = 10
	var h := n.duplicate()
	h.bg_color = col.lightened(0.12)
	var p := n.duplicate()
	p.bg_color = col.darkened(0.2)
	p.shadow_offset = Vector2(0, 1)
	b.add_theme_stylebox_override("normal", h if false else n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_color_override("font_color", Color("e8eef5"))
	b.add_theme_font_size_override("font_size", 14)
	return b


func build_console() -> void:
	console = Control.new()
	console.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(console)
	var hb := HBoxContainer.new()
	hb.position = Vector2(20, 22)
	hb.add_theme_constant_override("separation", 8)
	console.add_child(hb)
	hb.add_child(lbl("TEMPS", Color("7f8c99"), 12))
	for d in [["pause", "⏸", 0.0], ["x1", "×1", 1.0], ["x2", "×2", 2.0], ["x4", "×4", 4.0], ["x8", "×8", 8.0]]:
		var sp: float = d[2]
		var b := hw_btn(d[1], func(): set_speed(sp); refresh())
		b.custom_minimum_size = Vector2(52, 40)
		hb.add_child(b)
		hw[d[0]] = b
	# à droite du bureau (le clavier et les mains sont au centre) : vue 3D seule et pilote automatique
	var tb := hw_btn("VUE 3D (Tab)", func(): w.toggle_bridge())
	tb.anchor_left = 1.0
	tb.anchor_right = 1.0
	tb.offset_left = -350
	tb.offset_right = -220
	tb.offset_top = 22
	tb.offset_bottom = 62
	console.add_child(tb)
	hw["tab3d"] = tb
	var bb := hw_btn("🤖  PILOTE AUTO", func(): S.bot_toggle(); refresh(), Color("8a5a16"))
	bb.custom_minimum_size = Vector2(190, 40)
	bb.anchor_left = 1.0
	bb.anchor_right = 1.0
	bb.offset_left = -210
	bb.offset_right = -20
	bb.offset_top = 22
	bb.offset_bottom = 62
	console.add_child(bb)
	hw["bot"] = bb


func set_lit(id: String, on: bool) -> void:
	if hw.has(id):
		(hw[id] as Button).modulate = Color(1.5, 1.5, 1.3) if on else Color(1, 1, 1)


# ---------------------------------------------------------------- cockpit 2D en pixel art (« repaire de hacker ») :
# mur sombre, tuyaux, câbles, bras mécaniques des moniteurs, gadgets, néon ; au premier plan bureau, clavier et mains.
# Le fond est dessiné dans un SubViewport à 1/PXR de la résolution puis agrandi en pixels nets.
var cock_t := 0.0
const PXR := 2.0


func poly(pts: Array, col: Color) -> void:
	room.draw_colored_polygon(PackedVector2Array(pts), col)


func rivets(a: Vector2, b: Vector2, n: int) -> void:
	for k in n:
		room.draw_circle(a.lerp(b, (k + 0.5) / n), 2.0, Color("4a3a3e"))


# câble qui pend (chaînette)
func cable2(a: Vector2, b: Vector2, sag: float, wdt: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 17:
		var k := i / 16.0
		pts.append(a.lerp(b, k) + Vector2(0, sag * 4.0 * k * (1.0 - k)))
	room.draw_polyline(pts, col.darkened(0.5), wdt + 2.0)
	room.draw_polyline(pts, col, wdt)


# ---- illustration de cockpit fournie par l'utilisateur (prioritaire sur le décor dessiné)
var art_tex: Texture2D = null
var art_map := {}            # id du moniteur -> [x, y, largeur, hauteur] en fractions de l'image


func load_art() -> void:
	if ResourceLoader.exists("res://art/cockpit.png"):
		art_tex = load("res://art/cockpit.png")
	if art_tex != null and FileAccess.file_exists("res://art/cockpit.json"):
		var j = JSON.parse_string(FileAccess.get_file_as_string("res://art/cockpit.json"))
		if j is Dictionary:
			art_map = j


# rectangle où l'image est affichée : elle couvre toute la fenêtre en gardant ses proportions (centrée)
func art_rect(V: Vector2) -> Rect2:
	var ts := art_tex.get_size()
	var k := maxf(V.x / ts.x, V.y / ts.y)
	var sz := ts * k
	return Rect2((V - sz) * 0.5, sz)


func draw_room() -> void:
	var V := room.size
	if V.x < 100.0:
		return
	if art_tex != null:
		room.draw_texture_rect(art_tex, art_rect(V), false)
		return
	var f := get_theme_default_font()
	# --- mur du fond : brun-rouge très sombre, panneaux et rivets
	room.draw_rect(Rect2(Vector2.ZERO, V), Color("140c10"))
	for i in 12:
		for j in 7:
			var r := Rect2(i * 140 + 3, j * 140 + 3, 134, 134)
			room.draw_rect(r, Color("1c1216") if (i + j) % 2 == 0 else Color("180f13"))
			rivets(r.position + Vector2(8, 8), Vector2(r.end.x - 8, r.position.y + 8), 4)
	# tuyaux horizontaux et verticaux
	for k in 3:
		var y := 18.0 + k * 14.0
		room.draw_rect(Rect2(0, y, V.x, 9), Color("3a2a2e"))
		room.draw_line(Vector2(0, y + 2), Vector2(V.x, y + 2), Color("5a4246"), 2.0)
	for k in 4:
		var x := V.x * (0.08 + k * 0.28)
		room.draw_rect(Rect2(x, 0, 10, V.y - 160), Color("2e2226"))
		room.draw_line(Vector2(x + 2, 0), Vector2(x + 2, V.y - 160), Color("4a383c"), 2.0)
	# --- bras mécaniques derrière chaque moniteur, jusqu'au mur
	for m in mons:
		var r: Rect2 = m.home
		if r.size.x < 10.0:
			continue
		var c := r.get_center()
		var anchor := Vector2(c.x + (c.x - V.x * 0.5) * 0.15, c.y - r.size.y * 0.6 - 10.0)
		var mid := c.lerp(anchor, 0.5) + Vector2(r.size.x * 0.25 * signf(c.x - V.x * 0.5 + 0.01), 0)
		for seg in [[c, mid], [mid, anchor]]:
			room.draw_line(seg[0], seg[1], Color("2a2e36"), 14.0)
			room.draw_line(seg[0], seg[1], Color("4a505c"), 4.0)
		room.draw_circle(mid, 10.0, Color("3a3f4a"))
		room.draw_circle(mid, 4.0, Color("8a92a0"))
		room.draw_rect(Rect2(anchor - Vector2(14, 8), Vector2(28, 16)), Color("3a3f4a"))
	# câbles rouges et violets qui pendent entre les moniteurs
	var cols := [Color("8a1e34"), Color("5a2a7a"), Color("2a2a32"), Color("a02a3a")]
	var sd := 5
	for i in 16:
		sd = (sd * 16807) % 2147483647
		var a := Vector2(float(sd % 1000) / 1000.0 * V.x, 50.0 + float(sd % 37))
		sd = (sd * 16807) % 2147483647
		var b := Vector2(float(sd % 1000) / 1000.0 * V.x, 50.0 + float(sd % 53))
		cable2(a, b, 60.0 + float(sd % 140), 3.0 + float(sd % 3), cols[i % 4])
	# enseignes au néon (dessinées par-dessus les câbles), qui grésillent
	var flick := 1.0 if fmod(cock_t * 0.8, 5.0) > 0.3 else (0.35 if sin(cock_t * 50.0) > 0.0 else 1.0)
	room.draw_rect(Rect2(V.x - 214, 8, 196, 52), Color("1a1014"))
	room.draw_string(f, Vector2(V.x - 200, 48), "K-240", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(1.0, 0.25, 0.75, flick))
	room.draw_rect(Rect2(14, 10, 150, 34), Color("1a1014"))
	room.draw_string(f, Vector2(22, 34), "KUIPER", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.3, 0.9, 1.0, 0.9 * flick))
	# --- bureau au premier plan, en perspective (plateau qui s'élargit vers le bas)
	var dy := V.y - 160.0
	poly([Vector2(V.x * 0.06, dy + 8), Vector2(V.x * 0.94, dy + 8), Vector2(V.x, V.y), Vector2(0, V.y)], Color("2c2428"))
	poly([Vector2(V.x * 0.06, dy + 8), Vector2(V.x * 0.94, dy + 8), Vector2(V.x * 0.945, dy + 14), Vector2(V.x * 0.055, dy + 14)], Color("4a3c40"))
	room.draw_line(Vector2(V.x * 0.06, dy + 8), Vector2(V.x * 0.94, dy + 8), Color("6a5a5e"), 2.0)
	# lueur verte des écrans sur le bureau
	for k in 7:
		room.draw_circle(Vector2(V.x * 0.5, dy + 10), 420.0 - k * 55.0, Color(0.2, 1.0, 0.45, 0.022))
	# gadgets : boîtier à voyants, carte électronique, canette, câble enroulé, tasse
	var gb := Rect2(V.x * 0.25, dy + 28, 100, 44)
	room.draw_rect(gb, Color("3a3238"))
	room.draw_rect(Rect2(gb.position, Vector2(gb.size.x, 4)), Color("5a4e54"))
	room.draw_rect(Rect2(gb.position + Vector2(0, gb.size.y - 4), Vector2(gb.size.x, 4)), Color("221c20"))
	for k in 5:
		var on := fmod(cock_t * (0.6 + k * 0.3) + k, 1.8) < 1.1
		var lc: Color = Color("5ff0a0") if k % 2 == 0 else Color("ff5a5a")
		room.draw_rect(Rect2(gb.position + Vector2(10 + k * 17, 12), Vector2(10, 6)), lc if on else Color("2a1e22"))
		if on:
			room.draw_rect(Rect2(gb.position + Vector2(8 + k * 17, 10), Vector2(14, 10)), Color(lc.r, lc.g, lc.b, 0.25))
	var pcb := Rect2(V.x * 0.665, dy + 34, 112, 52)
	room.draw_rect(pcb, Color("1c3a24"))
	room.draw_rect(pcb, Color("2e5a38"), false, 2.0)
	for k in 8:
		room.draw_rect(Rect2(pcb.position + Vector2(8 + k * 12, 8), Vector2(6, 10)), Color("c8b060"))
		room.draw_line(pcb.position + Vector2(11 + k * 12, 18), pcb.position + Vector2(11 + k * 12, 44), Color("6ab070"), 1.0)
	room.draw_rect(Rect2(pcb.position + Vector2(30, 24), Vector2(40, 18)), Color("15151a"))
	var can := Rect2(V.x * 0.745, dy + 22, 24, 42)
	room.draw_rect(can, Color("b8303e"))
	room.draw_rect(Rect2(can.position + Vector2(4, 0), Vector2(5, can.size.y)), Color("e05060"))
	room.draw_rect(Rect2(can.position, Vector2(can.size.x, 5)), Color("d8d8d8"))
	for k in 3:
		room.draw_arc(Vector2(V.x * 0.205, dy + 84), 24.0 + k * 6.0, 0, TAU, 20, Color("15151a"), 4.0)
		room.draw_arc(Vector2(V.x * 0.205, dy + 82), 24.0 + k * 6.0, PI, TAU, 10, Color("3a3a44"), 1.0)
	# clavier en perspective : trapèze, touches à dessus clair et face avant sombre, quelques touches de couleur
	var kt := dy + 48.0
	var kbt := kt + 96.0
	var kl0 := V.x * 0.37
	var kr0 := V.x * 0.63
	var kl1 := V.x * 0.335
	var kr1 := V.x * 0.665
	poly([Vector2(kl0 - 6, kt - 6), Vector2(kr0 + 6, kt - 6), Vector2(kr1 + 8, kbt + 8), Vector2(kl1 - 8, kbt + 8)], Color("1e1e24"))
	poly([Vector2(kl0, kt), Vector2(kr0, kt), Vector2(kr1, kbt), Vector2(kl1, kbt)], Color("3c3c46"))
	var krows := 5
	var kcols := 15
	for r in krows:
		var t0 := float(r) / krows
		var t1 := float(r + 1) / krows
		var y0 := lerpf(kt, kbt, t0) + 3.0
		var y1 := lerpf(kt, kbt, t1) - 2.0
		var l0 := lerpf(kl0, kl1, t0)
		var r0 := lerpf(kr0, kr1, t0)
		var l1 := lerpf(kl0, kl1, t1)
		var r1 := lerpf(kr0, kr1, t1)
		for k in kcols:
			var a0 := lerpf(l0, r0, float(k) / kcols) + 2.0
			var b0 := lerpf(l0, r0, float(k + 1) / kcols) - 2.0
			var a1 := lerpf(l1, r1, float(k) / kcols) + 2.0
			var b1 := lerpf(l1, r1, float(k + 1) / kcols) - 2.0
			var key := Color("9a9aa6")
			if (r == 0 and k < 2) or (r == 4 and (k == 0 or k == 14)):
				key = Color("d0506a")
			elif r == 1 and k == 13:
				key = Color("4ac0a0")
			elif (r + k) % 7 == 0:
				key = Color("7a7a88")
			var ym := lerpf(y0, y1, 0.72)
			poly([Vector2(a0, y0), Vector2(b0, y0), Vector2(lerpf(b0, b1, 0.72), ym), Vector2(lerpf(a0, a1, 0.72), ym)], key)
			poly([Vector2(lerpf(a0, a1, 0.72), ym), Vector2(lerpf(b0, b1, 0.72), ym), Vector2(b1, y1), Vector2(a1, y1)], key.darkened(0.45))
			room.draw_line(Vector2(a0, y0), Vector2(b0, y0), key.lightened(0.25), 1.0)
	# mains : gauche nue sur le clavier, droite gantée (gant sans doigts, bracelet lumineux)
	draw_hand(Vector2(V.x * 0.44, kt + 40.0), false)
	draw_hand(Vector2(V.x * 0.59, kt + 46.0), true)
	# vignettage : coins assombris
	for k in 10:
		var a := 0.05
		room.draw_rect(Rect2(0, 0, 18.0 + k * 14.0, V.y), Color(0, 0, 0, a))
		room.draw_rect(Rect2(V.x - 18.0 - k * 14.0, 0, 18.0 + k * 14.0, V.y), Color(0, 0, 0, a))


# main en pixel art : avant-bras effilé avec ombre, dos de main bombé, articulations, doigts arrondis, ongles
func draw_hand(p: Vector2, gloved: bool) -> void:
	var skin := Color("c8906c")
	var skin_l := Color("e0aa84")
	var skin_d := Color("8e5a40")
	var glove := Color("26262e")
	var glove_l := Color("3c3c48")
	var s := 1.0 if gloved else -1.0
	var base := p + Vector2(s * 90.0, 190.0)
	# avant-bras : contour sombre, peau, reflet le long du bord éclairé
	poly([p + Vector2(-30, 10), p + Vector2(30, 10), base + Vector2(48, 30), base + Vector2(-48, 30)], skin_d)
	poly([p + Vector2(-25, 10), p + Vector2(25, 10), base + Vector2(40, 30), base + Vector2(-40, 30)], skin)
	poly([p + Vector2(-s * 22 - 4, 12), p + Vector2(-s * 22 + 4, 12), base + Vector2(-s * 36 + 8, 30), base + Vector2(-s * 36 - 6, 30)], skin_l)
	for k in 9:
		var q := p.lerp(base, 0.2 + k * 0.08) + Vector2(-14 + (k % 3) * 12, 0)
		room.draw_line(q, q + Vector2(3, 3), skin_d, 1.0)
	if gloved:
		# manchette du gant et bracelet lumineux
		poly([p + Vector2(-32, 4), p + Vector2(32, 4), p + Vector2(36, 44), p + Vector2(-36, 44)], glove)
		room.draw_rect(Rect2(p + Vector2(-36, 36), Vector2(72, 6)), Color(0.3, 0.9, 1.0))
		room.draw_rect(Rect2(p + Vector2(-38, 33), Vector2(76, 12)), Color(0.3, 0.9, 1.0, 0.25))
	# dos de la main, bombé (contour, aplat, reflet)
	var back := glove if gloved else skin
	var back_l := glove_l if gloved else skin_l
	poly([p + Vector2(-34, -14), p + Vector2(34, -14), p + Vector2(30, 18), p + Vector2(-30, 18)], skin_d if not gloved else Color("15151a"))
	poly([p + Vector2(-31, -12), p + Vector2(31, -12), p + Vector2(27, 15), p + Vector2(-27, 15)], back)
	poly([p + Vector2(-20, -10), p + Vector2(14, -10), p + Vector2(10, -2), p + Vector2(-18, -2)], back_l)
	# doigts recourbés : phalange (gant ou peau), articulation, bout arrondi avec ongle
	for k in 4:
		var x := -26.0 + k * 17.0
		var fl := 22.0 - absf(k - 1.5) * 3.0
		room.draw_rect(Rect2(p + Vector2(x, -14 - fl), Vector2(14, fl + 2)), Color("15151a") if gloved else skin_d)
		room.draw_rect(Rect2(p + Vector2(x + 1, -14 - fl), Vector2(12, fl)), back)
		room.draw_rect(Rect2(p + Vector2(x + 3, -12 - fl), Vector2(3, fl - 4)), back_l)
		# bout du doigt (toujours nu), arrondi
		var tip := p + Vector2(x + 7, -18 - fl)
		room.draw_circle(tip, 7.0, skin_d)
		room.draw_circle(tip + Vector2(0, 1), 6.0, skin)
		room.draw_rect(Rect2(tip + Vector2(-3, -5), Vector2(6, 4)), skin_l)
		room.draw_line(p + Vector2(x + 2, -14), p + Vector2(x + 12, -14), skin_d if not gloved else Color("15151a"), 1.0)
	# pouce, replié sur le côté
	var th := p + Vector2(-s * 34, -2)
	poly([th + Vector2(0, -6), th + Vector2(-s * 18, -18), th + Vector2(-s * 22, -10), th + Vector2(-s * 4, 6)], skin_d)
	poly([th + Vector2(0, -4), th + Vector2(-s * 16, -15), th + Vector2(-s * 19, -9), th + Vector2(-s * 3, 4)], skin)
	room.draw_circle(th + Vector2(-s * 19, -14), 5.0, skin)


# ---------------------------------------------------------------- écran agrandi (le cadre du moniteur reste visible)
func focus_screen(m) -> void:
	if focused != null:
		return
	if m is Control:
		m = mon_of(m)
	if m.is_empty():
		return
	focused = m.content
	fz_dir = 1.0
	fz_t = 0.0
	move_child(dim, -1)
	if m.has("warp"):
		move_child(m.warp, -1)
	else:
		move_child(m.mon, -1)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	if m.has("catcher"):
		m.catcher.visible = false
	m.rd.visible = true
	hint.visible = false
	do_layout()


func unfocus() -> void:
	if focused == null:
		return
	fz_dir = -1.0
	var m := mon_of(focused)
	if not m.is_empty():
		m.rd.visible = false


func animate_focus(dt: float) -> void:
	if focused == null:
		return
	fz_t = clampf(fz_t + fz_dir * dt / 0.3, 0.0, 1.0)
	dim.color.a = 0.78 * fz_t
	do_layout()
	if fz_dir < 0.0 and fz_t <= 0.0:
		var m := mon_of(focused)
		focused = null
		if m.has("catcher"):
			m.catcher.visible = true
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hint.visible = art_tex == null
		do_layout()


func draw_corners(ov: Control) -> void:
	var s := ov.size
	var c := Color(0.37, 0.83, 1.0, 0.85)
	var L := 14.0
	for p in [Vector2(0, 0), Vector2(s.x, 0), Vector2(0, s.y), Vector2(s.x, s.y)]:
		var dx := L if p.x == 0 else -L
		var dy := L if p.y == 0 else -L
		ov.draw_line(p, p + Vector2(dx, 0), c, 2.0)
		ov.draw_line(p, p + Vector2(0, dy), c, 2.0)


# ---------------------------------------------------------------- style
func make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 14
	th.set_color("font_color", "Label", TXT)
	th.set_color("font_color", "Button", Color("cfeaff"))
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_disabled_color", "Button", Color("5c7690"))
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.035, 0.12, 0.21, 0.92)
	n.border_color = Color("1f5a80")
	n.set_border_width_all(1)
	n.set_corner_radius_all(3)
	n.content_margin_left = 8
	n.content_margin_right = 8
	n.content_margin_top = 5
	n.content_margin_bottom = 5
	var hv := n.duplicate()
	hv.border_color = CY
	hv.bg_color = Color(0.07, 0.22, 0.36, 0.95)
	var pr := hv.duplicate()
	pr.bg_color = Color(0.1, 0.3, 0.45, 0.95)
	var ds := n.duplicate()
	ds.bg_color = Color(0.03, 0.07, 0.12, 0.9)
	ds.border_color = Color("173d5c")
	th.set_stylebox("normal", "Button", n)
	th.set_stylebox("hover", "Button", hv)
	th.set_stylebox("pressed", "Button", pr)
	th.set_stylebox("disabled", "Button", ds)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	var tp := StyleBoxFlat.new()
	tp.bg_color = Color(0.02, 0.06, 0.11, 0.6)
	tp.border_color = Color("173d5c")
	tp.set_border_width_all(1)
	tp.content_margin_left = 6
	tp.content_margin_right = 6
	tp.content_margin_top = 6
	tp.content_margin_bottom = 6
	th.set_stylebox("panel", "TabContainer", tp)
	var tsel := n.duplicate()
	tsel.border_color = CY
	tsel.bg_color = Color(0.07, 0.26, 0.42, 0.95)
	th.set_stylebox("tab_selected", "TabContainer", tsel)
	th.set_stylebox("tab_unselected", "TabContainer", n)
	th.set_stylebox("tab_hovered", "TabContainer", hv)
	th.set_color("font_selected_color", "TabContainer", Color.WHITE)
	th.set_color("font_unselected_color", "TabContainer", DIM)
	var pb := StyleBoxFlat.new()
	pb.bg_color = Color(0, 0, 0, 0.5)
	pb.set_corner_radius_all(2)
	var pf := StyleBoxFlat.new()
	pf.bg_color = OK
	pf.set_corner_radius_all(2)
	th.set_stylebox("background", "ProgressBar", pb)
	th.set_stylebox("fill", "ProgressBar", pf)
	return th


# ---------------------------------------------------------------- kit commun des écrans (tous sauf l'écran principal)
# Un seul cadre, un seul bandeau de titre, une seule échelle de texte. Chaque écran a une couleur d'accent
# (titre, jauges) prise dans ACC ; le reste est identique partout.
const ACC := {"info": Color("5fd4ff"), "res": Color("ffb347"), "ok": Color("5ff0a0"), "alert": Color("ff3ad0")}
const FS_TITLE := 14     # bandeau de titre
const FS_LABEL := 15     # libellés et lignes de texte
const FS_SMALL := 12     # libellés serrés, légendes
const FS_VALUE := 44     # grande valeur (énergie, horloge…)
const KIT_TOP := 40.0    # haut de la zone de contenu (sous le bandeau)
const KIT_PAD := 12.0    # marges intérieures
const HOME_W := 440.0    # largeur virtuelle d'un écran d'état à sa place (agrandi, il passe à 1:1)


func screen_panel(main := false, accent: Color = ACC.info) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.06, 0.11, 1.0) if not main else Color(0.01, 0.02, 0.04, 1.0)
	sb.border_color = Color("1d4d70")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.12)
	sb.shadow_size = 0 if art_tex != null else 10
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_STOP if not main else Control.MOUSE_FILTER_IGNORE
	return p


func header(par: Control, text: String, accent: Color = ACC.info) -> Label:
	var hb := ColorRect.new()
	hb.color = Color(accent.r, accent.g, accent.b, 0.1)
	hb.position = Vector2(2, 2)
	hb.size = Vector2(4000, 26)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	par.add_child(hb)
	var l := Label.new()
	l.text = text
	l.position = Vector2(12, 5)
	l.add_theme_color_override("font_color", accent)
	l.add_theme_font_size_override("font_size", FS_TITLE)
	par.add_child(l)
	par.clip_contents = true
	return l


# zone de contenu d'un écran, sous le bandeau
func kit_area(s: Vector2) -> Rect2:
	return Rect2(KIT_PAD, KIT_TOP, s.x - KIT_PAD * 2.0, s.y - KIT_TOP - KIT_PAD)


# ligne de texte ; renvoie le haut de la ligne suivante
func kit_text(c: Control, x: float, y: float, t: String, fs: int, col: Color, wmax := -1.0) -> float:
	var f := get_theme_default_font()
	c.draw_string(f, Vector2(x, y + f.get_ascent(fs)), t, HORIZONTAL_ALIGNMENT_LEFT, wmax, fs, col)
	return y + f.get_height(fs) + 4.0


# grande valeur et sa légende ; renvoie le bas du bloc
func kit_value(c: Control, x: float, y: float, value: String, sub: String, col: Color, fs := FS_VALUE) -> float:
	y = kit_text(c, x, y, value, fs, col)
	if sub != "":
		y = kit_text(c, x, y - 4.0, sub, FS_LABEL, DIM)
	return y + 8.0


# jauges en rangées : items = [[libellé, fraction, couleur], …], réparties dans r
func kit_gauges(c: Control, r: Rect2, items: Array) -> void:
	var n := items.size()
	if n == 0 or r.size.y <= 0.0:
		return
	var rh := minf(r.size.y / n, 56.0)
	var fs := FS_LABEL if rh >= 26.0 else FS_SMALL
	var lw := minf(r.size.x * 0.4, 240.0)
	var bh := clampf(rh * 0.4, 6.0, 16.0)
	var f := get_theme_default_font()
	for i in n:
		var it: Array = items[i]
		var col: Color = it[2]
		var cy := r.position.y + rh * (i + 0.5)
		c.draw_string(f, Vector2(r.position.x, cy + f.get_ascent(fs) * 0.5 - 1.0), it[0], HORIZONTAL_ALIGNMENT_LEFT, lw - 8.0, fs, col)
		var bar := Rect2(r.position.x + lw, cy - bh * 0.5, r.size.x - lw, bh)
		c.draw_rect(bar, Color(col.r, col.g, col.b, 0.15))
		c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(it[1], 0.0, 1.0), bh)), col)


func lbl(t := "", col := TXT, fs := 14) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", fs)
	return l


func btn(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func scroll_box(par: Control, name: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	par.add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 6)
	sc.add_child(vb)
	return vb


# ---------------------------------------------------------------- écran de gauche : gestion de la colonie (économie, population, recherche)
func build_left() -> void:
	header(left, "GESTION DE LA COLONIE")
	tabs = TabContainer.new()
	tabs.position = Vector2(8, 34)
	tabs.anchor_right = 1.0
	tabs.anchor_bottom = 1.0
	tabs.offset_right = -8
	tabs.offset_bottom = -8
	left.add_child(tabs)
	# --- colonie : ressources, énergie, population
	var vb := scroll_box(tabs, "Colonie")
	vb.add_child(lbl("RESSOURCES", CY, 12))
	for r in C.RES:
		var row := HBoxContainer.new()
		var n := lbl(C.RES[r].name, C.RES[r].color, 13)
		n.custom_minimum_size.x = 130
		var v := lbl("", TXT, 13)
		v.custom_minimum_size.x = 95
		var rt := lbl("", OK, 13)
		row.add_child(n)
		row.add_child(v)
		row.add_child(rt)
		vb.add_child(row)
		res_rows[r] = [v, rt]
	vb.add_child(HSeparator.new())
	lbl_energy = lbl()
	vb.add_child(lbl_energy)
	lbl_shield = lbl()
	vb.add_child(lbl_shield)
	vb.add_child(HSeparator.new())
	vb.add_child(lbl("POPULATION (SOUS TERRE)", CY, 12))
	lbl_pop = lbl()
	vb.add_child(lbl_pop)
	lbl_morale = lbl()
	vb.add_child(lbl_morale)
	bar_morale = ProgressBar.new()
	bar_morale.custom_minimum_size.y = 8
	bar_morale.show_percentage = false
	vb.add_child(bar_morale)
	lbl_pol = lbl()
	lbl_pol.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(lbl_pol)
	lbl_tax = lbl()
	vb.add_child(lbl_tax)
	sl_tax = HSlider.new()
	sl_tax.min_value = 0
	sl_tax.max_value = 40
	sl_tax.step = 1
	sl_tax.value = C.tax
	sl_tax.focus_mode = Control.FOCUS_NONE
	sl_tax.value_changed.connect(func(v): C.tax = v)
	vb.add_child(sl_tax)
	build_supervisors()
	# --- recherche : organigramme partant du centre de commandement (cliquez une recherche disponible)
	var rv := VBoxContainer.new()
	rv.name = "Recherche"
	tabs.add_child(rv)
	lbl_tech = lbl("", AMB, 13)
	lbl_tech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(lbl_tech)
	var rs := ScrollContainer.new()
	rs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(rs)
	rtree = Control.new()
	rtree.draw.connect(draw_rtree)
	rtree.gui_input.connect(rtree_input)
	rtree.mouse_filter = Control.MOUSE_FILTER_STOP
	rs.add_child(rtree)
	rv.add_child(lbl("■ acquise   ■ en cours   ■ disponible   ■ verrouillée", DIM, 11))
	layout_rtree()


# ---------------------------------------------------------------- écran principal : vue de l'astéroïde + construction, ou carte stratégique
func build_center() -> void:
	head_lbl = header(center, "VUE PRINCIPALE")
	var th := HBoxContainer.new()
	th.anchor_left = 1.0
	th.anchor_right = 1.0
	th.offset_left = -360
	th.offset_right = -46
	th.offset_top = 3
	th.add_theme_constant_override("separation", 4)
	center.add_child(th)
	for k in 2:
		var b := btn(["Astéroïde 3D", "Carte stratégique"][k], func(): show_map(k == 1))
		b.add_theme_font_size_override("font_size", 12)
		b.custom_minimum_size = Vector2(150, 24)
		th.add_child(b)
	# l'écran principal se déploie avec ce bouton (le clic dans la vue sert à piloter la caméra)
	var xb := btn("⛶", func(): focus_screen(center) if focused == null else unfocus())
	xb.tooltip_text = "Agrandir l’écran principal"
	xb.anchor_left = 1.0
	xb.anchor_right = 1.0
	xb.offset_left = -40
	xb.offset_right = -6
	xb.offset_top = 3
	xb.offset_bottom = 27
	center.add_child(xb)
	lbl_alert = lbl("", BAD, 13)
	lbl_alert.position = Vector2(300, 6)
	center.add_child(lbl_alert)
	# panneau Construire, à côté de la vue de l'astéroïde : on construit là où l'on voit les bâtiments
	build_side = ScrollContainer.new()
	build_side.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(build_side)
	var vc := VBoxContainer.new()
	vc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vc.add_theme_constant_override("separation", 5)
	build_side.add_child(vc)
	vc.add_child(lbl("CONSTRUIRE EN SURFACE", CY, 12))
	var info := lbl("Les bâtiments se débloquent phase après phase (objectifs : onglet Survie de la gestion). Le chantier s’installe sur le prochain emplacement libre.", DIM, 11)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vc.add_child(info)
	for t in C.BLD:
		if t == "spatioport" or t == "capsule":
			continue
		var b := btn("", func(): C.build(t); refresh())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 12)
		b.tooltip_text = C.BLD[t].desc
		vc.add_child(b)
		bld_btn[t] = b
	lbl_sites = lbl("", DIM, 11)
	lbl_sites.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vc.add_child(lbl_sites)
	map = Control.new()
	map.visible = false
	map.mouse_filter = Control.MOUSE_FILTER_STOP
	map.draw.connect(draw_map)
	map.gui_input.connect(map_input)
	center.add_child(map)
	var hb := HBoxContainer.new()
	hb.anchor_top = 1.0
	hb.anchor_bottom = 1.0
	hb.anchor_right = 1.0
	hb.offset_left = 8
	hb.offset_top = -36
	hb.offset_bottom = -6
	hb.offset_right = -8
	hb.add_theme_constant_override("separation", 4)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(hb)
	var names := ["Stratégique", "Front", "Tactique", "Base", "Industrie", "Spatioport", "Pirates", "Astéroïde"]
	for i in 8:
		var b := btn("%d %s" % [i + 1, names[i]], func(): w.apply_view(i))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 12)
		hb.add_child(b)


# ---------------------------------------------------------------- écran de droite en haut : radar tactique et contacts
func build_right() -> void:
	header(right, "RADAR TACTIQUE")
	radar = Control.new()
	radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radar.draw.connect(draw_radar)
	right.add_child(radar)
	var vb := VBoxContainer.new()
	vb.name = "infos"
	right.add_child(vb)
	vb.add_child(lbl("CONTACTS", CY, 12))
	lbl_contacts = lbl("", TXT, 12)
	lbl_contacts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(lbl_contacts)
	vb.add_child(HSeparator.new())
	vb.add_child(lbl("EFFECTIFS AU SOL", CY, 12))
	lbl_units = lbl("", TXT, 12)
	vb.add_child(lbl_units)
	# radar à gauche et contacts à droite si l'écran est large (agrandi), sinon contacts sous le radar
	right.resized.connect(func():
		var W := right.size.x - 16
		var H := right.size.y - 42
		if W > H * 1.5:
			var s := H
			radar.position = Vector2(8, 34)
			radar.size = Vector2(s, s)
			vb.position = Vector2(16 + s, 34)
			vb.size = Vector2(W - s - 8, H)
		else:
			var s := minf(W, H * 0.62)
			radar.position = Vector2(8 + (W - s) * 0.5, 34)
			radar.size = Vector2(s, s)
			vb.position = Vector2(10, 40 + s)
			vb.size = Vector2(W - 4, H - s - 6))


# ---------------------------------------------------------------- écran de droite en bas : commandement spatial (spatioport)
func build_right2() -> void:
	header(right2, "COMMANDEMENT SPATIAL")
	tabs2 = TabContainer.new()
	tabs2.position = Vector2(8, 34)
	tabs2.anchor_right = 1.0
	tabs2.anchor_bottom = 1.0
	tabs2.offset_right = -8
	tabs2.offset_bottom = -8
	right2.add_child(tabs2)
	# --- usine spatiale du spatioport
	var vu := scroll_box(tabs2, "Usine")
	vu.add_child(lbl("USINE SPATIALE (SPATIOPORT)", CY, 12))
	for u in S.UNITS:
		var b := btn("", func(): S.order(u); refresh())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 12)
		vu.add_child(b)
		unit_btn[u] = b
	lbl_queue = lbl("", DIM, 12)
	lbl_queue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vu.add_child(lbl_queue)
	# --- flottes et leurs ordres
	var vf := scroll_box(tabs2, "Flottes")
	lbl_hangar = lbl("", TXT, 12)
	lbl_hangar.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vf.add_child(lbl_hangar)
	vf.add_child(btn("＋ Nouvelle flotte", func(): S.fleet_new(); fleet_sig = ""; refresh()))
	fleet_box = VBoxContainer.new()
	fleet_box.add_theme_constant_override("separation", 4)
	vf.add_child(fleet_box)
	# --- renseignement : satellites espions et rapports de combat
	var vi := scroll_box(tabs2, "Renseignement")
	sat_btn = btn("", func(): S.launch_sat(); refresh())
	vi.add_child(sat_btn)
	lbl_intel = lbl("", TXT, 12)
	lbl_intel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vi.add_child(lbl_intel)
	sab_btn = btn("", func(): Fx.sabotage(); refresh())
	vi.add_child(sab_btn)
	vi.add_child(HSeparator.new())
	vi.add_child(lbl("RAPPORTS DE COMBAT", CY, 12))
	lbl_combat = lbl("", TXT, 12)
	lbl_combat.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vi.add_child(lbl_combat)


# ---------------------------------------------------------------- écrans d'état (petits moniteurs) : même kit que les grands écrans
# Mise en page relative à la taille de l'écran : à sa place, l'écran est rendu en HOME_W de large puis réduit ;
# agrandi, il est rendu à 1:1 comme les grands écrans (place_mon).
func status_screen(id: String, title: String, accent: Color) -> Panel:
	var p := screen_panel(false, accent)
	p.theme = th_ui
	header(p, title, accent)
	add_monitor(id, title.split(" ")[0], p, true)
	return p


# écran d'état dessiné par draw_deco
func deco_screen(id: String, title: String, accent: Color) -> void:
	var p := status_screen(id, title, accent)
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func(): draw_deco(id, c, accent))
	p.add_child(c)
	deco[id] = c


# écran d'état fait d'un texte qui défile (messages, pilote automatique)
func text_screen(id: String, title: String, accent: Color) -> Label:
	var p := status_screen(id, title, accent)
	var l := lbl("", accent, FS_LABEL)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.offset_left = KIT_PAD
	l.offset_top = KIT_TOP
	l.offset_right = -KIT_PAD
	l.offset_bottom = -KIT_PAD
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.clip_text = true
	p.add_child(l)
	return l


func build_small_screens() -> void:
	lbl_log = text_screen("log", "MESSAGES", ACC.ok)
	lbl_bot = text_screen("bot", "PILOTE AUTOMATIQUE", ACC.res)
	deco_screen("sys", "SYSTÈMES DE LA COLONIE", ACC.info)
	deco_screen("energy", "ÉNERGIE · BOUCLIER", ACC.info)
	deco_screen("alert", "ALERTES DE LA STATION", ACC.alert)
	# illustration : écrans supplémentaires sur les autres moniteurs du dessin (seulement s'ils sont décrits dans cockpit.json)
	var extra := [["data", "STOCKS DE LA COLONIE", ACC.res], ["net", "LIAISON SUBSPATIALE", ACC.ok], ["scan", "BALAYAGE", ACC.info],
		["pop", "POPULATION · SANTÉ", ACC.info], ["time", "HORLOGE DE MISSION", ACC.info], ["fleet", "FLOTTES", ACC.ok],
		["kron", "TERRE · ARCHE", ACC.res], ["cons", "TÉLÉSCRIPTEUR", ACC.ok]]
	for d in extra:
		if art_tex != null and art_map.has(d[0]):
			deco_screen(d[0], d[1], d[2])


func draw_deco(id: String, c: Control, col: Color) -> void:
	var a := kit_area(c.size)
	var x := a.position.x
	var y := a.position.y
	var f := get_theme_default_font()
	var tt := Time.get_ticks_msec() / 1000.0
	match id:
		"sys":
			kit_gauges(c, a, [["RÉACTEUR He-3", C.eff, col], ["BOUCLIER", w.SHD_E / 100.0, col], ["MORAL", C.morale / 100.0, col],
				["STOCKAGE FER", C.stock.fer / maxf(1.0, C.caps().fer), col],
				["RECHERCHE", (C.tech_p / C.TECH[C.tech_cur].time) if C.tech_cur != "" else 0.0, col]])
		"data":
			var items := []
			for k in C.RES:
				items.append([C.RES[k].name, C.stock.get(k, 0.0) / maxf(1.0, C.caps().get(k, 1.0)), col])
			kit_gauges(c, a, items)
		"energy":
			var e: Dictionary = C.energy
			y = kit_value(c, x, y, "%d / %d" % [int(e.p), int(e.c)], "produits / demandés", BAD if e.c > e.p else col)
			var down: bool = w.SHD_DOWN > 0.0
			kit_gauges(c, Rect2(x, y, a.size.x, minf(56.0, a.end.y - y)), [["BOUCLIER " + ("EFFONDRÉ" if down else "%d %%" % int(w.SHD_E)), w.SHD_E / 100.0, BAD if down else col]])
		"pop":
			y = kit_value(c, x, y, "%d" % int(C.pop), "habitants", col)
			kit_gauges(c, Rect2(x, y, a.size.x, a.end.y - y), [["SANTÉ", Sv.health / 100.0, col], ["MORAL", C.morale / 100.0, col],
				["POLLUTION", C.pollution / 50.0, BAD]])
		"time":
			var gt: float = w.war.time
			kit_value(c, x, y, "%02d:%02d:%02d" % [int(gt / 3600.0), int(gt / 60.0) % 60, int(gt) % 60],
				"EN PAUSE" if w.paused else "vitesse ×%s" % str(w.tscale), AMB if w.paused else col)
		"fleet":
			var nh := 0
			for u in S.hangar:
				nh += int(S.hangar[u])
			y = kit_value(c, x, y, "%d" % S.fleets.size(), "flotte(s)", col)
			y = kit_text(c, x, y, "%d vaisseau(x) au hangar" % nh, FS_LABEL, TXT)
			y = kit_text(c, x, y, "%d colonie(s)" % S.col.size(), FS_LABEL, TXT)
			kit_text(c, x, y, "%d raid(s) pirate(s) en route" % S.emoves.size(), FS_LABEL, BAD if S.emoves.size() > 0 else DIM)
		"kron":
			y = kit_value(c, x, y, "%d %%" % int(Sv.ark), "construction de l’arche", col)
			kit_gauges(c, Rect2(x, y, a.size.x, minf(40.0, a.end.y - y)), [["ARCHE", Sv.ark / 100.0, col]])
			y += 48.0
			y = kit_text(c, x, y, "Latence : %.1f h-lumière" % Sv.latency_h, FS_LABEL, TXT)
			kit_text(c, x, y, "Réputation Terre : %d" % Sv.rep, FS_LABEL, TXT)
		"alert":
			var al: String = S.alert_txt()
			if al == "":
				y = kit_text(c, x, y, "SURVEILLANCE", FS_VALUE * 2 / 3, col)
				kit_text(c, x, y, "aucune menace immédiate", FS_LABEL, DIM)
			else:
				if fmod(tt, 1.0) < 0.6:
					kit_text(c, x, y, "ALERTE ACTIVE", FS_VALUE * 2 / 3, BAD)
				y += f.get_height(FS_VALUE * 2 / 3) + 8.0
				c.draw_multiline_string(f, Vector2(x, y + f.get_ascent(FS_LABEL)), al, HORIZONTAL_ALIGNMENT_LEFT, a.size.x, FS_LABEL, -1, col)
		"net":
			var gh := a.size.y - f.get_height(FS_LABEL) - 8.0
			for k in 3:
				var pts := PackedVector2Array()
				for i in 60:
					var px := x + i * a.size.x / 59.0
					pts.append(Vector2(px, y + gh * (0.25 + 0.25 * k) + sin(i * 0.4 + tt * (2.0 + k) + k) * gh * 0.1 * (0.5 + 0.5 * sin(tt * 0.7 + i * 0.1))))
				c.draw_polyline(pts, Color(col.r, col.g, col.b, 0.9 - k * 0.25), 2.0)
			kit_text(c, x, a.end.y - f.get_height(FS_LABEL), "LIAISON KRONOS · %d paquets/s" % int(800 + 200 * sin(tt)), FS_LABEL, col)
		"scan":
			var n: int = S.emoves.size()
			var th := f.get_height(FS_LABEL) + 8.0
			var ctr := Vector2(a.get_center().x, y + (a.size.y - th) * 0.5)
			var rr := minf(a.size.x, a.size.y - th) * 0.45
			for k in 3:
				c.draw_arc(ctr, rr * (k + 1) / 3.0, 0, TAU, 40, Color(col.r, col.g, col.b, 0.35), 2.0)
			for k in 12:
				c.draw_line(ctr, ctr + Vector2.from_angle(tt * 2.0 - k * 0.05) * rr, Color(col.r, col.g, col.b, 0.5 - k * 0.04), 3.0)
			for k in n:
				c.draw_circle(ctr + Vector2.from_angle(k * 2.1 + 0.5) * rr * 0.7, 5.0, BAD)
			kit_text(c, x, a.end.y - th + 8.0, "%d contact(s) hostile(s)" % n, FS_LABEL, BAD if n > 0 else col)
		"cons":
			var line: String = C.log[0] if C.log.size() > 0 else "K-240 · EN LIGNE"
			var tw: float = f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_VALUE).x + a.size.x
			kit_text(c, a.end.x - fmod(tt * 120.0, tw), a.get_center().y - f.get_height(FS_VALUE) * 0.5, line, FS_VALUE, col)


func set_speed(s: float) -> void:
	if s == 0.0:
		w.paused = true
	else:
		w.paused = false
		w.tscale = s


# illustration : les moniteurs plaqués en perspective ne reçoivent pas la souris ; clic et survol testés sur leur quadrilatère
var art_hover := false
func art_mon_at(p: Vector2) -> Dictionary:
	for i in range(mons.size() - 1, -1, -1):
		var m: Dictionary = mons[i]
		if m.has("quad") and m.quad.size() == 4 and Geometry2D.is_point_in_polygon(p, m.quad):
			return m
	return {}


func _input(e: InputEvent) -> void:
	if art_tex == null or not visible or focused != null:
		if art_hover:
			art_hover = false
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var m := art_mon_at(e.position)
		if not m.is_empty():
			focus_screen(m)
			get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion:
		var hov := not art_mon_at(e.position).is_empty()
		if hov != art_hover:
			art_hover = hov
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if hov else Input.CURSOR_ARROW)


# ---------------------------------------------------------------- mise à jour
func _process(dt: float) -> void:
	if not visible:
		return
	animate_focus(dt)
	for id in deco:
		deco[id].queue_redraw()
	sweep = fmod(sweep + dt * 1.3, TAU)
	cock_t += dt
	room.queue_redraw()
	radar.queue_redraw()
	if map.visible:
		map.queue_redraw()
	t_ui -= dt
	if t_ui <= 0.0:
		t_ui = 0.3
		refresh()


func fmt(v: float) -> String:
	return str(int(v)) if absf(v) >= 10.0 else "%.1f" % v


func refresh() -> void:
	if C == null:
		return
	head_lbl.text = "VUE PRINCIPALE · " + view_name.to_upper()
	var cap: Dictionary = C.caps()
	for r in res_rows:
		var row: Array = res_rows[r]
		(row[0] as Label).text = "%s / %d" % [fmt(C.stock[r]), int(cap[r])]
		var rt: float = C.rates[r]
		(row[1] as Label).text = ("+" if rt >= 0.0 else "") + "%.2f/s" % rt
		(row[1] as Label).add_theme_color_override("font_color", OK if rt >= 0.0 else BAD)
	var e: Dictionary = C.energy
	lbl_energy.text = "Énergie : %d produits / %d demandés%s" % [int(e.p), int(e.c), "  — DÉFICIT" if e.c > e.p else ""]
	lbl_energy.add_theme_color_override("font_color", BAD if e.c > e.p else TXT)
	var sh := "EFFONDRÉ (%ds)" % int(ceil(w.SHD_DOWN)) if w.SHD_DOWN > 0.0 else "%d %%" % int(w.SHD_E)
	lbl_shield.text = "Bouclier du centre de commandement : " + sh
	lbl_shield.add_theme_color_override("font_color", BAD if w.SHD_DOWN > 0.0 else CY)
	lbl_pop.text = "Habitants : %d / %d" % [int(C.pop), int(C.housing())]
	lbl_morale.text = "Moral : %d %%" % int(C.morale)
	bar_morale.value = C.morale
	lbl_pol.text = "Pollution industrielle : %.1f (moral −%d)" % [C.pollution, int(C.pollution * C.COLONY.pollutionMorale)]
	lbl_pol.add_theme_color_override("font_color", AMB if C.pollution > 8.0 else TXT)
	lbl_tax.text = "Impôts : %d %%  (+%.2f crédits/s)" % [int(C.tax), C.pop * C.tax / 100.0 * C.COLONY.taxIncome]
	# construction
	for t in bld_btn:
		var B: Dictionary = C.BLD[t]
		var why: String = C.can_build(t)
		var line2: String = C.cost_txt(B.cost) + " · %d s" % int(B.time)
		if why != "":
			line2 = why + " · " + line2
		var fx: Array = []
		if B.has("energy"):
			fx.append(("+" if B.energy > 0 else "") + "%d énergie" % int(B.energy))
		if B.has("pollution"):
			fx.append("pollution %.1f" % B.pollution)
		var b: Button = bld_btn[t]
		b.text = "%s  (%d)\n%s\n%s" % [B.name, C.count(t), line2, ", ".join(fx)]
		b.disabled = why != ""
		# survie : seuls les bâtiments de la phase atteinte sont proposés
		b.visible = int(B.get("ph", 1)) <= C.phase()
	var sites: Array = []
	for x in C.inst:
		if not x.done:
			sites.append("%s %d %%" % [C.BLD[x.t].name, int(x.p / C.BLD[x.t].time * 100.0)])
	lbl_sites.text = ("Chantiers : " + ", ".join(sites)) if sites.size() > 0 else "Aucun chantier en cours."
	# recherche
	if C.tech_cur != "":
		lbl_tech.text = "En cours : %s — %d %%" % [C.TECH[C.tech_cur].name, int(C.tech_p / C.TECH[C.tech_cur].time * 100.0)]
	else:
		lbl_tech.text = "Aucune recherche en cours. Cliquez une recherche disponible."
	rtree.queue_redraw()
	refresh_fleets()
	# renseignement
	var tr := false
	for s in S.sats:
		if not s.on:
			tr = true
	sat_btn.text = "🛰 Lancer un satellite espion · " + C.cost_txt(S.SATC)
	sat_btn.disabled = not C.tech_done.has("espion") or tr or C.count_done("spatioport") == 0
	lbl_intel.text = S.intel_txt()
	lbl_combat.text = "\n\n".join(S.combat_log) if S.combat_log.size() > 0 else "Aucun combat pour l’instant."
	var al: String = S.alert_txt()
	if al == "" and Sv != null:
		al = Sv.alert_txt()
	lbl_alert.text = al
	lbl_bot.text = S.bot_intent if S.bot_on else "Désengagé.\nAppuyez sur le bouton ambre PILOTE AUTO pour laisser l’IA jouer."
	if (S.won or S.lost) and not end_shown:
		end_shown = true
		show_end(S.won)
	# console
	lbl_log.text = "\n".join(C.log.slice(0, 4))
	# voyants des boutons des accoudoirs
	set_lit("pause", w.paused)
	for k in [[1.0, "x1"], [2.0, "x2"], [4.0, "x4"], [8.0, "x8"]]:
		set_lit(k[1], not w.paused and w.tscale == k[0])
	set_lit("bot", S.bot_on)
	refresh_contacts()
	refresh_extra()
	refresh_survival()


func refresh_contacts() -> void:
	var war = w.war
	var lines: Array = []
	for d in war.DS:
		var dist := int(w.planar(d.g.position).length())
		var st := "approche" if d.t < 9.0 else ("débarquement" if d.t < 15.0 else "redécollage")
		lines.append("▲ Navette pirate · %s · %d m" % [st, dist])
	var nr := 0
	var near := 1e9
	for F in war.FORM:
		if F.side == "r":
			nr += 1
			near = minf(near, w.planar(F.p).length())
	if nr > 0:
		lines.append("● %d formations pirates · la plus proche à %d m" % [nr, int(near)])
	var nf := 0
	for f in war.FT:
		if f.side == "r":
			nf += 1
	if nf > 0:
		lines.append("✈ %d chasseurs pirates" % nf)
	lbl_contacts.text = "\n".join(lines) if lines.size() > 0 else "Aucun contact hostile."
	var h: Dictionary = war.stats()
	var names := {"rifle": "Fusiliers", "flame": "Lance-flammes", "robot": "Robots", "tank": "Chars"}
	var t := "                 COLONIE   PIRATES\n"
	for k in ["rifle", "flame", "robot", "tank"]:
		t += "%-14s %6d %9d\n" % [names[k], h.m.get("b" + k, 0), h.m.get("r" + k, 0)]
	t += "Pertes          %6d %9d" % [h.kills.r, h.kills.b]
	lbl_units.text = t


# ---------------------------------------------------------------- dessin du radar (vue de dessus, le front vers le haut)
func draw_radar() -> void:
	var s := radar.size
	var c := s * 0.5
	var R := minf(s.x, s.y) * 0.5 - 4.0
	var rng_m := 560.0
	var k := R / rng_m
	var to := func(q: Vector2) -> Vector2: return c + Vector2(q.x, -q.y) * k
	radar.draw_circle(c, R, Color(0.01, 0.06, 0.05))
	for i in range(1, 5):
		radar.draw_arc(c, R * i / 4.0, 0, TAU, 64, Color(0.37, 0.94, 0.63, 0.18), 1.0)
	radar.draw_line(c - Vector2(R, 0), c + Vector2(R, 0), Color(0.37, 0.94, 0.63, 0.12))
	radar.draw_line(c - Vector2(0, R), c + Vector2(0, R), Color(0.37, 0.94, 0.63, 0.12))
	# balayage
	for j in 18:
		var a := sweep - j * 0.03
		radar.draw_line(c, c + Vector2(cos(a), sin(a)) * R, Color(0.37, 0.94, 0.63, 0.22 * (1.0 - j / 18.0)), 2.0)
	# couloir du front
	var war = w.war
	var p0: Vector2 = to.call(Vector2(war.P0.x, war.P0.z))
	var p1: Vector2 = to.call(Vector2(war.P1.x, war.P1.z))
	radar.draw_line(p0, p1, Color(1, 0.7, 0.3, 0.35), maxf(2.0, 96.0 * k))
	# bouclier et bâtiments
	radar.draw_arc(c, w.SHD_R * k, 0, TAU, 48, Color(0.37, 0.83, 1.0, 0.0 if w.SHD_DOWN > 0.0 else 0.8), 1.5)
	radar.draw_rect(Rect2(c - Vector2(3, 3), Vector2(6, 6)), CY)
	for hg in w.HANGARS:
		radar.draw_rect(Rect2(to.call(w.planar(hg.door)) - Vector2(2, 2), Vector2(4, 4)), CY)
	for h in w.harvesters:
		radar.draw_circle(to.call(w.planar(h.n.position)), 2.0, AMB)
	# formations au sol
	for F in war.FORM:
		var q: Vector2 = to.call(w.planar(F.p))
		var col := OK if F.side == "b" else BAD
		radar.draw_circle(q, 2.5 + minf(4.0, F.alive.size() * 0.12), col)
	# chasseurs et navettes
	for f in war.FT:
		var q: Vector2 = to.call(w.planar(f.g.position))
		radar.draw_circle(q, 1.6, OK if f.side == "b" else BAD)
	for d in war.DS:
		var q: Vector2 = to.call(w.planar(d.g.position))
		radar.draw_colored_polygon(PackedVector2Array([q + Vector2(0, -6), q + Vector2(5, 4), q + Vector2(-5, 4)]), BAD)
	radar.draw_arc(c, R, 0, TAU, 96, Color(0.37, 0.94, 0.63, 0.55), 2.0)
	radar.draw_string(get_theme_default_font(), c + Vector2(-R + 6, -R + 16), "FRONT ↑", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.7, 0.3, 0.7))
	radar.draw_string(get_theme_default_font(), c + Vector2(-R + 6, R - 6), "%d m" % int(rng_m), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)


# ---------------------------------------------------------------- organigramme de recherche
func t_state(k: String) -> String:
	if C.tech_done.has(k):
		return "done"
	if C.tech_cur == k:
		return "cur"
	if not C.requires_ok(C.TECH[k]):
		return "lock"
	return "ok" if C.affordable(C.TECH[k].cost) else "poor"


func t_depth(k: String) -> int:
	var t: Dictionary = C.TECH[k]
	if t.has("requires") and C.TECH.has(t.requires):
		return 1 + t_depth(t.requires)
	return 0


# ce qu'une recherche débloque (bâtiments, vaisseaux)
func t_unlocks(k: String) -> String:
	var a: Array = []
	for b in C.BLD:
		if C.BLD[b].get("requires", "") == k:
			a.append(C.BLD[b].name)
	for u in S.UNITS:
		if S.UNITS[u].get("requires", "") == k:
			a.append(S.UNITS[u].name)
	return ", ".join(a)


func t_kids(p: String) -> Array:
	var out: Array = []
	for x in C.TECH:
		if C.TECH[x].get("requires", "") == p:
			out.append(x)
	return out


var rt_rows := {}


func rt_place(k: String, min_y: float) -> void:
	var d := t_depth(k)
	var y: float = maxf(rt_rows.get(d, 0.0), min_y)
	rt_pos[k] = Vector2(110 + 14 + d * (NW + 14), 6 + y)
	rt_rows[d] = y + NH + 8
	for c in t_kids(k):
		if not rt_pos.has(c):
			rt_place(c, y)


func layout_rtree() -> void:
	rt_pos.clear()
	rt_rows.clear()
	var roots: Array = []
	for k in C.TECH:
		if t_depth(k) == 0:
			roots.append(k)
	roots.sort_custom(func(a, b): return t_kids(a).size() > t_kids(b).size())
	for k in roots:
		rt_place(k, 0.0)
	var H := 0.0
	var W := 0.0
	for k in rt_pos:
		H = maxf(H, rt_pos[k].y + NH + 6)
		W = maxf(W, rt_pos[k].x + NW + 6)
	rtree.custom_minimum_size = Vector2(W, H)


func draw_rtree() -> void:
	var f := get_theme_default_font()
	var cols := {"done": OK, "cur": Color("ffd27a"), "ok": CY, "poor": Color("5fa8d4"), "lock": Color("5a6672")}
	var H := rtree.custom_minimum_size.y
	var root := Rect2(6, H * 0.5 - NH * 0.5, 104, NH)
	for k in rt_pos:
		var p: Vector2 = rt_pos[k]
		var t: Dictionary = C.TECH[k]
		var a: Vector2
		var done := true
		if t.has("requires"):
			a = rt_pos[t.requires] + Vector2(NW, NH * 0.5)
			done = C.tech_done.has(t.requires)
		else:
			a = root.position + Vector2(root.size.x, NH * 0.5)
		var b := p + Vector2(0, NH * 0.5)
		var pts := PackedVector2Array()
		for i in 13:
			pts.append(a.bezier_interpolate(a + Vector2(16, 0), b - Vector2(16, 0), b, i / 12.0))
		rtree.draw_polyline(pts, cols.done if done else cols.lock, 1.5, true)
	rtree.draw_rect(root, Color(0.02, 0.08, 0.13, 0.95))
	rtree.draw_rect(root, OK, false, 1.5)
	rtree.draw_string(f, root.position + Vector2(8, 20), "Centre de", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TXT)
	rtree.draw_string(f, root.position + Vector2(8, 35), "commandement", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TXT)
	rtree.draw_string(f, root.position + Vector2(8, 49), "actif", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, OK)
	for k in rt_pos:
		var p: Vector2 = rt_pos[k]
		var t: Dictionary = C.TECH[k]
		var st := t_state(k)
		var c: Color = cols[st]
		var r := Rect2(p, Vector2(NW, NH))
		var bg := Color(0.02, 0.08, 0.13, 0.92)
		if st == "done":
			bg = Color(0.08, 0.24, 0.16, 0.9)
		elif st == "cur":
			bg = Color(0.24, 0.19, 0.05, 0.9)
		rtree.draw_rect(r, bg)
		rtree.draw_rect(r, c, false, 2.0 if st == "ok" or st == "cur" else 1.0)
		var l2 := ""
		match st:
			"done":
				l2 = "✔ Acquise"
			"cur":
				l2 = "En cours : %d %%" % int(C.tech_p / t.time * 100.0)
			"lock":
				l2 = "Requiert " + C.TECH[t.requires].name
			_:
				l2 = C.cost_txt(t.cost)
		var u := t_unlocks(k)
		rtree.draw_string(f, p + Vector2(7, 16), t.name, HORIZONTAL_ALIGNMENT_LEFT, NW - 10, 12, Color("8f9aa6") if st == "lock" else Color("e6f1ff"))
		rtree.draw_string(f, p + Vector2(7, 31), l2, HORIZONTAL_ALIGNMENT_LEFT, NW - 10, 10, c)
		rtree.draw_string(f, p + Vector2(7, 45), ("Débloque : " + u) if u != "" else t.desc, HORIZONTAL_ALIGNMENT_LEFT, NW - 10, 10, Color("9fb4c8"))
		if st == "cur":
			rtree.draw_rect(Rect2(p + Vector2(5, NH - 5), Vector2((NW - 10) * minf(1.0, C.tech_p / t.time), 3)), cols.cur)


func rtree_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		for k in rt_pos:
			if Rect2(rt_pos[k], Vector2(NW, NH)).has_point(e.position):
				C.research(k)
				refresh()
				return


# ---------------------------------------------------------------- usine spatiale et flottes
func refresh_fleets() -> void:
	for u in unit_btn:
		var d: Dictionary = S.UNITS[u]
		var why := ""
		if d.has("requires") and not C.tech_done.has(d.requires):
			why = "Requiert : " + C.TECH[d.requires].name
		elif C.count_done("spatioport") == 0:
			why = "Spatioport requis"
		var b: Button = unit_btn[u]
		b.text = "%s — vitesse %d · blindage %d · attaque %d\n%s%s · %d s" % [d.name, d.speed, d.armor, d.attack, (why + " · ") if why != "" else "", C.cost_txt(d.cost), int(d.time)]
		b.disabled = why != "" or not C.affordable(d.cost)
	var q: Array = []
	for i in S.queue.size():
		var x: Dictionary = S.queue[i]
		q.append(S.UNITS[x.u].name + ("" if i > 0 else " (%d %%)" % int(x.p / S.UNITS[x.u].time * 100.0)))
	lbl_queue.text = "Production : " + (", ".join(q) if q.size() > 0 else "file vide")
	var cols_names: Array = []
	for id in S.col:
		cols_names.append(S.A(id).name)
	lbl_hangar.text = "Hangar (vaisseaux inactifs) : " + S.ships_txt(S.hangar) + ".\nAstéroïdes colonisés : " + (", ".join(cols_names) if cols_names.size() > 0 else "aucun") + "."
	# liste des flottes, reconstruite seulement si elle change
	var sig := str(S.fleets) + str(S.hangar) + str(S.emoves.size()) + str(S.col) + str(S.E.dead)
	for m in S.moves:
		sig += str(m.fid) + str(m.back)
	if sig == fleet_sig:
		return
	fleet_sig = sig
	for c in fleet_box.get_children():
		c.queue_free()
	if S.fleets.is_empty():
		var l := lbl("Aucune flotte. Créez-en une, puis incorporez-y les vaisseaux du hangar : seuls les vaisseaux en flotte reçoivent des ordres.", DIM, 12)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fleet_box.add_child(l)
		return
	for f in S.fleets:
		var box := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.02, 0.08, 0.13, 0.6)
		sb.border_color = Color(0.37, 0.83, 1.0, 0.25)
		sb.set_border_width_all(1)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		box.add_theme_stylebox_override("panel", sb)
		fleet_box.add_child(box)
		var vb := VBoxContainer.new()
		box.add_child(vb)
		var home: bool = f.loc == "home"
		var st := "En mission"
		if home:
			st = "Patrouille défensive" if f.ord == "def" else "Au hangar"
		vb.add_child(lbl("%s · %s" % [f.name, st], CY, 13))
		vb.add_child(lbl(S.ships_txt(f.ships) if home else "En route", TXT, 12))
		var fl := HFlowContainer.new()
		vb.add_child(fl)
		var id: int = f.id
		if home:
			for u in S.hangar:
				if S.hangar[u] > 0:
					var uu: String = u
					fl.add_child(small_btn("+1 %s (%d)" % [S.UNITS[u].name, S.hangar[u]], func(): S.fleet_add(id, uu)))
			if S.nships(S.hangar) > 0:
				fl.add_child(small_btn("+ Tout le hangar", func(): S.fleet_add(id, "*")))
			fl.add_child(small_btn("Défendre K-240" + (" ✔" if f.ord == "def" else ""), func(): S.fleet_order(id, "def")))
			if S.nships(f.ships) > 0:
				for e in S.emoves:
					var eid: int = e.id
					fl.add_child(small_btn("Intercepter (%s)" % S.ships_txt(e.ships), func(): S.fleet_order(id, "int:%d" % eid)))
				for a in S.MAP:
					var aid: String = a.id
					if S.owner(a) == "neutral":
						fl.add_child(small_btn("Coloniser " + a.name, func(): S.fleet_order(id, "col:" + aid)))
					elif S.owner(a) == "enemy":
						fl.add_child(small_btn("Attaquer " + a.name, func(): S.fleet_order(id, "atk:" + aid)))
				fl.add_child(small_btn("Renvoyer au hangar", func(): S.fleet_rem(id)))
			fl.add_child(small_btn("Dissoudre", func(): S.fleet_del(id)))
		else:
			fl.add_child(small_btn("Rentrer à la base", func(): S.fleet_order(id, "rtb")))


func small_btn(t: String, cb: Callable) -> Button:
	var b := btn(t, func():
		cb.call()
		fleet_sig = ""
		refresh())
	b.add_theme_font_size_override("font_size", 11)
	return b


# ---------------------------------------------------------------- carte stratégique (sur l'écran principal)
func show_map(on: bool) -> void:
	map.visible = on

	build_side.visible = not on
	do_layout()


func map_xf(p: Vector2) -> Vector2:
	var s := map.size
	var k := minf(s.x / 100.0, s.y / 70.0)
	var o := (s - Vector2(100, 70) * k) * 0.5
	return o + p * k


func draw_map() -> void:
	var s := map.size
	var f := get_theme_default_font()
	map.draw_rect(Rect2(Vector2.ZERO, s), Color(0.05, 0.04, 0.07))
	var k := minf(s.x / 100.0, s.y / 70.0)
	var sd := 7
	for i in 160:
		sd = (sd * 16807) % 2147483647
		var x := float(sd % 10000) / 10000.0
		sd = (sd * 16807) % 2147483647
		var y := float(sd % 10000) / 10000.0
		map.draw_circle(Vector2(x, y) * s, 0.8, Color(1, 1, 1, 0.35))
	var home: Dictionary = S.A("home")
	var hp := map_xf(Vector2(home.x, home.y))
	var kr: Dictionary = S.A("kronos")
	var kp := map_xf(Vector2(kr.x, kr.y))
	for a in S.MAP:
		if a.id != "home":
			map.draw_dashed_line(hp, map_xf(Vector2(a.x, a.y)), Color(0.37, 0.83, 1.0, 0.12), 1.0, 6.0)
	for m in S.emoves:
		var t: float = minf(1.0, m.p / m.dur)
		map.draw_line(kp, hp, Color(1, 0.35, 0.35, 0.6), 1.5)
		map.draw_circle(kp.lerp(hp, t), 5.0, BAD)
	for m in S.moves:
		var a: Dictionary = S.A(m.to) if m.to != "home" else kr
		var ap := map_xf(Vector2(a.x, a.y))
		if m.kind == "int" or m.kind == "ret":
			ap = hp.lerp(kp, 0.5)
		var t: float = minf(1.0, m.p / m.dur)
		var p: Vector2 = ap.lerp(hp, t) if m.back else hp.lerp(ap, t)
		map.draw_line(hp, ap, Color(0.37, 0.94, 0.63, 0.5), 1.5)
		map.draw_circle(p, 4.5, OK)
	# factions extraterrestres : couleur de la relation, traité
	if Fx != null:
		for fc in Fx.FAC:
			var fp := map_xf(Vector2(fc.x, fc.y))
			var fs: Dictionary = Fx.fac[fc.id]
			var rc: Color = BAD if fs.treaty == "guerre" else (OK if fs.treaty == "alliance" else fc.color)
			map.draw_colored_polygon(PackedVector2Array([fp + Vector2(0, -9), fp + Vector2(8, 0), fp + Vector2(0, 9), fp + Vector2(-8, 0)]), rc.darkened(0.4))
			map.draw_polyline(PackedVector2Array([fp + Vector2(0, -9), fp + Vector2(8, 0), fp + Vector2(0, 9), fp + Vector2(-8, 0), fp + Vector2(0, -9)]), rc, 1.5)
			map.draw_string(get_theme_default_font(), fp + Vector2(-70, 22), fc.name, HORIZONTAL_ALIGNMENT_CENTER, 140, 11, rc)
			map.draw_string(get_theme_default_font(), fp + Vector2(-70, 34), Fx.treaty_txt(fc.id), HORIZONTAL_ALIGNMENT_CENTER, 140, 10, DIM)
		# astéroïde-bélier en route
		if Fx.ram != null:
			var a0: Dictionary = S.A(Fx.ram.from)
			var ap := map_xf(Vector2(a0.x, a0.y))
			var t: float = minf(1.0, Fx.ram.p / Fx.ram.dur)
			var rp := ap.lerp(kp, t)
			map.draw_line(ap, kp, Color(1, 0.7, 0.3, 0.4), 1.5)
			map.draw_circle(rp, 7.0, Color("b0a89a"))
			map.draw_line(rp, rp - (kp - ap).normalized() * 22.0, Color(1, 0.6, 0.2, 0.9), 4.0)
	for st in S.sats:
		var t: float = 1.0 if st.on else st.p / st.dur
		map.draw_circle(hp.lerp(kp, t) + (Vector2(0, -14) if st.on else Vector2.ZERO), 3.0, AMB)
	for a in S.MAP:
		var p := map_xf(Vector2(a.x, a.y))
		var o: String = S.owner(a)
		var c: Color = Color("b0a89a")
		if o == "player":
			c = CY
		elif o == "enemy":
			c = BAD
		var r := (4.5 if a.id == "home" or a.id == "kronos" else 3.0) * k
		map.draw_circle(p, r, c.darkened(0.55))
		map.draw_arc(p, r, 0, TAU, 32, c, 3.0 if a.id == map_sel else 1.2)
		var sub: String = {"player": "à vous", "neutral": "neutre", "enemy": "pirates"}[o]
		map.draw_string(f, p + Vector2(-40, r + 16), a.name, HORIZONTAL_ALIGNMENT_CENTER, 80, 14, c)
		map.draw_string(f, p + Vector2(-50, r + 30), sub, HORIZONTAL_ALIGNMENT_CENTER, 100, 11, DIM)
		if a.has("income"):
			var inc: Array = []
			for rr in a.income:
				inc.append("+%s %s/s" % [str(a.income[rr]), C.RES[rr].name])
			map.draw_string(f, p + Vector2(-80, r + 43), ", ".join(inc), HORIZONTAL_ALIGNMENT_CENTER, 160, 10, Color("9fb4c8"))
	map.draw_string(f, Vector2(12, 22), "CARTE STRATÉGIQUE — Ceinture de Kuiper, secteur K-240", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, CY)
	var info := "Cliquez un astéroïde. Les ordres se donnent dans l’onglet Flottes."
	if map_sel != "":
		var a: Dictionary = S.A(map_sel)
		var o: String = S.owner(a)
		var what: String = {"player": "à vous", "neutral": "neutre : colonisable avec une flotte (un vaisseau reste en station)", "enemy": "colonie pirate : attaquez-la avec une flotte pour gagner la partie"}[o]
		var dd := "Votre base." if a.id == "home" else "Distance : %d · trajet d’un éclaireur : %d s." % [int(S.dist(a)), int(S.dist(a) / 8.0 * 2.0)]
		info = "%s — %s. %s" % [a.name, what, dd]
	map.draw_string(f, Vector2(12, s.y - 12), info, HORIZONTAL_ALIGNMENT_LEFT, s.x - 24, 13, TXT)


func map_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		map_sel = ""
		for a in S.MAP:
			if map_xf(Vector2(a.x, a.y)).distance_to(e.position) < 30.0:
				map_sel = a.id


# ---------------------------------------------------------------- fin de partie
func show_end(win: bool) -> void:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.1, 0.07, 0.96) if win else Color(0.1, 0.03, 0.03, 0.96)
	sb.border_color = OK if win else BAD
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	p.add_theme_stylebox_override("panel", sb)
	add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	p.add_child(vb)
	vb.add_child(lbl("VICTOIRE" if win else ("LA COLONIE A PÉRI" if S.lose_txt != "" else "K-240 EST TOMBÉE"), OK if win else BAD, 30))
	var txt := "Kronos est conquis : la menace pirate est anéantie et la ceinture de Kuiper est à vous."
	if win and S.win_kind == "arche":
		txt = "Le vaisseau-arche s’élance vers Alpha du Centaure. La ceinture de Kuiper, dernière station-service du Système solaire, a servi de tremplin à l’humanité."
	if not win and S.lose_txt != "":
		txt = S.lose_txt
	elif not win:
		txt = "Le bouclier a cédé, la flotte pirate a imposé un blocus, ses troupes ont forcé le bunker d’accès et se sont battues dans les galeries jusqu’au centre de commandement."
	var t := lbl(txt, TXT, 15)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 460
	vb.add_child(t)
	vb.add_child(btn("Continuer" if win else "Nouvelle partie", func():
		if win:
			p.queue_free()
		else:
			w.get_tree().reload_current_scene()))
	p.reset_size()
	p.position = (size - p.size) * 0.5


# ---------------------------------------------------------------- superviseurs (onglet de l'écran de gestion)
func build_supervisors() -> void:
	var vs := scroll_box(tabs, "Superviseurs")
	var info := lbl("Déléguez la gestion : un superviseur développe une colonie (revenus ×1,5 puis ×2 et ×2,5) contre un salaire ; le superviseur industriel gère l’économie de K-240 à votre place.", DIM, 12)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vs.add_child(info)
	sup_box = VBoxContainer.new()
	sup_box.add_theme_constant_override("separation", 6)
	vs.add_child(sup_box)


# ---------------------------------------------------------------- diplomatie (moniteur en haut à gauche)
func build_diplo() -> void:
	header(diplo, "DIPLOMATIE · FACTIONS DE LA CEINTURE")
	var sc := ScrollContainer.new()
	sc.position = Vector2(8, 34)
	sc.anchor_right = 1.0
	sc.anchor_bottom = 1.0
	sc.offset_right = -8
	sc.offset_bottom = -8
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	diplo.add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 6)
	sc.add_child(vb)
	lbl_diplo_log = lbl("", AMB, 12)
	lbl_diplo_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(lbl_diplo_log)
	diplo_box = VBoxContainer.new()
	diplo_box.add_theme_constant_override("separation", 6)
	vb.add_child(diplo_box)


# ---------------------------------------------------------------- opérations spéciales (onglet du commandement spatial)
func build_ops() -> void:
	var vo := scroll_box(tabs2, "Opérations")
	var info := lbl("Astéroïde-bélier : équipez une de vos colonies de propulseurs et précipitez-la sur Kronos. Vous perdez la colonie ; la flotte de Kronos peut dévier l’astéroïde.", DIM, 12)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vo.add_child(info)
	ops_box = VBoxContainer.new()
	ops_box.add_theme_constant_override("separation", 6)
	vo.add_child(ops_box)


func fac_box(par: Control) -> VBoxContainer:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.08, 0.13, 0.6)
	sb.border_color = Color(0.37, 0.83, 1.0, 0.25)
	sb.set_border_width_all(1)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	box.add_theme_stylebox_override("panel", sb)
	par.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	box.add_child(vb)
	return vb


func refresh_extra() -> void:
	if Fx == null:
		return
	sab_btn.text = "🕵 Envoyer un saboteur sur Kronos · " + C.cost_txt(Fx.SAB_COST)
	sab_btn.disabled = S.E.dead or S.sat_on().is_empty() or not C.affordable(Fx.SAB_COST)
	lbl_diplo_log.text = Fx.log[0] if Fx.log.size() > 0 else "Négociez avec les factions : cadeaux, traités, marché. Les clans exigent des tributs, les marchands et les savants font des offres."
	# --- diplomatie
	var sig := market_open
	for f in Fx.FAC:
		var st: Dictionary = Fx.fac[f.id]
		sig += "%s%d%s%s%s%d" % [f.id, int(st.rel / 5.0), st.treaty, str(st.demand.is_empty()), str(st.offer.is_empty()), int(C.stock.credits / 50.0)]
	if sig != diplo_sig:
		diplo_sig = sig
		for c in diplo_box.get_children():
			c.queue_free()
		for f in Fx.FAC:
			var id: String = f.id
			var st: Dictionary = Fx.fac[id]
			var vb := fac_box(diplo_box)
			vb.add_child(lbl("%s — %s · relation %s (%d)" % [f.name, Fx.treaty_txt(id), Fx.rel_txt(st.rel), int(st.rel)], f.color, 13))
			var pb := ProgressBar.new()
			pb.min_value = -100
			pb.max_value = 100
			pb.value = st.rel
			pb.show_percentage = false
			pb.custom_minimum_size.y = 6
			vb.add_child(pb)
			var d := lbl(f.desc, DIM, 11)
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vb.add_child(d)
			if not st.demand.is_empty():
				vb.add_child(lbl("⚠ Exigence : tribut de %d crédits (%d s)" % [int(st.demand.amount), int(st.demand.t)], BAD, 12))
			if not st.offer.is_empty():
				vb.add_child(lbl("Offre : %s (%d s)" % [st.offer.txt, int(st.offer.t)], OK, 12))
			var fl := HFlowContainer.new()
			vb.add_child(fl)
			if not st.demand.is_empty() or not st.offer.is_empty():
				fl.add_child(dbtn("✔ Accepter", func(): Fx.answer(id, true)))
				fl.add_child(dbtn("✕ Refuser", func(): Fx.answer(id, false)))
			fl.add_child(dbtn("Cadeau (50 cr.)", func(): Fx.gift(id)))
			if st.treaty == "guerre":
				fl.add_child(dbtn("Proposer la paix (150 cr.)", func(): Fx.make_peace(id)))
			else:
				for t in ["commerce", "paix", "alliance"]:
					if st.treaty != t:
						var tt: String = t
						fl.add_child(dbtn(Fx.TREATY[t].name, func(): Fx.propose(id, tt)))
				fl.add_child(dbtn("Déclarer la guerre", func(): Fx.declare_war(id)))
			if Fx.can_trade(id):
				fl.add_child(dbtn("Marché ▾" if market_open == id else "Marché ▸", func(): market_open = "" if market_open == id else id))
			if market_open == id and Fx.can_trade(id):
				var mk := GridContainer.new()
				mk.columns = 3
				vb.add_child(mk)
				for i in Fx.MARKET.size():
					var m: Array = Fx.MARKET[i]
					var ii: int = i
					mk.add_child(lbl("%d %s" % [m[1], C.RES[m[0]].name], TXT, 11))
					mk.add_child(dbtn("Acheter %d cr." % int(float(m[2]) * Fx.price_mult(id)), func(): Fx.buy(id, ii)))
					mk.add_child(dbtn("Vendre %d cr." % int(float(m[3]) / Fx.price_mult(id)), func(): Fx.sell(id, ii)))
	# --- superviseurs
	var ss := str(S.col.keys()) + str(Fx.sup) + str(Fx.industrial)
	if ss != sup_sig:
		sup_sig = ss
		for c in sup_box.get_children():
			c.queue_free()
		var vb := fac_box(sup_box)
		vb.add_child(lbl("Superviseur industriel de K-240 — %s" % ("en poste" if Fx.industrial else "vacant"), CY, 13))
		vb.add_child(lbl("Gère énergie, stockage, raffineries et moissonneuses · salaire %.1f cr./s" % Fx.IND_UPKEEP, DIM, 11))
		vb.add_child(dbtn("Renvoyer" if Fx.industrial else "Nommer", func(): Fx.toggle_industrial()))
		if S.col.is_empty():
			sup_box.add_child(lbl("Aucune colonie : colonisez Alpha, Beta ou Gamma avec une flotte (commandement spatial).", DIM, 12))
		for aid in S.col:
			var a: Dictionary = S.A(aid)
			var v2 := fac_box(sup_box)
			var id2: String = aid
			if Fx.sup.has(aid):
				v2.add_child(lbl("%s — superviseur niveau %d (revenus ×%s)" % [a.name, Fx.sup[aid].lvl, str(Fx.income_mult(aid))], OK, 13))
				v2.add_child(lbl("Salaire %.1f cr./s · niveau suivant toutes les 2 min (max 3)" % Fx.SUP_UPKEEP, DIM, 11))
			else:
				v2.add_child(lbl("%s — sans superviseur" % a.name, TXT, 13))
				v2.add_child(dbtn("Nommer un superviseur (%d cr.)" % int(Fx.SUP_COST), func(): Fx.hire(id2)))
	# --- opérations
	var so := str(S.col.keys()) + str(Fx.ram != null) + str(C.tech_done.has("propulseurs")) + str(S.E.dead)
	if so != ops_sig:
		ops_sig = so
		for c in ops_box.get_children():
			c.queue_free()
		if S.E.dead:
			ops_box.add_child(lbl("Kronos est conquis.", OK, 12))
		elif Fx.ram != null:
			ops_box.add_child(lbl("☄ Astéroïde-bélier en route vers Kronos.", AMB, 13))
		elif not C.tech_done.has("propulseurs"):
			ops_box.add_child(lbl("Recherche requise : Propulseurs d’astéroïde (après Propulsion ionique).", DIM, 12))
		elif S.col.is_empty():
			ops_box.add_child(lbl("Il faut une colonie (Alpha, Beta ou Gamma) à transformer en bélier.", DIM, 12))
		else:
			ops_box.add_child(lbl("Coût : " + C.cost_txt(Fx.RAM_COST), TXT, 12))
			for aid in S.col:
				var id3: String = aid
				ops_box.add_child(dbtn("☄ Précipiter %s sur Kronos" % S.A(aid).name, func(): Fx.launch_ram(id3)))
	if Fx.ram != null:
		var c0 = ops_box.get_child(0) if ops_box.get_child_count() > 0 else null
		if c0 is Label:
			c0.text = "☄ Astéroïde-bélier en route : impact dans %d s." % int(ceil(Fx.ram.dur - Fx.ram.p))


func dbtn(t: String, cb: Callable) -> Button:
	var b := btn(t, func():
		cb.call()
		diplo_sig = ""
		sup_sig = ""
		ops_sig = ""
		refresh())
	b.add_theme_font_size_override("font_size", 11)
	return b


# ---------------------------------------------------------------- survie à 40 UA et liaison avec la Terre (écran de gestion)
var lbl_phase: Label
var lbl_obj: Label
var lbl_life: Label
var bar_o2: ProgressBar
var bar_bat: ProgressBar
var bar_stab: ProgressBar
var cap_btn: Button
var mine_btn: Button
var bunk_btn: Button
var rep_btn: Button


func gauge(vs: Control, title: String) -> ProgressBar:
	vs.add_child(lbl(title, DIM, 11))
	var b := ProgressBar.new()
	b.custom_minimum_size.y = 9
	b.show_percentage = false
	vs.add_child(b)
	return b


func build_survival() -> void:
	var vs := scroll_box(tabs, "Survie")
	# phase, objectifs, actions de l'équipage
	lbl_phase = lbl("", AMB, 15)
	vs.add_child(lbl_phase)
	lbl_obj = lbl("", TXT, 12)
	lbl_obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vs.add_child(lbl_obj)
	var hb := HFlowContainer.new()
	vs.add_child(hb)
	cap_btn = btn("Réparer la capsule", func(): w.vie.repair_capsule(); refresh())
	mine_btn = btn("", func(): w.vie.toggle_mining(); refresh())
	bunk_btn = btn("", func(): w.vie.toggle_bunker(); refresh())
	rep_btn = btn("", func(): w.vie.toggle_repair(); refresh())
	for b in [cap_btn, mine_btn, bunk_btn, rep_btn]:
		hb.add_child(b)
	vs.add_child(HSeparator.new())
	vs.add_child(lbl("SYSTÈMES DE SURVIE", CY, 12))
	bar_o2 = gauge(vs, "Oxygène")
	bar_bat = gauge(vs, "Batteries")
	bar_stab = gauge(vs, "Stabilité de la rotation")
	lbl_life = lbl("", TXT, 12)
	lbl_life.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vs.add_child(lbl_life)
	vs.add_child(HSeparator.new())
	vs.add_child(lbl("SANTÉ DE LA POPULATION", CY, 12))
	bar_health = ProgressBar.new()
	bar_health.custom_minimum_size.y = 10
	bar_health.show_percentage = false
	vs.add_child(bar_health)
	lbl_surv = lbl("", TXT, 12)
	lbl_surv.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vs.add_child(lbl_surv)
	var vt := scroll_box(tabs, "Terre")
	var info := lbl("La Terre est à 40 UA : chaque message met plusieurs heures à arriver, un convoi des années. Livrez ses contrats (catapulte ou spatioport) pour gagner primes et réputation ; une colonie fiable reçoit des convois de ravitaillement.", DIM, 12)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vt.add_child(info)
	lbl_earth = lbl("", TXT, 13)
	lbl_earth.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vt.add_child(lbl_earth)
	ship_btn = btn("Expédier la cargaison vers la Terre", func(): Sv.ship(); refresh())
	vt.add_child(ship_btn)
	# vaisseau-arche : dans l'onglet Opérations du commandement spatial
	var vo: Control = tabs2.get_node("Opérations").get_child(0)
	vo.add_child(HSeparator.new())
	vo.add_child(lbl("VAISSEAU-ARCHE · ALPHA DU CENTAURE", CY, 12))
	lbl_ark = lbl("", TXT, 12)
	lbl_ark.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vo.add_child(lbl_ark)
	ark_btn = btn("", func(): Sv.ark_toggle(); refresh())
	vo.add_child(ark_btn)


func bar_col(b: ProgressBar, v: float, lo: float, hi: float) -> void:
	b.value = v
	var fill: StyleBoxFlat = b.get_theme_stylebox("fill").duplicate()
	fill.bg_color = OK if v >= hi else (AMB if v >= lo else BAD)
	b.add_theme_stylebox_override("fill", fill)


func refresh_life() -> void:
	var V = w.vie
	if V == null or lbl_phase == null:
		return
	lbl_phase.text = "PHASE %d — %s" % [V.phase, V.PHASE_NAME[V.phase].to_upper()]
	var ol: Array = []
	for o in V.objectives():
		ol.append(("✔ " if o[1] else "☐ ") + o[0])
	if V.phase >= 4:
		ol.append("Expansion : réacteurs, spatioport, commerce… et défense contre les pirates de Kronos.")
	elif V.phase == 1 and V.capsule_p >= 0.0 and not V.capsule_ok:
		ol.append("Réparation en cours : %d %%" % int(V.capsule_p / V.CAPSULE_TIME * 100.0))
	lbl_obj.text = "\n".join(ol)
	cap_btn.visible = not V.capsule_ok
	cap_btn.disabled = V.can_repair_capsule() != ""
	mine_btn.text = "⛏ Minage à la main : " + ("EN COURS" if V.mining else "arrêté")
	bunk_btn.text = "🛡 Mode bunker : " + ("ACTIVÉ" if V.bunker else "non")
	var nd: int = V.damaged().size()
	rep_btn.visible = nd > 0
	rep_btn.text = "🔧 Réparer à la main (%d dégât%s) : %s" % [nd, "s" if nd > 1 else "", "EN COURS" if V.repairing else "non"]
	var cap: Dictionary = C.caps()
	bar_col(bar_o2, C.stock.oxygene / maxf(1.0, cap.oxygene) * 100.0, 15.0, 35.0)
	bar_col(bar_bat, C.battery / maxf(1.0, C.bat_cap()) * 100.0, 15.0, 40.0)
	bar_col(bar_stab, 100.0 - V.instab, 40.0, 60.0)
	var L: Array = []
	L.append("%s · soleil %d° · %s" % ["☀ JOUR" if V.daylight > 0.0 else "☾ NUIT", int(V.sun_el), "rotation : 1 jour = %d s" % int(V.DAY)])
	L.append("Oxygène %d (%+.2f/s) · CO2 %.2f %% · eau %d · nourriture %d" % [int(C.stock.oxygene), C.rates.oxygene, V.co2, int(C.stock.eau), int(C.stock.nourriture)])
	L.append("Température de la base : %d °C%s" % [int(V.temp), " — FROID" if V.temp < 5.0 else (" — SURCHAUFFE" if V.temp > 38.0 else "")])
	L.append("Énergie : %d / %d · batteries %d / %d%s" % [int(C.energy.p), int(C.energy.c), int(C.battery), int(C.bat_cap()), " · générateur H2 %d" % int(C.h2_out) if C.h2_out > 0.0 else ""])
	L.append("Logement : %d / %d habitants" % [int(C.pop), int(C.housing())])
	L.append("Brèches : %d · bâtiments endommagés : %d" % [V.breaches(), nd])
	if V.phase >= 2:
		L.append("Micrométéorites : %s" % ("PLUIE EN COURS (%d s)" % int(ceil(V.meteor)) if V.meteor > 0.0 else ("prochaine pluie dans %d s" % int(V.meteor_t) if C.count_ok("radar") > 0 or V.meteor_t < 10.0 else "un radar préviendrait à l’avance")))
	L.append("Stabilité : instabilité %d %% · dérive orbitale %d %%%s" % [int(V.instab), int(V.drift), " — propulseurs d’attitude nécessaires" if V.instab > 50.0 else ""])
	lbl_life.text = "\n".join(L)


func refresh_survival() -> void:
	if Sv == null:
		return
	refresh_life()
	var T: Dictionary = C.tech_done
	bar_health.value = Sv.health
	var fill: StyleBoxFlat = bar_health.get_theme_stylebox("fill").duplicate()
	fill.bg_color = OK if Sv.health >= 60.0 else (AMB if Sv.health >= 35.0 else BAD)
	bar_health.add_theme_stylebox_override("fill", fill)
	var lines: Array = []
	lines.append("Santé : %d %%  (moral −%d)" % [int(Sv.health), int(Sv.morale_malus())])
	lines.append("Radiations : %.2f %s" % [Sv.dose, "— ÉRUPTION SOLAIRE (%d s)" % int(ceil(Sv.storm)) if Sv.storm > 0.0 else "(fond cosmique ; prochaine éruption dans ~%d s)" % int(Sv.storm_t)])
	lines.append("Protection : %s, %s%s" % ["blindage à l’eau ✔" if T.has("blindage_eau") else "pas de blindage à l’eau", "bouclier magnétique ✔" if T.has("bouclier_mag") else "pas de bouclier magnétique", ", le dôme absorbe 40 % pendant une éruption" if w.vie.at_war() else ""])
	lines.append("Microgravité : %s" % ("anneau centrifuge ✔" if T.has("anneau") else "perte osseuse et musculaire (recherchez l’anneau centrifuge)"))
	var V = w.vie
	lines.append("Abri : %d %% de la population à couvert (galeries, mode bunker)%s" % [int(V.shelter() * 100.0), " — recyclage à 99,9 % ✔" if T.has("recyclage") else ""])
	lines.append("")
	lines.append("Sol %s%s." % ["glacé (astéroïde peu dense) : la chaleur des réacteurs et raffineries fait fondre la glace sous les fondations" if Sv.icy() else "rocheux : risque d’affaissement faible sous les bâtiments chauds", " — fondations cryogéniques ✔" if T.has("fondations") else ""])
	var mining: int = C.count_done("moissonneuse") + C.count_done("foreuse")
	lines.append("Tas de gravats : %d engins de minage (seuil %d)%s." % [mining, 6 if Sv.icy() else 10, " — ancrage par harpons ✔" if T.has("harpons") else ""])
	lines.append("")
	lines.append("Journal : " + (" · ".join(Sv.log.slice(0, 3)) if Sv.log.size() > 0 else "rien à signaler."))
	lbl_surv.text = "\n".join(lines)
	# Terre
	var c: Dictionary = Sv.contract
	var e := ""
	if c.is_empty():
		e = "Message de la Terre en transit (latence ~%d h, arrivée dans %d s)." % [int(Sv.latency_h), int(ceil(Sv.incoming))]
	else:
		e = "Contrat : livrer %d %s · prime %d crédits · reste %d s.\nStock : %d." % [c.qty, C.RES[c.res].name, c.reward, int(ceil(c.t)), int(C.stock[c.res])]
	e += "\nRéputation auprès de la Terre : %d%s" % [Sv.rep, " — convois de ravitaillement réguliers" if Sv.rep >= 3 else " (3 pour obtenir des convois)"]
	lbl_earth.text = e
	ship_btn.disabled = Sv.can_ship() != ""
	# vaisseau-arche
	if C.count_done("chantier_arche") == 0:
		lbl_ark.text = "Recherchez « Propulsion à fusion », puis construisez le chantier interstellaire (écran principal, panneau Construire)."
		ark_btn.text = "Chantier interstellaire requis"
		ark_btn.disabled = true
	else:
		var need: Array = []
		for r in Sv.ARK_NEED:
			need.append("%.1f %s/s" % [Sv.ARK_NEED[r], C.RES[r].name])
		lbl_ark.text = "Assemblage : %d %%%s. Consomme %s ; environ %d min à plein régime." % [int(Sv.ark), " (en cours)" if Sv.ark_on else "", ", ".join(need), int(Sv.ARK_TIME / 60.0)]
		ark_btn.text = "Suspendre l’assemblage" if Sv.ark_on else "Lancer l’assemblage du vaisseau-arche"
		ark_btn.disabled = Sv.ark_won
