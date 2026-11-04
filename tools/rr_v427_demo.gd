extends SceneTree
## v0.4.27 演示：未装满预转落在有弹仓；稀有度四档；一体弹道 + 火药屑；死亡肢体乱飞。
var _ui = null
var _title: Label = null

func _initialize() -> void:
	call_deferred("_run")

func _wait_volley(max_sec: float) -> void:
	var t := 0.0
	await create_timer(0.1).timeout
	while t < max_sec and (_ui._volley_ui_running or _ui.state.is_volley_pending()):
		await process_frame
		t += 1.0 / 30.0

func _foes(hp: int) -> void:
	var st = _ui.state
	st.sandbox_clear_enemies()
	for pair in [[1, 4], [2, 5], [3, 6], [4, 7], [5, 8], [1, 9]]:
		st.sandbox_spawn_enemy(int(pair[0]), int(pair[1]))
	for e in st.enemies:
		e.hp = hp
		e.max_hp = hp
		e.atk = 0
	_ui._refresh()

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
	var st = _ui.state
	st.player_hp = 99999
	st.player_max_hp = 99999
	st.sandbox_clear_muzzle()
	st.sandbox_clear_enemies()
	st.auto_enemy_advance = false
	st.sandbox_spawn_dummy(99999, 3)
	_ui._refresh()
	_show_title("1 没装满：开火前随机转，只停在有子弹的仓")
	_ui._combat_speed = 0.6
	for start in [1, 3, 4]:
		st.dev_force_load([16, -1, 26, -1, -1, 1] as Array[int])
		st.magazine.set_start(start)
		_ui._refresh()
		await create_timer(0.7).timeout
		_ui._on_fire()
		await _wait_volley(10.0)
		await create_timer(0.3).timeout
	_title.text = "2 稀有度：普通无 · 稀有流光 · 更稀有同色辉光 · 最稀有七彩+字发亮"
	st.dev_clear_bag()
	for aid in [1, 1, 22, 22, 28, 26, 26, 21, 24, 24, 27, 16]:
		st.sandbox_add_ammo(int(aid), 1, 0.0)
	st.dev_force_load([1, 22, 26, 24, 1, 22] as Array[int])
	st.magazine.set_start(0)
	_ui._refresh()
	await create_timer(4.5).timeout
	_title.text = "3 一体弹道 · 火药附着（炸药）沿路撒黑灰火药屑 · 打死飞肢体"
	_foes(2)
	st.sandbox_clear_muzzle()
	_ui._combat_speed = 0.6
	st.dev_force_load([27, 1, 26, 1, 22, 1] as Array[int])
	st.magazine.set_start(0)
	_ui._refresh()
	await create_timer(0.6).timeout
	_ui._on_fire()
	await _wait_volley(12.0)
	await create_timer(1.2).timeout
	_title.text = "4 死亡肢体乱飞（各种小动物，1×）"
	_ui._combat_speed = 1.0
	_foes(1)
	st.dev_force_load([1, 1, 1, 1, 1, 1] as Array[int])
	_ui._refresh()
	await create_timer(0.5).timeout
	_ui._on_fire()
	await _wait_volley(10.0)
	await create_timer(2.0).timeout
	print("DEMO_DONE audit=%d" % _ui.shot_audit.size())
	quit(0)

func _show_title(text: String) -> void:
	_title = Label.new()
	_title.text = text
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55))
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_title.add_theme_constant_override("outline_size", 8)
	_title.z_index = 200
	_title.position = Vector2(10, 64)
	_title.size = Vector2(700, 70)
	_ui.add_child(_title)
