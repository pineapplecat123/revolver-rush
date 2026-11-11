extends GutTest
## v0.4.15 商店稀有度：弹药 rarity、加权货架、按档定价。

const ShopState = preload("res://scripts/shop/shop_state.gd")
const ShopConstants = preload("res://scripts/shop/shop_constants.gd")


func before_each() -> void:
	DataRegistry.reload()


func test_changelog_has_0_4_15_entry() -> void:
	## 版本号会继续递增；此处只断言 0.4.15 条目仍在更新日志中。
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.15"' in text or '"version":"0.4.15"' in text)


func test_shop_pool_rarity_table_snapshot() -> void:
	## 本分支商店池只剩平庸。
	assert_eq(DataRegistry.all_ammo().size(), 1)
	assert_true(DataRegistry.is_ammo_reward_eligible(CombatConstants.WHITE_AMMO_ID))
	assert_eq(DataRegistry.get_ammo_rarity(CombatConstants.WHITE_AMMO_ID), "common")


func test_price_formula_matches_constants() -> void:
	var shop := ShopState.new()
	assert_eq(shop.ammo_price(1), 5)
	assert_eq(ShopConstants.price_for_rarity("common"), 5)
	assert_eq(ShopConstants.price_for_rarity("uncommon"), 8)
	assert_eq(ShopConstants.price_for_rarity("rare"), 14)
	assert_eq(ShopConstants.price_for_rarity("epic"), 22)


func test_weighted_stock_has_five_slots() -> void:
	var shop := ShopState.new()
	shop.begin(99, [CombatConstants.WHITE_AMMO_ID], 2, 41515)
	assert_eq(shop.stock.size(), 5)
	for aid in shop.stock:
		assert_true(DataRegistry.is_ammo_reward_eligible(int(aid)))
