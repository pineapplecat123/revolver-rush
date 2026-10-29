extends SceneTree
## RR 竖屏截图：主菜单 + rush! 战斗（三等分：战斗区 / 转轮+弹药袋 / 操作区）+ 奖励弹窗。
## 用法：xvfb-run -a godot --path . --resolution 720x1280 -s tools/shot_rr_portrait.gd

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
	change_scene_to_file("res://scenes/main.tscn")
	await create_timer(0.5).timeout
	await _save("rr_v030_main_menu")
	change_scene_to_file("res://scenes/combat.tscn")
	await create_timer(0.6).timeout
	var scene = current_scene
	await _save("rr_v030_sin_pick")
	scene._on_sin_picked(FireResolver.ID_WRATH)
	await create_timer(2.0).timeout
	# 打两只敌人看枪线/飙血：dev 加一只强盗 + 手动装弹 3 发
	scene.state.dev_spawn_enemy(2, 6)
	scene._refresh()
	for _i in 3:
		scene._on_manual_load()
		await create_timer(0.6).timeout
	var top: Control = scene.get_node("Margin/RootVBox/TopPanel")
	var mid: Control = scene.get_node("Margin/RootVBox/MidPanel")
	var bot: Control = scene.get_node("Margin/RootVBox/BottomPanel")
	print("THIRDS top=%s mid=%s bot=%s" % [top.get_global_rect(), mid.get_global_rect(), bot.get_global_rect()])
	print("MAG_LOADED=%d BAG=%d" % [scene.state.magazine.loaded_count(), scene.state.bag.size()])
	await _save("rr_v030_portrait_combat")
	scene._on_fire()
	await create_timer(0.55).timeout
	await _save("rr_v030_portrait_firing")
	await create_timer(3.0).timeout
	# 奖励弹窗适配
	scene.state.dev_kill_all_enemies()
	await create_timer(1.6).timeout
	await _save("rr_v030_reward")
	# 商店弹窗（假装第 5 波后）
	var cs = scene.state
	scene._set_reward_open(false)
	cs.skip_reward_for_gold()
	cs.wave_index = 5
	cs.rush_shop_done = false
	cs.gold = 60
	scene._open_rush_shop()
	await create_timer(0.4).timeout
	await _save("rr_v030_shop")
	scene._on_rush_shop_leave()
	await create_timer(0.3).timeout
	scene._on_next_wave()
	await create_timer(2.5).timeout
	scene._toggle_dev()
	await create_timer(0.3).timeout
	await _save("rr_v030_dev")
	quit(0)
