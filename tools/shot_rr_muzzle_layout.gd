extends SceneTree
## v0.3.8：转轮位置 vs 枪口芯片数量（0 / 1 / 3+）测量 + 截图。
## xvfb-run -a godot --path . --resolution 720x1280 -s tools/shot_rr_muzzle_layout.gd

const OUT_PREFIX := "/workspace/rr_layout_chips"


func _initialize() -> void:
	call_deferred("_run")


func _rect_str(c) -> String:
	if c == null:
		return "null"
	var r: Rect2 = c.get_global_rect()
	return "x=%.0f..%.0f w=%.0f cx=%.1f y=%.0f" % [r.position.x, r.end.x, r.size.x, r.get_center().x, r.position.y]


func _run() -> void:
	change_scene_to_file("res://scenes/combat.tscn")
	await create_timer(0.5).timeout
	var scene = current_scene
	scene._on_sin_picked(FireResolver.ID_WRATH)
	for _i in 30:
		await process_frame
	var cs = scene.state
	for e in cs.enemies:
		e.hp = 400
		e.max_hp = 400
		e.atk = 0
	var setups: Array = [
		{},
		{"w": [3.2]},
		{"w": [1.0, 2.6, 3.9], "f": [3.0], "p": [6.0, 11.0], "g": [2.0]},
	]
	var labels: Array = ["0", "1", "3"]
	for k in setups.size():
		var s: Dictionary = setups[k]
		cs._muzzle_wrath_layers = s.get("w", []).duplicate()
		cs._muzzle_fire_layers = s.get("f", []).duplicate()
		cs._muzzle_pride_layers = s.get("p", []).duplicate()
		cs._muzzle_greed_layers = s.get("g", []).duplicate()
		scene._refresh_muzzle_hud()
		scene._refresh()
		for _i in 6:
			await process_frame
		var wheel = scene.get_node_or_null("Margin/RootVBox/MidPanel/MidSection/MagCol/MagWheel")
		var col = scene.get_node_or_null("Margin/RootVBox/MidPanel/MidSection/MagCol")
		var bag = scene.get_node_or_null("Margin/RootVBox/MidPanel/MidSection/BagPanel")
		print("[layout] chips=%d entries=%d" % [scene._muzzle_chip_nodes.size(), cs.muzzle_status_entries().size()])
		print("[layout]   MagCol   ", _rect_str(col))
		print("[layout]   MagWheel ", _rect_str(wheel))
		print("[layout]   Muzzle   ", _rect_str(scene._muzzle_slot))
		print("[layout]   BagPanel ", _rect_str(bag))
		if scene.get("_disk") != null:
			print("[layout]   Disk     ", _rect_str(scene._disk))
		var img: Image = root.get_viewport().get_texture().get_image()
		var pre: String = OS.get_environment("RR_SHOT_PREFIX")
		if pre == "":
			pre = OUT_PREFIX
		img.save_png("%s%s.png" % [pre, labels[k]])
	quit(0)
