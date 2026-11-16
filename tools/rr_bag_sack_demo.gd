extends SceneTree
## 录布袋倒出：装满袋，再点「倒出」。用法：
##   DISPLAY=:2 godot --path . -w --resolution 720x1280 --fixed-fps 30 --quit-after 240 \
##     --write-movie /tmp/rr_bag_sack_pour.avi -s tools/rr_bag_sack_demo.gd

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
	ui.state.dev_clear_bag()
	for aid in BAG_IDS:
		ui.state.sandbox_add_ammo(int(aid), 1, 0.0)
	ui._refresh()
	# 等子弹落进袋
	for _j in 50:
		await process_frame
	await create_timer(0.7).timeout
	if ui.has_method("_on_manual_load"):
		ui._on_manual_load()
	await create_timer(8.0).timeout
	quit(0)
