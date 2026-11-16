extends SceneTree
## v0.4.48：录小猫待机晃动。用法：
##   godot --path . -w --resolution 720x1280 --fixed-fps 30 --quit-after 240 \
##     --write-movie docs/shots/rr_v0448_cat_idle.avi -s tools/rr_v0448_idle_demo.gd

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
	# 尽快收起沙盒控制台，让小猫露出来
	for _i in 180:
		await process_frame
		ui = current_scene
		if ui == null:
			continue
		if ui.get("_dev_open") == true:
			ui._toggle_dev()
		if ui.get("state") != null and ui.state.sandbox_mode and ui.get("_dev_open") == false:
			break
	if ui != null and ui.get("_skel_player") != null:
		ui._skel_player.anim.play(&"idle")
	# 保持到 --quit-after 结束
	await create_timer(12.0).timeout
	quit(0)
