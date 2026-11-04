extends SceneTree
## 实时测 连发窗 / 倾泻 在一键连射 + 0.25s/发 + 装弹锁 下的实际贡献。
const W := 1
const BURST := 21
const DUMP := 23
var _ui = null

func _initialize() -> void:
	call_deferred("_run")

func _dummy_dmg(st) -> int:
	var tot := 0
	for e in st.enemies:
		if e != null:
			tot += e.max_hp - e.hp
	return tot

func _case(name: String, six: Array, spam: bool, start: int = 0) -> void:
	var st = _ui.state
	st.sandbox_clear_muzzle()
	st.sandbox_clear_enemies()
	st.sandbox_spawn_dummy(99999, 3)
	st.burst_window_remaining = 0.0
	st.player_fire_gate_remaining = 0.0
	var arr: Array[int] = []
	for v in six:
		arr.append(int(v))
	st.dev_force_load(arr)
	st.magazine.set_start(start)
	# 关掉随机预转，固定起点，方便比较
	_ui._refresh()
	await create_timer(0.3).timeout
	var t0 := Time.get_ticks_msec()
	_ui._on_fire()
	var free_shots := 0
	var press_ok_while_window := 0
	var press_blocked_btn := 0
	var t := 0.0
	var volley_end_ms := -1
	var window_seen_after := false
	while t < 4.0:
		await create_timer(0.1).timeout
		t += 0.1
		if volley_end_ms < 0 and not _ui._volley_ui_running and not st.is_volley_pending() and not st.is_dump_pending():
			volley_end_ms = Time.get_ticks_msec() - t0
			if st.is_burst_window_active():
				window_seen_after = true
		if spam:
			if st.is_burst_window_active() and not _ui._volley_ui_running:
				_ui._refresh()
				if _ui.btn_fire.disabled:
					press_blocked_btn += 1
				var before: int = _dummy_dmg(st)
				_ui._on_fire()
				await process_frame
				if _dummy_dmg(st) > before:
					free_shots += 1
	print("BDPROBE %-28s volley_ms=%5d dmg=%3d free_shots_after_volley=%d btn_disabled_presses=%d window_open_at_end=%s" % [name, volley_end_ms, _dummy_dmg(st), free_shots, press_blocked_btn, window_seen_after])

func _run() -> void:
	var cs_script: GDScript = load("res://scripts/combat/combat_state.gd")
	cs_script.set("boot_sandbox", true)
	change_scene_to_file("res://scenes/combat.tscn")
	for _i in 90:
		await process_frame
		_ui = current_scene
		if _ui != null and _ui.get("state") != null and _ui.state.sandbox_mode:
			break
	await create_timer(0.4).timeout
	if _ui.get("_dev_open") == true:
		_ui._toggle_dev()
	# 关掉预转：把 spin 的随机交给固定起点（直接比较节奏）
	_ui.state.auto_enemy_advance = true
	for _rep in 3:
		await _cases()
	quit(0)

func _cases() -> void:
	await _case("6x平庸", [W, W, W, W, W, W], false)
	await _case("连发在第1发+5平庸", [BURST, W, W, W, W, W], true)
	await _case("连发在第6发(最后)+5平庸", [W, W, W, W, W, BURST], true)
	await _case("连发x2(第5,6)+4平庸", [W, W, W, W, BURST, BURST], true)
	await _case("连发单发(只装1发)", [BURST, -1, -1, -1, -1, -1], true)
	await _case("倾泻在第1发+5平庸", [DUMP, W, W, W, W, W], false)
	await _case("倾泻在第3发+5平庸", [W, W, DUMP, W, W, W], false)
	await _case("4平庸(不满)", [W, W, -1, W, W, -1], false)
