extends SceneTree
## v0.4.34：小石头逐步合成石头 + 全身燃烧烟火。

const PEBBLE := 32

var _ui
var _title: Label

func _initialize() -> void:
	call_deferred("_run")

func _wait_busy(max_sec: float) -> void:
	var t := 0.0
	await create_timer(0.08).timeout
	while t < max_sec:
		var busy := false
		if _ui != null:
			busy = bool(_ui._firing) or bool(_ui._volley_ui_running) or bool(_ui._wheel_animating)
			if _ui.state != null and _ui.state.is_volley_pending():
				busy = true
			if _ui._in_flight_shots > 0:
				busy = true
		if not busy:
			await create_timer(0.2).timeout
			break
		await process_frame
		t += 1.0 / 30.0

func _banner(text: String) -> void:
	if _title == null:
		_title = Label.new()
		_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_title.add_theme_font_size_override("font_size", 22)
		_title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55))
		_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_title.add_theme_constant_override("outline_size", 8)
		_title.z_index = 200
		_title.position = Vector2(10, 52)
		_title.size = Vector2(700, 100)
		_ui.add_child(_title)
	_title.text = text

func _run() -> void:
	var cs_script: GDScript = load("res://scripts/combat/combat_state.gd")
	cs_script.set("boot_sandbox", true)
	change_scene_to_file("res://scenes/combat.tscn")
	for _i in 90:
		await process_frame
		_ui = current_scene
		if _ui != null and _ui.get("state") != null and _ui.state.sandbox_mode:
			break
	await create_timer(0.3).timeout
	if _ui._dev_open:
		_ui._toggle_dev()
	var st = _ui.state
	st.player_hp = 99999
	st.sandbox_clear_enemies()
	st.sandbox_spawn_dummy(80, 5)
	_banner("1 小石头→石头：右侧小石头逐步飞入合成，再打出石头")
	st.dev_force_load([PEBBLE, PEBBLE, PEBBLE, PEBBLE, -1, -1] as Array[int])
	st.magazine.set_start(0)
	_ui._combat_speed = 0.85
	_ui._refresh()
	await create_timer(0.7).timeout
	# 不随机转：直接逐步合并 → 开火，合并过程更易看清
	_ui._display_hold.clear()
	_ui._snap_disk_to_logic()
	var run: int = st.peek_pebble_merge_run()
	await _ui._play_pebble_merge_sequence(run)
	await create_timer(0.35).timeout
	var pack: Dictionary = _ui._resolve_fire_logic()
	for rec in pack.get("shots", []):
		if _ui.is_chamber_shot(rec):
			_ui._display_hold[int(rec["slot"])] = int(rec.get("ammo_id", -1))
	_ui._refresh_mag_contents()
	await _ui._present_resolved_fire_async(pack)
	if st.is_volley_pending():
		await _ui._run_volley_autofire(pack.get("shots", []).is_empty())
	_ui._display_hold.clear()
	_ui._volley_ui_running = false
	_ui._snap_disk_to_logic()
	_ui._refresh()
	await create_timer(0.9).timeout

	_banner("2 燃烧：全身火焰 + 上升黑烟（跟随走动）")
	st.sandbox_clear_enemies()
	st.sandbox_spawn_dummy(200, 7)
	await create_timer(0.25).timeout
	_ui._refresh()
	await create_timer(0.15).timeout
	var e = st.enemies[0] if not st.enemies.is_empty() else null
	if e != null:
		e.burn_stacks = 8
		e.burn_peak = 8
		e.walking = true
		if e.pos_x < -100.0:
			e.pos_x = float(e.cell)
	_ui._refresh()
	_ui._update_burn_vfx()
	await create_timer(0.4).timeout
	for k in 120:
		if e != null and is_instance_valid(e) and e.is_alive():
			e.pos_x = maxf(1.8, e.pos_x - 0.016)
			e.walking = true
			e.burn_stacks = 8
		_ui._update_enemy_animal_motion()
		_ui._update_burn_vfx()
		await process_frame
	await create_timer(0.8).timeout
	print("DEMO_DONE v0.4.34")
	quit(0)
