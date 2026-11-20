extends SceneTree
## 弹药袋静帧：沙盒装满后等沉降，截全屏和袋区。
## xvfb-run -a godot --path . --resolution 720x1280 --quit-after 600 -s tools/rr_v0475_bag_shots.gd
## 用户参数：-- --tag before|after

const BAG_IDS := [
	40, 40, 41, 41, 42, 42, 43, 43, 44, 44,
	45, 45, 46, 46, 47, 47, 48, 49, 49, 50,
	51, 52, 53, 54, 40, 41, 42, 44, 49, 50,
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var tag := "shot"
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--tag="):
			tag = a.substr(6)
		elif a == "before" or a == "after":
			tag = a
	var cs_script: GDScript = load("res://scripts/combat/combat_state.gd")
	cs_script.set("boot_sandbox", true)
	var err := change_scene_to_file("res://scenes/combat.tscn")
	if err != OK:
		push_error("change_scene failed %s" % err)
		quit(1)
		return
	var ui = null
	for _i in 180:
		await process_frame
		ui = current_scene
		if ui == null:
			continue
		if ui.get("_dev_open") == true:
			ui._toggle_dev()
		if ui.get("state") != null and ui.state.sandbox_mode and ui.get("_dev_open") == false:
			break
	if ui == null or ui.get("state") == null:
		push_error("no combat ui")
		quit(1)
		return
	if ui.has_method("_fit_combat_viewport"):
		ui._fit_combat_viewport(Vector2(720, 1280))
	ui.state.dev_clear_bag()
	for aid in BAG_IDS:
		ui.state.sandbox_add_ammo(int(aid), 1, 0.0)
	ui._refresh()
	for _j in 90:
		await process_frame
	await _stamp(ui, "rr_v0475_bag_%s" % tag)
	if tag == "after":
		if ui.has_method("_on_manual_load"):
			ui._on_manual_load()
		for _k in 40:
			await process_frame
		await _stamp(ui, "rr_v0475_bag_after_partial")
		for _k2 in 50:
			await process_frame
		await _stamp(ui, "rr_v0475_bag_after_poured")
	print("bag_shot_done tag=", tag)
	quit(0)


func _stamp(ui, name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = ui.get_viewport().get_texture().get_image()
	var full := "/tmp/%s.png" % name
	img.save_png(full)
	print("saved ", full, " ", img.get_width(), "x", img.get_height())
	var bag = ui.get("bag_panel")
	if bag != null and bag is Control:
		var r: Rect2 = (bag as Control).get_global_rect()
		var x := maxi(0, int(r.position.x) - 8)
		var y := maxi(0, int(r.position.y) - 8)
		var w := mini(img.get_width() - x, int(r.size.x) + 16)
		var h := mini(img.get_height() - y, int(r.size.y) + 16)
		if w > 8 and h > 8:
			var crop := img.get_region(Rect2i(x, y, w, h))
			var cp := "/tmp/%s_crop.png" % name
			crop.save_png(cp)
			print("saved ", cp, " ", w, "x", h, " at ", x, ",", y)
