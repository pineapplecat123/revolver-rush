extends SceneTree
## Deterministic non-browser evidence. Seeds table-colored flame layers, then
## fires a zero-damage utility shot and positive shots through real manual UI.
var ui
const DT := 1.0 / 30.0
func _initialize() -> void:
	call_deferred("_run")
func _frames(n: int) -> void:
	for i in n:
		await process_frame
func _stamp(name: String) -> void:
	await _frames(2)
	ui.get_viewport().get_texture().get_image().save_png("res://docs/shots/rr_v0480_flames_%s.png" % name)
	print("FLAMES ", name, " groups=", ui.state.volley_muzzle_buffs(), " damage=", ui.state.last_shot_planned_damage)
func _fire() -> void:
	ui.state.player_fire_gate_remaining = 0.0
	ui._volley_ui_running = true
	var pack: Dictionary = ui._resolve_manual_fire_logic()
	await ui._present_manual_resolved(pack)
	ui._volley_ui_running = false
func _run() -> void:
	var cs_script: GDScript = load("res://scripts/combat/combat_state.gd")
	cs_script.set("boot_sandbox", true)
	cs_script.set("boot_campaign", false)
	change_scene_to_file("res://scenes/combat.tscn")
	await _frames(12)
	ui = current_scene
	ui.state.auto_enemy_advance = false
	ui.state.player_fire_gate_remaining = 0.0
	ui.state.enemies.clear()
	ui.state.dev_spawn_enemy(CombatConstants.DUMMY_ENEMY_ID, 3)
	ui.state.enemies[0].hp = 9999
	ui.state.enemies[0].max_hp = 9999
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
	await _frames(2)
	await _stamp("created_burst")
	await _frames(40)
	await _stamp("five_layers")
	await _fire()
	await _frames(20)
	await _stamp("zero_retains_five")
	await _frames(20)
	await _fire()
	await _frames(16)
	await _stamp("positive_three_layers")
	await _frames(20)
	await _fire()
	await _frames(16)
	await _stamp("positive_one_layer")
	await _frames(20)
	await _fire()
	await _frames(20)
	await _stamp("consumed")
	await _frames(15)
	quit()
