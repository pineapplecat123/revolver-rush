extends SceneTree
## v0.3.8：经验条 + 无波次状态行 + 多层叠加半透明枪口进度条截图；再截一张升级三选一。
## xvfb-run -a godot --path . --resolution 720x1280 -s tools/shot_rr_xp.gd

const OUT_ABS := "/workspace/rr_xp.png"
const OUT_LV_ABS := "/workspace/rr_xp_levelup.png"


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
	cs.elapsed_sec = 75.0
	cs.gain_xp(cs.xp_needed() + 22)  # Lv1→Lv2 后再溢出 22
	cs._finish_one_levelup_reward()  # 截图 1：不弹窗，只看经验条
	# 多层：愤怒 3 层不同剩余（各自一条半透明条叠在一起，快到期那条偏红）+ 傲慢 2 层
	cs._muzzle_wrath_layers = [0.8, 2.4, 3.9]
	cs._muzzle_pride_layers = [4.5, 11.0]
	scene._refresh_muzzle_hud()
	scene._refresh()
	for _i in 6:
		await process_frame
	var texts: Array = []
	for n in scene._muzzle_chip_nodes:
		texts.append("%s bars=%d" % [(n["label"] as Label).text, (n["bars"] as Array).size()])
	print("[shot] Lv%d xp %d/%d chips %s" % [cs.level, cs.xp, cs.xp_needed(), texts])
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(OUT_ABS)
	img.save_png(ProjectSettings.globalize_path("res://docs/shots/rr_xp.png"))
	# 截图 2：经验满 → 暂停 + 三选一
	cs.gain_xp(cs.xp_needed() - cs.xp)
	scene._refresh()
	await create_timer(1.2).timeout
	var img2: Image = root.get_viewport().get_texture().get_image()
	img2.save_png(OUT_LV_ABS)
	print("[shot] levelup pending=", cs.reward_pending, " choices=", cs.reward_choices)
	quit(0)
