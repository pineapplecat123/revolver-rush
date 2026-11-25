extends GutTest

const ShopState = preload("res://scripts/shop/shop_state.gd")
const ShopConstants = preload("res://scripts/shop/shop_constants.gd")
const CombatUiScene = preload("res://scenes/combat.tscn")
const MainScene = preload("res://scenes/main.tscn")
## 商店：买 / 删 / 递增费用 / 离店重置 / 重随 / 无稀有度随机库存与统一定价。


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
	assert_eq(price, ShopConstants.AMMO_PRICE)
	assert_true(shop.buy(0))
	assert_eq(shop.gold, 50 - price)
	assert_eq(shop.bag.size(), before_bag + 1)
	assert_eq(shop.bag[shop.bag.size() - 1], ammo_id)
	assert_true(shop.sold[0])
	assert_false(shop.can_buy(0))


func test_all_shop_ammo_uniform_five_gold() -> void:
	var shop := ShopState.new()
	assert_eq(ShopConstants.AMMO_PRICE, 5)
	for item in DataRegistry.all_ammo():
		var aid: int = int(item.get("id", 0))
		assert_eq(shop.ammo_price(aid), ShopConstants.AMMO_PRICE)
	var white_def: Dictionary = DataRegistry.get_ammo(CombatConstants.WHITE_AMMO_ID)
	white_def["price"] = 12
	assert_eq(shop.ammo_price(CombatConstants.WHITE_AMMO_ID), 5)
	white_def.erase("price")
	assert_eq(shop.ammo_price(CombatConstants.WHITE_AMMO_ID), ShopConstants.AMMO_PRICE)


func test_shop_constants_has_no_rarity_tables() -> void:
	var src: String = (load("res://scripts/shop/shop_constants.gd") as GDScript).source_code
	for token in ["const RARITY_", "RARITY_LABEL", "RARITY_WEIGHT", "RARITY_PRICE", "rarity_label", "price_for_rarity", "\"普通\"", "\"精良\"", "\"稀有\"", "\"史诗\""]:
		assert_false(token in src, "ShopConstants 不应保留稀有度定义：%s" % token)


func test_all_current_ammo_rarity_stays_blank() -> void:
	assert_eq(DataRegistry.all_ammo().size(), 28)
	for item in DataRegistry.all_ammo():
		var aid: int = int(item.get("id", 0))
		assert_eq(DataRegistry.get_ammo_rarity(aid), "", "未填写稀有度保持空白: ammo %d" % aid)
	assert_eq(DataRegistry.get_ammo_rarity(999999), "")


func test_stock_roll_uniform_no_rarity_tiers() -> void:
	var seen: Dictionary = {}
	var eligible: Array[int] = []
	for item in DataRegistry.all_ammo():
		var aid: int = int(item.get("id", 0))
		if DataRegistry.is_ammo_reward_eligible(aid):
			eligible.append(aid)
	for seed_v in range(1, 121):
		var shop := ShopState.new()
		shop.begin(100, [CombatConstants.WHITE_AMMO_ID], 1, seed_v * 97)
		assert_eq(shop.stock.size(), ShopConstants.STOCK_SIZE)
		var per_roll: Dictionary = {}
		for aid in shop.stock:
			var idv: int = int(aid)
			assert_true(DataRegistry.is_ammo_reward_eligible(idv))
			assert_false(per_roll.has(idv), "池足够时单次货架不重复")
			per_roll[idv] = true
			seen[idv] = int(seen.get(idv, 0)) + 1
	for aid in eligible:
		assert_gt(int(seen.get(aid, 0)), 0, "无稀有度加权后每发可买弹都应有机会出现: %d" % aid)


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


func test_shop_ui_hides_rarity_labels_and_weights() -> void:
	CombatState.boot_sandbox = true
	var ui = add_child_autofree(CombatUiScene.instantiate())
	await wait_process_frames(2)
	ui._open_rush_shop()
	await wait_process_frames(2)
	assert_true(ui._shop_open)
	var forbidden := ["普通", "精良", "稀有", "史诗", "稀有度"]
	var texts: Array[String] = [ui._shop_hint.text]
	for child in ui._shop_stock.get_children():
		if child is Label:
			texts.append((child as Label).text)
		for sub in child.get_children():
			if sub is Label:
				texts.append((sub as Label).text)
	var row_labels := 0
	for child in ui._shop_stock.get_children():
		if child is HBoxContainer:
			for sub in child.get_children():
				if sub is Label:
					row_labels += 1
					assert_true(("· %d 金" % ShopConstants.AMMO_PRICE) in (sub as Label).text)
	assert_eq(row_labels, ShopConstants.STOCK_SIZE)
	for t in texts:
		for bad in forbidden:
			assert_false(bad in t, "商店文案不应包含稀有度词 %s: %s" % [bad, t])
	ui._on_rush_shop_leave()


func test_codex_hides_blank_rarity_labels() -> void:
	var menu = add_child_autofree(MainScene.instantiate())
	await wait_process_frames(2)
	menu._on_codex_pressed()
	await wait_process_frames(2)
	var list: GridContainer = menu.get_node("%CodexList")
	var forbidden := ["普通", "精良", "稀有", "史诗"]
	var first_id := -1
	for cell in list.get_children():
		if str(cell.name).begins_with("CodexCell_"):
			if first_id < 0:
				first_id = int(str(cell.name).get_slice("_", 1))
			for sub in cell.find_children("*", "Label", true, false):
				var txt: String = (sub as Label).text
				for bad in forbidden:
					assert_false(txt == bad, "图鉴格子不应显示未填稀有度: %s" % txt)
	menu._on_codex_cell_pressed(first_id)
	await wait_process_frames(1)
	for sub in menu.get_node("%CodexDetailBody").find_children("*", "Label", true, false):
		var txt2: String = (sub as Label).text
		for bad in forbidden:
			assert_false(bad in txt2, "图鉴详情不应显示未填稀有度 %s: %s" % [bad, txt2])
	menu._on_codex_detail_close_pressed()
