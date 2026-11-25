extends SceneTree
## Seeded actual-UI stills of the upright muzzle flame. Not a random run.
var ui
var note: Label
func _initialize() -> void:
	call_deferred("_run")
func _frames(n: int) -> void:
	for i in n:
		await process_frame
func _stamp(name: String) -> void:
	await _frames(3)
	var img: Image = ui.get_viewport().get_texture().get_image()
	img.save_png("res://docs/shots/rr_v0482_%s.png" % name)
	var muzzle: Vector2 = ui._player_shot_origin_global()
	var crop := Rect2i(int(muzzle.x) - 140, int(muzzle.y) - 240, 280, 300)
	crop.position.x = clampi(crop.position.x, 0, img.get_width() - crop.size.x)
	crop.position.y = clampi(crop.position.y, 0, img.get_height() - crop.size.y)
	img.get_region(crop).save_png("res://docs/shots/rr_v0482_%s_muzzle.png" % name)
	print("UPRIGHT ", name, " muzzle=", muzzle, " envelope=", ui._muzzle_status_hud._flame.envelope, " icons=", ui._muzzle_status_hud._icons.size())
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
	note = Label.new()
	note.position = Vector2(14, 329)
	note.size = Vector2(690, 45)
	note.add_theme_font_size_override("font_size", 20)
	note.add_theme_color_override("font_color", Color.WHITE)
	note.add_theme_color_override("font_outline_color", Color.BLACK)
	note.add_theme_constant_override("outline_size", 4)
	note.z_index = 120
	ui.add_child(note)
	note.text = "UPRIGHT fire: 3 green + 2 gold layers, burning up"
	await _stamp("creation")
	await _frames(90)
	note.text = "WAITED: still 5 layers, flame stays upright"
	await _stamp("wait_five")
	await _frames(30)
	await _fire()
	note.text = "ZERO damage: 5 layers kept, no tracer"
	await _stamp("zero_five")
	await _frames(40)
	await _fire()
	note.text = "POSITIVE shot: 3 layers remain, flame smaller"
	await _stamp("after_one")
	await _frames(40)
	quit()
