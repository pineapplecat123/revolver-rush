class_name CampaignRules
extends RefCounted
## 闯关数据：9 层 × 每层 3 段小怪 + 离开第 3 次商店后打本层首领。波次与首领数值来自 data/campaign.json。

const DATA_PATH := "res://data/campaign.json"
const FLOOR_COUNT := 9
const SEGMENTS_PER_FLOOR := 3

const PHASE_INACTIVE := 0
const PHASE_OFFER := 1
const PHASE_ENTER := 2
const PHASE_COMBAT := 3
const PHASE_WALK_SHOP := 4
const PHASE_SHOP := 5
const PHASE_BOSS := 6
const PHASE_BOSS_REWARD := 7
const PHASE_WALK_FLOOR := 8
const PHASE_VICTORY := 9
const PHASE_LEAVE_SHOP := 10

static var _cache: Dictionary = {}


static func reload() -> Dictionary:
	var text := FileAccess.get_file_as_string(DATA_PATH)
	assert(not text.is_empty(), "missing campaign data: %s" % DATA_PATH)
	var parsed: Variant = JSON.parse_string(text)
	assert(typeof(parsed) == TYPE_DICTIONARY, "bad campaign json root")
	_cache = parsed
	return _cache


static func data() -> Dictionary:
	if _cache.is_empty():
		return reload()
	return _cache


static func opening_offer_count() -> int:
	return maxi(1, int(data().get("opening_offer_count", 3)))


static func opening_white_count() -> int:
	## 开局袋里的白板数量（选子弹之前）。选完再加 1 发，合计比白板多 1。
	return maxi(1, int(data().get("opening_white_count", 5)))


static func walk_combat_tempo() -> float:
	return maxf(0.05, float(data().get("walk_combat_tempo", 0.72)))


static func walk_shop_tempo() -> float:
	return maxf(0.05, float(data().get("walk_shop_tempo", 1.85)))


static func walk_to_shop_sec() -> float:
	return maxf(0.0, float(data().get("walk_to_shop_sec", 1.6)))


static func walk_from_shop_sec() -> float:
	return maxf(0.0, float(data().get("walk_from_shop_sec", 2.55)))


static func shop_house_width() -> float:
	return 360.0


static func shop_house_height() -> float:
	return 236.0


static func shop_house_entrance_x() -> float:
	## 入口门洞中心相对房屋左缘。
	return 62.0


static func shop_house_exit_x() -> float:
	## 另一扇门（侧门/后门）中心相对房屋左缘。
	return 304.0


static func shop_house_entrance_half_w() -> float:
	return 23.0


static func shop_house_exit_half_w() -> float:
	return 20.0


static func shop_house_clear_pad() -> float:
	return 80.0


static func walk_enter_sec() -> float:
	return maxf(0.0, float(data().get("walk_enter_sec", 1.0)))


static func walk_floor_sec() -> float:
	return maxf(0.0, float(data().get("walk_floor_sec", 1.2)))


static func walk_world_drift_px() -> float:
	## 走路时地上碎块每秒移动像素（再乘当前走路节奏；方向由 CombatState 取负号向左）。
	return maxf(0.0, float(data().get("walk_world_drift_px", 80.0)))


static func floor_count() -> int:
	var floors: Array = data().get("floors", [])
	return floors.size()


static func floor_def(floor_index: int) -> Dictionary:
	## floor_index 从 1 起。
	var floors: Array = data().get("floors", [])
	var i: int = floor_index - 1
	if i < 0 or i >= floors.size():
		return {}
	var d: Variant = floors[i]
	return d if d is Dictionary else {}


static func floor_name(floor_index: int) -> String:
	var d: Dictionary = floor_def(floor_index)
	var n: String = str(d.get("name", "")).strip_edges()
	if n.is_empty():
		return "第%d关" % floor_index
	return n


static func segment_def(floor_index: int, segment_index: int) -> Dictionary:
	var segs: Array = floor_def(floor_index).get("segments", [])
	var i: int = segment_index - 1
	if i < 0 or i >= segs.size():
		return {}
	var d: Variant = segs[i]
	return d if d is Dictionary else {}


static func wave_count(floor_index: int, segment_index: int) -> int:
	var waves: Array = segment_def(floor_index, segment_index).get("waves", [])
	return waves.size()


static func wave_spawns(floor_index: int, segment_index: int, wave_index: int) -> Array:
	var waves: Array = segment_def(floor_index, segment_index).get("waves", [])
	var i: int = wave_index - 1
	if i < 0 or i >= waves.size():
		return []
	var w: Variant = waves[i]
	return w if w is Array else []


static func boss_def(floor_index: int) -> Dictionary:
	var d: Variant = floor_def(floor_index).get("boss", {})
	return d if d is Dictionary else {}


static func _registry():
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("DataRegistry")


static func opening_pool() -> Array[int]:
	## 开局三选一：奖励池子弹，排除白板（开局袋里已有白板）和罪孽/临时/未启用弹。
	var pool: Array[int] = []
	var reg = _registry()
	if reg == null:
		return pool
	for item in reg.all_ammo():
		var aid: int = int(item.get("id", 0))
		if aid == CombatConstants.WHITE_AMMO_ID:
			continue
		if reg.is_ammo_reward_eligible(aid):
			pool.append(aid)
	return pool


static func roll_opening_offers(rng: RandomNumberGenerator) -> Array[int]:
	var pool: Array[int] = opening_pool()
	var need: int = opening_offer_count()
	var out: Array[int] = []
	if pool.is_empty():
		return out
	var work: Array[int] = pool.duplicate()
	# Fisher-Yates
	for i in range(work.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = work[i]
		work[i] = work[j]
		work[j] = tmp
	var take: int = mini(need, work.size())
	for i in take:
		out.append(work[i])
	return out


static func phase_title(phase: int) -> String:
	match phase:
		PHASE_OFFER:
			return "开局自选"
		PHASE_ENTER:
			return "进场"
		PHASE_COMBAT:
			return "战斗"
		PHASE_WALK_SHOP:
			return "走向商店"
		PHASE_SHOP:
			return "商店"
		PHASE_BOSS:
			return "楼层首领"
		PHASE_BOSS_REWARD:
			return "首领奖励"
		PHASE_WALK_FLOOR:
			return "前往下层"
		PHASE_VICTORY:
			return "胜利"
		PHASE_LEAVE_SHOP:
			return "离店"
		_:
			return ""
