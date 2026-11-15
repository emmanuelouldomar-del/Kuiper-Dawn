extends SceneTree
# test : gros plans sur un char et un fantassin de chaque camp (captures dans le dossier passé en argument)
var t := 0.0
var main
var shot := 0
var out := ""
var spawned := false
var ok_t := -1.0
func _init():
	out = OS.get_cmdline_user_args()[0]
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func pick(kind: String, side: String) -> Dictionary:
	for F in main.war.FORM:
		if F.kind == kind and F.side == side and not F.dead and F.alive.size() > 0 and not F.get("tr", false):
			return F
	return {}
func _process(dt):
	t += dt
	if main.bridge != null and main.bridge.visible:
		main.toggle_bridge()
	if t > 1.0 and not spawned:
		spawned = true
		main.war.spawn("b", "tank", 0.35, 0.0)
		main.war.spawn("r", "tank", 0.65, 0.0)
		main.war.spawn("b", "rifle", 0.4, 48.0)
		main.war.spawn("r", "rifle", 0.6, -48.0)
	if t < 4.0:
		return false
	var kind := "tank" if shot < 2 else "rifle"
	var side := "b" if shot % 2 == 0 else "r"
	var F := pick(kind, side)
	if F.is_empty():
		shot += 1
		if shot >= 4:
			quit()
		return false
	var p: Vector3
	var fw: Vector3 = F.f
	var up: Vector3 = main.up_at(F.p)
	var dist := 24.0
	if kind == "tank":
		p = F.tanks[0].h.global_position
		fw = F.tanks[0].h.global_transform.basis.x.normalized()
	else:
		p = main.war.mpos(F, F.alive[0])
		dist = 4.5
	var sv := fw.cross(up).normalized()
	var eye := p + fw * dist * 0.75 + sv * dist * 0.55 + up * dist * 0.3
	var look := p + up * (1.8 if kind == "tank" else 1.0)
	main.target = look
	main.dist = look.distance_to(eye)
	main.cb = Basis.looking_at(look - eye, up)
	if ok_t < 0.0:
		ok_t = t
	if t - ok_t > 0.4:
		root.get_texture().get_image().save_png(out + "/close_%d.png" % shot)
		shot += 1
		ok_t = -1.0
		if shot >= 4:
			quit()
	return false
