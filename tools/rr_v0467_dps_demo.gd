extends SceneTree
## v0.4.67：拍转轮下方 DPS/伤害修正（收起控制台）。

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
	for _j in 8:
		await process_frame
	if ui != null and ui.state != null:
		if ui.state.enemies.size() > 0:
			ui.state._notify_enemy_damage(ui.state.enemies[0], 9, "")
			ui.state._notify_enemy_damage(ui.state.enemies[1] if ui.state.enemies.size() > 1 else ui.state.enemies[0], 12, "")
		ui.state._volley_muzzle_buffs = [
			{"id": "qishi", "effect_kind": "damage_pct", "stacks": 1, "source_ammo_id": CombatConstants.QISHI_AMMO_ID},
			{"id": "xuli", "effect_kind": "damage_mult", "stacks": 1, "source_ammo_id": CombatConstants.XULI_AMMO_ID},
			{"id": "huiwei", "effect_kind": "damage_flat", "amount": 8, "source_ammo_id": CombatConstants.HUIWEI_AMMO_ID},
		]
		ui.state.magazine.clear()
		ui.state.magazine.start_index = 0
		ui.state.magazine.set_slot(0, CombatConstants.BAIBAN_AMMO_ID)
		ui._update_sandbox_stats_hud()
	await process_frame
	await process_frame
	var hud = ui.get("_sb_stats_panel") if ui != null else null
	if hud is Control:
		print("HUD=", (hud as Control).get_global_rect())
		print("parent=", (hud as Control).get_parent().name if (hud as Control).get_parent() else "null")
	var wheel = ui.get_node_or_null("Margin/RootVBox/MidPanel/MidSection/MagCol/MagWheel")
	var action = ui.get_node_or_null("%ActionRow")
	var top = ui.get_node_or_null("Margin/RootVBox/TopPanel")
	if wheel: print("Wheel=", (wheel as Control).get_global_rect())
	if action: print("Action=", (action as Control).get_global_rect(), " h=", (action as Control).size.y)
	if top: print("Top=", (top as Control).get_global_rect())
	var img: Image = ui.get_viewport().get_texture().get_image()
	img.save_png("/tmp/rr_v0467_dps_under_wheel.png")
	print("saved /tmp/rr_v0467_dps_under_wheel.png ", img.get_width(), "x", img.get_height())
	quit(0)
