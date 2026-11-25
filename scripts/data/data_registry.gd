extends Node
## 读取 data/*.json。Autoload：DataRegistry

const AMMO_PATH := "res://data/ammo.json"
const ENEMIES_PATH := "res://data/enemies.json"
const ENEMY_TAGS_PATH := "res://data/enemy_tags.json"

var _ammo_by_id: Dictionary = {}
var _enemies_by_id: Dictionary = {}
var _tags_by_id: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	_ammo_by_id = _load_by_int_id(AMMO_PATH)
	_enemies_by_id = _load_by_int_id(ENEMIES_PATH)
	_tags_by_id = _load_by_string_id(ENEMY_TAGS_PATH)


func _read_items(path: String) -> Array:
	var text := FileAccess.get_file_as_string(path)
	assert(not text.is_empty(), "missing data file: %s" % path)
	var parsed: Variant = JSON.parse_string(text)
	assert(typeof(parsed) == TYPE_DICTIONARY, "bad json root: %s" % path)
	return parsed.get("items", [])


func _load_by_int_id(path: String) -> Dictionary:
	var into := {}
	for item in _read_items(path):
		into[int(item["id"])] = item
	return into


func _load_by_string_id(path: String) -> Dictionary:
	var into := {}
	for item in _read_items(path):
		into[str(item["id"])] = item
	return into


func get_ammo(ammo_id: int) -> Dictionary:
	return _ammo_by_id.get(CombatConstants.migrate_ammo_id(ammo_id), {})


func ammo_display_name(ammo_id: int) -> String:
	## 当前图鉴名。缺条目或名为空时回退「未知#id」，供伤害修正/枪口展示跟随改名。
	var nid: int = CombatConstants.migrate_ammo_id(ammo_id)
	var def: Dictionary = get_ammo(nid)
	if def.is_empty():
		return "未知#%d" % nid
	var n: String = str(def.get("name", "")).strip_edges()
	if n.is_empty():
		return "未知#%d" % nid
	return n


func muzzle_source_ammo_id(entry: Dictionary) -> int:
	## 用稳定状态 id / 记录的来源弹 id 找回效果来源子弹，不用写死展示名。
	var sid: int = int(entry.get("source_ammo_id", 0))
	if sid > 0:
		return CombatConstants.migrate_ammo_id(sid)
	var kind: String = str(entry.get("id", "")).strip_edges()
	if kind == "qishi":
		return CombatConstants.QISHI_AMMO_ID
	if kind == "xuli":
		return CombatConstants.XULI_AMMO_ID
	if kind == "huiwei":
		return CombatConstants.HUIWEI_AMMO_ID
	if kind == "chuandi":
		return CombatConstants.CHUANDI_AMMO_ID
	if kind == "weijiabei":
		return CombatConstants.WEIJIABEI_AMMO_ID
	if kind == "jiasu":
		return CombatConstants.JIASU_AMMO_ID
	return 0


func muzzle_buff_display_label(entry: Dictionary) -> String:
	## 伤害类枪口展示名跟随来源子弹当前图鉴名；其它状态仍用数据里的短标签。
	var kind: String = str(entry.get("effect_kind", ""))
	var sid: int = muzzle_source_ammo_id(entry)
	if kind == "damage_pct" or kind == "damage_mult" or kind == "damage_flat" or sid == CombatConstants.QISHI_AMMO_ID or sid == CombatConstants.XULI_AMMO_ID or sid == CombatConstants.HUIWEI_AMMO_ID or sid == CombatConstants.CHUANDI_AMMO_ID or sid == CombatConstants.WEIJIABEI_AMMO_ID:
		if sid > 0:
			return ammo_display_name(sid)
	if sid > 0 and str(entry.get("label", "")).strip_edges().is_empty():
		return ammo_display_name(sid)
	var lab: String = str(entry.get("label", "")).strip_edges()
	if not lab.is_empty():
		return lab
	var nm: String = str(entry.get("name", "")).strip_edges()
	if not nm.is_empty():
		return nm
	if sid > 0:
		return ammo_display_name(sid)
	return ""


func get_enemy(enemy_id: int) -> Dictionary:
	return _enemies_by_id.get(enemy_id, {})


func get_tag(tag_id: String) -> Dictionary:
	return _tags_by_id.get(tag_id, {})


func all_ammo() -> Array:
	return _ammo_by_id.values()


func all_enemies() -> Array:
	return _enemies_by_id.values()


func is_ammo_enabled(ammo_id: int) -> bool:
	return bool(get_ammo(ammo_id).get("enabled_in_combat", false))


func is_ammo_runtime_visible(ammo_id: int) -> bool:
	## 运行时列表（图鉴/店/奖励/沙盒）只含 data 里启用的弹。
	return is_ammo_enabled(ammo_id)


func is_ammo_ephemeral(ammo_id: int) -> bool:
	## 战斗衍生物（如幽灵）：战后消失，不进奖励/商店。
	return bool(get_ammo(ammo_id).get("ephemeral", false))


func is_sin_ammo(ammo_id: int) -> bool:
	## 标签「罪孽」：商店不可移除（设计：初始罪孽不能被删除）。
	var tags = get_ammo(ammo_id).get("tags", [])
	if tags is Array:
		return "罪孽" in tags
	return false


func is_ammo_reward_eligible(ammo_id: int) -> bool:
	## 奖励/商店池：启用、非 ephemeral、不是罪孽。罪孽只能开局选。
	## in_reward_pool 可显式覆盖非罪孽弹；罪孽标签一律排除。
	var def: Dictionary = get_ammo(ammo_id)
	if def.is_empty():
		return false
	if is_sin_ammo(ammo_id):
		return false
	if not bool(def.get("enabled_in_combat", false)):
		return false
	if def.has("in_reward_pool"):
		return bool(def["in_reward_pool"])
	return not bool(def.get("ephemeral", false))


func get_ammo_rarity(ammo_id: int) -> String:
	## common/uncommon/rare/epic；缺省 uncommon（对齐旧统一价）。
	var def: Dictionary = get_ammo(ammo_id)
	var r: String = str(def.get("rarity", "")).strip_edges()
	if r.is_empty() or r == "null":
		return "uncommon"
	return r


func is_enemy_enabled(enemy_id: int) -> bool:
	return bool(get_enemy(enemy_id).get("enabled_in_combat", false))


## 游戏内子弹描述性文本（图鉴、详情、提示、奖励、商店等共用）。名称仍走 ammo_display_name。
## 新子弹默认「普通的一个子弹...」；缺字段时回退到 blurb / special，不改机制数值。
const DEFAULT_AMMO_GAME_DESCRIPTION := "普通的一个子弹..."


func ammo_game_description(ammo_id: int) -> String:
	if ammo_id == CombatConstants.INVALID_AMMO_ID:
		return str(CombatConstants.INVALID_AMMO_SPECIAL)
	var def: Dictionary = get_ammo(ammo_id)
	if def.is_empty():
		return ""
	if def.has("game_description"):
		return str(def.get("game_description", "")).strip_edges()
	var blurb := str(def.get("blurb", "")).strip_edges()
	if blurb != "":
		return blurb
	var special := str(def.get("special", "")).strip_edges()
	if special != "" and special != "无":
		return special
	return ""


## 袋内悬停/长按详情：名称 / 基础伤害 / 由游戏内描述提供的效果说明（无效弹用本地常量）。
func format_ammo_detail_text(ammo_id: int) -> String:
	if ammo_id == CombatConstants.INVALID_AMMO_ID:
		return "名称：%s\n基础伤害：0\n效果：\n%s" % [
			CombatConstants.INVALID_AMMO_NAME,
			CombatConstants.INVALID_AMMO_SPECIAL,
		]
	var def: Dictionary = get_ammo(ammo_id)
	if def.is_empty():
		return "未知弹药 #%d" % ammo_id
	var nm := str(def.get("name", "未知"))
	var mode := str(def.get("base_damage_mode", ""))
	var dmg = def.get("base_damage", null)
	var dmg_s: String
	if dmg == null:
		dmg_s = "（公式/%s，见表效果）" % mode
	else:
		dmg_s = "%s（%s）" % [str(dmg), mode if mode != "" else "fixed"]
	var tags = def.get("tags", [])
	var tag_s := "、".join(tags) if tags is Array and tags.size() > 0 else "无"
	var school := str(def.get("school", "")).strip_edges()
	var desc := ammo_game_description(ammo_id)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("名称：%s" % nm)
	lines.append("基础伤害：%s" % dmg_s)
	if school != "":
		lines.append("流派：%s" % school)
	lines.append("标签：%s" % tag_s)
	lines.append("效果：")
	lines.append(desc if desc != "" else "无")
	return "\n".join(lines)

## 奖励三选一用短摘要：取游戏内描述并截断。旁注勿整段。伤X 仍来自数值字段。
func format_ammo_reward_blurb(ammo_id: int, max_chars: int = 28) -> String:
	if ammo_id == CombatConstants.INVALID_AMMO_ID:
		return "伤0 · 占袋无效弹"
	var def: Dictionary = get_ammo(ammo_id)
	if def.is_empty():
		return "未知弹药"
	var dmg = def.get("base_damage", null)
	var blurb := ammo_game_description(ammo_id)
	if blurb.is_empty():
		blurb = "常规"
	else:
		for sep in ["。", "；", "，", ".", ";", ","]:
			var idx := blurb.find(sep)
			if idx >= 0 and idx <= max_chars + 4:
				blurb = blurb.substr(0, idx)
				break
		if blurb.length() > max_chars:
			blurb = blurb.substr(0, max_chars) + "…"
		if blurb == "无" or blurb.begins_with("无，") or blurb.begins_with("无特殊"):
			blurb = "常规"
	if dmg == null:
		return blurb
	return "伤%s · %s" % [str(dmg), blurb]


func muzzle_status_of(ammo_id: int) -> Dictionary:
	## 子弹定义里的枪口状态（可选）。没有声明则返回空。
	var def: Dictionary = get_ammo(ammo_id)
	if def.is_empty():
		return {}
	var raw = def.get("muzzle_status", null)
	if raw == null or typeof(raw) != TYPE_DICTIONARY or (raw as Dictionary).is_empty():
		return {}
	var src: Dictionary = raw
	var out := src.duplicate(true)
	if not out.has("id") or str(out.get("id", "")).strip_edges() == "":
		out["id"] = str(def.get("name", ammo_id))
	out["source_ammo_id"] = ammo_id
	var display: String = ammo_display_name(ammo_id)
	if not out.has("name") or str(out.get("name", "")).strip_edges() == "":
		out["name"] = display
	var kind: String = str(out.get("effect_kind", ""))
	# 伤害类枪口标签跟当前子弹名走，不用数据里写死的旧称（如「起势」「蓄力」）。
	if kind == "damage_pct" or kind == "damage_mult" or kind == "damage_flat" or kind == "transfer_decay" or kind == "end_flat":
		out["name"] = display
		out["label"] = display
	else:
		var label := str(out.get("label", "")).strip_edges()
		if label.is_empty():
			label = _default_muzzle_status_label(display if not display.begins_with("未知#") else str(out.get("name", "")))
		out["label"] = label
		if str(out.get("name", "")).strip_edges() == "":
			out["name"] = display
	if not out.has("duration_type") or str(out.get("duration_type", "")).strip_edges() == "":
		out["duration_type"] = "rest_of_volley"
	var explicit := _muzzle_status_color(out.get("color", null), ammo_id)
	if explicit.a > 0.0 and out.get("color", null) != null and str(out.get("color", "")).strip_edges() != "":
		out["color"] = explicit
	else:
		out["color"] = AmmoColors.muzzle_color(ammo_id)
	return out


static func _default_muzzle_status_label(name: String) -> String:
	var s := name.strip_edges()
	if s.ends_with("弹"):
		s = s.substr(0, s.length() - 1)
	if s.length() > 2:
		s = s.substr(0, 2)
	return s


static func _muzzle_status_color(raw, _ammo_id: int) -> Color:
	return AmmoColors.parse_hex_color(raw)


static func format_muzzle_status_duration(entry: Dictionary) -> String:
	return "【火焰层数】%d" % maxi(0, int(entry.get("remaining", entry.get("layer_count", 1))))


static func format_muzzle_status_effect(entry: Dictionary) -> String:
	var kind := str(entry.get("effect_kind", ""))
	var stacks: int = maxi(int(entry.get("remaining", entry.get("stacks", 1))), 1)
	var per: float = float(entry.get("effect_per_stack", 0.0))
	if kind == "damage_pct":
		return "每层伤害×%s；当前×%s" % [_format_muzzle_mult(1.0 + per), _format_muzzle_mult(pow(1.0 + per, stacks))]
	if kind == "damage_mult":
		var mul: float = 1.0
		for _i in stacks:
			mul *= per if per > 0.0 else 1.0
		var shown := _format_muzzle_mult(mul)
		if str(entry.get("duration_type", "")) == "until_last":
			return "最后一发×%s" % shown
		return "下一发×%s" % shown
	if kind == "transfer_decay":
		return "伤害+%d；每次消耗一层后减1，最低0" % int(entry.get("remaining", 0))
	if kind == "end_flat":
		return "每颗剩余结束弹伤害+%s" % _format_muzzle_mult(float(entry.get("amount", 0)))
	if kind == "damage_flat" and str(entry.get("id", "")) == "total_transfer":
		return "每层+%s；当前伤害+%s" % [_format_muzzle_mult(float(entry.get("amount", 0))), _format_muzzle_mult(float(entry.get("amount", 0)) * float(stacks))]
	if kind == "damage_flat":
		var amt: int = int(entry.get("amount", 0))
		if amt == 0:
			amt = int(round(per * float(stacks)))
		return "伤害+%d" % amt
	if kind == "speed_pct":
		var pct: int = int(round(per * 100.0 * float(stacks)))
		return "开火节奏+%d%%" % pct
	var custom := str(entry.get("effect", "")).strip_edges()
	if not custom.is_empty():
		return custom
	return ""


static func _format_muzzle_mult(v: float) -> String:
	var rounded: float = snapped(v, 0.01)
	if is_equal_approx(rounded, float(int(round(rounded)))):
		return str(int(round(rounded)))
	var s := "%.2f" % rounded
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s

