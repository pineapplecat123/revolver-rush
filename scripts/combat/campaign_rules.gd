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
const PHASE_WALK_ALLEY := 11
const PHASE_ALLEY := 12
const PHASE_LEAVE_ALLEY := 13

const ALLEY_GUMBALL := "gumball"
const ALLEY_TRASH := "trash"

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


static func shop_walk_speed_px() -> float:
	return walk_shop_tempo() * walk_world_drift_px()


static func shop_house_view_width() -> float:
	## 设计布局宽度；房屋从这一侧的右缘外进场，由视口裁切。
	return 720.0


static func shop_house_visual_pad() -> float:
	## 屋顶/烟囱伸出左缘以外的余量，保证整栋楼先完全在画面右外。
	return 16.0


static func shop_house_approach_travel_px() -> float:
	## 从右缘外到入口对准小猫的路程（与近景 drift 同速，所以时长=路程/速度）。
	return shop_house_view_width() + shop_house_visual_pad() + shop_house_entrance_x()


static func shop_house_exit_travel_px() -> float:
	## 出门后整栋从左侧完全离开画面。
	return shop_house_width() + shop_house_visual_pad() + shop_house_clear_pad()


static func walk_to_shop_sec() -> float:
	## 以「从右屏外走进门口」的路程为准，配置值只做下限，不缩短到会凭空出现。
	var need: float = shop_house_approach_travel_px() / maxf(shop_walk_speed_px(), 0.01)
	var cfg: float = maxf(0.0, float(data().get("walk_to_shop_sec", 0.0)))
	return maxf(need, cfg)


static func walk_from_shop_sec() -> float:
	var need: float = shop_house_exit_travel_px() / maxf(shop_walk_speed_px(), 0.01)
	var cfg: float = maxf(0.0, float(data().get("walk_from_shop_sec", 0.0)))
	return maxf(need, cfg)


static func shop_house_width() -> float:
	return 360.0


static func shop_house_height() -> float:
	return 236.0


static func shop_house_door_w() -> float:
	## 两扇门同一宽度。
	return 46.0


static func shop_house_door_h() -> float:
	## 两扇门同一高度（含门槛以上的门洞）。
	return 118.0


static func shop_house_door_frame() -> float:
	## 两扇门同一门框厚度。
	return 5.0


static func shop_house_threshold() -> float:
	## 门槛压住走道顶边的高度，两门相同。
	return 3.0


static func shop_house_entrance_x() -> float:
	## 入口门洞中心相对房屋左缘。
	return 62.0


static func shop_house_exit_x() -> float:
	## 另一扇门中心相对房屋左缘（尺寸与入口相同，只是位置不同）。
	return 304.0


static func shop_house_door_half_w() -> float:
	return shop_house_door_w() * 0.5


static func shop_house_entrance_half_w() -> float:
	return shop_house_door_half_w()


static func shop_house_exit_half_w() -> float:
	return shop_house_door_half_w()


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
		PHASE_WALK_ALLEY:
			return "随机事件走近"
		PHASE_ALLEY:
			return "随机事件"
		PHASE_LEAVE_ALLEY:
			return "离开随机事件"
		_:
			return ""

static func gumball_price() -> int:
	return maxi(1, int(data().get("gumball_price", 5)))


static func trash_gold_amount() -> int:
	return maxi(1, int(data().get("trash_gold_amount", 8)))


static func trash_outcome_weights() -> Vector3:
	## 子弹 / 金币 / 大量经验，三项互斥且和为 1，默认 10/35/55，没有空结果。
	var b: float = maxf(0.0, float(data().get("trash_p_bullet", 0.10)))
	var g: float = maxf(0.0, float(data().get("trash_p_gold", 0.35)))
	var x: float = maxf(0.0, float(data().get("trash_p_xp", 0.55)))
	var s: float = b + g + x
	if s <= 0.0001:
		return Vector3(0.10, 0.35, 0.55)
	return Vector3(b / s, g / s, x / s)


static func trash_outcome_at(u: float) -> String:
	var w: Vector3 = trash_outcome_weights()
	var v: float = clampf(u, 0.0, 0.999999)
	if v < w.x:
		return "bullet"
	if v < w.x + w.y:
		return "gold"
	return "xp"


static func roll_trash_outcome(rng: RandomNumberGenerator) -> String:
	if rng == null:
		return "xp"
	return trash_outcome_at(rng.randf())


static func trash_xp_amount(level: int) -> int:
	## 按当前等级升级门槛发放一整份，相对当前等级能看见涨幅；溢出走标准 gain_xp。
	var k: int = maxi(level, 1) - 1
	return CombatConstants.XP_BASE + CombatConstants.XP_LINEAR * k + CombatConstants.XP_QUAD * k * k


static func alley_event_pool() -> Array:
	var raw: Variant = data().get("alley_event_pool", [])
	var out: Array = []
	if raw is Array:
		for item in raw:
			if not (item is Dictionary):
				continue
			var id: String = str(item.get("id", "")).strip_edges()
			if id != ALLEY_GUMBALL and id != ALLEY_TRASH:
				continue
			var w: float = maxf(0.0, float(item.get("weight", 1)))
			out.append({"id": id, "weight": w})
	if out.is_empty():
		out.append({"id": ALLEY_GUMBALL, "weight": 1.0})
		out.append({"id": ALLEY_TRASH, "weight": 1.0})
	return out


static func roll_alley_event(rng: RandomNumberGenerator) -> String:
	var pool: Array = alley_event_pool()
	var total: float = 0.0
	for item in pool:
		total += float(item.get("weight", 0.0))
	if total <= 0.0 or rng == null:
		return str(pool[0].get("id", ALLEY_GUMBALL))
	var u: float = rng.randf() * total
	var acc: float = 0.0
	for item in pool:
		acc += float(item.get("weight", 0.0))
		if u <= acc:
			return str(item.get("id", ALLEY_GUMBALL))
	return str(pool[pool.size() - 1].get("id", ALLEY_GUMBALL))


static func alley_event_title(kind: String) -> String:
	if kind == ALLEY_GUMBALL:
		return "糖果机"
	if kind == ALLEY_TRASH:
		return "垃圾桶"
	return "随机事件"


static func gumball_width() -> float:
	return GumballMachine.WIDTH


static func gumball_height() -> float:
	return GumballMachine.HEIGHT


static func gumball_use_x() -> float:
	return GumballMachine.USE_X


static func gumball_visual_pad() -> float:
	return 12.0


static func trash_width() -> float:
	return 100.0


static func trash_height() -> float:
	return 156.0


static func trash_use_x() -> float:
	return 50.0


static func trash_visual_pad() -> float:
	return 12.0


static func alley_clear_pad() -> float:
	return 40.0


static func alley_width(kind: String) -> float:
	return gumball_width() if kind == ALLEY_GUMBALL else trash_width()


static func alley_height(kind: String) -> float:
	return gumball_height() if kind == ALLEY_GUMBALL else trash_height()


static func alley_use_x(kind: String) -> float:
	return gumball_use_x() if kind == ALLEY_GUMBALL else trash_use_x()


static func alley_visual_pad(kind: String) -> float:
	return gumball_visual_pad() if kind == ALLEY_GUMBALL else trash_visual_pad()


static func alley_approach_travel_px(kind: String) -> float:
	return shop_house_view_width() + alley_visual_pad(kind) + alley_use_x(kind)


static func alley_exit_travel_px(kind: String) -> float:
	return alley_width(kind) + alley_visual_pad(kind) + alley_clear_pad()


static func walk_to_alley_sec(kind: String) -> float:
	return alley_approach_travel_px(kind) / maxf(shop_walk_speed_px(), 0.01)


static func walk_from_alley_sec(kind: String) -> float:
	return alley_exit_travel_px(kind) / maxf(shop_walk_speed_px(), 0.01)


static func alley_reward_pool() -> Array[int]:
	## 与常规奖励池相同（含白板，若白板在奖励池里）；排除未启用/临时/罪孽。
	var pool: Array[int] = []
	var reg = _registry()
	if reg == null:
		return pool
	for item in reg.all_ammo():
		var aid: int = int(item.get("id", 0))
		if reg.is_ammo_reward_eligible(aid):
			pool.append(aid)
	return pool


static func roll_alley_ammo(rng: RandomNumberGenerator) -> int:
	var pool: Array[int] = alley_reward_pool()
	if pool.is_empty() or rng == null:
		return CombatConstants.WHITE_AMMO_ID
	return int(pool[rng.randi_range(0, pool.size() - 1)])

