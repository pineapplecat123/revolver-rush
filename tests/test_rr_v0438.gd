extends GutTest
## v0.4.38：开始类型子弹互不影响（起势/蓄力不作用在开始弹上）。

const WHITE := CombatConstants.WHITE_AMMO_ID
const QISHI := CombatConstants.QISHI_AMMO_ID
const XULI := CombatConstants.XULI_AMMO_ID
const DIZENG := CombatConstants.DIZENG_AMMO_ID
const ZHONGSHEN := CombatConstants.ZHONGSHEN_AMMO_ID
const EMPTY := Magazine.EMPTY


func before_each() -> void:
	DataRegistry.reload()


func test_version_is_at_least_0_4_38() -> void:
	assert_true(GameVersion.STRING >= "0.4.38")
	assert_true("0.4.38" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_is_start_type_is_tag_driven() -> void:
	assert_true(FireResolver.is_start_type(QISHI))
	assert_true(FireResolver.is_start_type(XULI))
	assert_false(FireResolver.is_start_type(WHITE))
	assert_false(FireResolver.is_start_type(DIZENG))
	assert_false(FireResolver.is_start_type(ZHONGSHEN))
	assert_false(FireResolver.is_start_type(EMPTY))
	assert_eq(AmmoColors.type_tag_of(DataRegistry.get_ammo(QISHI)), "开始")
	assert_eq(AmmoColors.type_tag_of(DataRegistry.get_ammo(XULI)), "开始")


func test_xuli_passes_through_qishi_to_plain() -> void:
	# 蓄力→起势→平庸：平庸 ×1.5×1.1
	var d: Array[float] = FireResolver.compute_volley_damages([XULI, QISHI, WHITE])
	assert_almost_eq(d[0], 0.0, 0.0001)
	assert_almost_eq(d[1], 0.0, 0.0001)
	assert_almost_eq(d[2], 3.0 * 1.5 * 1.1, 0.0001)


func test_xuli_chains_through_start_and_empties() -> void:
	# 两颗蓄力中间夹起势，仍连乘到 ×2.25，再加起势 +10%
	var d: Array[float] = FireResolver.compute_volley_damages([XULI, QISHI, XULI, WHITE])
	assert_almost_eq(d[3], 3.0 * 2.25 * 1.1, 0.0001)
	# 空仓仍不消耗；起势也不消耗
	var with_empty: Array[float] = FireResolver.compute_volley_damages([
		XULI, EMPTY, QISHI, EMPTY, WHITE
	])
	assert_almost_eq(with_empty[4], 3.0 * 1.5 * 1.1, 0.0001)
	# 连续蓄力仍连乘（中间无非开始弹）
	var chain: Array[float] = FireResolver.compute_volley_damages([XULI, XULI, WHITE])
	assert_almost_eq(chain[2], 3.0 * 2.25, 0.0001)


func test_qishi_bonus_skips_start_applies_to_mid_and_end() -> void:
	# 起势→蓄力→平庸：蓄力（开始）不吃 +10%，平庸吃两种加成
	var d: Array[float] = FireResolver.compute_volley_damages([QISHI, XULI, WHITE])
	assert_almost_eq(d[1], 0.0, 0.0001)
	assert_almost_eq(d[2], 3.0 * 1.5 * 1.1, 0.0001)
	# 递增（中间）仍吃起势与蓄力：第 3 格 3+1.5=4.5，×1.1×1.5
	var mid: Array[float] = FireResolver.compute_volley_damages([QISHI, XULI, DIZENG])
	assert_almost_eq(mid[2], 4.5 * 1.1 * 1.5, 0.0001)
	# 终审（结束）仍吃两种加成
	var end: Array[float] = FireResolver.compute_volley_damages([QISHI, XULI, WHITE, ZHONGSHEN])
	assert_almost_eq(end[2], 4.95, 0.0001)
	assert_almost_eq(end[3], 2.475 * 1.1, 0.0001)
	# 两颗起势仍对非开始弹加叠
	var stacked: Array[float] = FireResolver.compute_volley_damages([QISHI, QISHI, WHITE])
	assert_almost_eq(stacked[2], 3.0 * 1.2, 0.0001)
