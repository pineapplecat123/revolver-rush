extends GutTest
## v0.4.60：入库模仿弹与回味弹；后续效果说明统一为枪口状态。


const QISHI := CombatConstants.QISHI_AMMO_ID
const XULI := CombatConstants.XULI_AMMO_ID
const DIZENG := CombatConstants.DIZENG_AMMO_ID
const ZHONGSHEN := CombatConstants.ZHONGSHEN_AMMO_ID
const JIASU := CombatConstants.JIASU_AMMO_ID
const XIANWEI := CombatConstants.XIANWEI_AMMO_ID
const BAIBAN := CombatConstants.BAIBAN_AMMO_ID
const MOFANG := CombatConstants.MOFANG_AMMO_ID
const HUIWEI := CombatConstants.HUIWEI_AMMO_ID
const EMPTY := Magazine.EMPTY


func before_each() -> void:
	DataRegistry.reload()
	CombatState.boot_sandbox = false


func test_version_is_at_least_0_4_60() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.60") >= 0)
	assert_true("0.4.60" in FileAccess.get_file_as_string("res://data/changelog.json"))
	assert_true("模仿弹" in FileAccess.get_file_as_string("res://data/changelog.json"))
	assert_true("回味弹" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_mofang_and_huiwei_in_registry() -> void:
	assert_eq(str(DataRegistry.get_ammo(MOFANG).get("name")), "模仿弹")
	assert_eq(str(DataRegistry.get_ammo(HUIWEI).get("name")), "回味弹")
	assert_eq(FireResolver.type_tag(MOFANG), "中间")
	assert_eq(FireResolver.type_tag(HUIWEI), "中间")
	assert_eq(FireResolver.base_damage_for(MOFANG, [], 0), 3)
	assert_eq(FireResolver.base_damage_for(HUIWEI, [], 0), 2)
	assert_true(DataRegistry.is_ammo_reward_eligible(MOFANG))
	assert_true(DataRegistry.is_ammo_reward_eligible(HUIWEI))
	assert_eq(DataRegistry.all_ammo().size(), 20)
	var raw := FileAccess.get_file_as_string("res://companion/bullet-editor/data.json")
	assert_true('"name": "模仿弹"' in raw)
	assert_true('"name": "回味弹"' in raw)
	# 回味编辑器伤害已同步为 2，且已入库
	assert_true('"damage": "2"' in raw)


func test_muzzle_wording_and_status_presentation() -> void:
	for ammo_id in [QISHI, XULI, JIASU, HUIWEI]:
		var special := str(DataRegistry.get_ammo(ammo_id).get("special", ""))
		assert_true("枪口" in special, "%s 应写明枪口状态" % DataRegistry.get_ammo(ammo_id).get("name"))
	var chuandi := str(DataRegistry.get_ammo(CombatConstants.CHUANDI_AMMO_ID).get("special", ""))
	assert_true("枪口" in chuandi)
	# 加速弹枪口说明此前没有 format 文本，这里补上节奏加值
	var speed := {"effect_kind": "speed_pct", "effect_per_stack": 1.0, "stacks": 2}
	assert_eq(DataRegistry.format_muzzle_status_effect(speed), "开火节奏+200%")
	var flat := {"effect_kind": "damage_flat", "amount": 2, "stacks": 1}
	assert_eq(DataRegistry.format_muzzle_status_effect(flat), "伤害+2")
	var pct := {"effect_kind": "damage_pct", "effect_per_stack": 0.5, "stacks": 2}
	assert_eq(DataRegistry.format_muzzle_status_effect(pct), "每层伤害×1.5；当前×2.25")


func test_mofang_keeps_own_base_and_copies_adjacent_skill() -> void:
	assert_eq(FireResolver.copied_adjacent_effect_id([MOFANG, BAIBAN], 0), 0)
	assert_eq(FireResolver.copied_adjacent_effect_id([EMPTY, MOFANG], 1), 0)
	assert_eq(FireResolver.copied_adjacent_effect_id([QISHI, MOFANG], 1), QISHI)
	assert_eq(FireResolver.copied_adjacent_effect_id([QISHI, EMPTY, MOFANG], 2), 0)
	assert_eq(FireResolver.copied_adjacent_effect_id([QISHI, MOFANG, MOFANG], 2), QISHI)
	# 获得加伤枪口，但自己仍是中间弹且基础伤害 3，再吃上一颗加伤：3×1.5=4.5
	var d: Array[float] = FireResolver.compute_volley_damages([QISHI, MOFANG, BAIBAN])
	assert_almost_eq(d[1], 6.75, 0.0001)
	assert_almost_eq(d[2], 6.75, 0.0001)
	# 前一格空仓：不跳到加伤
	var gap: Array[float] = FireResolver.compute_volley_damages([QISHI, EMPTY, MOFANG, BAIBAN])
	assert_almost_eq(gap[2], 6.75, 0.0001)  # 模仿本身仍吃加伤（自己是中间），但不挂第二层
	assert_almost_eq(gap[3], 4.5, 0.0001)
	# 不复制倍伤的 0 伤害
	var x: Array[float] = FireResolver.compute_volley_damages([XULI, MOFANG])
	assert_almost_eq(x[1], 4.5, 0.0001)
	# 吃尾公式属于技能，按公式算（基础仍是 3 + 每结束 3）
	var tail: Array[int] = FireResolver.compute_shot_damages([XIANWEI, MOFANG, CombatConstants.ZHONGSHEN_AMMO_ID])
	assert_eq(tail[0], 6)
	assert_eq(tail[1], 6)


func test_mofang_does_not_wrap_and_chain_through_mimics() -> void:
	# 不绕圈：最后一格的加伤不会给第一格模仿，也不会回溯给中间的白板
	var wrap: Array[float] = FireResolver.compute_volley_damages([MOFANG, BAIBAN, QISHI])
	assert_almost_eq(wrap[0], 3.0, 0.0001)
	assert_almost_eq(wrap[1], 3.0, 0.0001)
	# 连续模仿拿到同一技能
	var chain: Array[float] = FireResolver.compute_volley_damages([QISHI, MOFANG, MOFANG, BAIBAN])
	assert_almost_eq(chain[1], 10.125, 0.0001)
	assert_almost_eq(chain[2], 15.1875, 0.0001)
	assert_almost_eq(chain[3], 15.1875, 0.0001)


func _ready_cs(seed: int) -> CombatState:
	var cs := CombatState.new(seed)
	cs.start_rush(seed, FireResolver.ID_WRATH)
	cs.pace_after_fire = false
	cs.defer_impacts = false
	cs.auto_enemy_advance = false
	while not cs.enemies.is_empty():
		cs.enemies.pop_back()
	cs.dev_spawn_enemy(CombatConstants.DUMMY_ENEMY_ID, 3)
	cs.enemies[cs.enemies.size() - 1].hp = 99
	cs.enemies[cs.enemies.size() - 1].max_hp = 99
	cs.enemies[cs.enemies.size() - 1].atk = 0
	cs.dev_clear_bag()
	cs.magazine.clear()
	cs.magazine.start_index = 0
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	return cs


func _huiwei_amount(cs: CombatState) -> int:
	var total := 0
	for b in cs.volley_muzzle_buffs():
		if str(b.get("id", "")) == "huiwei":
			total += int(b.get("amount", 0)) * int(b.get("remaining", 1))
	return total


func test_huiwei_grants_actual_dealt_flat_and_cleans_up() -> void:
	var cs := _ready_cs(46001)
	cs.magazine.set_slot(0, HUIWEI)
	cs.magazine.set_slot(1, BAIBAN)
	cs._volley_session = true
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	assert_eq(cs.last_shot_dealt, 2)
	assert_eq(_huiwei_amount(cs), 2)
	assert_eq(DataRegistry.format_muzzle_status_effect(cs.volley_muzzle_buffs()[cs.volley_muzzle_buffs().size() - 1]), "伤害+2")
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	assert_eq(cs.last_shot_planned_damage, 5)
	assert_eq(cs.last_shot_dealt, 5)
	cs._volley_session = false
	cs._reset_volley_plan()
	assert_eq(_huiwei_amount(cs), 0)
	assert_true(cs.volley_muzzle_buffs().is_empty())


func test_huiwei_uses_actual_dealt_not_planned() -> void:
	# 实际伤害沿用 apply_hit 的返回值：含溢出，但不含被豁免或未命中。
	# 石头标签免疫小于 4 的伤害，回味预计 2 但实际 0，不能按预计伤害挂枪口。
	var cs := _ready_cs(46002)
	cs.enemies[0].tags.append("石头")
	cs.magazine.set_slot(0, HUIWEI)
	cs.magazine.set_slot(1, BAIBAN)
	cs._volley_session = true
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	assert_eq(cs.last_shot_planned_damage, 2)
	assert_eq(cs.last_shot_dealt, 0)
	assert_eq(_huiwei_amount(cs), 0)
	while not cs.enemies.is_empty():
		cs.enemies.pop_back()
	cs.dev_spawn_enemy(CombatConstants.DUMMY_ENEMY_ID, 4)
	cs.enemies[cs.enemies.size() - 1].hp = 99
	cs.enemies[cs.enemies.size() - 1].max_hp = 99
	cs.enemies[cs.enemies.size() - 1].atk = 0
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	assert_eq(cs.last_shot_planned_damage, 3)
	assert_eq(cs.last_shot_dealt, 3)
	cs._volley_session = false
	cs._reset_volley_plan()


func test_huiwei_no_damage_grants_no_phantom_buff() -> void:
	var cs := _ready_cs(46003)
	while not cs.enemies.is_empty():
		cs.enemies.pop_back()
	cs.magazine.set_slot(0, HUIWEI)
	cs.magazine.set_slot(1, BAIBAN)
	cs._volley_session = true
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	assert_eq(cs.last_shot_dealt, 0)
	assert_eq(_huiwei_amount(cs), 0)
	assert_true(cs.volley_muzzle_buffs().is_empty())
	cs.dev_spawn_enemy(CombatConstants.DUMMY_ENEMY_ID, 3)
	cs.enemies[cs.enemies.size() - 1].hp = 99
	cs.enemies[cs.enemies.size() - 1].max_hp = 99
	cs.enemies[cs.enemies.size() - 1].atk = 0
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	assert_eq(cs.last_shot_dealt, 3)
	assert_eq(_huiwei_amount(cs), 0)
	cs._volley_session = false
	cs._reset_volley_plan()


func test_huiwei_stacks_and_magazine_end_cleanup() -> void:
	var cs := _ready_cs(46004)
	cs.magazine.set_slot(0, HUIWEI)
	cs.magazine.set_slot(1, HUIWEI)
	cs.magazine.set_slot(2, BAIBAN)
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	cs.fire_tap(true)
	assert_eq(cs.last_shot_dealt, 11)  # 3 + 2（第一发）+ 4（第二发实际）
	assert_false(cs.volley_muzzle_buffs().is_empty(), "未消耗的层保留，不按弹夹或时间清除")


func test_huiwei_subsequent_zhongshen_sees_buffed_shots() -> void:
	# 回味打 2，白板变成 5，终审 prior=7 一半 3.5，且终审本身也吃回味 +2 → 5.5→6
	var cs := _ready_cs(46005)
	cs.magazine.set_slot(0, HUIWEI)
	cs.magazine.set_slot(1, BAIBAN)
	cs.magazine.set_slot(2, ZHONGSHEN)
	cs._volley_session = true
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	assert_eq(cs.last_shot_dealt, 7)
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	assert_eq(cs.last_shot_planned_damage, 7)  # 3.5 + 2 → 5.5 → 6
	assert_eq(cs.last_shot_dealt, 7)
	cs._volley_session = false
	cs._reset_volley_plan()


func test_mofang_of_huiwei_keeps_base_3_then_hangs_dealt() -> void:
	var cs := _ready_cs(46006)
	cs.magazine.set_slot(0, HUIWEI)
	cs.magazine.set_slot(1, MOFANG)
	cs.magazine.set_slot(2, BAIBAN)
	cs._volley_session = true
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	assert_eq(cs.last_shot_dealt, 2)
	assert_eq(_huiwei_amount(cs), 4)
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	# 模仿自身伤害 3+2，并再按实际 5 累加回味
	assert_eq(cs.last_shot_dealt, 7)
	assert_eq(_huiwei_amount(cs), 9)
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	assert_eq(cs.last_shot_dealt, 12)
	cs._volley_session = false
	cs._reset_volley_plan()
