extends GutTest
## v0.4.19 按压测强弱重排弹药稀有度（数值不动）。

const ShopState = preload("res://scripts/shop/shop_state.gd")
const ShopConstants = preload("res://scripts/shop/shop_constants.gd")


func before_each() -> void:
	DataRegistry.reload()


func test_version_is_0_4_19() -> void:
	## 版本号会继续递增；此处只断言 0.4.19 条目仍在更新日志中。
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.19"' in text or '"version":"0.4.19"' in text)


func test_rarity_remap_snapshot() -> void:
	## 商店池关键档位契约（改档须同步本表与设计表）。
	var expect := {
		1: "common",
		8: "uncommon",
		16: "epic",
		17: "rare",
		18: "rare",
		19: "epic",
		21: "rare",
		22: "uncommon",
		23: "epic",
		24: "epic",
		25: "uncommon",
		26: "rare",
		27: "epic",
		28: "uncommon",
		29: "common",
		30: "uncommon",
		31: "uncommon",
		33: "epic",
		34: "rare",
		35: "rare",
		36: "rare",
		37: "rare",
	}
	var sins := [16, 17, 18, 34, 35, 36, 37]
	for aid in expect.keys():
		if int(aid) in sins:
			assert_false(DataRegistry.is_ammo_reward_eligible(int(aid)), "sin stays out of shop %s" % aid)
		else:
			assert_true(DataRegistry.is_ammo_reward_eligible(int(aid)), "eligible %s" % aid)
		assert_eq(DataRegistry.get_ammo_rarity(int(aid)), expect[aid], "rarity id=%s" % aid)


func test_remapped_prices_follow_rarity() -> void:
	var shop := ShopState.new()
	assert_eq(shop.ammo_price(29), int(ShopConstants.RARITY_PRICE["common"]))  # 保险
	assert_eq(shop.ammo_price(28), int(ShopConstants.RARITY_PRICE["uncommon"]))  # 散射
	assert_eq(shop.ammo_price(21), int(ShopConstants.RARITY_PRICE["rare"]))  # 连发
	assert_eq(shop.ammo_price(26), int(ShopConstants.RARITY_PRICE["rare"]))  # 火焰
	assert_eq(shop.ammo_price(24), int(ShopConstants.RARITY_PRICE["epic"]))  # 回声
	assert_eq(shop.ammo_price(23), int(ShopConstants.RARITY_PRICE["epic"]))  # 倾泻
	assert_eq(shop.ammo_price(16), int(ShopConstants.RARITY_PRICE["epic"]))  # 愤怒
	assert_eq(shop.ammo_price(27), int(ShopConstants.RARITY_PRICE["epic"]))  # 炸药
	assert_eq(shop.ammo_price(19), 22)  # 墓碑仍史诗
	assert_eq(shop.ammo_price(33), 22)  # 正义仍史诗
