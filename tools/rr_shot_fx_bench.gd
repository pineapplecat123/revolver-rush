extends SceneTree
## v0.4.30 弹道压力：直接并发拉起大量 _animate_shot_projectile（火药+罪孽），测池化前后。
## RR_NO_SHOT_POOL=1 关池。DISPLAY=:99 godot --path . -s tools/rr_shot_fx_bench.gd

var _ui
var _frames: Array = []
var _cpu: Array = []
var _last := 0
var _frame_i := 0
var _phase := 0
var _spawned := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var cs_script: GDScript = load("res://scripts/combat/combat_state.gd")
	cs_script.set("boot_sandbox", true)
	change_scene_to_file("res://scenes/combat.tscn")
	for _i in 90:
		await process_frame
		_ui = current_scene
		if _ui != null and _ui.get("state") != null and _ui.state.sandbox_mode:
			break
	await create_timer(0.2).timeout
	if _ui.get("_dev_open") == true:
		_ui._toggle_dev()
	var st = _ui.state
	st.player_hp = 99999
	st.sandbox_clear_enemies()
	st.spawn_paused = true
	for k in 10:
		st.sandbox_spawn_dummy(99999, 2 + (k % 7))
	_ui._refresh()
	await process_frame
	if OS.get_environment("RR_NO_SHOT_POOL") == "1":
		_ui.shot_fx_pool_enabled = false
	# Also optionally skip shared caches to approximate old alloc path
	print("BENCH_SHOT pool=%s" % str(_ui.shot_fx_pool_enabled))
	_last = Time.get_ticks_usec()
	_phase = 1

func _fire_burst() -> void:
	var from_g: Vector2 = _ui._player_shot_origin_global()
	if from_g == Vector2.ZERO:
		from_g = Vector2(80, 280)
	var cols_out: Array[Color] = [Color(0.95, 0.75, 0.15), Color(0.75, 0.12, 0.12)]
	for i in 6:
		var to_g: Vector2 = from_g + Vector2(420.0 + float(i) * 12.0, randf_range(-40, 40))
		var core: Color = [Color(0.35, 0.32, 0.28), Color(0.75, 0.12, 0.12), Color(0.92, 0.92, 0.94)][i % 3]
		var powder: bool = (i % 2 == 0)
		var sin_shot: bool = (i % 3 == 1)
		# fire-and-forget coroutine
		_ui._animate_shot_projectile(from_g, to_g, core, cols_out, [], 0.35, powder, sin_shot)
		_spawned += 1

func _process(_d: float) -> bool:
	if _phase == 0:
		return false
	var now := Time.get_ticks_usec()
	var dt := now - _last
	_last = now
	_frame_i += 1
	if _phase == 1:
		if _frame_i >= 20:
			_frames.clear()
			_cpu.clear()
			_phase = 2
			_frame_i = 0
		return false
	if _phase == 2:
		_frames.append(dt)
		_cpu.append(Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
		if _frame_i % 4 == 0:
			_fire_burst()
		if _frame_i >= 180:
			_report()
			quit()
	return false

func _report() -> void:
	var s := 0.0
	for f in _frames:
		s += float(f)
	var avg: float = s / float(maxi(_frames.size(), 1)) / 1000.0
	var sorted := _frames.duplicate()
	sorted.sort()
	var p95: float = float(sorted[int(sorted.size() * 0.95)]) / 1000.0
	var cs := 0.0
	for c in _cpu:
		cs += float(c)
	var cpu_ms: float = cs / float(maxi(_cpu.size(), 1)) * 1000.0
	print("BENCH_SHOT_RESULT pool=%s avg_ms=%.2f p95_ms=%.2f fps=%.0f cpu_ms=%.2f spawned=%d pool_hosts=%d" % [
		str(_ui.shot_fx_pool_enabled), avg, p95, 1000.0 / maxf(avg, 0.001), cpu_ms, _spawned,
		_ui._shot_host_pool.size(),
	])
