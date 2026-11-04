extends SceneTree
## 实时（非录像）探针：多轮连射，打印每发出膛帧的 红圈仓 / 逻辑击发仓 / 红圈下显示的弹。
const WHITE := CombatConstants.WHITE_AMMO_ID
var _ui = null

func _initialize() -> void:
	call_deferred("_run")

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
	var st = _ui.state
	if _ui.get("_dev_open") == true:
		_ui._toggle_dev()
	st.sandbox_clear_enemies()
	for c in CombatConstants.SANDBOX_DEFAULT_DUMMY_CELLS:
		st.sandbox_spawn_dummy(99999, int(c))
	var layouts := [
		[16, 1, 22, 1, 26, 24],
		[16, -1, -1, 1, -1, 26],
		[1, -1, -1, -1, -1, -1],
		[16, 1, 16, 1, 16, 1],
		[23, 1, 16, 26, 1, 24],
		[21, 1, 16, -1, 26, 1],
		[1, 23, -1, 16, 1, -1],
		[20, 1, 19, 1, 24, 16],
	]
	var fps_env := OS.get_environment("PROBE_FPS")
	if fps_env != "":
		Engine.max_fps = int(fps_env)
	var sp_env := OS.get_environment("PROBE_SPEED")
	if sp_env != "":
		_ui._combat_speed = float(sp_env)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(OS.get_environment("PROBE_SEED")) if OS.get_environment("PROBE_SEED") != "" else 7
	for round_i in 16:
		var lay: Array = layouts[round_i % layouts.size()]
		var six: Array[int] = []
		for v in lay:
			six.append(int(v))
		st.dev_force_load(six)
		st.magazine.set_start(rng.randi_range(0, 5))
		_ui._refresh()
		await create_timer(0.3).timeout
		_ui._on_fire()
		var t := 0.0
		while t < 8.0 and (_ui._volley_ui_running or st.is_volley_pending()):
			await create_timer(0.03).timeout
			t += 0.03
		while _ui._volley_ui_running:
			await create_timer(0.03).timeout
		await create_timer(0.3).timeout
	var bad := 0
	for a in _ui.shot_audit:
		var ok: bool = a["ring"] == a["fired"] and a["shown"] == a["ammo"]
		if not ok:
			bad += 1
		print("AUDIT ring=%d fired=%d ammo=%d shown=%d flash=%d disk=%.2f %s" % [a["ring"], a["fired"], a["ammo"], a["shown"], a["flash"], a["disk_steps"], "OK" if ok else "MISMATCH"])
	print("AUDIT_SUMMARY shots=%d bad=%d" % [_ui.shot_audit.size(), bad])
	quit(0)
