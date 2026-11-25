extends SceneTree
## One full-window still: largest 5-layer upright flame must leave top HUD readable.
var ui
func _initialize() -> void:
	call_deferred("_run")
func _frames(n: int) -> void:
	for i in n:
		await process_frame
func _run() -> void:
	var cs_script: GDScript = load("res://scripts/combat/combat_state.gd")
	cs_script.set("boot_sandbox", true)
	cs_script.set("boot_campaign", false)
	change_scene_to_file("res://scenes/combat.tscn")
	await _frames(20)
	ui = current_scene
	ui.state.auto_enemy_advance = false
	ui.state.enemies.clear()
	ui.state.dev_spawn_enemy(CombatConstants.DUMMY_ENEMY_ID, 6)
	ui.state.enemies[0].hp = 99999
	ui.state.enemies[0].max_hp = 99999
	ui.state.enemies[0].atk = 0
	ui.state.magazine.clear()
	ui.state.magazine.start_index = 0
	ui.state.magazine.set_slot(0, 45)
	for i in range(1, 4):
		ui.state.magazine.set_slot(i, 49)
	ui.state._reset_muzzle()
	ui.state._reset_volley_plan()
	var resolver: GDScript = load("res://scripts/combat/fire_resolver.gd")
	ui.state._volley_muzzle_buffs = [resolver.make_flame(40, -2, 3), resolver.make_flame(52, -1, 2, 1.0)]
	ui.state._set_phase(cs_script.get_script_constant_map()["Phase"]["AWAIT_ACTION"])
	if ui._dev_open:
		ui._toggle_dev()
	ui._refresh()
	await _frames(12)
	var img: Image = ui.get_viewport().get_texture().get_image()
	img.save_png("res://docs/shots/rr_v0484_wait_five.png")
	var muzzle: Vector2 = ui._player_shot_origin_global()
	print("V0484 muzzle=", muzzle, " envelope=", ui._muzzle_status_hud._flame.envelope, " icons=", ui._muzzle_status_hud._icons.size(), " flame_z=", ui._muzzle_status_hud.z_index, " hud_z=", ui.Z_TOP_HUD)
	quit()
