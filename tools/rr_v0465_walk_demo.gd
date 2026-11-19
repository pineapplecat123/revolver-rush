extends SceneTree
## v0.4.65：录小猫原地走路，再回待机并打一枪。用法：
##   godot --path . -w --resolution 720x1280 --fixed-fps 30 --quit-after 240 \
##     --write-movie /tmp/rr_v0465_cat_walk.avi -s tools/rr_v0465_walk_demo.gd
## 触发：只预览动画，不移动玩家格子。沙盒里也可点「预览走路动画」。

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
	for _i in 180:
		await process_frame
		ui = current_scene
		if ui == null:
			continue
		if ui.get("_dev_open") == true:
			ui._toggle_dev()
		if ui.get("state") != null and ui.state.sandbox_mode and ui.get("_dev_open") == false:
			break
	var cat = ui.get("_skel_player") if ui != null else null
	if cat != null:
		cat.set_walking(true)
	await create_timer(6.0).timeout
	if cat != null:
		cat.set_walking(false)
	await create_timer(1.6).timeout
	if cat != null:
		cat.play_shoot()
	await create_timer(1.8).timeout
	quit(0)
