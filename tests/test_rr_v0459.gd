extends GutTest
## v0.4.59：入库更名弹与叠势/爆穿/传递；编辑器按类型给子弹颜色。


const QISHI := CombatConstants.QISHI_AMMO_ID
const XULI := CombatConstants.XULI_AMMO_ID
const DIZENG := CombatConstants.DIZENG_AMMO_ID
const ZHONGSHEN := CombatConstants.ZHONGSHEN_AMMO_ID
const CHETUI := CombatConstants.CHETUI_AMMO_ID
const XIANWEI := CombatConstants.XIANWEI_AMMO_ID
const DIESHI := CombatConstants.DIESHI_AMMO_ID
const BAOCHUAN := CombatConstants.BAOCHUAN_AMMO_ID
const CHUANDI := CombatConstants.CHUANDI_AMMO_ID
const BAIBAN := CombatConstants.BAIBAN_AMMO_ID
const EMPTY := Magazine.EMPTY


func before_each() -> void:
	DataRegistry.reload()
	CombatState.boot_sandbox = false


func test_version_is_at_least_0_4_59() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.59") >= 0)
	assert_true("0.4.59" in FileAccess.get_file_as_string("res://data/changelog.json"))
	assert_true("叠势弹" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_renamed_ingested_ammo_keep_ids() -> void:
	assert_eq(str(DataRegistry.get_ammo(QISHI).get("name")), "加伤弹")
	assert_eq(str(DataRegistry.get_ammo(XULI).get("name")), "倍伤弹")
	assert_eq(str(DataRegistry.get_ammo(DIZENG).get("name")), "伤害递增弹")
	assert_eq(str(DataRegistry.get_ammo(ZHONGSHEN).get("name")), "总伤二分弹")
	assert_eq(str(DataRegistry.get_ammo(CHETUI).get("name")), "随机复制弹")
	assert_eq(str(DataRegistry.get_ammo(XIANWEI).get("name")), "吃尾弹")
	assert_eq(FireResolver.type_tag(QISHI), "开始")
	assert_eq(FireResolver.type_tag(CHETUI), "开始")
	assert_eq(FireResolver.type_tag(XIANWEI), "开始")
	assert_eq(FireResolver.type_tag(DIZENG), "中间")
	assert_eq(FireResolver.type_tag(ZHONGSHEN), "结束")


func test_flames_preserve_zero_damage_start_types_and_empty_chambers() -> void:
	# t640：零伤害开始弹与空仓保留火焰；不是按开始类型豁免。
	var d: Array[float] = FireResolver.compute_volley_damages([QISHI, QISHI, BAIBAN])
	assert_almost_eq(d[2], 10.125, 0.0001)  # 三层逐层相乘：3×1.5³
	d = FireResolver.compute_volley_damages([XULI, QISHI, BAIBAN])
	# 倍伤穿过开始弹，加伤再叠一层：3×1.5×1.5=6.75
	assert_almost_eq(d[2], 6.75, 0.0001)
	d = FireResolver.compute_volley_damages([XULI, EMPTY, BAIBAN])
	assert_almost_eq(d[2], 4.5, 0.0001)


func test_sui_ji_fu_zhi_still_copies_loaded() -> void:
	var cs := CombatState.new(45901)
	cs.start_sandbox(45901, FireResolver.ID_WRATH, false)
	cs.pace_after_fire = false
	cs.dev_clear_bag()
	cs.magazine.clear()
	cs.magazine.set_slot(0, CHETUI)
	cs.magazine.set_slot(1, BAIBAN)
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	cs.fire_tap(true)
	assert_eq(cs.bag.size(), 1)
	for i in cs.bag.size():
		assert_eq(float(cs.bag_temp[i]), CombatConstants.FIRE_ONCE_TEMP)
		assert_true(bool(cs.bag_envy_copy[i]))


func test_die_shi_bonus_needs_streak_of_two() -> void:
	var none: Array[int] = FireResolver.compute_shot_damages([DIESHI])
	assert_eq(none[0], 3)
	var one: Array[int] = FireResolver.compute_shot_damages([BAIBAN, DIESHI])
	assert_eq(one[1], 3, "n=1 不加伤")
	var two: Array[int] = FireResolver.compute_shot_damages([BAIBAN, BAIBAN, DIESHI])
	# 3 × (1 + 2×0.65) = 6.9 → 7
	assert_eq(two[2], 7)
	var three: Array[int] = FireResolver.compute_shot_damages([BAIBAN, BAIBAN, BAIBAN, DIESHI])
	# 3 × (1 + 3×0.65) = 8.85 → 9
	assert_eq(three[3], 9)
	# 空仓跳过且不打断
	var gap: Array[int] = FireResolver.compute_shot_damages([BAIBAN, EMPTY, BAIBAN, DIESHI])
	assert_eq(gap[3], 7)
	# 不同类型打断
	var cut: Array[int] = FireResolver.compute_shot_damages([ZHONGSHEN, BAIBAN, DIESHI])
	assert_eq(cut[2], 3)
	# 与加伤相乘：两层同类型后再叠势，再吃一层加伤
	var buff: Array[float] = FireResolver.compute_volley_damages([QISHI, BAIBAN, BAIBAN, DIESHI])
	assert_almost_eq(buff[3], 6.9 * 1.5, 0.0001)
	assert_eq(FireResolver.round_damage(buff[3]), 10)


func test_chuandi_passes_bonus_to_next_shot() -> void:
	# 两层加伤使传递 3×1.5²=6.75→7，超额4；白板先乘剩余加伤，再加4→9
	var d: Array[int] = FireResolver.compute_shot_damages([QISHI, CHUANDI, BAIBAN])
	assert_eq(d[1], 7)
	assert_eq(d[2], 9)
	# 没有加强则不传
	var plain: Array[int] = FireResolver.compute_shot_damages([CHUANDI, BAIBAN])
	assert_eq(plain[0], 3)
	assert_eq(plain[1], 3)
	# 空仓之后的下一颗实际子弹接收
	var gap: Array[int] = FireResolver.compute_shot_damages([QISHI, CHUANDI, EMPTY, BAIBAN])
	assert_eq(gap[1], 7)
	assert_eq(gap[3], 9)


func test_baochuan_pierces_only_when_planned_over_7() -> void:
	assert_false(FireResolver.shot_self_pierce(BAOCHUAN, 7))
	assert_true(FireResolver.shot_self_pierce(BAOCHUAN, 8))
	assert_false(FireResolver.shot_self_pierce(BAIBAN, 9))
	# 三次授予共六层：3×1.5⁶=34.171875→34
	var d: Array[int] = FireResolver.compute_shot_damages([QISHI, QISHI, QISHI, BAOCHUAN])
	assert_eq(d[3], 34)
	assert_true(FireResolver.shot_self_pierce(BAOCHUAN, d[3]))
	var low: Array[int] = FireResolver.compute_shot_damages([QISHI, BAOCHUAN])
	assert_eq(low[1], 5)
	assert_false(FireResolver.shot_self_pierce(BAOCHUAN, low[1]))


func test_baochuan_self_pierce_decays_and_does_not_mount_muzzle() -> void:
	var cs := CombatState.new(45910)
	cs.start_rush(45910, FireResolver.ID_WRATH)
	cs.pace_after_fire = false
	cs.defer_impacts = false
	cs.auto_enemy_advance = false
	while not cs.enemies.is_empty():
		cs.enemies.pop_back()
	for cell in [2, 4, 6]:
		cs.dev_spawn_enemy(CombatConstants.DUMMY_ENEMY_ID, cell)
		cs.enemies[cs.enemies.size() - 1].hp = 20
		cs.enemies[cs.enemies.size() - 1].max_hp = 20
		cs.enemies[cs.enemies.size() - 1].atk = 0
	assert_eq(cs.enemies.size(), 3)
	cs.magazine.clear()
	cs.magazine.start_index = 0
	cs.magazine.set_slot(0, QISHI)
	cs.magazine.set_slot(1, QISHI)
	cs.magazine.set_slot(2, QISHI)
	cs.magazine.set_slot(3, BAOCHUAN)
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	cs.fire_tap(true)
	assert_true(cs.last_shot_was_pierce)
	assert_eq(cs.last_shot_hit_amounts.size(), 3)
	assert_eq(cs.last_shot_hit_amounts[0], 34)
	assert_eq(cs.last_shot_hit_amounts[1], 33)
	assert_eq(cs.last_shot_hit_amounts[2], 32)
	assert_false(cs._muzzle_pierce, "爆穿只作用于本发，不应挂穿甲枪口")


func test_new_ammo_in_registry_and_reward_pool() -> void:
	assert_eq(str(DataRegistry.get_ammo(DIESHI).get("name")), "叠势弹")
	assert_eq(str(DataRegistry.get_ammo(BAOCHUAN).get("name")), "爆穿")
	assert_eq(str(DataRegistry.get_ammo(CHUANDI).get("name")), "传递弹")
	assert_eq(FireResolver.type_tag(DIESHI), "中间")
	assert_eq(FireResolver.type_tag(BAOCHUAN), "结束")
	assert_eq(FireResolver.type_tag(CHUANDI), "中间")
	assert_true(DataRegistry.is_ammo_reward_eligible(DIESHI))
	assert_true(DataRegistry.is_ammo_reward_eligible(BAOCHUAN))
	assert_true(DataRegistry.is_ammo_reward_eligible(CHUANDI))
	assert_eq(DataRegistry.all_ammo().size(), 20)


func test_editor_marks_ingested_and_blocks_ambiguous() -> void:
	var raw := FileAccess.get_file_as_string("res://companion/bullet-editor/data.json")
	assert_true("叠势弹" in raw)
	assert_true('"in_game": true' in raw)
	assert_true("模仿弹" in raw)
	assert_true("回味弹" in raw)
	var found_copy := false
	for item in DataRegistry.all_ammo():
		if str(item.get("name", "")) == "随机复制弹":
			found_copy = true
	assert_true(found_copy)
