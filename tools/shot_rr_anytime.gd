extends SceneTree
## mid-fight：已装弹、打过 1 发后两键仍可用（随时开火/装弹）。
## xvfb-run -a godot --path . --resolution 720x1280 -s tools/shot_rr_anytime.gd

const OUT_DIR := "res://docs/shots"
const OUT_ABS := "/workspace/rr_anytime.png"


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
	await create_timer(0.6).timeout
	var scene = current_scene
	scene._on_sin_picked(FireResolver.ID_WRATH)
	await create_timer(1.5).timeout
	scene.state.dev_spawn_enemy(2, 5)
	scene.state.enemies[0].hp = 80
	scene.state.enemies[0].max_hp = 80
	scene._refresh()
	# 手装 4 发
	for _i in 4:
		scene._on_manual_load()
		await create_timer(0.45).timeout
	# 点射 1 发（动画期间短暂锁键；等序列结束）
	scene._on_fire()
	await create_timer(2.8).timeout
	# 此时应可再装/再射
	var can_load: bool = scene.state.can_manual_load()
	var can_fire: bool = scene.state.can_fire()
	var busy: bool = scene._busy()
	print("ANYTIME can_manual=%s can_fire=%s busy=%s phase=%s loaded=%d btn_load_dis=%s btn_fire_dis=%s" % [
		can_load, can_fire, busy, scene.state.phase_name(),
		scene.state.magazine.loaded_count(),
		scene.btn_manual_load.disabled, scene.btn_fire.disabled
	])
	var img: Image = await _save_res("rr_anytime")
	img.save_png(OUT_ABS)
	print("COPIED %s" % OUT_ABS)
	quit(0)
