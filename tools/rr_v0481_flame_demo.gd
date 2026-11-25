extends SceneTree
## Actual manual-shot UI, seeded effects declared explicitly; no screenshot replacement.
var ui
var note: Label
var single := false
var prefix := "mixed"
func _initialize() -> void:
	call_deferred("_run")
func _frames(n: int) -> void:
	for i in n:
		await process_frame
func _stage(text: String) -> void:
	note.text = text
func _stamp(name: String) -> void:
	await _frames(3)
	ui.get_viewport().get_texture().get_image().save_png("res://docs/shots/rr_v0481_%s_%s.png" % [prefix, name])
	print("PROOF ",prefix," ",name," icons=",ui._muzzle_status_hud._icons.size()," envelope=",ui._muzzle_status_hud._flame.envelope," damage=",ui.state.last_shot_planned_damage," buffs=",ui.state.volley_muzzle_buffs())
func _fire() -> void:
	ui.state.player_fire_gate_remaining = 0.0
	ui._volley_ui_running = true
	var pack: Dictionary = ui._resolve_manual_fire_logic()
	await ui._present_manual_resolved(pack)
	ui._volley_ui_running = false
func _run() -> void:
	single = OS.get_cmdline_user_args().has("--single")
	prefix = "single" if single else "mixed"
	if OS.get_cmdline_user_args().has("--default-probe"):
		prefix = "default450"
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
	for i in range(1, 6 if single else 4):
		ui.state.magazine.set_slot(i, 49)
	ui.state._reset_muzzle()
	ui.state._reset_volley_plan()
	var resolver: GDScript = load("res://scripts/combat/fire_resolver.gd")
	ui.state._volley_muzzle_buffs = [resolver.make_flame(52, -1, 5, 1.0)] if single else [resolver.make_flame(40, -2, 3), resolver.make_flame(52, -1, 2, 1.0)]
	ui.state._set_phase(cs_script.get_script_constant_map()["Phase"]["AWAIT_ACTION"])
	if ui._dev_open:
		ui._toggle_dev()
	ui._refresh()
	note = Label.new()
	note.position = Vector2(14, 329)
	note.size = Vector2(690, 45)
	note.add_theme_font_size_override("font_size", 20)
	note.add_theme_color_override("font_color", Color.WHITE)
	note.add_theme_color_override("font_outline_color", Color.BLACK)
	note.add_theme_constant_override("outline_size", 4)
	note.z_index = 120
	ui.add_child(note)
	_stage("SEEDED: five layers. Persistent fire, not a timer.")
	await _stamp("creation")
	await _frames(120)
	_stage("WAITED 2s: still 5 layers; muzzle stays burning")
	await _stamp("wait_five")
	if OS.get_cmdline_user_args().has("--default-probe"):
		quit()
		return
	await _frames(60)
	_stage("FIRING zero-damage utility: no consumption or tracer")
	await _fire()
	_stage("ZERO damage: still FIVE icons / no tracer")
	await _stamp("zero_five")
	await _frames(90)
	for shot in (5 if single else 3):
		_stage("POSITIVE SHOT %d: watch icons and flaming bullet" % [shot + 1])
		await _fire()
		await _frames(5)
		var count: int = ui._muzzle_status_hud._icons.size()
		_stage("SHOT %d: damage %d, %d real icons remain" % [shot + 1, ui.state.last_shot_planned_damage, count])
		await _stamp("shot_%d_%d_layers" % [shot + 1, count])
		await _frames(90)
	await _frames(30)
	quit()
