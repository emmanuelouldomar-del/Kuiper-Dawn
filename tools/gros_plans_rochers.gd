extends SceneTree
var t := 0.0
var main
var shot := 0
var out := ""
var targets := []
func _init():
	out = OS.get_cmdline_user_args()[0]
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(dt):
	t += dt
	if main.bridge != null and main.bridge.visible:
		main.toggle_bridge()
	if t < 2.0:
		return false
	if targets.is_empty():
		for nm in ["arche_0", "aiguille_0", "mesa_0", "cristaux_0", "arche_1"]:
			var mesh = main.rock_glb(nm)
			for c in main.get_children():
				if c is MultiMeshInstance3D and c.multimesh.mesh == mesh and c.multimesh.instance_count > 0:
					targets.append([nm, c.multimesh.get_instance_transform(0)])
					break
		print("CIBLES ", targets.size())
		if targets.is_empty():
			quit()
			return false
	if shot >= targets.size():
		quit()
		return false
	var xf: Transform3D = targets[shot][1]
	var p := xf.origin
	var up: Vector3 = main.up_at(p)
	var s := xf.basis.get_scale().x
	var size := s * (5.0 if String(targets[shot][0]).begins_with("arche") else (4.0 if String(targets[shot][0]).begins_with("aiguille") else 1.5))
	var side := up.cross(Vector3.RIGHT).normalized()
	var eye := p + side * size * 2.2 + up * size * 0.8
	var look := p + up * size * 0.4
	main.target = look
	main.dist = look.distance_to(eye)
	main.cb = Basis.looking_at(look - eye, up)
	if fmod(t, 1.0) < dt and t > 3.0:
		root.get_texture().get_image().save_png(out + "/rock_%d.png" % shot)
		shot += 1
	return false
