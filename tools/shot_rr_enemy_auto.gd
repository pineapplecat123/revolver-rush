extends SceneTree
## mid-fight：敌人已自动左移若干格，玩家两键仍可用。
## xvfb-run -a godot --path . --resolution 720x1280 -s tools/shot_rr_enemy_auto.gd

const OUT_DIR := "res://docs/shots"
const OUT_ABS := "/workspace/rr_enemy_auto.png"


func _initialize() -> void:
	call_deferred("_run")


func _save_res(name: String) -> Image:
	await process_frame
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, name])
	img.save_png(path)
	print("SHOT %s size=%dx%d" % [path, img.get_width(), img.get_height()])
	return img


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	change_scene_to_file("res://scenes/combat.tscn")
	await create_timer(0.5).timeout
	var scene = current_scene
	scene._on_sin_picked(FireResolver.ID_WRATH)
	await create_timer(1.2).timeout
	scene.state.dev_spawn_enemy(2, 8)
	scene.state.enemies[0].hp = 80
	scene.state.enemies[0].max_hp = 80
	# 放到更远格，方便看见自动左移
	for e in scene.state.enemies:
		if e.cell < 7:
			e.cell = 7
	scene._refresh()
	for _i in 4:
		scene._on_manual_load()
		await create_timer(0.35).timeout
	var cell0: int = scene.state.enemies_sorted_by_cell()[0].cell
	# 等自动推进 2 拍（加速等待：直接 tick + 也让 timer 跑）
	scene.state.tick_enemy_auto_step()
	scene._refresh()
	await create_timer(0.3).timeout
	scene.state.tick_enemy_auto_step()
	scene._refresh()
	await create_timer(0.3).timeout
	var cell1: int = scene.state.enemies_sorted_by_cell()[0].cell
	print("AUTO_MOVE cell %d -> %d can_fire=%s can_load=%s btnF=%s btnL=%s" % [
		cell0, cell1, scene.state.can_fire(), scene.state.can_manual_load(),
		not scene.btn_fire.disabled, not scene.btn_manual_load.disabled
	])
	scene._on_fire()
	await create_timer(1.8).timeout
	var img: Image = await _save_res("rr_enemy_auto")
	img.save_png(OUT_ABS)
	print("COPIED %s" % OUT_ABS)
	quit(0)
