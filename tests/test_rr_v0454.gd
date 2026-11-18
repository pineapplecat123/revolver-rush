extends GutTest
## v0.4.54：入库衔尾蛇/重复开始/白板；调整递增/起势/加速公式；临时复制体能倒出；沙盒条目可滑动。


const WHITE := CombatConstants.WHITE_AMMO_ID
const QISHI := CombatConstants.QISHI_AMMO_ID
const XULI := CombatConstants.XULI_AMMO_ID
const DIZENG := CombatConstants.DIZENG_AMMO_ID
const ZHONGSHEN := CombatConstants.ZHONGSHEN_AMMO_ID
const JIASU := CombatConstants.JIASU_AMMO_ID
const CHETUI := CombatConstants.CHETUI_AMMO_ID
const XIANWEI := CombatConstants.XIANWEI_AMMO_ID
const CHONGFU := CombatConstants.CHONGFU_KAISHI_AMMO_ID
const BAIBAN := CombatConstants.BAIBAN_AMMO_ID
const EMPTY := Magazine.EMPTY


func before_each() -> void:
	DataRegistry.reload()
	CombatState.boot_sandbox = false


func test_version_is_at_least_0_4_54() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.54") >= 0)
	assert_true("0.4.54" in FileAccess.get_file_as_string("res://data/changelog.json"))
	assert_true("衔尾蛇弹" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_new_ammo_defs() -> void:
	assert_eq(str(DataRegistry.get_ammo(XIANWEI).get("name")), "衔尾蛇弹")
	assert_eq(FireResolver.type_tag(XIANWEI), "开始")
	assert_eq(FireResolver.base_damage_for(XIANWEI, [], 0), 3)
	assert_true(DataRegistry.is_ammo_reward_eligible(XIANWEI))
	assert_eq(str(DataRegistry.get_ammo(CHONGFU).get("name")), "重复开始弹")
	assert_eq(FireResolver.type_tag(CHONGFU), "开始")
	assert_eq(FireResolver.base_damage_for(CHONGFU, [], 0), 0)
	assert_eq(str(DataRegistry.get_ammo(BAIBAN).get("name")), "白板弹")
	assert_eq(FireResolver.type_tag(BAIBAN), "中间")
	assert_eq(FireResolver.base_damage_for(BAIBAN, [], 0), 3)
	# 白板无特殊效果，基础伤害与平庸相同，但带中间标签
	var d: Array[float] = FireResolver.compute_volley_damages([BAIBAN, BAIBAN])
	assert_almost_eq(d[0], 3.0, 0.0001)
	assert_almost_eq(d[1], 3.0, 0.0001)


func test_dizeng_formula_and_rounding() -> void:
	# 第1格 2.75→3；第2格 3.5→4；第6格 6.5→7。空仓占格。
	var raw: Array[float] = FireResolver.compute_volley_damages([
		DIZENG, EMPTY, EMPTY, EMPTY, EMPTY, DIZENG
	])
	assert_almost_eq(raw[0], 2.75, 0.0001)
	assert_almost_eq(raw[5], 6.5, 0.0001)
	var rounded: Array[int] = FireResolver.compute_shot_damages([
		DIZENG, EMPTY, EMPTY, EMPTY, EMPTY, DIZENG
	])
	assert_eq(rounded[0], 3)
	assert_eq(rounded[5], 7)
	assert_eq(FireResolver.round_damage(2.75), 3)
	assert_eq(FireResolver.round_damage(6.5), 7)
	var slot2: Array[int] = FireResolver.compute_shot_damages([EMPTY, DIZENG])
	assert_eq(slot2[1], 4)


func test_qishi_additive_50_percent_per_stack() -> void:
	var one: Array[float] = FireResolver.compute_volley_damages([QISHI, WHITE])
	assert_almost_eq(one[1], 4.5, 0.0001)
	var two: Array[float] = FireResolver.compute_volley_damages([QISHI, QISHI, WHITE])
	assert_almost_eq(two[2], 6.0, 0.0001, "两层加法是 ×2.0，不是 ×1.5×1.5")
	# 蓄力仍是 ×1.5，且与起势相乘
	var both: Array[float] = FireResolver.compute_volley_damages([QISHI, XULI, WHITE])
	assert_almost_eq(both[2], 3.0 * 1.5 * 1.5, 0.0001)
	var chain: Array[float] = FireResolver.compute_volley_damages([XULI, XULI, WHITE])
	assert_almost_eq(chain[2], 3.0 * 2.25, 0.0001, "蓄力连乘未改")


func test_jiasu_100_percent_additive_and_cap() -> void:
	assert_almost_eq(CombatConstants.JIASU_SPEED_PER_STACK, 1.0, 0.0001)
	var cs := _ready_fight(45401)
	cs.magazine.set_slot(0, JIASU)
	cs.magazine.set_slot(1, JIASU)
	cs.magazine.set_slot(2, WHITE)
	cs.fire_tap(false)
	assert_almost_eq(cs.volley_speed_mult(), 2.0, 0.0001)
	cs.player_fire_gate_remaining = 0.0
	cs.take_volley_shot()
	var cap: float = CombatConstants.VOLLEY_SHOT_INTERVAL_SEC / CombatConstants.MIN_FIRE_INTERVAL_SEC
	assert_almost_eq(cs.volley_speed_mult(), minf(3.0, cap), 0.0001)


func test_xianwei_plus_three_per_end_bullet() -> void:
	var none: Array[float] = FireResolver.compute_volley_damages([XIANWEI, WHITE])
	assert_almost_eq(none[0], 3.0, 0.0001, "没有结束弹时是基础 3")
	var one: Array[float] = FireResolver.compute_volley_damages([XIANWEI, ZHONGSHEN])
	assert_almost_eq(one[0], 6.0, 0.0001)
	var two: Array[float] = FireResolver.compute_volley_damages([ZHONGSHEN, XIANWEI, ZHONGSHEN])
	assert_almost_eq(two[1], 9.0, 0.0001)
	# 开始弹不吃起势加成
	var with_q: Array[float] = FireResolver.compute_volley_damages([QISHI, XIANWEI, ZHONGSHEN])
	assert_almost_eq(with_q[1], 6.0, 0.0001)


func test_chongfu_copies_previous_start_effect() -> void:
	assert_eq(FireResolver.copied_start_effect_id([CHONGFU, WHITE], 0), 0)
	assert_eq(FireResolver.copied_start_effect_id([QISHI, CHONGFU], 1), QISHI)
	assert_eq(FireResolver.copied_start_effect_id([XULI, WHITE, CHONGFU], 2), XULI)
	assert_eq(FireResolver.copied_start_effect_id([QISHI, CHONGFU, CHONGFU], 2), QISHI)
	# 复制起势：自己无伤，后续平庸吃两层起势
	var q: Array[float] = FireResolver.compute_volley_damages([QISHI, CHONGFU, WHITE])
	assert_almost_eq(q[0], 0.0, 0.0001)
	assert_almost_eq(q[1], 0.0, 0.0001)
	assert_almost_eq(q[2], 6.0, 0.0001)
	# 复制蓄力
	var x: Array[float] = FireResolver.compute_volley_damages([XULI, CHONGFU, WHITE])
	assert_almost_eq(x[2], 3.0 * 2.25, 0.0001)
	# 复制衔尾蛇
	var w: Array[float] = FireResolver.compute_volley_damages([XIANWEI, CHONGFU, ZHONGSHEN])
	assert_almost_eq(w[1], 6.0, 0.0001)
	# 没有上一颗开始弹则无效果
	var none: Array[float] = FireResolver.compute_volley_damages([CHONGFU, WHITE])
	assert_almost_eq(none[0], 0.0, 0.0001)
	assert_almost_eq(none[1], 3.0, 0.0001)


func test_chongfu_copies_jiasu_and_chetui_on_fire() -> void:
	var cs := _ready_fight(45402)
	cs.magazine.set_slot(0, JIASU)
	cs.magazine.set_slot(1, CHONGFU)
	cs.magazine.set_slot(2, WHITE)
	cs.fire_tap(false)
	assert_almost_eq(cs.volley_speed_mult(), 2.0, 0.0001)
	cs.player_fire_gate_remaining = 0.0
	cs.take_volley_shot()
	var cap: float = CombatConstants.VOLLEY_SHOT_INTERVAL_SEC / CombatConstants.MIN_FIRE_INTERVAL_SEC
	assert_almost_eq(cs.volley_speed_mult(), minf(3.0, cap), 0.0001, "复制加速弹也加一层节奏")
	cs = _ready_fight(45403)
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.bag_envy_copy.clear()
	cs.magazine.set_slot(0, CHETUI)
	cs.magazine.set_slot(1, CHONGFU)
	cs.fire_tap(false)
	cs.player_fire_gate_remaining = 0.0
	var bag0: int = cs.bag.size()
	cs.take_volley_shot()
	assert_gt(cs.bag.size(), bag0, "复制撤退弹效果后应再生成临时复制体")
	for i in cs.bag.size():
		assert_eq(float(cs.bag_temp[i]), CombatConstants.FIRE_ONCE_TEMP)


func test_chetui_temp_copies_dump_to_hand_keep_identity() -> void:
	var cs := CombatState.new(45404)
	cs.start_sandbox(45404, FireResolver.ID_WRATH, false)
	cs._bag_append(WHITE, CombatConstants.FIRE_ONCE_TEMP, true)
	cs._bag_append(CHETUI, CombatConstants.FIRE_ONCE_TEMP, true)
	assert_eq(cs.bag.size(), 2)
	var recs: Array = []
	for i in cs.bag.size():
		recs.append({
			"id": int(cs.bag[i]),
			"temp": true,
			"envy": true,
		})
	var n: int = cs.dump_to_hand_items(recs)
	assert_eq(n, 2, "撤退弹生成的临时复制体应能倒进手里")
	assert_eq(cs.bag.size(), 0)
	assert_eq(cs.hand.size(), 2)
	for i in cs.hand.size():
		assert_eq(float(cs.hand_temp[i]), CombatConstants.FIRE_ONCE_TEMP)
		assert_true(bool(cs.hand_envy_copy[i]), "打出即毁标记随身份进手")
		assert_gt(int(cs.hand_uid[i]), 0)


func test_sandbox_drag_on_entry_scrolls_without_adding() -> void:
	CombatState.boot_sandbox = true
	var scene = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(3)
	assert_true(scene.dev_panel.visible)
	var scroll: ScrollContainer = scene.dev_panel.find_child("DevScroll", true, false)
	assert_not_null(scroll)
	var inner: Control = scroll.get_child(0) as Control if scroll.get_child_count() > 0 else null
	assert_not_null(inner)
	inner.custom_minimum_size = Vector2(0, 2400)
	await wait_process_frames(2)
	var btn: Button = null
	for b in scene.dev_panel.find_children("*", "Button", true, false):
		if (b as Button).text == "袋+" and (b as Button).is_visible_in_tree():
			btn = b
			break
	assert_not_null(btn)
	var bag0: int = scene.state.bag.size()
	var before: int = scroll.scroll_vertical
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(10, 10)
	scene._sb_on_scroll_gui_input(btn, press, func(): scene.state.sandbox_add_ammo(WHITE, 1))
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = Vector2(10, 10 + scene.SB_TAP_MAX_PX + 24)
	motion.relative = Vector2(0, -(scene.SB_TAP_MAX_PX + 24))
	scene._sb_on_scroll_gui_input(btn, motion, func(): scene.state.sandbox_add_ammo(WHITE, 1))
	assert_gt(scroll.scroll_vertical, before, "在子弹按钮上拖应滚动")
	assert_eq(scene.state.bag.size(), bag0, "滑动不得加弹")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = motion.position
	scene._sb_on_scroll_gui_input(btn, release, func(): scene.state.sandbox_add_ammo(WHITE, 1))
	assert_eq(scene.state.bag.size(), bag0, "滑动松手不得加弹")
	# 轻点仍加减
	var tap_p := InputEventMouseButton.new()
	tap_p.button_index = MOUSE_BUTTON_LEFT
	tap_p.pressed = true
	tap_p.position = Vector2(8, 8)
	scene._sb_on_scroll_gui_input(btn, tap_p, func(): scene.state.sandbox_add_ammo(WHITE, 1))
	var tap_r := InputEventMouseButton.new()
	tap_r.button_index = MOUSE_BUTTON_LEFT
	tap_r.pressed = false
	tap_r.position = Vector2(8, 8)
	scene._sb_on_scroll_gui_input(btn, tap_r, func(): scene.state.sandbox_add_ammo(WHITE, 1))
	assert_eq(scene.state.bag.size(), bag0 + 1, "轻点仍应加弹")
	CombatState.boot_sandbox = false


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
