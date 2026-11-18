extends GutTest
## v0.4.42：加速弹（本轮射速+50%，加法叠层）、撤退弹（临时复制体进背包）。

const WHITE := CombatConstants.WHITE_AMMO_ID
const QISHI := CombatConstants.QISHI_AMMO_ID
const XULI := CombatConstants.XULI_AMMO_ID
const JIASU := CombatConstants.JIASU_AMMO_ID
const CHETUI := CombatConstants.CHETUI_AMMO_ID


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


func _fire_all(cs: CombatState, n: int) -> void:
	cs.fire_tap(false)
	for _i in n - 1:
		cs.player_fire_gate_remaining = 0.0
		cs.take_volley_shot()


func test_version_is_at_least_0_4_42() -> void:
	assert_true(GameVersion.STRING >= "0.4.42")
	assert_true("0.4.42" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_defs_tags_colors_and_reward_pool() -> void:
	for id in [JIASU, CHETUI]:
		assert_eq(FireResolver.type_tag(id), "开始")
		assert_eq(FireResolver.base_damage_for(id, [], 0), 0)
		assert_true(DataRegistry.is_ammo_reward_eligible(id), "进奖励池")
	assert_eq(str(DataRegistry.get_ammo(JIASU).get("name")), "加速弹")
	assert_eq(str(DataRegistry.get_ammo(CHETUI).get("name")), "撤退弹")
	var jm: Dictionary = DataRegistry.muzzle_status_of(JIASU)
	assert_eq((jm["color"] as Color).to_html(false).to_upper(), "94FFF1")
	var cm: Dictionary = DataRegistry.muzzle_status_of(CHETUI)
	assert_eq((cm["color"] as Color).to_html(false).to_upper(), "5855E0")
	assert_eq(str(DataRegistry.get_ammo(CHETUI).get("bullet_color")), "#52C76B")


func test_zero_damage_and_start_skip() -> void:
	var d: Array[float] = FireResolver.compute_volley_damages([JIASU, CHETUI, QISHI, WHITE])
	assert_almost_eq(d[0], 0.0, 0.0001)
	assert_almost_eq(d[1], 0.0, 0.0001)
	assert_almost_eq(d[3], 4.5, 0.0001, "加速/撤退不改伤害，起势照常")
	var x: Array[float] = FireResolver.compute_volley_damages([XULI, JIASU, CHETUI, WHITE])
	assert_almost_eq(x[3], 4.5, 0.0001, "蓄力穿过其它开始弹")


func test_jiasu_additive_speed_stacking() -> void:
	var cs := _ready_fight(44201)
	cs.magazine.set_slot(0, JIASU)
	cs.magazine.set_slot(1, JIASU)
	cs.magazine.set_slot(2, WHITE)
	cs.magazine.set_slot(3, WHITE)
	assert_almost_eq(cs.volley_speed_mult(), 1.0, 0.0001)
	cs.fire_tap(false)
	assert_almost_eq(cs.volley_speed_mult(), 2.0, 0.0001, "一颗 +100%")
	cs.player_fire_gate_remaining = 0.0
	cs.take_volley_shot()
	assert_almost_eq(cs.volley_speed_mult(), 2.5, 0.0001, "两颗未封顶为3倍，受最小间隔封顶为2.5")
	assert_almost_eq(cs.volley_wait_scaled_sec(), CombatState.volley_wait_before_next_sec() / 2.5, 0.0001)


func test_jiasu_speed_capped_and_resets() -> void:
	var cs := _ready_fight(44202)
	for i in 4:
		cs.magazine.set_slot(i, JIASU)
	cs.magazine.set_slot(4, WHITE)
	_fire_all(cs, 4)
	assert_true(cs.volley_speed_mult() <= 2.5 + 0.0001)
	assert_true(cs.volley_wait_scaled_sec() >= CombatConstants.MIN_FIRE_INTERVAL_SEC - 0.0001)
	cs._reset_volley_plan()
	assert_almost_eq(cs.volley_speed_mult(), 1.0, 0.0001, "新一轮重置")


func test_chetui_makes_two_fire_once_copies_in_bag() -> void:
	var cs := _ready_fight(44203)
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.bag_envy_copy.clear()
	cs.magazine.set_slot(0, CHETUI)
	cs.magazine.set_slot(1, WHITE)
	cs.magazine.set_slot(2, QISHI)
	cs.fire_tap(false)
	assert_eq(cs.bag.size(), 2, "生成 2 颗")
	var seen: Array[int] = []
	for i in cs.bag.size():
		var aid: int = int(cs.bag[i])
		assert_true(aid in [CHETUI, WHITE, QISHI], "只复制弹仓内子弹（含自己）")
		assert_true(aid not in seen, "两颗不能挑同一仓")
		seen.append(aid)
		assert_true(bool(cs.bag_envy_copy[i]), "一次性临时标记")
		assert_eq(float(cs.bag_temp[i]), CombatConstants.FIRE_ONCE_TEMP)


func test_chetui_alone_copies_itself_once() -> void:
	var cs := _ready_fight(44204)
	cs.bag.clear()
	cs.bag_temp.clear()
	cs.bag_envy_copy.clear()
	cs.magazine.set_slot(0, CHETUI)
	cs.fire_tap(false)
	assert_eq(cs.bag.size(), 1, "只有自己时可复制 1 颗")
	assert_eq(int(cs.bag[0]), CHETUI)
	assert_true(bool(cs.bag_envy_copy[0]), "一次性临时标记")
	assert_eq(float(cs.bag_temp[0]), CombatConstants.FIRE_ONCE_TEMP)



func test_chetui_status_has_no_outline_on_followers() -> void:
	var cs := _ready_fight(44205)
	cs.magazine.set_slot(0, CHETUI)
	cs.magazine.set_slot(1, WHITE)
	cs.fire_tap(false)
	cs.player_fire_gate_remaining = 0.0
	var second: Array = cs.take_volley_shot()
	assert_eq(second.size(), 1)
	assert_eq((second[0].get("buff_outlines", []) as Array).size(), 0)
