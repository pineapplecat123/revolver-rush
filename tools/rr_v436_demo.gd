extends SceneTree
## v0.4.36：仓内幽灵/小石头圆形倒计时环 + 临时罪孽（无环、打出即毁）。

const GHOST := 20
const PEBBLE := 32
const WRATH := 16

var _ui
var _title: Label

func _initialize() -> void:
	call_deferred("_run")

func _banner(text: String) -> void:
	if _title == null:
		_title = Label.new()
		_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_title.add_theme_font_size_override("font_size", 20)
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
	await create_timer(0.25).timeout
	if _ui._dev_open:
		_ui._toggle_dev()
	var st = _ui.state
	st.player_hp = 99999
	st.sandbox_clear_enemies()
	st.sandbox_spawn_dummy(200, 5)
	_banner("TTL 弹：转轮仓圆形倒计时环（幽灵/小石头）；临时罪孽无环")
	# bag: ghost + pebble with TTL; wrath fire-once temp
	st.bag.clear()
	st.bag_temp.clear()
	st.bag_envy_copy.clear()
	st._bag_append(GHOST, 30.0)
	st._bag_append(PEBBLE, 30.0)
	st._bag_append(WRATH, true)
	st._bag_append(WRATH, true)
	# chambers: ghost, pebble, fire-once wrath
	st.dev_force_load([GHOST, PEBBLE, WRATH, -1, -1, -1] as Array[int])
	st.magazine.set_slot(0, GHOST, 22.0)
	st.magazine.set_slot(1, PEBBLE, 12.0)
	st.magazine.set_slot(2, WRATH, true)
	st.magazine.set_start(0)
	_ui._refresh()
	_ui._update_temp_sin_timers()
	await create_timer(0.6).timeout
	# tick TTL so rings visibly shrink
	for k in 90:
		st.tick_temp_sin_lifetimes(0.12)
		_ui._update_temp_sin_timers()
		_ui._refresh_mag_contents()
		await process_frame
	await create_timer(0.5).timeout
	_banner("临时罪孽打出即毁（不进弃牌）")
	# put fire-once at hammer and fire
	st.dev_force_load([WRATH, -1, -1, -1, -1, -1] as Array[int])
	st.magazine.set_slot(0, WRATH, true)
	st.magazine.set_start(0)
	_ui._refresh()
	await create_timer(0.4).timeout
	_ui._on_fire()
	await create_timer(2.5).timeout
	print("DEMO_DONE v0.4.36")
	quit(0)
