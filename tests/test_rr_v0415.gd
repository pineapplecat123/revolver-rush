extends GutTest
## v0.4.15 历史快照兼容（已移除商店稀有度分级后，确认白板与基础购买仍正常）。

const ShopState = preload("res://scripts/shop/shop_state.gd")
const ShopConstants = preload("res://scripts/shop/shop_constants.gd")


func before_each() -> void:
	DataRegistry.reload()


func test_changelog_has_0_4_15_entry() -> void:
	## 版本号会继续递增；此处只断言 0.4.15 条目仍在更新日志中。
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.15"' in text or '"version":"0.4.15"' in text)


func test_shop_pool_rarity_table_snapshot() -> void:
	## 28 颗现役弹药与退休平庸弹迁移保持兼容；未填稀有度保持空白。
	assert_eq(DataRegistry.all_ammo().size(), 28)
	assert_true(DataRegistry.is_ammo_reward_eligible(CombatConstants.XIANWEI_AMMO_ID))
	assert_true(DataRegistry.is_ammo_reward_eligible(CombatConstants.CHONGFU_KAISHI_AMMO_ID))
	assert_true(DataRegistry.is_ammo_reward_eligible(CombatConstants.BAIBAN_AMMO_ID))
	assert_eq(CombatConstants.WHITE_AMMO_ID, CombatConstants.BAIBAN_AMMO_ID)
	assert_true(DataRegistry.is_ammo_reward_eligible(CombatConstants.WHITE_AMMO_ID))
	assert_true(DataRegistry.is_ammo_reward_eligible(CombatConstants.WEIZHONG_AMMO_ID))
	assert_eq(DataRegistry.get_ammo_rarity(CombatConstants.WHITE_AMMO_ID), "")


func test_price_formula_matches_constants() -> void:
	var shop := ShopState.new()
	assert_eq(shop.ammo_price(CombatConstants.WHITE_AMMO_ID), ShopConstants.AMMO_PRICE)
	assert_eq(shop.ammo_price(CombatConstants.RETIRED_PINGYONG_AMMO_ID), ShopConstants.AMMO_PRICE)


func test_weighted_stock_has_five_slots() -> void:
	var shop := ShopState.new()
	shop.begin(99, [CombatConstants.WHITE_AMMO_ID], 2, 41515)
	assert_eq(shop.stock.size(), 5)
	for aid in shop.stock:
		assert_true(DataRegistry.is_ammo_reward_eligible(int(aid)))
