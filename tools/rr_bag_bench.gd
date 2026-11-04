extends SceneTree
## v0.4.29 袋内小球性能基准：72 球（各稀有度+罪孽+临时），分「滚动中」「静止」两段测平均帧时。
## 用法：DISPLAY=:99 godot --path . -s tools/rr_bag_bench.gd  （输出 BENCH 行）

var N_BALLS := int(OS.get_environment("BENCH_N")) if OS.get_environment("BENCH_N") != "" else 72
var _box: Control
var _ui: Object
var _frames: Array = []
var _phase := 0
var _t0 := 0
var _frame_i := 0
var _last := 0
var _cpu: Array = []


func _initialize() -> void:
	var dr = root.get_node("DataRegistry")
	dr.reload()
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(900, 700)
	_ui = load("res://scripts/combat/combat_ui.gd").new()
	_box = load("res://scripts/combat/bag_physics_box.gd").new()
	_box.color_lookup = Callable(_ui, "_ammo_colors")
	_box.name_lookup = Callable(_ui, "_ammo_bag_glyph")
	_box.position = Vector2(20, 20)
	_box.size = Vector2(420, 520)
	root.add_child(_box)
	var ids: Array = []
	var temps: Array = []
	var pool: Array = []
	for d in dr.all_ammo():
		pool.append(int(d.get("id", 1)))
	var only := OS.get_environment("BENCH_ONLY")
	if only != "":
		pool = [int(only)]
	for i in N_BALLS:
		ids.append(int(pool[i % pool.size()]))
		temps.append(i % 9 == 0)
	_box.sync_ammo_ids(ids, temps)
	_last = Time.get_ticks_usec()


func _process(_d: float) -> bool:
	var now := Time.get_ticks_usec()
	var dt := now - _last
	_last = now
	_frame_i += 1
	# 0..59 预热；60..299 滚动段（每 40 帧踢一下）；300..419 等静止；420..659 静止段
	if _frame_i >= 60 and _frame_i < 300:
		_frames.append(dt)
		_cpu.append(Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
		if _frame_i % 40 == 0:
			for b in _box._balls:
				b["vel"] = Vector2(randf_range(-500, 500), randf_range(-900, -300))
				b["asleep"] = false
	elif _frame_i == 59 or _frame_i == 419:
		var bs0 = _box.get_script()
		bs0.prof_draw_usec = 0
		bs0.prof_phys_usec = 0
		bs0.prof_draw_calls = 0
	elif _frame_i == 300:
		_report("moving")
		_frames.clear()
		_cpu.clear()
	elif _frame_i >= 420 and _frame_i < 660:
		_frames.append(dt)
		_cpu.append(Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
	elif _frame_i == 660:
		_report("settled")
		quit()
	return false


func _report(tag: String) -> void:
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
	var bs = _box.get_script()
	var nfr: float = float(maxi(_frames.size(), 1))
	print("BENCH_BAG %s draw_ms_per_frame=%.3f physics_ms_per_frame=%.3f draws=%d" % [tag, float(bs.prof_draw_usec) / nfr / 1000.0, float(bs.prof_phys_usec) / nfr / 1000.0, bs.prof_draw_calls])
	bs.prof_draw_usec = 0
	bs.prof_phys_usec = 0
	bs.prof_draw_calls = 0
	print("BENCH %s balls=%d frame_avg_ms=%.2f p95_ms=%.2f fps=%.0f cpu_process+physics_ms=%.3f" % [tag, _box.ball_count(), avg, p95, 1000.0 / maxf(avg, 0.001), cpu_ms])
