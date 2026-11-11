extends GutTest

const ShopState = preload("res://scripts/shop/shop_state.gd")
const ShopConstants = preload("res://scripts/shop/shop_constants.gd")
## 商店：买 / 删 / 递增费用 / 离店重置 / 重随 / 稀有度定价与权重。


func before_each() -> void:
	DataRegistry.reload()


func test_buy_adds_ammo_and_spends_gold() -> void:
	var shop := ShopState.new()
	shop.begin(50, [CombatConstants.WHITE_AMMO_ID], 3, 11)
	assert_eq(shop.stock.size(), ShopConstants.STOCK_SIZE)
	assert_true(shop.can_buy(0))
	var before_bag := shop.bag.size()
	var ammo_id: int = shop.stock[0]
	var price: int = shop.ammo_price(ammo_id)
	assert_true(shop.buy(0))
	assert_eq(shop.gold, 50 - price)
	assert_eq(shop.bag.size(), before_bag + 1)
	assert_eq(shop.bag[shop.bag.size() - 1], ammo_id)
	assert_true(shop.sold[0])
	assert_false(shop.can_buy(0))


func test_ammo_price_scales_by_rarity() -> void:
	var shop := ShopState.new()
	assert_eq(shop.ammo_price(CombatConstants.WHITE_AMMO_ID), int(ShopConstants.RARITY_PRICE["common"]))
	assert_eq(ShopConstants.price_for_rarity("uncommon"), int(ShopConstants.RARITY_PRICE["uncommon"]))
	assert_eq(ShopConstants.price_for_rarity("epic"), int(ShopConstants.RARITY_PRICE["epic"]))


func test_all_enabled_reward_ammo_have_rarity() -> void:
	for item in DataRegistry.all_ammo():
		var aid: int = int(item.get("id", 0))
		if not DataRegistry.is_ammo_reward_eligible(aid):
			continue
		var r: String = DataRegistry.get_ammo_rarity(aid)
		assert_true(
			r in ["common", "uncommon", "rare", "epic"],
			"ammo %d rarity=%s" % [aid, r]
		)


func test_stock_roll_prefers_lower_rarity_over_many_seeds() -> void:
	## 统计多 seed：common+uncommon 应明显多于 epic（权重 45+30 vs 7）。
	var counts := {"common": 0, "uncommon": 0, "rare": 0, "epic": 0}
	var total := 0
	for seed_v in range(1, 81):
		var shop := ShopState.new()
		shop.begin(100, [CombatConstants.WHITE_AMMO_ID], 1, seed_v * 97)
		for aid in shop.stock:
			var r: String = DataRegistry.get_ammo_rarity(int(aid))
			counts[r] = int(counts.get(r, 0)) + 1
			total += 1
	assert_eq(total, 80 * ShopConstants.STOCK_SIZE)
	assert_gt(counts["common"] + counts["uncommon"], counts["epic"] * 2)
	assert_gt(counts["common"] + counts["uncommon"] + counts["rare"], 0)


func test_remove_cost_escalates_then_resets_on_leave() -> void:
	var shop := ShopState.new()
	var bag: Array[int] = []
	for _i in 4:
		bag.append(CombatConstants.WHITE_AMMO_ID)
	shop.begin(100, bag, 3, 22)
	assert_eq(shop.next_remove_cost(), ShopConstants.REMOVE_BASE_COST)
	assert_true(shop.remove_at(0))
	assert_eq(shop.removes_done, 1)
	assert_eq(shop.gold, 100 - ShopConstants.REMOVE_BASE_COST)
	assert_eq(shop.next_remove_cost(), ShopConstants.REMOVE_BASE_COST + ShopConstants.REMOVE_COST_STEP)
	assert_true(shop.remove_at(0))
	assert_eq(shop.removes_done, 2)
	assert_eq(
		shop.gold,
		100 - ShopConstants.REMOVE_BASE_COST - (ShopConstants.REMOVE_BASE_COST + ShopConstants.REMOVE_COST_STEP)
	)
	var payload := shop.end_session()
	assert_false(shop.open)
	assert_eq(shop.removes_done, 0)
	shop.begin(int(payload["gold"]), payload["bag"], 3, 33)
	assert_eq(shop.next_remove_cost(), ShopConstants.REMOVE_BASE_COST)
	assert_eq(shop.removes_done, 0)


func test_reroll_free_then_paid() -> void:
	var shop := ShopState.new()
	shop.begin(20, [CombatConstants.WHITE_AMMO_ID], 3, 44)
	assert_eq(shop.reroll_cost_now(), 0)
	assert_eq(shop.free_rerolls_left, ShopConstants.FREE_REROLLS)
	var first_stock := shop.stock.duplicate()
	assert_true(shop.reroll())
	assert_eq(shop.free_rerolls_left, ShopConstants.FREE_REROLLS - 1)
	assert_eq(shop.gold, 20)
	assert_eq(shop.reroll_cost_now(), ShopConstants.REROLL_COST)
	assert_true(shop.reroll())
	assert_eq(shop.gold, 20 - ShopConstants.REROLL_COST)
	assert_eq(shop.stock.size(), ShopConstants.STOCK_SIZE)
	for s in shop.sold:
		assert_false(s)
	first_stock = first_stock

