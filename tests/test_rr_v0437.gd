extends GutTest
## v0.4.37：清算四弹（起势/蓄力/递增/终审）、开局袋扩充、类型默认色。

const WHITE := CombatConstants.WHITE_AMMO_ID
const QISHI := CombatConstants.QISHI_AMMO_ID
const XULI := CombatConstants.XULI_AMMO_ID
const DIZENG := CombatConstants.DIZENG_AMMO_ID
const ZHONGSHEN := CombatConstants.ZHONGSHEN_AMMO_ID
const EMPTY := Magazine.EMPTY


func before_each() -> void:
	DataRegistry.reload()


func test_version_is_at_least_0_4_37() -> void:
	assert_true(GameVersion.STRING >= "0.4.37")
	assert_true("0.4.37" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_ammo_defs_and_tag_colors() -> void:
	assert_eq(str(DataRegistry.get_ammo(QISHI).get("name")), "起势弹")
	assert_eq(str(DataRegistry.get_ammo(XULI).get("name")), "蓄力弹")
	assert_eq(str(DataRegistry.get_ammo(DIZENG).get("name")), "递增弹")
	assert_eq(str(DataRegistry.get_ammo(ZHONGSHEN).get("name")), "终审弹")
	assert_eq(AmmoColors.type_tag_of(DataRegistry.get_ammo(QISHI)), "开始")
	assert_eq(AmmoColors.type_tag_of(DataRegistry.get_ammo(XULI)), "开始")
	assert_eq(AmmoColors.type_tag_of(DataRegistry.get_ammo(DIZENG)), "中间")
	assert_eq(AmmoColors.type_tag_of(DataRegistry.get_ammo(ZHONGSHEN)), "结束")
	var g: Dictionary = AmmoColors.colors_for(QISHI)
	var y: Dictionary = AmmoColors.colors_for(DIZENG)
	var r: Dictionary = AmmoColors.colors_for(ZHONGSHEN)
	assert_gt((g["bg"] as Color).g, (g["bg"] as Color).r)
	assert_gt((y["bg"] as Color).r, 0.7)
	assert_gt((y["bg"] as Color).g, 0.6)
	assert_gt((r["bg"] as Color).r, (r["bg"] as Color).g)
	# 平庸无标签，保持浅灰白
	var w: Dictionary = AmmoColors.colors_for(WHITE)
	assert_gt((w["bg"] as Color).r, 0.85)
	assert_almost_eq((w["bg"] as Color).r, (w["bg"] as Color).g, 0.05)


func test_qishi_additive_stacking() -> void:
	# 起势, 起势, 平庸, 平庸 → 平庸各 ×1.20
	var d: Array[float] = FireResolver.compute_volley_damages([QISHI, QISHI, WHITE, WHITE])
	assert_almost_eq(d[0], 0.0, 0.0001)
	assert_almost_eq(d[1], 0.0, 0.0001)
	assert_almost_eq(d[2], 3.0 * 1.2, 0.0001)
	assert_almost_eq(d[3], 3.0 * 1.2, 0.0001)
	# 单颗起势：+10%
	var one: Array[float] = FireResolver.compute_volley_damages([QISHI, WHITE])
	assert_almost_eq(one[1], 3.3, 0.0001)


func test_xuli_chain_2_25() -> void:
	# 两颗蓄力连着，下一发 ×2.25
	var d: Array[float] = FireResolver.compute_volley_damages([XULI, XULI, WHITE])
	assert_almost_eq(d[0], 0.0, 0.0001)
	assert_almost_eq(d[1], 0.0, 0.0001)
	assert_almost_eq(d[2], 3.0 * 2.25, 0.0001)
	# 空仓不消耗蓄力
	var with_empty: Array[float] = FireResolver.compute_volley_damages([XULI, EMPTY, EMPTY, WHITE])
	assert_almost_eq(with_empty[3], 4.5, 0.0001)
	# v0.4.38：开始弹互不影响，蓄力穿过起势落到平庸（×1.5×1.1）
	var pass_through: Array[float] = FireResolver.compute_volley_damages([XULI, QISHI, WHITE])
	assert_almost_eq(pass_through[1], 0.0, 0.0001)
	assert_almost_eq(pass_through[2], 3.0 * 1.5 * 1.1, 0.0001, "蓄力穿过起势，平庸吃 ×1.5×1.1")


func test_dizeng_slot_counts_empty_chambers() -> void:
	# 第 1 格：3+0.5=3.5；隔 4 个空仓后第 6 格：3+3=6
	var d: Array[float] = FireResolver.compute_volley_damages([
		DIZENG, EMPTY, EMPTY, EMPTY, EMPTY, DIZENG
	])
	assert_almost_eq(d[0], 3.5, 0.0001)
	assert_almost_eq(d[1], 0.0, 0.0001)
	assert_almost_eq(d[5], 6.0, 0.0001)
	# 只打第 6 位
	var only6: Array[float] = FireResolver.compute_volley_damages([
		EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, DIZENG
	])
	assert_almost_eq(only6[5], 6.0, 0.0001)


func test_zhongshen_half_of_prior_including_buffs_and_overkill() -> void:
	# 平庸 3 + 平庸 3，终审 = 3
	var plain: Array[float] = FireResolver.compute_volley_damages([WHITE, WHITE, ZHONGSHEN])
	assert_almost_eq(plain[2], 3.0, 0.0001)
	# 起势后两发平庸各 3.3（含加成，与敌人 HP 无关）；终审基础 3.3，再吃起势 ×1.1 = 3.63
	var buffed: Array[float] = FireResolver.compute_volley_damages([QISHI, WHITE, WHITE, ZHONGSHEN])
	assert_almost_eq(buffed[1], 3.3, 0.0001)
	assert_almost_eq(buffed[2], 3.3, 0.0001)
	assert_almost_eq(buffed[3], 3.63, 0.0001)
	# 终审自己也吃起势与蓄力：先前只有一发平庸 3，终审基础 1.5，×1.1×1.5
	var on_zhong: Array[float] = FireResolver.compute_volley_damages([QISHI, XULI, WHITE, ZHONGSHEN])
	# 平庸：3 * 1.1 * 1.5 = 4.95；终审基础 4.95/2，×1.1（一颗起势）且蓄力已消耗
	assert_almost_eq(on_zhong[2], 4.95, 0.0001)
	assert_almost_eq(on_zhong[3], 2.475 * 1.1, 0.0001)
	# 蓄力直接接到终审
	var xuli_z: Array[float] = FireResolver.compute_volley_damages([WHITE, XULI, ZHONGSHEN])
	# 终审基础 3/2=1.5，×1.5 蓄力 = 2.25
	assert_almost_eq(xuli_z[2], 2.25, 0.0001)


func test_buffs_reset_each_volley() -> void:
	var mag := Magazine.new()
	mag.set_slot(0, QISHI)
	mag.set_slot(1, WHITE)
	var first: Array[float] = FireResolver.compute_volley_damages(mag.volley_sequence())
	assert_almost_eq(first[1], 3.3, 0.0001)
	# 新的一轮（同样排列）不会继承上一轮起势
	var second: Array[float] = FireResolver.compute_volley_damages(mag.volley_sequence())
	assert_almost_eq(second[1], 3.3, 0.0001)
	# 战斗里两轮连射：打完后再装同样两发，第二轮平庸仍是 3.3 而不是 3.6
	var cs := CombatState.new(43701)
	cs.start_rush(43701, FireResolver.ID_WRATH)
	cs.pace_after_fire = false
	while not cs.enemies.is_empty():
		cs.enemies.pop_back()
	cs.dev_spawn_enemy(1, 5)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.enemies[0].atk = 0
	cs.magazine.clear()
	cs.magazine.start_index = 0
	cs.magazine.set_slot(0, QISHI)
	cs.magazine.set_slot(1, WHITE)
	var shots1: Array = cs.fire_tap(true)
	assert_gt(shots1.size(), 0)
	# 第二轮重新装
	cs.player_fire_gate_remaining = 0.0
	cs.magazine.clear()
	cs.magazine.start_index = 0
	cs.magazine.set_slot(0, QISHI)
	cs.magazine.set_slot(1, WHITE)
	assert_true(cs.begin_fire())
	# 计划应是新一轮：平庸计算伤害 3.3，落地四舍五入为 3
	var planned: Array[int] = cs._fire_damages
	assert_eq(planned[0], 0, "第二轮起势仍是 0")
	# begin_fire 只排队第一发；再看整轮计划
	var seq: Array[float] = FireResolver.compute_volley_damages(cs.magazine.volley_sequence())
	assert_almost_eq(seq[1], 3.3, 0.0001)


func test_zero_damage_does_not_count_as_hit() -> void:
	var cs := CombatState.new(43702)
	cs.start_rush(43702, FireResolver.ID_WRATH)
	cs.pace_after_fire = false
	while not cs.enemies.is_empty():
		cs.enemies.pop_back()
	cs.dev_spawn_enemy(1, 5)
	var hp0: int = cs.enemies[0].hp
	cs.magazine.clear()
	cs.magazine.start_index = 0
	cs.magazine.set_slot(0, QISHI)
	var shots: Array = cs.fire_tap(true)
	assert_gt(shots.size(), 0)
	assert_eq(cs.enemies[0].hp, hp0)
	assert_eq(cs.last_shot_dealt, 0)
	assert_eq(cs.dmg_stats_hits, 0)


func test_starter_bag_has_clearing_bullets() -> void:
	var cs := CombatState.new()
	cs.start_rush(43703, FireResolver.ID_WRATH)
	assert_eq(cs.bag.size(), CombatConstants.STARTER_BAG_TOTAL)
	assert_eq(cs.total_ammo_count(WHITE), CombatConstants.STARTER_WHITE_COUNT)
	assert_eq(cs.total_ammo_count(QISHI), 2)
	assert_eq(cs.total_ammo_count(XULI), 2)
	assert_eq(cs.total_ammo_count(DIZENG), 2)
	assert_eq(cs.total_ammo_count(ZHONGSHEN), 2)


func test_round_damage_half_away_from_zero() -> void:
	assert_eq(FireResolver.round_damage(3.3), 3)
	assert_eq(FireResolver.round_damage(3.5), 4)
	assert_eq(FireResolver.round_damage(4.5), 5)
	assert_eq(FireResolver.round_damage(2.25), 2)
	assert_eq(FireResolver.round_damage(2.475 * 1.1), 3)
