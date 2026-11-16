extends SceneTree
## v0.4.50：拍一张装满子弹外形的弹药袋。用法：
##   godot --path . -w --resolution 720x1280 -s tools/rr_v0449_shot.gd

const BAG_IDS := [
	1, 1, 1, 1, 40, 40, 40, 41, 41, 41,
	42, 42, 42, 43, 43, 43, 44, 44, 44,
	45, 45, 45, 46, 46, 46, 1, 40, 42, 43, 44,
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var cs_script: GDScript = load("res://scripts/combat/combat_state.gd")
	cs_script.set("boot_sandbox", true)
	var err := change_scene_to_file("res://scenes/combat.tscn")
	if err != OK:
		push_error("change_scene failed %s" % err)
		quit(1)
		return
	var ui = null
	for _i in 90:
		await process_frame
		ui = current_scene
		if ui != null and ui.get("state") != null and ui.state.sandbox_mode:
			break
	await create_timer(0.4).timeout
	ui = current_scene
	if ui == null or ui.get("state") == null:
		push_error("no combat ui")
		quit(1)
		return
	# 收起沙盒控制台，让袋完全露出来
	if ui.get("_dev_open") == true:
		ui._toggle_dev()
	# 清空袋后再加一组弹，凑满一袋
	ui.state.dev_clear_bag()
	for aid in BAG_IDS:
		ui.state.sandbox_add_ammo(int(aid), 1, 0.0)
	ui._refresh()
	# 等物理落稳
	for _j in 120:
		await process_frame
	await create_timer(1.6).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		push_error("no image")
		quit(1)
		return
	var out := ProjectSettings.globalize_path("res://docs/shots/rr_v0450_bag_bullets.png")
	var serr := img.save_png(out)
	print("SHOT_RESULT=%s path=%s size=%sx%s balls=%s" % [
		serr, out, img.get_width(), img.get_height(),
		ui._bag_physics.ball_count() if ui._bag_physics else -1
	])
	quit(0 if serr == OK else 1)
