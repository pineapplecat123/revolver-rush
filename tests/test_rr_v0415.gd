extends GutTest
## v0.4.15 商店稀有度：弹药 rarity、加权货架、按档定价。

const ShopState = preload("res://scripts/shop/shop_state.gd")
const ShopConstants = preload("res://scripts/shop/shop_constants.gd")


func before_each() -> void:
	DataRegistry.reload()


func test_version_is_0_4_15() -> void:
	assert_eq(GameVersion.STRING, "0.4.15")
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.15"' in text or '"version":"0.4.15"' in text)


func test_shop_pool_rarity_table_snapshot() -> void:
	## 商店池关键档位契约（改档须同步本表与设计表）。
	var expect := {
		1: "common",
		8: "uncommon",
		16: "rare",
		17: "rare",
		18: "rare",
		19: "epic",
		21: "uncommon",
		22: "uncommon",
		23: "rare",
		24: "rare",
		25: "uncommon",
		26: "uncommon",
		27: "rare",
		28: "rare",
		29: "uncommon",
		30: "uncommon",
		31: "uncommon",
		33: "epic",
		34: "rare",
		35: "rare",
		36: "rare",
		37: "rare",
	}
	for aid in expect.keys():
		assert_true(DataRegistry.is_ammo_reward_eligible(int(aid)), "eligible %s" % aid)
		assert_eq(DataRegistry.get_ammo_rarity(int(aid)), expect[aid], "rarity id=%s" % aid)


func test_price_formula_matches_constants() -> void:
	var shop := ShopState.new()
	assert_eq(shop.ammo_price(1), 5)
	assert_eq(shop.ammo_price(22), 8)
	assert_eq(shop.ammo_price(24), 14)
	assert_eq(shop.ammo_price(19), 22)
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
