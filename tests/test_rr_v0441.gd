extends GutTest
## v0.4.41：枪口状态进「枪口：」行、火焰加大、加强弹道描边、伤害缩放弹道、飘字加倍。

const WHITE := CombatConstants.WHITE_AMMO_ID
const QISHI := CombatConstants.QISHI_AMMO_ID
const XULI := CombatConstants.XULI_AMMO_ID


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CombatState.boot_sandbox = true


func after_each() -> void:
	CombatState.boot_sandbox = false


func _ui_sandbox():
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(3)
	var cs: CombatState = ui.state
	cs.sandbox_clear_enemies()
	cs.player_hp = 99999
	cs.player_max_hp = 99999
	ui._wave_bannering = false
	ui._rolling = false
	ui._loading = false
	ui._sin_pick_open = false
	ui._reward_delaying = false
	if ui._dev_open:
		ui._toggle_dev()
	return ui


func _ready_fight(seed_v: int) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v, FireResolver.ID_WRATH)
	cs.pace_after_fire = false
	cs.defer_impacts = false
	cs.auto_enemy_advance = false
	while not cs.enemies.is_empty():
		cs.enemies.pop_back()
	cs.dev_spawn_enemy(1, 5)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.enemies[0].atk = 0
	cs.magazine.clear()
	cs.magazine.start_index = 0
	return cs


func test_version_is_0_4_41() -> void:
	assert_eq(GameVersion.STRING, "0.4.41")
	assert_true("0.4.41" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_shot_size_scale_base_three_and_cap() -> void:
	var CUI = load("res://scripts/combat/combat_ui.gd")
	assert_eq(CUI.shot_size_scale(3), 1.0)
	assert_eq(CUI.shot_size_scale(6), 2.0)
	assert_eq(CUI.shot_size_scale(12), 2.4)
	assert_eq(CUI.shot_size_scale(99), 2.4)
	assert_eq(CUI.shot_size_scale(1), 0.75)
	assert_eq(CUI.shot_size_scale(0), 0.75)


func test_damage_float_font_doubled() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/combat/combat_ui.gd")
	assert_true("const DMG_FLOAT_FONT_MIN := 52" in src)
	assert_true("const DMG_FLOAT_FONT_MAX := 144" in src)


func test_start_shot_has_no_buff_outlines() -> void:
	var cs := _ready_fight(44101)
	cs.magazine.set_slot(0, QISHI)
	cs.magazine.set_slot(1, WHITE)
	var first: Array = cs.fire_tap(false)
	assert_eq(first.size(), 1)
	assert_eq((first[0].get("buff_outlines", ["x"]) as Array).size(), 0, "开始弹不吃加强，无描边")


func test_following_white_inherits_qishi_outline() -> void:
	var cs := _ready_fight(44102)
	cs.magazine.set_slot(0, QISHI)
	cs.magazine.set_slot(1, WHITE)
	cs.magazine.set_slot(2, WHITE)
	cs.fire_tap(false)
	cs.player_fire_gate_remaining = 0.0
	var second: Array = cs.take_volley_shot()
	assert_eq(second.size(), 1)
	var outlines: Array = second[0].get("buff_outlines", [])
	assert_eq(outlines.size(), 1)
	assert_eq(str(outlines[0].get("id", "")), "qishi")
	var c: Color = outlines[0].get("color", Color(0, 0, 0))
	var expect: Color = DataRegistry.muzzle_status_of(QISHI).get("color", Color(0, 0, 0))
	assert_almost_eq(c.r, expect.r, 0.01)
	assert_almost_eq(c.g, expect.g, 0.01)
	assert_almost_eq(c.b, expect.b, 0.01)


func test_layered_outlines_most_recent_last() -> void:
	var cs := _ready_fight(44103)
	cs.magazine.set_slot(0, QISHI)
	cs.magazine.set_slot(1, XULI)
	cs.magazine.set_slot(2, WHITE)
	cs.fire_tap(false)
	cs.player_fire_gate_remaining = 0.0
	cs.take_volley_shot()
	cs.player_fire_gate_remaining = 0.0
	var third: Array = cs.take_volley_shot()
	assert_eq(third.size(), 1)
	var outlines: Array = third[0].get("buff_outlines", [])
	assert_eq(outlines.size(), 2, "起势与蓄力同时挂着时两层描边")
	assert_eq(str(outlines[0].get("id", "")), "qishi")
	assert_eq(str(outlines[1].get("id", "")), "xuli", "最近一次在数组末尾，画在最外圈")


func test_icons_sit_after_muzzle_label_not_at_gun() -> void:
	var ui = await _ui_sandbox()
	var cs: CombatState = ui.state
	cs.pace_after_fire = false
	cs.defer_impacts = false
	cs.auto_enemy_advance = false
	cs.dev_spawn_enemy(1, 5)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.enemies[0].atk = 0
	cs.magazine.clear()
	cs.magazine.start_index = 0
	cs.magazine.set_slot(0, QISHI)
	cs.magazine.set_slot(1, WHITE)
	cs.fire_tap(false)
	ui._ensure_muzzle_hud()
	ui._ensure_muzzle_status_hud()
	ui._refresh_muzzle_hud()
	await wait_process_frames(8)
	var host: Control = ui._volley_buff_host
	assert_not_null(host, "「枪口：」后应有齐射加强槽")
	assert_eq(host.name, "VolleyBuffHost")
	var label: Label = ui._muzzle_label
	assert_not_null(label)
	assert_eq(label.text, "枪口：")
	assert_eq(host.get_parent(), label.get_parent())
	assert_eq(host.get_index(), label.get_index() + 1, "图标槽紧跟「枪口：」")
	assert_gt(host.get_child_count(), 0, "起势后应出现状态圆")
	var ic: Control = host.get_child(0) as Control
	assert_not_null(ic)
	assert_eq(ic.get_parent(), host)
	# 不应再漂在场上枪口旁边（旧偏移约 muzzle + (16,-30)）
	var muzzle: Vector2 = ui._player_shot_origin_global()
	if muzzle != Vector2.ZERO:
		var ic_c: Vector2 = ic.get_global_rect().get_center()
		assert_gt(ic_c.distance_to(muzzle + Vector2(16, -30)), 40.0, "图标不能留在场上枪口旁")
	# 火焰仍在枪口 HUD 上
	var hud = ui._muzzle_status_hud
	assert_not_null(hud)
	var flame = hud.get_node_or_null("MuzzleFlame")
	assert_not_null(flame)
	assert_true(flame.visible)
	# 有齐射状态时不显示「—」
	for c in ui._muzzle_chips.get_children():
		if c is Label:
			assert_ne((c as Label).text, "—")


func test_buffed_tracer_has_outer_highlight_and_scales() -> void:
	var ui = await _ui_sandbox()
	var green := Color(0.29, 0.88, 0.42)
	var teal := Color(0.17, 0.77, 0.71)
	var cols: Array[Color] = [green, teal]
	var scale_hi: float = ui.shot_size_scale(9)
	assert_almost_eq(scale_hi, 2.4, 0.01)
	ui._animate_shot_projectile(Vector2(80, 400), Vector2(600, 400), Color.WHITE, [] as Array[Color], [], 0.8, false, false, scale_hi, cols)
	await wait_process_frames(6)
	var found := 0
	var wmin := 999.0
	var wmax := 0.0
	var core_w := 0.0
	for c in ui.get_children():
		if c is Control and c.z_index == ui.Z_SHOT_VFX:
			for cc in c.get_children():
				if cc is Line2D and str(cc.name).begins_with("BuffOutline"):
					found += 1
					var w: float = (cc as Line2D).width
					wmin = minf(wmin, w)
					wmax = maxf(wmax, w)
				if cc is Line2D and cc.name == "Tip":
					core_w = (cc as Line2D).width
	assert_eq(found, 2, "两层加强应画出两圈外轮廓")
	assert_gt(wmin, ui.SHOT_TRAIL_THICK * scale_hi, "轮廓在芯线外侧")
	assert_almost_eq(core_w, ui.SHOT_TRAIL_THICK * scale_hi, 0.05, "弹头宽度随伤害放大")
	assert_gt(wmax - wmin, 1.0, "最近一次加强在最外圈，更宽")
	await wait_seconds(1.1)
