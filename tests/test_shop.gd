extends GutTest

const ShopState = preload("res://scripts/shop/shop_state.gd")
const ShopConstants = preload("res://scripts/shop/shop_constants.gd")
## 商店灰盒：买 / 删 / 递增费用 / 离店重置 / 重随。


func before_each() -> void:
	DataRegistry.reload()


func test_buy_adds_ammo_and_spends_gold() -> void:
	var shop := ShopState.new()
	shop.begin(50, [CombatConstants.WHITE_AMMO_ID], 3, 11)
	assert_eq(shop.stock.size(), ShopConstants.STOCK_SIZE)
	assert_true(shop.can_buy(0))
	var before_bag := shop.bag.size()
	var ammo_id: int = shop.stock[0]
	assert_true(shop.buy(0))
	assert_eq(shop.gold, 50 - ShopConstants.AMMO_PRICE)
	assert_eq(shop.bag.size(), before_bag + 1)
	assert_eq(shop.bag[shop.bag.size() - 1], ammo_id)
	assert_true(shop.sold[0])
	assert_false(shop.can_buy(0))


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
	# 再次进店：移除费用从 10 起
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
	# first_stock may equal by chance; just ensure sold flags reset
	for s in shop.sold:
		assert_false(s)
	first_stock = first_stock  # silence unused if identical


func test_cannot_remove_sin_ammo() -> void:
	## 设计：罪孽弹药不能被删除；商店移除须拦截（平庸仍可删）。
	var shop := ShopState.new()
	var bag: Array[int] = [
		CombatConstants.WHITE_AMMO_ID,
		FireResolver.ID_WRATH,
		FireResolver.ID_PRIDE,
		FireResolver.ID_GREED,
	]
	shop.begin(100, bag, 3, 66)
	assert_false(DataRegistry.is_sin_ammo(CombatConstants.WHITE_AMMO_ID))
	assert_true(DataRegistry.is_sin_ammo(FireResolver.ID_WRATH))
	assert_true(DataRegistry.is_sin_ammo(FireResolver.ID_PRIDE))
	assert_true(DataRegistry.is_sin_ammo(FireResolver.ID_GREED))
	# 罪孽索引不可移除
	assert_false(shop.can_remove_at(1))
	assert_false(shop.remove_at(1))
	assert_string_contains(shop.last_message, "罪孽")
	assert_eq(shop.bag.size(), 4)
	assert_eq(shop.gold, 100)
	assert_eq(shop.removes_done, 0)
	assert_false(shop.remove_at(2))
	assert_false(shop.remove_at(3))
	# 平庸仍可删
	assert_true(shop.can_remove_at(0))
	assert_true(shop.remove_at(0))
	assert_eq(shop.bag.size(), 3)
	assert_eq(shop.removes_done, 1)
	assert_eq(shop.gold, 100 - ShopConstants.REMOVE_BASE_COST)
	# 删后袋内只剩罪孽，仍不可删
	assert_false(shop.can_remove_at(0))
	assert_false(shop.remove_at(0))

