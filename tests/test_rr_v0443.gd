extends GutTest
## v0.4.43：加速弹只改开火节奏；撤退弹含自己、无放回、不足则少复制；新增尾重弹。

const WHITE := CombatConstants.WHITE_AMMO_ID
const QISHI := CombatConstants.QISHI_AMMO_ID
const XULI := CombatConstants.XULI_AMMO_ID
const JIASU := CombatConstants.JIASU_AMMO_ID
const CHETUI := CombatConstants.CHETUI_AMMO_ID
const WEIZHONG := CombatConstants.WEIZHONG_AMMO_ID
const WRATH := FireResolver.ID_WRATH
const EMPTY := Magazine.EMPTY


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


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


func _clear_bag(cs: CombatState) -> void:
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.bag_envy_copy.clear()


func _envy_copies(cs: CombatState) -> Array:
	var out: Array = []
	for i in cs.bag.size():
		if i < cs.bag_envy_copy.size() and bool(cs.bag_envy_copy[i]):
			out.append(int(cs.bag[i]))
	return out


func test_version_is_0_4_43() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.43") >= 0)
	assert_true("0.4.43" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_jiasu_two_stacks_are_double_speed() -> void:
	var cs := _ready_fight(44301)
	cs.magazine.set_slot(0, JIASU)
	cs.magazine.set_slot(1, JIASU)
	cs.magazine.set_slot(2, WHITE)
	assert_almost_eq(cs.volley_speed_mult(), 1.0, 0.0001)
	cs.fire_tap(false)
	assert_almost_eq(cs.volley_speed_mult(), 3.0, 0.0001, "一颗 +100%")
	cs.player_fire_gate_remaining = 0.0
	cs.take_volley_shot()
	assert_almost_eq(cs.volley_speed_mult(), 4.0, 0.0001, "两颗为 3 倍速")
	assert_almost_eq(cs.volley_wait_scaled_sec(), 0.0625, 0.0001)


func test_chetui_with_one_other_copies_self_and_other() -> void:
	var cs := _ready_fight(44302)
	_clear_bag(cs)
	cs.magazine.set_slot(0, CHETUI)
	cs.magazine.set_slot(1, WHITE)
	cs.fire_tap(false)
	var copies: Array = _envy_copies(cs)
	assert_eq(copies.size(), 1)
	copies.sort()
	var expect: Array = [WHITE]
	expect.sort()
	assert_eq(copies, expect, "恰好复制自己和另一颗")
	for i in cs.bag.size():
		if i < cs.bag_envy_copy.size() and bool(cs.bag_envy_copy[i]):
			assert_eq(float(cs.bag_temp[i]), CombatConstants.FIRE_ONCE_TEMP)


func test_chetui_pool_excludes_already_fired() -> void:
	var cs := _ready_fight(44303)
	_clear_bag(cs)
	cs.magazine.set_slot(0, WHITE)
	cs.magazine.set_slot(1, CHETUI)
	cs.magazine.set_slot(2, QISHI)
	cs.fire_tap(false)
	# 第一发是平庸，已出仓；再打撤退弹时，可选的应是起势和自己
	assert_eq(cs.last_shot_ammo_id, WHITE)
	cs.player_fire_gate_remaining = 0.0
	cs.take_volley_shot()
	assert_eq(cs.last_shot_ammo_id, CHETUI)
	var copies: Array = _envy_copies(cs)
	assert_eq(copies.size(), 1)
	copies.sort()
	var expect: Array = [QISHI]
	expect.sort()
	assert_eq(copies, expect, "不含本轮已打出的平庸")
	assert_true(WHITE not in copies)


func test_chetui_skips_sin_and_copies_self_if_needed() -> void:
	var cs := _ready_fight(44304)
	_clear_bag(cs)
	cs.magazine.set_slot(0, CHETUI)
	cs.magazine.set_slot(1, WRATH)
	cs.fire_tap(false)
	var copies: Array = _envy_copies(cs)
	assert_eq(copies.size(), 1, "罪孽弹排除后只剩自己，复制 1 颗")
	assert_eq(int(copies[0]), 16)


func test_chetui_no_duplicate_pick_with_two_same_type() -> void:
	## 两颗平庸分属不同仓，允许都复制；但不能从同一仓抽两次。
	var cs := _ready_fight(44305)
	_clear_bag(cs)
	cs.magazine.set_slot(0, CHETUI)
	cs.magazine.set_slot(1, WHITE)
	cs.magazine.set_slot(2, WHITE)
	cs.fire_tap(false)
	var copies: Array = _envy_copies(cs)
	assert_eq(copies.size(), 2)
	var whites := 0
	var selves := 0
	for aid in copies:
		if int(aid) == WHITE:
			whites += 1
		elif int(aid) == CHETUI:
			selves += 1
		else:
			assert_true(false, "只能是平庸或自己")
	assert_eq(whites + selves, 2)
	assert_true(whites <= 2)
	assert_true(selves <= 1, "自己只有一仓，不能抽两次")


func test_descriptions_match_resolved_rules() -> void:
	var js := str(DataRegistry.get_ammo(JIASU).get("special", ""))
	assert_true("加法叠加" in js)
	assert_true("飞行" in js)
	var cs_ := str(DataRegistry.get_ammo(CHETUI).get("special", ""))
	assert_true("不包括自己" in cs_)
	assert_false("不含罪孽" in cs_)
	assert_true("不够2颗" in cs_ or "不够 2 颗" in cs_)
	var wz := str(DataRegistry.get_ammo(WEIZHONG).get("special", ""))
	assert_true("0.5" in wz)
	assert_true("空仓" in wz)
	assert_true("枪口火焰" in wz)
	assert_true("自身公式" in wz)


func test_weizhong_def_and_starter_bag() -> void:
	assert_eq(FireResolver.type_tag(WEIZHONG), "中间")
	assert_eq(FireResolver.base_damage_for(WEIZHONG, [], 0), 3)
	assert_true(DataRegistry.is_ammo_reward_eligible(WEIZHONG), "进奖励池")
	assert_eq(str(DataRegistry.get_ammo(WEIZHONG).get("school")), "通用")
	assert_eq(str(DataRegistry.get_ammo(WEIZHONG).get("bullet_color")), "#F2CC38")
	assert_eq(str(DataRegistry.get_ammo(WEIZHONG).get("muzzle_color")), "#F2CC38")
	assert_true(WEIZHONG in CombatConstants.starter_clearing_ids())
	var cs := CombatState.new()
	cs.start_rush(44310, FireResolver.ID_WRATH)
	assert_eq(cs.bag.size(), 16)
	assert_eq(cs.total_ammo_count(WEIZHONG), 2)
	assert_eq(cs.total_ammo_count(WHITE), 6)


func test_weizhong_slot_bands_count_empties() -> void:
	var front: Array[float] = FireResolver.compute_volley_damages([WEIZHONG, WEIZHONG, WEIZHONG])
	assert_almost_eq(front[0], 1.5, 0.0001, "第1格 ×0.5")
	assert_almost_eq(front[1], 1.5, 0.0001, "第2格 ×0.5")
	assert_almost_eq(front[2], 1.5, 0.0001, "第3格 ×0.5")
	var back: Array[float] = FireResolver.compute_volley_damages([
		WHITE, WHITE, WHITE, WEIZHONG, WEIZHONG, WEIZHONG
	])
	assert_almost_eq(back[3], 6.0, 0.0001, "第4格 ×2")
	assert_almost_eq(back[4], 6.0, 0.0001, "第5格 ×2")
	assert_almost_eq(back[5], 6.0, 0.0001, "第6格 ×2")
	var with_empty: Array[float] = FireResolver.compute_volley_damages([
		EMPTY, EMPTY, EMPTY, WEIZHONG
	])
	assert_almost_eq(with_empty[0], 0.0, 0.0001)
	assert_almost_eq(with_empty[3], 6.0, 0.0001, "三个空仓之后是第4格")


func test_weizhong_multiplies_with_qishi_and_xuli() -> void:
	# 起势在第1格，尾重在第2格：3×0.5×1.5 = 2.25
	var q: Array[float] = FireResolver.compute_volley_damages([QISHI, WEIZHONG])
	assert_almost_eq(q[1], 2.25, 0.0001)
	# 蓄力在第3格（前两格为空），尾重在第5格：3×2×1.5 = 9
	var x: Array[float] = FireResolver.compute_volley_damages([EMPTY, EMPTY, XULI, EMPTY, WEIZHONG])
	assert_almost_eq(x[4], 9.0, 0.0001)
	# 两颗起势 + 蓄力 + 第6格尾重：3×2×2.0×1.5 = 18
	var both: Array[float] = FireResolver.compute_volley_damages([
		QISHI, QISHI, XULI, EMPTY, EMPTY, WEIZHONG
	])
	assert_almost_eq(both[5], 68.34375, 0.0001)
