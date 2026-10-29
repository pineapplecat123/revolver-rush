extends SceneTree
## v0.3.8：临时罪孽寿命倒计时（袋内寿命环 + 转轮仓秒数）截图。
## xvfb-run -a godot --path . --resolution 720x1280 -s tools/shot_rr_temp_sin_timer.gd

const OUT_ABS := "/workspace/rr_temp_sin_timer.png"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://docs/shots")
	change_scene_to_file("res://scenes/combat.tscn")
	await create_timer(0.5).timeout
	var scene = current_scene
	scene._on_sin_picked(FireResolver.ID_WRATH)
	for _i in 20:
		await process_frame
	var cs = scene.state
	for e in cs.enemies:
		e.atk = 0
	var full: float = CombatConstants.TEMP_SIN_LIFETIME_SEC
	cs._bag_append(FireResolver.ID_WRATH, full)
	cs._bag_append(FireResolver.ID_WRATH, full * 0.55)
	cs._bag_append(FireResolver.ID_GREED, full * 0.18)
	cs._bag_append(FireResolver.ID_PRIDE, full * 0.8)
	cs.magazine.set_slot(0, FireResolver.ID_WRATH, 12.4)
	cs.magazine.set_slot(2, FireResolver.ID_PRIDE, 3.2)
	scene._refresh()
	for _i in 90:
		await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(OUT_ABS)
	img.save_png(ProjectSettings.globalize_path("res://docs/shots/rr_temp_sin_timer.png"))
	print("[shot] bag temp lifes: ", cs.temp_lifetimes_in_bag().filter(func(v): return v > 0.0), " mag0=", cs.magazine.slot_temp_life(0), " mag2=", cs.magazine.slot_temp_life(2))
	quit(0)
