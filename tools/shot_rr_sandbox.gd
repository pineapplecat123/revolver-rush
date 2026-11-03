extends SceneTree
## 沙盒截图：面板 + 战场（DPS/单次最大 HUD）。
## 用法：xvfb-run -a godot --path . --resolution 720x1280 -s tools/shot_rr_sandbox.gd

const OUT_DIR := "res://docs/shots"


func _initialize() -> void:
	call_deferred("_run")


func _save(name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, name])
	var err := img.save_png(path)
	print("SHOT %s err=%s size=%dx%d" % [path, err, img.get_width(), img.get_height()])


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var cs_script: GDScript = load("res://scripts/combat/combat_state.gd")
	cs_script.set("boot_sandbox", true)
	change_scene_to_file("res://scenes/combat.tscn")
	await create_timer(0.8).timeout
	var scene = current_scene
	await _save("rr_sandbox_panel")
	if scene.has_method("_sandbox_select_tab"):
		scene._sandbox_select_tab(1)
		await create_timer(0.2).timeout
		await _save("rr_sandbox_panel_muzzle")
		scene._sandbox_select_tab(0)
	scene._toggle_dev()
	await create_timer(0.3).timeout
	for _i in 4:
		scene._on_manual_load()
		await create_timer(0.4).timeout
	for _i in 3:
		scene._on_fire()
		await create_timer(0.5).timeout
	await create_timer(0.8).timeout
	await _save("rr_sandbox_board")
	# 墓碑：袋里有幽灵 → 幽灵先飞到转轮再一起射出
	scene.state.sandbox_add_ammo(20, 3, 0.0)
	scene.state.dev_force_load([19, -1, -1, -1, -1, -1] as Array[int])
	scene._refresh()
	await create_timer(0.6).timeout
	scene._on_fire()
	await create_timer(0.08).timeout
	await _save("rr_sandbox_tomb_gather")
	await create_timer(1.0).timeout
	quit()
