extends SceneTree
## v0.3.7：多层独立计时枪口截图。
## xvfb-run -a godot --path . --resolution 720x1280 -s tools/shot_rr_muzzle_layers.gd

const OUT_DIR := "res://docs/shots"
const OUT_ABS := "/workspace/rr_muzzle_layers.png"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	change_scene_to_file("res://scenes/combat.tscn")
	await create_timer(0.5).timeout
	var scene = current_scene
	scene._on_sin_picked(FireResolver.ID_WRATH)
	var guard := 0
	while scene._wave_bannering and guard < 400:
		await process_frame
		guard += 1
	var cs = scene.state
	for e in cs.enemies:
		e.hp = 400
		e.max_hp = 400
		e.atk = 0
	# 两层愤怒（旧层较短）+ 一层火 + 一层傲慢
	cs._muzzle_wrath_layers = [2.1, 3.8]
	cs._muzzle_fire_layers = [1.5]
	cs._muzzle_pride_layers = [9.4]
	scene._refresh_muzzle_hud()
	scene._refresh()
	for _i in 8:
		await process_frame
	var texts: Array = []
	for n in scene._muzzle_chip_nodes:
		texts.append((n["label"] as Label).text)
	print("[shot] muzzle chips: ", texts)
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(OUT_ABS)
	img.save_png(ProjectSettings.globalize_path("%s/rr_muzzle_layers.png" % OUT_DIR))
	print("[shot] saved ", OUT_ABS)
	quit(0)
