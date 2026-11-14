class_name AmmoColors
## 弹药色板：类型标签有默认色（开始绿 / 中间黄 / 结束红），单弹可在 ammo.json 用 color 覆盖。
## 无标签的旧弹（如平庸）沿用原来的按 id 色。

const TAG_START := "开始"
const TAG_MID := "中间"
const TAG_END := "结束"

## 像素风、和现有袋内球对比够清楚的默认色。
const TAG_DEFAULTS := {
	"开始": {"bg": Color(0.32, 0.78, 0.42), "fg": Color(0.07, 0.16, 0.08)},
	"中间": {"bg": Color(0.95, 0.80, 0.22), "fg": Color(0.18, 0.12, 0.03)},
	"结束": {"bg": Color(0.86, 0.24, 0.22), "fg": Color(1.0, 0.94, 0.93)},
}


static func colors_for(ammo_id: int) -> Dictionary:
	if ammo_id == CombatConstants.INVALID_AMMO_ID:
		return {"bg": Color(0.28, 0.28, 0.3), "fg": Color(0.95, 0.55, 0.55)}
	var def: Dictionary = DataRegistry.get_ammo(ammo_id)
	if not def.is_empty():
		var from_bullet := parse_hex_color(def.get("bullet_color", null))
		if from_bullet.a > 0.0:
			return {"bg": from_bullet, "fg": _contrast_fg(from_bullet)}
		var over := _parse_override(def.get("color", null))
		if not over.is_empty():
			return over
		var tag := type_tag_of(def)
		if tag != "" and TAG_DEFAULTS.has(tag):
			return TAG_DEFAULTS[tag]
	return _legacy_id_colors(ammo_id)


static func muzzle_color(ammo_id: int) -> Color:
	var def: Dictionary = DataRegistry.get_ammo(ammo_id)
	var named := parse_hex_color(def.get("muzzle_color", null))
	if named.a > 0.0:
		return named
	return colors_for(ammo_id).get("bg", Color(0.32, 0.78, 0.42))


static func parse_hex_color(raw) -> Color:
	## 缺省/无法解析时返回 a=0，调用方据此回退。
	if raw == null:
		return Color(0, 0, 0, 0)
	if raw is Color:
		return raw
	if raw is Array and raw.size() >= 3:
		var a: float = float(raw[3]) if raw.size() > 3 else 1.0
		return Color(float(raw[0]), float(raw[1]), float(raw[2]), a)
	var s := str(raw).strip_edges()
	if s.is_empty():
		return Color(0, 0, 0, 0)
	if not s.begins_with("#") and s.length() == 6:
		s = "#" + s
	if s.begins_with("#") and (s.length() == 7 or s.length() == 9):
		return Color.from_string(s, Color(0, 0, 0, 0))
	return Color(0, 0, 0, 0)


static func _contrast_fg(bg: Color) -> Color:
	var lum: float = bg.r * 0.3 + bg.g * 0.6 + bg.b * 0.1
	return Color(0.08, 0.08, 0.1) if lum > 0.55 else Color(0.96, 0.97, 0.94)


static func type_tag_of(def: Dictionary) -> String:
	var tags = def.get("tags", [])
	if tags is Array:
		for t in tags:
			var s := str(t).strip_edges()
			if TAG_DEFAULTS.has(s):
				return s
	return ""


static func _parse_override(raw) -> Dictionary:
	if raw == null or typeof(raw) != TYPE_DICTIONARY:
		return {}
	if not raw.has("bg"):
		return {}
	return {
		"bg": _as_color(raw.get("bg"), Color(0.85, 0.85, 0.88)),
		"fg": _as_color(raw.get("fg"), Color(0.1, 0.1, 0.1)),
	}


static func _as_color(v, fallback: Color) -> Color:
	if v is Color:
		return v
	if v is String:
		var s := str(v).strip_edges()
		if s.begins_with("#") or s.begins_with("rgb"):
			return Color.from_string(s, fallback)
	if v is Array and v.size() >= 3:
		var a: float = float(v[3]) if v.size() > 3 else 1.0
		return Color(float(v[0]), float(v[1]), float(v[2]), a)
	return fallback


static func _legacy_id_colors(ammo_id: int) -> Dictionary:
	match ammo_id:
		FireResolver.ID_WHITE, 1:
			return {"bg": Color(0.92, 0.92, 0.94), "fg": Color(0.08, 0.08, 0.1)}
		FireResolver.ID_GOLD:
			return {"bg": Color(0.95, 0.75, 0.15), "fg": Color(0.2, 0.12, 0.02)}
		FireResolver.ID_FLAME:
			return {"bg": Color(1.0, 0.45, 0.15), "fg": Color(0.15, 0.05, 0.0)}
		FireResolver.ID_WRATH:
			return {"bg": Color(0.75, 0.12, 0.12), "fg": Color(1.0, 0.92, 0.9)}
		FireResolver.ID_PRIDE:
			return {"bg": Color(0.55, 0.35, 0.85), "fg": Color(0.98, 0.95, 1.0)}
		FireResolver.ID_GREED:
			return {"bg": Color(0.2, 0.65, 0.35), "fg": Color(0.95, 1.0, 0.95)}
		FireResolver.ID_LUST:
			return {"bg": Color(0.85, 0.25, 0.55), "fg": Color(1.0, 0.94, 0.97)}
		FireResolver.ID_ENVY:
			return {"bg": Color(0.25, 0.7, 0.45), "fg": Color(0.94, 1.0, 0.96)}
		FireResolver.ID_GLUTTONY:
			return {"bg": Color(0.75, 0.45, 0.15), "fg": Color(1.0, 0.96, 0.9)}
		FireResolver.ID_SLOTH:
			return {"bg": Color(0.45, 0.55, 0.75), "fg": Color(0.94, 0.96, 1.0)}
		FireResolver.ID_TOMBSTONE:
			return {"bg": Color(0.42, 0.4, 0.38), "fg": Color(0.95, 0.93, 0.88)}
		FireResolver.ID_GHOST:
			return {"bg": Color(0.72, 0.88, 0.95, 0.85), "fg": Color(0.08, 0.18, 0.28)}
		FireResolver.ID_ARMOR_PIERCE:
			return {"bg": Color(0.55, 0.78, 0.92), "fg": Color(0.04, 0.12, 0.2)}
		FireResolver.ID_ECHO:
			return {"bg": Color(0.35, 0.9, 0.78), "fg": Color(0.04, 0.16, 0.14)}
		FireResolver.ID_LIFESTEAL:
			return {"bg": Color(0.78, 0.12, 0.28), "fg": Color(1.0, 0.92, 0.94)}
		FireResolver.ID_EXPLOSIVE:
			return {"bg": Color(0.95, 0.4, 0.08), "fg": Color(0.12, 0.04, 0.0)}
		FireResolver.ID_SCATTER:
			return {"bg": Color(0.72, 0.55, 0.95), "fg": Color(0.1, 0.05, 0.18)}
		FireResolver.ID_INSURANCE:
			return {"bg": Color(0.78, 0.82, 0.88), "fg": Color(0.08, 0.1, 0.14)}
		FireResolver.ID_FOCUS:
			return {"bg": Color(0.45, 0.85, 1.0), "fg": Color(0.05, 0.12, 0.18)}
		FireResolver.ID_STONE:
			return {"bg": Color(0.55, 0.52, 0.48), "fg": Color(0.95, 0.93, 0.9)}
		FireResolver.ID_PEBBLE:
			return {"bg": Color(0.7, 0.66, 0.6), "fg": Color(0.2, 0.16, 0.12)}
		FireResolver.ID_JUSTICE:
			return {"bg": Color(0.92, 0.9, 0.75), "fg": Color(0.18, 0.14, 0.05)}
		_:
			return {"bg": Color(0.85, 0.85, 0.88), "fg": Color(0.1, 0.1, 0.1)}
