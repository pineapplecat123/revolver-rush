extends GutTest
## v0.4.19 历史快照兼容（商店已去除稀有度分档与按档定价）。

const ShopState = preload("res://scripts/shop/shop_state.gd")
const ShopConstants = preload("res://scripts/shop/shop_constants.gd")


func before_each() -> void:
	DataRegistry.reload()


func test_version_is_0_4_19() -> void:
	## 版本号会继续递增；此处只断言 0.4.19 条目仍在更新日志中。
	var text := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true('"version": "0.4.19"' in text or '"version":"0.4.19"' in text)


func test_rarity_remap_snapshot() -> void:
	assert_eq(DataRegistry.get_ammo_rarity(CombatConstants.WHITE_AMMO_ID), "")
	assert_true(DataRegistry.get_ammo(8).is_empty())
	assert_true(DataRegistry.get_ammo(16).is_empty())


func test_remapped_prices_follow_rarity() -> void:
	var shop := ShopState.new()
	assert_eq(shop.ammo_price(CombatConstants.WHITE_AMMO_ID), ShopConstants.AMMO_PRICE)
