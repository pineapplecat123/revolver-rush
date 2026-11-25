extends SceneTree
## Native still fixture only. Calls actual synchronous fire/manual logic; no gameplay overrides are exported.
var ui
func _initialize() -> void:
	call_deferred("_run")
func _frames(n: int) -> void:
	for i in n: await process_frame
func _snap(name: String) -> void:
	ui._refresh()
	await create_timer(1.8).timeout
	await _frames(8)
	var image: Image = ui.get_viewport().get_texture().get_image()
	image.save_png("res://docs/shots/rr_v0485_%s.png" % name)
	print("V0485 ", name, " hp=", ui.state.enemies.map(func(e):return e.hp), " flames=", ui.state.volley_muzzle_buffs(), " planned=",ui.state.last_shot_planned_damage)
func _load(ids: Array[int]) -> void:
	var cs = ui.state
	cs._reset_muzzle()
	cs._volley_session=false
	cs._volley_pending=false
	cs._reset_volley_plan()
	cs.magazine.clear()
	cs.magazine.start_index=0
	for i in ids.size(): cs.magazine.set_slot(i,ids[i])
	cs.player_fire_gate_remaining=0.0
	cs._set_phase(cs.get_script().get_script_constant_map()["Phase"]["AWAIT_ACTION"])
func _fire() -> void:
	ui.state.fire_manual_tap()
func _run() -> void:
	var script: GDScript = load("res://scripts/combat/combat_state.gd")
	script.set("boot_sandbox",true)
	script.set("boot_campaign",false)
	change_scene_to_file("res://scenes/combat.tscn")
	await _frames(20)
	ui=current_scene
	ui.state.auto_enemy_advance=false
	ui.state.pace_after_fire=false
	ui.state.defer_impacts=false
	ui.state.enemies.clear()
	for cell in [3,6,8]:
		ui.state.dev_spawn_enemy(CombatConstants.DUMMY_ENEMY_ID,cell)
		var e: EnemyInstance=ui.state.enemies[-1]
		e.hp=1000
		e.max_hp=1000
		e.atk=0
	if ui._dev_open: ui._toggle_dev()
	_load([60,61,63,64,65,67])
	_fire()
	await _snap("total_six")
	_fire()
	await _snap("double_twelve")
	_fire()
	_fire()
	await _snap("detonate_all")
	_fire()
	await _snap("split_all")
	_load([62,51,56,66,59,67])
	_fire()
	await _snap("end_share")
	_load([55,49,40])
	_fire()
	_fire()
	await _snap("tail_arrives")
	_fire()
	await _snap("tail_cleared")
	quit()
