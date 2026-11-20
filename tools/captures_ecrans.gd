extends SceneTree
# captures de la passerelle : vue d'ensemble, puis chaque écran agrandi (sauf l'écran principal)
# Godot --path . --resolution 1600x900 --script tools/captures_ecrans.gd -- <dossier>
var t := 0.0
var main
var out := ""
var ids: Array = []
var i := -1
var t_next := 6.0
func _init():
	out = OS.get_cmdline_user_args()[0]
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(dt):
	t += dt
	if t < t_next:
		return false
	var B = main.bridge
	if i == -1:
		root.get_texture().get_image().save_png(out + "/passerelle.png")
		for m in B.mons:
			if m.id != "center":
				ids.append(m.id)
		i = 0
	else:
		root.get_texture().get_image().save_png(out + "/ecran_%s.png" % ids[i])
		B.focused = null
		B.fz_t = 0.0
		B.dim.color.a = 0.0
		B.do_layout()
		i += 1
	if i >= ids.size():
		quit()
		return false
	for m in B.mons:
		if m.id == ids[i]:
			B.focus_screen(m)
	t_next = t + 0.8
	return false
