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
var cockpit                  # cockpit.gd
var picker: Control
var overlay: Control
var hint: Label
var home_vp := {}
var fz_from := Rect2()
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
var close_btn: Button
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
	# poste de pilotage en 3D : rendu dans un monde à part, affiché en fond
	cockpit = preload("res://cockpit.gd").new()
	add_child(cockpit)
	cockpit.setup(Vector2i(get_viewport().size))
	var view := TextureRect.new()
	view.texture = cockpit.cv.get_texture()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	# calque de sélection : clic sur un moniteur (le déployer) ou sur un bouton d'accoudoir
	picker = Control.new()
	picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	picker.mouse_filter = Control.MOUSE_FILTER_STOP
	picker.gui_input.connect(pick_input)
	add_child(picker)
	# écrans de jeu, chacun dans le SubViewport de son moniteur
	left = screen_panel()
	center = screen_panel(true)
	right = screen_panel()
	right2 = screen_panel()
	diplo = screen_panel()
	home_vp = {left: "left", center: "center", right: "right", right2: "right2", diplo: "lefttop"}
	for p in home_vp:
		p.theme = th_ui
		var vp: SubViewport = cockpit.screens[home_vp[p]].vp
		vp.add_child(p)
		p.set_anchors_preset(Control.PRESET_FULL_RECT)
		p.position = Vector2.ZERO
		p.size = Vector2(vp.size)
	build_left()
	build_center()
	build_right()
	build_right2()
	build_diplo()
	build_ops()
	build_survival()
	build_small_screens()
	for p in home_vp:
		var ov := Control.new()
		ov.set_anchors_preset(Control.PRESET_FULL_RECT)
		ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ov.draw.connect(func(): draw_corners(ov))
		p.add_child(ov)
	# écran agrandi : fond assombri, puis l'écran, puis le bouton Réduire
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			unfocus())
	add_child(dim)
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	close_btn = btn("✕  RÉDUIRE L’ÉCRAN  (Échap)", unfocus)
	close_btn.add_theme_color_override("font_color", Color("ffd6d2"))
	var cs: StyleBoxFlat = th_ui.get_stylebox("normal", "Button").duplicate()
	cs.bg_color = Color(0.16, 0.03, 0.03, 0.92)
	cs.border_color = Color("ff6b5f")
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.visible = false
	add_child(close_btn)
	hint = lbl("Cliquez sur un moniteur pour l’agrandir · boutons des accoudoirs : vitesse, vue 3D, pilote automatique", Color(0.6, 0.85, 1.0, 0.75), 13)
	hint.position = Vector2(16, 8)
	add_child(hint)
	resized.connect(do_layout)
	do_layout()
	refresh()


# ---------------------------------------------------------------- disposition
func do_layout() -> void:
	var V := size
	if V.x < 10:
		V = Vector2(get_viewport().size)
	cockpit.resize(Vector2i(V))
	close_btn.position = Vector2(V.x - 300, 6)
	close_btn.size = Vector2(280, 30)
	if focused != null:
		var full := Rect2(V.x * 0.03, V.y * 0.06, V.x * 0.94, V.y * 0.88)
		var t := ease(fz_t, -2.2)
		focused.position = fz_from.position.lerp(full.position, t)
		focused.size = fz_from.size.lerp(full.size, t)
	if map != null:
		map.position = Vector2(6, 34)
		map.size = center.size - Vector2(12, 34 + 40)
	if build_side != null:
		build_side.position = Vector2(6, 34)
		build_side.size = Vector2(SIDE_W, center.size.y - 34 - 40)
	if w != null:
		w.layout_screen()


# zone de la vue 3D dans l'écran principal (repère de l'écran) : à droite du panneau Construire
func screen_rect_local() -> Rect2:
	var off := SIDE_W + 6.0 if build_side != null and build_side.visible else 0.0
	return Rect2(Vector2(6 + off, 34), center.size - Vector2(12 + off, 34 + 40))


# zone de la vue 3D à l'écran, seulement quand l'écran principal est agrandi (sinon la souris ne pilote pas la caméra)
func screen_rect() -> Rect2:
	if focused != center or fz_t < 1.0 or fz_dir < 0.0:
		return Rect2()
	var r := screen_rect_local()
	return Rect2(center.global_position + r.position, r.size)


# ---------------------------------------------------------------- moniteurs : sélection et écran agrandi
func pick_input(e: InputEvent) -> void:
	if focused != null:
		return
	if e is InputEventMouseMotion:
		var h: Dictionary = cockpit.pick(e.position)
		var on: bool = not h.is_empty() and (h.kind == "button" or home_id(h.id) != null)
		picker.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var h: Dictionary = cockpit.pick(e.position)
		if h.is_empty():
			return
		if h.kind == "screen":
			var p = home_id(h.id)
			if p != null:
				focus_screen(p)
		else:
			press(h.id)


func home_id(id: String):
	for p in home_vp:
		if home_vp[p] == id:
			return p
	return null


# boutons des accoudoirs
func press(id: String) -> void:
	match id:
		"pause":
			set_speed(0.0)
		"x1":
			set_speed(1.0)
		"x2":
			set_speed(2.0)
		"x4":
			set_speed(4.0)
		"x8":
			set_speed(8.0)
		"tab":
			w.toggle_bridge()
		"bot":
			S.bot_toggle()
	refresh()


func focus_screen(p: Control) -> void:
	if focused != null:
		return
	focused = p
	fz_dir = 1.0
	fz_t = 0.0
	fz_from = cockpit.project_rect(home_vp[p])
	p.reparent(overlay, false)
	p.set_anchors_preset(Control.PRESET_TOP_LEFT)
	p.position = fz_from.position
	p.size = fz_from.size
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	picker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	close_btn.visible = true
	hint.visible = false
	do_layout()


func unfocus() -> void:
	if focused == null:
		return
	fz_dir = -1.0
	close_btn.visible = false


func animate_focus(dt: float) -> void:
	if focused == null:
		return
	fz_t = clampf(fz_t + fz_dir * dt / 0.35, 0.0, 1.0)
	dim.color.a = 0.75 * fz_t
	do_layout()
	if fz_dir < 0.0 and fz_t <= 0.0:
		var p := focused
		focused = null
		var vp: SubViewport = cockpit.screens[home_vp[p]].vp
		p.reparent(vp, false)
		p.set_anchors_preset(Control.PRESET_FULL_RECT)
		p.position = Vector2.ZERO
		p.size = Vector2(vp.size)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picker.mouse_filter = Control.MOUSE_FILTER_STOP
		hint.visible = true
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


func screen_panel(main := false) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.06, 0.11, 1.0) if not main else Color(0.01, 0.02, 0.04, 1.0)
	sb.border_color = Color("1d4d70")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	sb.shadow_color = Color(0.12, 0.5, 1.0, 0.12)
	sb.shadow_size = 10
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_STOP if not main else Control.MOUSE_FILTER_IGNORE
	return p


func header(par: Control, text: String) -> Label:
	var hb := ColorRect.new()
	hb.color = Color(0.37, 0.83, 1.0, 0.1)
	hb.position = Vector2(2, 2)
	hb.size = Vector2(4000, 26)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	par.add_child(hb)
	var l := Label.new()
	l.text = text
	l.position = Vector2(12, 5)
	l.add_theme_color_override("font_color", CY)
	l.add_theme_font_size_override("font_size", 14)
	par.add_child(l)
	par.clip_contents = true
	return l


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
	var info := lbl("Industrie polluante, extraction et stockage. Le chantier s’installe sur le prochain emplacement libre.", DIM, 11)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vc.add_child(info)
	for t in C.BLD:
		if t == "spatioport":
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


# ---------------------------------------------------------------- petits écrans du cockpit (accoudoirs et moniteurs secondaires)
func small_screen(id: String, title: String, col: Color) -> Control:
	var vp: SubViewport = cockpit.screens[id].vp
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r * 0.06, col.g * 0.06, col.b * 0.06, 1.0)
	sb.border_color = col.darkened(0.4)
	sb.set_border_width_all(3)
	p.add_theme_stylebox_override("panel", sb)
	p.theme = th_ui
	vp.add_child(p)
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.position = Vector2.ZERO
	p.size = Vector2(vp.size)
	var l := lbl(title, col, 22)
	l.position = Vector2(14, 8)
	p.add_child(l)
	return p


func build_small_screens() -> void:
	# accoudoir gauche : messages de la colonie
	var lg := small_screen("log", "MESSAGES", Color("5ff0a0"))
	lbl_log = lbl("", Color("5ff0a0"), 17)
	lbl_log.position = Vector2(14, 44)
	lbl_log.size = Vector2(472, 220)
	lbl_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lg.add_child(lbl_log)
	# accoudoir droit : pilote automatique
	var bt := small_screen("bot", "PILOTE AUTOMATIQUE", Color("ffb347"))
	lbl_bot = lbl("", Color("ffb347"), 19)
	lbl_bot.position = Vector2(14, 50)
	lbl_bot.size = Vector2(472, 210)
	lbl_bot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bt.add_child(lbl_bot)
	# moniteurs secondaires : systèmes, flux de données, énergie, alertes
	for id in ["sys", "energy", "alert"]:
		var col: Color = {"sys": CY, "lefttop": Color("3dffb0"), "energy": CY, "alert": Color("ff3ad0")}[id]
		var title: String = {"sys": "SYSTÈMES DE LA COLONIE", "lefttop": "FLUX DE DONNÉES", "energy": "ÉNERGIE · BOUCLIER", "alert": "ALERTES DE LA STATION"}[id]
		var p := small_screen(id, title, col)
		var c := Control.new()
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		c.draw.connect(func(): draw_deco(id, c, col))
		p.add_child(c)
		deco[id] = c


func draw_deco(id: String, c: Control, col: Color) -> void:
	var s := c.size
	var f := get_theme_default_font()
	var tt := Time.get_ticks_msec() / 1000.0
	match id:
		"sys":
			var items := [["RÉACTEUR He-3", C.eff], ["BOUCLIER", w.SHD_E / 100.0], ["MORAL", C.morale / 100.0], ["STOCKAGE FER", C.stock.fer / maxf(1.0, C.caps().fer)], ["RECHERCHE", (C.tech_p / C.TECH[C.tech_cur].time) if C.tech_cur != "" else 0.0]]
			for i in items.size():
				var y := 52.0 + i * 52.0
				c.draw_string(f, Vector2(18, y), items[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)
				c.draw_rect(Rect2(260, y - 18, s.x - 290, 18), Color(col.r, col.g, col.b, 0.15))
				c.draw_rect(Rect2(260, y - 18, (s.x - 290) * clampf(items[i][1], 0.0, 1.0), 18), col)
		"lefttop":
			for k in 3:
				var pts := PackedVector2Array()
				for i in 60:
					var x := 14.0 + i * (s.x - 28) / 59.0
					pts.append(Vector2(x, s.y * (0.35 + 0.2 * k) + sin(i * 0.4 + tt * (2.0 + k) + k) * 18.0 * (0.5 + 0.5 * sin(tt * 0.7 + i * 0.1))))
				c.draw_polyline(pts, Color(col.r, col.g, col.b, 0.9 - k * 0.25), 2.0)
			c.draw_string(f, Vector2(18, s.y - 16), "LIAISON KRONOS · %d paquets/s" % int(800 + 200 * sin(tt)), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
		"energy":
			var e: Dictionary = C.energy
			c.draw_string(f, Vector2(18, 70), "%d / %d" % [int(e.p), int(e.c)], HORIZONTAL_ALIGNMENT_LEFT, -1, 44, BAD if e.c > e.p else col)
			c.draw_string(f, Vector2(18, 104), "produits / demandés", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, DIM)
			var sh: String = "EFFONDRÉ" if w.SHD_DOWN > 0.0 else "%d %%" % int(w.SHD_E)
			c.draw_string(f, Vector2(18, 170), "BOUCLIER " + sh, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, BAD if w.SHD_DOWN > 0.0 else col)
			c.draw_rect(Rect2(18, 190, (s.x - 36) * w.SHD_E / 100.0, 14), col)
		"alert":
			var a: String = S.alert_txt()
			var blink := fmod(tt, 1.0) < 0.6
			if a == "":
				c.draw_string(f, Vector2(18, 90), "STATION · SURVEILLANCE", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, col)
				c.draw_string(f, Vector2(18, 130), "aucune menace immédiate", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, DIM)
			else:
				if blink:
					c.draw_string(f, Vector2(18, 86), "ALERTE ACTIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color("ff5a5a"))
				c.draw_multiline_string(f, Vector2(18, 130), a, HORIZONTAL_ALIGNMENT_LEFT, s.x - 36, 20, -1, col)


func set_speed(s: float) -> void:
	if s == 0.0:
		w.paused = true
	else:
		w.paused = false
		w.tscale = s


# ---------------------------------------------------------------- mise à jour
func _process(dt: float) -> void:
	if not visible:
		return
	animate_focus(dt)
	cockpit.update(dt, get_viewport().get_mouse_position(), Vector2(get_viewport().size))
	for id in deco:
		deco[id].queue_redraw()
	sweep = fmod(sweep + dt * 1.3, TAU)
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
	lbl_pop.text = "Habitants : %d / %d" % [int(C.pop), int(C.COLONY.housing)]
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
	cockpit.set_lit("pause", w.paused)
	for k in [[1.0, "x1"], [2.0, "x2"], [4.0, "x4"], [8.0, "x8"]]:
		cockpit.set_lit(k[1], not w.paused and w.tscale == k[0])
	cockpit.set_lit("bot", S.bot_on)
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
	vb.add_child(lbl("VICTOIRE" if win else "K-240 EST TOMBÉE", OK if win else BAD, 30))
	var txt := "Kronos est conquis : la menace pirate est anéantie et la ceinture de Kuiper est à vous."
	if win and S.win_kind == "arche":
		txt = "Le vaisseau-arche s’élance vers Alpha du Centaure. La ceinture de Kuiper, dernière station-service du Système solaire, a servi de tremplin à l’humanité."
	if not win:
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
func build_survival() -> void:
	var vs := scroll_box(tabs, "Survie")
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


func refresh_survival() -> void:
	if Sv == null:
		return
	var T: Dictionary = C.tech_done
	bar_health.value = Sv.health
	var fill: StyleBoxFlat = bar_health.get_theme_stylebox("fill").duplicate()
	fill.bg_color = OK if Sv.health >= 60.0 else (AMB if Sv.health >= 35.0 else BAD)
	bar_health.add_theme_stylebox_override("fill", fill)
	var lines: Array = []
	lines.append("Santé : %d %%  (moral −%d)" % [int(Sv.health), int(Sv.morale_malus())])
	lines.append("Radiations : %.2f %s" % [Sv.dose, "— TEMPÊTE DE RAYONS COSMIQUES (%d s)" % int(ceil(Sv.storm)) if Sv.storm > 0.0 else "(fond cosmique ; prochaine tempête dans ~%d s)" % int(Sv.storm_t)])
	lines.append("Protection : %s, %s, %s" % ["blindage à l’eau ✔" if T.has("blindage_eau") else "pas de blindage à l’eau", "bouclier magnétique ✔" if T.has("bouclier_mag") else "pas de bouclier magnétique", "le dôme absorbe 40 % pendant une tempête"])
	lines.append("Microgravité : %s" % ("anneau centrifuge ✔" if T.has("anneau") else "perte osseuse et musculaire (recherchez l’anneau centrifuge)"))
	lines.append("Besoins vitaux : eau %s, volatils %s%s" % ["MANQUE" if Sv.short_water else "ok", "MANQUE" if Sv.short_vol else "ok", " (recyclage à 99,9 % ✔)" if T.has("recyclage") else " (sans recyclage : forte consommation de glace)"])
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
