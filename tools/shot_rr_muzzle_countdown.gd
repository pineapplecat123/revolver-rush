extends SceneTree
## v0.3.5：枪口倒计时芯片截图（720×1280）。
## xvfb-run -a godot --path . --resolution 720x1280 -s tools/shot_rr_muzzle_countdown.gd

const OUT_DIR := "res://docs/shots"
const OUT_ABS := "/workspace/rr_muzzle_countdown.png"


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
	cs._muzzle_wrath = 2
	cs._muzzle_wrath_t = 3.2
	cs._muzzle_fire = true
	cs._muzzle_fire_t = 0.9
	cs._muzzle_pride = 1
	scene._refresh_muzzle_hud()
	scene._refresh()
	# 跑几帧让倒计时实时走（验证原地刷新）
	for _i in 12:
		await process_frame
	var texts: Array = []
	for n in scene._muzzle_chip_nodes:
		texts.append((n["label"] as Label).text)
	print("[shot] muzzle chips: ", texts)
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(OUT_ABS)
	img.save_png(ProjectSettings.globalize_path("%s/rr_muzzle_countdown.png" % OUT_DIR))
	print("[shot] saved ", OUT_ABS)
	quit(0)
