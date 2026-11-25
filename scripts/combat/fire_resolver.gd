class_name FireResolver
## 整匣射击：按表计算每发基础伤害。

const ID_WHITE := CombatConstants.WHITE_AMMO_ID
const ID_GOLD := 8
const ID_WRATH := 16  ## 愤怒
const ID_PRIDE := 17  ## 傲慢
const ID_GREED := 18  ## 贪婪
const ID_TOMBSTONE := 19  ## 墓碑（设计表编号9）
const ID_GHOST := 20  ## 幽灵（设计表编号10，墓碑衍生物）
const ID_ARMOR_PIERCE := 22  ## 穿甲（设计表编号12）
const ID_ECHO := 24  ## 回声（设计表编号21）
const ID_LIFESTEAL := 25  ## 吸血（设计表编号22）
const ID_FLAME := 26  ## 火焰（设计表编号17）
const ID_EXPLOSIVE := 27  ## 炸药（设计表编号18）
const ID_SCATTER := 28  ## 散射（设计表编号15）
const ID_INSURANCE := 29  ## 保险（设计表编号16）
const ID_FOCUS := 30  ## 聚能（设计表编号19）
const ID_STONE := 31  ## 石头（设计表编号13）
const ID_PEBBLE := 32  ## 小石头（设计表编号14）
const ID_JUSTICE := 33  ## 正义（设计表编号20）
const ID_LUST := 34  ## 色欲
const ID_ENVY := 35  ## 嫉妒
const ID_GLUTTONY := 36  ## 暴食
const ID_SLOTH := 37  ## 懒惰
const ID_QISHI := CombatConstants.QISHI_AMMO_ID
const ID_XULI := CombatConstants.XULI_AMMO_ID
const ID_DIZENG := CombatConstants.DIZENG_AMMO_ID
const ID_ZHONGSHEN := CombatConstants.ZHONGSHEN_AMMO_ID
const ID_WEIZHONG := CombatConstants.WEIZHONG_AMMO_ID
const ID_XIANWEI := CombatConstants.XIANWEI_AMMO_ID
const ID_CHONGFU_KAISHI := CombatConstants.CHONGFU_KAISHI_AMMO_ID
const ID_BAIBAN := CombatConstants.BAIBAN_AMMO_ID
const ID_DIESHI := CombatConstants.DIESHI_AMMO_ID
const ID_BAOCHUAN := CombatConstants.BAOCHUAN_AMMO_ID
const ID_CHUANDI := CombatConstants.CHUANDI_AMMO_ID
const ID_MOFANG := CombatConstants.MOFANG_AMMO_ID
const ID_HUIWEI := CombatConstants.HUIWEI_AMMO_ID
const ID_WEIJIABEI := CombatConstants.WEIJIABEI_AMMO_ID
const ID_ENCOURAGE := 56
const ID_HALF_PREV := 57
const ID_DOUBLE_PREV := 58
const ID_EMPTY_BEAT := 59
# t666: approved table designs. IDs preserve the original table values (including blank explosion damage).
const ID_TOTAL_TRANSFER := 60
const ID_DOUBLE_LAYERS := 61
const ID_END_SHARE := 62
const ID_DRAIN := 63
const ID_DETONATE := 64
const ID_SPLIT := 65
const ID_EMPTY_NEIGHBOR := 66
const ID_BLACK_SIGHT := 67

const XULI_MULT := 1.5
const WEIJIABEI_MULT := 1.5
const QISHI_BONUS := 0.5
const DIZENG_BASE := 2.0
const DIZENG_PER_SLOT := 0.75
const XIANWEI_BASE := 3.0
const XIANWEI_PER_END := 3.0
const DIESHI_BONUS := 0.65
const DIESHI_BASE := 3.0
const CHUANDI_BASE := 3.0
const BAOCHUAN_PIERCE_OVER := 7


static func count_by_id(order: Array[int]) -> Dictionary:
	var c := {}
	for id in order:
		c[id] = int(c.get(id, 0)) + 1
	return c


static func base_damage_for(ammo_id: int, _order: Array[int], _index: int) -> int:
	match ammo_id:
		ID_WHITE:
			return 3
		ID_GOLD:
			return 3
		ID_WRATH:
			return 3
		ID_PRIDE, ID_GREED:
			return 2
		ID_TOMBSTONE, ID_GHOST:
			return 2
		ID_ARMOR_PIERCE:
			return 3
		ID_ECHO:
			return 1
		ID_LIFESTEAL:
			return 1
		ID_FLAME:
			return 1
		ID_EXPLOSIVE:
			return 1
		ID_SCATTER:
			return 5
		ID_INSURANCE:
			return 1
		ID_FOCUS:
			return 3
		ID_STONE:
			return 3
		ID_PEBBLE:
			return 1
		ID_JUSTICE:
			return 3
		ID_LUST, ID_ENVY, ID_GLUTTONY, ID_SLOTH:
			return 2
		ID_QISHI, ID_XULI, ID_ZHONGSHEN, ID_CHONGFU_KAISHI, ID_WEIJIABEI:
			return 0
		ID_HUIWEI:
			return 2
		ID_DIZENG, ID_WEIZHONG, ID_XIANWEI, ID_BAIBAN, ID_DIESHI, ID_BAOCHUAN, ID_CHUANDI, ID_MOFANG:
			return 3
		_:
			var def: Dictionary = DataRegistry.get_ammo(ammo_id)
			if def.get("base_damage", null) != null:
				return int(def["base_damage"])
			return 0


static func round_damage(value: float) -> int:
	## 内部用 float 算；落到敌人/飘字时四舍五入（.5 远离 0）。
	return int(round(value))


static func type_tag(ammo_id: int) -> String:
	## 弹药的开始/中间/结束标签；无则空串。按 tags 读取，不写死 id。
	var tags = DataRegistry.get_ammo(ammo_id).get("tags", [])
	if tags is Array:
		var found: Dictionary = {}
		for t in tags:
			found[str(t).strip_edges()] = true
		for name in ["开始", "中间", "结束"]:
			if found.has(name):
				return name
	return ""


static func is_start_type(ammo_id: int) -> bool:
	return type_tag(ammo_id) == "开始"


static func load_type_rank(ammo_id: int) -> int:
	## 自动装填优先级：开始 0、中间 1、结束 2、无标签 3。
	var tag := type_tag(ammo_id)
	if tag == "开始":
		return 0
	if tag == "中间":
		return 1
	if tag == "结束":
		return 2
	return 3


static func compute_volley_damages(order: Array[int], flat_at: Array = [], actual_at: Array = []) -> Array[float]:
	return compute_volley_details(order, flat_at, actual_at)["damages"]


static func flame_applies(flame: Dictionary, intrinsic: float, last: bool, shot_type: String = "") -> bool:
	# Eligibility is decided BEFORE flat boosts. Utility shots cannot bootstrap damage.
	return round_damage(intrinsic) > 0 and (str(flame.get("duration_type", "")) != "until_last" or last) and (str(flame.get("effect_kind", "")) != "end_flat" or shot_type == "结束")


static func apply_flames(intrinsic: float, flames: Array, last: bool = false, shot_type: String = "") -> float:
	var damage := intrinsic
	for flame in flames:
		if not flame_applies(flame, intrinsic, last, shot_type):
			continue
		var layers := maxi(0, int(flame.get("remaining", 1)))
		match str(flame.get("effect_kind", "")):
			"damage_pct":
				damage *= pow(1.0 + float(flame.get("effect_per_stack", 0.5)), layers)
			"damage_mult":
				damage *= pow(float(flame.get("effect_per_stack", 1.5)), layers)
			"end_flat":
				damage += float(flame.get("amount", 0))
			"damage_flat", "transfer_decay":
				damage += float(flame.get("amount", 0)) * float(layers)
	return damage


static func consume_flame_layers(flames: Array, intrinsic: float, last: bool = false, shot_type: String = "") -> Array:
	# t640: each effect TYPE loses one layer, not one per grant or one globally.
	# Repeated grants remain separate, ordered groups; consume oldest group of
	# each source effect first, preserving all surviving creation order.
	var consumed: Dictionary = {}
	var kept: Array = []
	for src in flames:
		var f: Dictionary = src.duplicate(true)
		var effect: String = str(f.get("id", f.get("source_ammo_id", "")))
		if not consumed.has(effect) and flame_applies(f, intrinsic, last, shot_type):
			f["remaining"] = maxi(0, int(f.get("remaining", 1)) - 1)
			consumed[effect] = true
		if int(f.get("remaining", 0)) > 0:
			kept.append(f)
	return kept


static func make_flame(source_id: int, index: int, layers: int, amount: float = 0.0) -> Dictionary:
	var entry: Dictionary = DataRegistry.muzzle_status_of(source_id).duplicate(true)
	if entry.is_empty() or layers <= 0 or str(entry.get("effect_kind", "none")) == "none":
		return {}
	entry["source_ammo_id"] = source_id
	entry["ammo_id"] = source_id
	entry["created_index"] = index
	entry["uid"] = "%s:%d" % [str(entry.get("id", source_id)), index]
	entry["stacks"] = 1
	entry["remaining"] = layers
	entry["total"] = layers
	entry["amount"] = amount
	return entry


static func flame_layer_count(flames: Array) -> int:
	var n := 0
	for f in flames:
		n += maxi(0, int(f.get("remaining", 0)))
	return n


static func _is_actual_at(actual_at: Array, index: int) -> bool:
	return index < actual_at.size() and actual_at[index] != null


static func compute_volley_details(order: Array[int], flat_at: Array = [], actual_at: Array = [], seed_flames: Array = [], generation: int = 0) -> Dictionary:
	var flames: Array = seed_flames.duplicate(true)
	var tail_pending: Array = []
	var out: Array[float] = []
	var intrinsic_values: Array[float] = []
	var before: Array = []
	var after: Array = []
	var consumed_at: Array[int] = []
	var prior := 0.0
	var actual_sum := 0.0
	var previous := 0.0
	var old_flat := 0.0
	var consumed_total := 0
	var last_loaded := -1
	var loaded_count := 0
	var black_sight := order.has(ID_BLACK_SIGHT)
	for i in order.size():
		if order[i] != Magazine.EMPTY:
			last_loaded = i
			loaded_count += 1
	for index in order.size():
		var rem := 0
		for j in range(index + 1, order.size()):
			if order[j] != Magazine.EMPTY:
				rem += 1
		var flat: float = float(flat_at[index]) if index < flat_at.size() else old_flat
		if flat > old_flat:
			var mounted := make_flame(ID_HUIWEI, index - 1, rem + 1, flat - old_flat)
			if not mounted.is_empty():
				mounted["uid"] = "%d:%s" % [generation, mounted["uid"]]
				flames.append(mounted)
		old_flat = flat
		var ammo_id: int = order[index]
		var effect_id := resolve_shot_effect_id(order, index)
		var last := index == last_loaded
		if last:
			flames.append_array(tail_pending)
			if effect_id == ID_WEIJIABEI:
				flames.append(make_flame(ID_WEIJIABEI, index, 1))
		before.append(flames.duplicate(true))
		if ammo_id == Magazine.EMPTY:
			out.append(0.0)
			intrinsic_values.append(0.0)
			consumed_at.append(0)
			after.append(flames.duplicate(true))
			continue
		var shot_type := type_tag(ammo_id)
		var base := _formula_base_for_shot(ammo_id, effect_id, index + 1, prior, order, index)
		if effect_id == ID_HALF_PREV:
			base = ceilf(previous * 0.5)
		elif effect_id == ID_DOUBLE_PREV:
			base = previous * 2.0
		elif effect_id == ID_ENCOURAGE:
			var consumed := flame_layer_count(flames) - flame_layer_count(consume_flame_layers(flames, base, last, shot_type))
			base *= 1.0 + float(consumed)
		elif effect_id == ID_DRAIN:
			# Count prior ACTUALLY consumed layers. Own consumption cannot recursively amplify this shot.
			base *= pow(2.0, consumed_total)
		elif effect_id == ID_SPLIT:
			# A prediction must not masquerade as previous actual damage.
			base = previous if _previous_live_has_actual(order, actual_at, index) else 0.0
		elif effect_id == ID_EMPTY_NEIGHBOR:
			var empty_neighbors := 0
			for step in [-1, 1]:
				if black_sight or order[posmod(index + step, order.size())] == Magazine.EMPTY:
					empty_neighbors += 1
			base *= 1.0 + float(empty_neighbors)
		intrinsic_values.append(base)
		var pre_count := flame_layer_count(flames)
		var dmg := 0.0
		var spent := 0
		if effect_id == ID_DOUBLE_LAYERS:
			# No application, no consumption; double each surviving group in place.
			for flame in flames:
				flame["remaining"] = int(flame["remaining"]) * 2
				flame["total"] = maxi(int(flame.get("total", 0)), int(flame["remaining"]))
			dmg = base
		elif effect_id == ID_DETONATE:
			spent = pre_count
			dmg = 4.0 * float(spent)
			flames.clear()
		else:
			dmg = apply_flames(base, flames, last, shot_type)
			flames = consume_flame_layers(flames, base, last, shot_type)
			spent = pre_count - flame_layer_count(flames)
		consumed_total += spent
		consumed_at.append(spent)
		var def: Dictionary = DataRegistry.muzzle_status_of(effect_id)
		var layers := rem
		if str(def.get("duration_type", "")) in ["until_consumed", "until_last"]:
			layers = 1
		var amount := 0.0
		if effect_id == ID_CHUANDI:
			layers = maxi(0, round_damage(dmg) - int(CHUANDI_BASE))
			amount = 1.0
		elif effect_id == ID_EMPTY_BEAT:
			layers = order.size() if black_sight else order.count(Magazine.EMPTY)
		elif effect_id == ID_WEIJIABEI:
			if not last:
				tail_pending.append(make_flame(ID_WEIJIABEI, index, 1))
			layers = 0 # generated only on arrival at last live bullet, never immediately
		elif effect_id == ID_TOTAL_TRANSFER:
			layers = loaded_count if _is_actual_at(actual_at, index) else 0
			amount = (actual_sum + float(actual_at[index])) / float(loaded_count) if layers > 0 else 0.0
		elif effect_id == ID_END_SHARE:
			layers = 0
			if _is_actual_at(actual_at, index):
				for j in range(index + 1, order.size()):
					if order[j] != Magazine.EMPTY and type_tag(order[j]) == "结束":
						layers += 1
			amount = float(actual_at[index]) / float(layers) if layers > 0 else 0.0
		var f := make_flame(effect_id, index, layers, amount)
		if not f.is_empty() and effect_id != ID_HUIWEI:
			f["uid"] = "%d:%s" % [generation, f["uid"]]
			flames.append(f)
		after.append(flames.duplicate(true))
		out.append(dmg)
		# 总伤二分 only totals actual settled hits (including pierce/AOE).
		# Missing actuals must not fall back to a planned float.
		if _is_actual_at(actual_at, index):
			var actual: float = float(actual_at[index])
			prior += actual
			actual_sum += actual
			previous = float(round_damage(actual))
		else:
			previous = float(round_damage(dmg))
	return {"damages": out, "intrinsic": intrinsic_values, "before": before, "after": after, "consumed": consumed_at}


static func _previous_live_has_actual(order: Array[int], actual_at: Array, index: int) -> bool:
	for i in range(index - 1, -1, -1):
		if order[i] != Magazine.EMPTY:
			return _is_actual_at(actual_at, i)
	return false


static func count_end_type(order: Array[int]) -> int:
	var n := 0
	for ammo_id in order:
		if ammo_id != Magazine.EMPTY and type_tag(ammo_id) == "结束":
			n += 1
	return n


static func copied_start_effect_id(order: Array[int], index: int) -> int:
	## 重复开始弹：复制轮盘里上一颗开始弹的效果；没有则 0。上一颗若也是重复开始弹，再往前找。
	if index < 0 or index >= order.size():
		return 0
	if int(order[index]) != ID_CHONGFU_KAISHI:
		return int(order[index])
	var i: int = index - 1
	while i >= 0:
		var aid: int = int(order[i])
		if aid != Magazine.EMPTY and is_start_type(aid):
			return resolve_shot_effect_id(order, i)
		i -= 1
	return 0


static func copied_adjacent_effect_id(order: Array[int], index: int) -> int:
	## 模仿弹：只看紧邻的前一个弹夹槽位。前一格空仓或没有前一格则 0，不跳空仓、不绕圈。
	## 若前一格也是模仿弹，沿用重复开始弹的连续解析：再往前走模仿链，直到非模仿或空/没有。
	if index < 0 or index >= order.size():
		return 0
	if int(order[index]) != ID_MOFANG:
		return resolve_shot_effect_id(order, index)
	if index <= 0:
		return 0
	var prev: int = int(order[index - 1])
	if prev == Magazine.EMPTY:
		return 0
	return resolve_shot_effect_id(order, index - 1)


static func resolve_shot_effect_id(order: Array[int], index: int) -> int:
	## 本发实际采用的技能效果 id；没有可复制的效果时为 0。
	if index < 0 or index >= order.size():
		return 0
	var ammo_id: int = int(order[index])
	if ammo_id == Magazine.EMPTY:
		return 0
	if ammo_id == ID_CHONGFU_KAISHI:
		return copied_start_effect_id(order, index)
	if ammo_id == ID_MOFANG:
		return copied_adjacent_effect_id(order, index)
	return ammo_id


static func effect_replaces_own_base(effect_id: int) -> bool:
	## 这些技能本身就是伤害公式，模仿弹获得后按公式结算，而不是先抄对方的基础伤害数字。
	match effect_id:
		ID_DIZENG, ID_WEIZHONG, ID_ZHONGSHEN, ID_XIANWEI, ID_DIESHI, ID_HALF_PREV, ID_DOUBLE_PREV, ID_DRAIN, ID_SPLIT, ID_EMPTY_NEIGHBOR:
			return true
		_:
			return false


static func _formula_base_for_shot(ammo_id: int, effect_id: int, slot: int, prior_computed: float, order: Array[int], index: int) -> float:
	if ammo_id == ID_MOFANG:
		if effect_id > 0 and effect_replaces_own_base(effect_id):
			return _formula_base(effect_id, slot, prior_computed, order, index)
		return float(base_damage_for(ID_MOFANG, order, index))
	if ammo_id == ID_CHONGFU_KAISHI:
		if effect_id <= 0:
			return 0.0
		return _formula_base(effect_id, slot, prior_computed, order, index)
	return _formula_base(ammo_id, slot, prior_computed, order, index)


static func _same_type_streak(order: Array[int], index: int) -> int:
	## 本轮在 index 之前、紧邻的同类型实际开火次数。空仓跳过且不打断。
	if index < 0 or index >= order.size():
		return 0
	var tag := type_tag(int(order[index]))
	if tag.is_empty():
		return 0
	var n := 0
	var i: int = index - 1
	while i >= 0:
		var aid: int = int(order[i])
		if aid == Magazine.EMPTY:
			i -= 1
			continue
		if type_tag(aid) == tag:
			n += 1
			i -= 1
		else:
			break
	return n


static func _formula_base(ammo_id: int, slot: int, prior_computed: float, order: Array[int] = [], index: int = -1) -> float:
	match ammo_id:
		ID_QISHI, ID_XULI, ID_CHONGFU_KAISHI, ID_WEIJIABEI, ID_EMPTY_BEAT:
			return 0.0
		ID_DIZENG:
			return DIZENG_BASE + float(slot) * DIZENG_PER_SLOT
		ID_WEIZHONG:
			return 3.0 * (0.5 if slot <= 3 else 2.0)
		ID_ZHONGSHEN:
			return prior_computed * 0.5
		ID_XIANWEI:
			return XIANWEI_BASE + XIANWEI_PER_END * float(count_end_type(order))
		ID_DIESHI:
			var n: int = _same_type_streak(order, index if index >= 0 else slot - 1)
			if n < 2:
				return DIESHI_BASE
			return DIESHI_BASE * (1.0 + DIESHI_BONUS * float(n))
		_:
			return float(base_damage_for(ammo_id, [], 0))


static func shot_self_pierce(ammo_id: int, planned_damage: int) -> bool:
	## 爆穿：预计伤害（四舍五入后）大于 7 时本发自带穿透；不挂枪口。
	if ammo_id != ID_BAOCHUAN:
		return false
	return planned_damage > BAOCHUAN_PIERCE_OVER


static func compute_shot_damages(order: Array[int]) -> Array[int]:
	var floats: Array[float] = compute_volley_damages(order)
	var out: Array[int] = []
	for v in floats:
		out.append(round_damage(v))
	return out


static func inherits_from(ammo_id: int) -> Dictionary:
	## 该发自带的状态效果旗标（击发后挂上枪口，后续击发都附带）。
	## 旧色弹与旧穿透/汽油/火/水/雷子弹已删除；枪口种类仍由在役弹挂上。
	return {
		"pierce": ammo_id == ID_ARMOR_PIERCE,
		"gas": false,
		"fire": ammo_id == ID_FLAME,
		"water": false,
		"thunder": false,
		"wrath": ammo_id == ID_WRATH,
		"pride": ammo_id == ID_PRIDE,
		"greed": ammo_id == ID_GREED,
		"lust": ammo_id == ID_LUST,
		"envy": ammo_id == ID_ENVY,
		"gluttony": ammo_id == ID_GLUTTONY,
		"sloth": ammo_id == ID_SLOTH,
		"echo": ammo_id == ID_ECHO,
		"lifesteal": ammo_id == ID_LIFESTEAL,
		"explosive": ammo_id == ID_EXPLOSIVE,
	}
