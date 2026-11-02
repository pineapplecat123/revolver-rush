class_name ShopState
## 商店会话逻辑（纯数据）。打开时拷贝 gold/bag；离开时写回 rush! 战斗状态。
## v0.4.15：库存按稀有度权重抽取；售价按稀有度；罪孽弹药不可去除。

const ShopConstants = preload("res://scripts/shop/shop_constants.gd")

var open: bool = false
var node_id: int = -1
var gold: int = 0
var bag: Array[int] = []
## 货架上的弹药 id；与 sold 等长
var stock: Array[int] = []
var sold: Array[bool] = []
var removes_done: int = 0
var free_rerolls_left: int = ShopConstants.FREE_REROLLS
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var last_message: String = ""


func begin(from_gold: int, from_bag: Array, shop_node_id: int, seed_value: int = 0) -> void:
	open = true
	node_id = shop_node_id
	gold = from_gold
	bag = _copy_ints(from_bag)
	removes_done = 0
	free_rerolls_left = ShopConstants.FREE_REROLLS
	last_message = ""
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	_roll_stock()


func end_session() -> Dictionary:
	## 离店：重置本店移除计数与免费重随（下次 begin 也会重置）。
	var payload := {
		"gold": gold,
		"bag": bag.duplicate(),
		"node_id": node_id,
	}
	open = false
	node_id = -1
	removes_done = 0
	free_rerolls_left = ShopConstants.FREE_REROLLS
	stock.clear()
	sold.clear()
	last_message = ""
	return payload


func ammo_price(ammo_id: int = 0) -> int:
	## 售价按稀有度；缺字段回退 uncommon=AMMO_PRICE。
	var rarity: String = DataRegistry.get_ammo_rarity(ammo_id)
	return ShopConstants.price_for_rarity(rarity)


func next_remove_cost() -> int:
	return ShopConstants.REMOVE_BASE_COST + removes_done * ShopConstants.REMOVE_COST_STEP


func reroll_cost_now() -> int:
	if free_rerolls_left > 0:
		return 0
	return ShopConstants.REROLL_COST


func can_buy(slot: int) -> bool:
	if not open:
		return false
	if slot < 0 or slot >= stock.size():
		return false
	if sold[slot]:
		return false
	return gold >= ammo_price(stock[slot])


func buy(slot: int) -> bool:
	if not can_buy(slot):
		last_message = "无法购买（已售出或金币不足）。"
		return false
	var ammo_id: int = stock[slot]
	var price: int = ammo_price(ammo_id)
	gold -= price
	bag.append(ammo_id)
	sold[slot] = true
	last_message = "购买 %s，-%d 金。" % [_ammo_name(ammo_id), price]
	return true


func can_remove_at(bag_index: int) -> bool:
	if not open:
		return false
	if bag_index < 0 or bag_index >= bag.size():
		return false
	if DataRegistry.is_sin_ammo(int(bag[bag_index])):
		return false
	return gold >= next_remove_cost()


func remove_at(bag_index: int) -> bool:
	if bag_index >= 0 and bag_index < bag.size() and DataRegistry.is_sin_ammo(int(bag[bag_index])):
		last_message = "罪孽弹药不可去除。"
		return false
	if not can_remove_at(bag_index):
		last_message = "无法移除（索引无效或金币不足）。"
		return false
	var cost: int = next_remove_cost()
	var ammo_id: int = bag[bag_index]
	gold -= cost
	bag.remove_at(bag_index)
	removes_done += 1
	last_message = "移除 %s，-%d 金（本店第 %d 次）。" % [_ammo_name(ammo_id), cost, removes_done]
	return true


func can_reroll() -> bool:
	if not open:
		return false
	return gold >= reroll_cost_now()


func reroll() -> bool:
	if not can_reroll():
		last_message = "金币不足，无法重随。"
		return false
	var cost: int = reroll_cost_now()
	if free_rerolls_left > 0:
		free_rerolls_left -= 1
		last_message = "免费重随库存。"
	else:
		gold -= cost
		last_message = "重随库存，-%d 金。" % cost
	_roll_stock()
	return true


func _roll_stock() -> void:
	var by_rarity: Dictionary = _pool_by_rarity()
	stock.clear()
	sold.clear()
	var used: Dictionary = {}
	for _i in ShopConstants.STOCK_SIZE:
		var aid: int = _pick_weighted_ammo(by_rarity, used)
		stock.append(aid)
		sold.append(false)
		used[aid] = true


func _pool_by_rarity() -> Dictionary:
	var out := {
		ShopConstants.RARITY_COMMON: [],
		ShopConstants.RARITY_UNCOMMON: [],
		ShopConstants.RARITY_RARE: [],
		ShopConstants.RARITY_EPIC: [],
	}
	for item in DataRegistry.all_ammo():
		var aid: int = int(item.get("id", 0))
		if not DataRegistry.is_ammo_reward_eligible(aid):
			continue
		var rarity: String = DataRegistry.get_ammo_rarity(aid)
		if not out.has(rarity):
			rarity = ShopConstants.RARITY_UNCOMMON
		out[rarity].append(aid)
	return out


func _pick_weighted_ammo(by_rarity: Dictionary, used: Dictionary) -> int:
	## 先按权重抽稀有度，再在该档未用尽的池中抽；档空则向下/向上找。
	var order: Array[String] = [
		ShopConstants.RARITY_COMMON,
		ShopConstants.RARITY_UNCOMMON,
		ShopConstants.RARITY_RARE,
		ShopConstants.RARITY_EPIC,
	]
	var weights: Array[int] = []
	var total := 0
	for r in order:
		var w: int = int(ShopConstants.RARITY_WEIGHT.get(r, 0))
		## 该档完全没货则权重记 0，避免抽空档
		if _available_in_tier(by_rarity, r, used).is_empty() and _any_in_tier(by_rarity, r).is_empty():
			w = 0
		weights.append(w)
		total += w
	var chosen_rarity: String = ShopConstants.RARITY_UNCOMMON
	if total > 0:
		var roll: int = rng.randi_range(1, total)
		var acc := 0
		for i in order.size():
			acc += weights[i]
			if roll <= acc:
				chosen_rarity = order[i]
				break
	var pick: int = _pick_from_tier_with_fallback(by_rarity, chosen_rarity, used, order)
	if pick <= 0:
		return CombatConstants.WHITE_AMMO_ID
	return pick


func _any_in_tier(by_rarity: Dictionary, rarity: String) -> Array:
	return by_rarity.get(rarity, [])


func _available_in_tier(by_rarity: Dictionary, rarity: String, used: Dictionary) -> Array:
	var out: Array = []
	for aid in by_rarity.get(rarity, []):
		if not used.has(int(aid)):
			out.append(int(aid))
	return out


func _pick_from_tier_with_fallback(by_rarity: Dictionary, rarity: String, used: Dictionary, order: Array[String]) -> int:
	var idx: int = order.find(rarity)
	if idx < 0:
		idx = 1
	## 优先同档未用；再同档可重复；再向下；再向上。
	var try_order: Array[int] = []
	try_order.append(idx)
	for d in range(1, order.size()):
		if idx - d >= 0:
			try_order.append(idx - d)
		if idx + d < order.size():
			try_order.append(idx + d)
	for ti in try_order:
		var r: String = order[ti]
		var avail: Array = _available_in_tier(by_rarity, r, used)
		if not avail.is_empty():
			return int(avail[rng.randi_range(0, avail.size() - 1)])
	for ti in try_order:
		var r2: String = order[ti]
		var all_tier: Array = _any_in_tier(by_rarity, r2)
		if not all_tier.is_empty():
			return int(all_tier[rng.randi_range(0, all_tier.size() - 1)])
	return CombatConstants.WHITE_AMMO_ID


func _enabled_ammo_ids() -> Array[int]:
	var out: Array[int] = []
	for item in DataRegistry.all_ammo():
		var aid: int = int(item.get("id", 0))
		if DataRegistry.is_ammo_reward_eligible(aid):
			out.append(aid)
	return out


func _ammo_name(ammo_id: int) -> String:
	var def: Dictionary = DataRegistry.get_ammo(ammo_id)
	return str(def.get("name", ammo_id))


func _copy_ints(src) -> Array[int]:
	var out: Array[int] = []
	for x in src:
		out.append(int(x))
	return out
