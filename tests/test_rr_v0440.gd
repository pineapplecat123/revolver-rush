extends GutTest
## v0.4.40：白矩形修复、开局 6 平庸、零伤害喷火、枪口状态、子弹颜色同步。

const WHITE := CombatConstants.WHITE_AMMO_ID
const QISHI := CombatConstants.QISHI_AMMO_ID
const XULI := CombatConstants.XULI_AMMO_ID
const DIZENG := CombatConstants.DIZENG_AMMO_ID
const ZHONGSHEN := CombatConstants.ZHONGSHEN_AMMO_ID


func before_each() -> void:
	DataRegistry.reload()


func test_changelog_still_has_0_4_40() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.40") >= 0)
	assert_true("0.4.40" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_starter_bag_is_six_white_plus_clearing() -> void:
	assert_eq(CombatConstants.STARTER_WHITE_COUNT, 6)
	assert_eq(CombatConstants.STARTER_CLEARING_EACH, 2)
	assert_eq(CombatConstants.STARTER_BAG_TOTAL, 14)
	var cs := CombatState.new()
	cs.start_rush(44001, FireResolver.ID_WRATH)
	assert_eq(cs.bag.size(), 14)
	assert_eq(cs.total_ammo_count(WHITE), 6)
	assert_eq(cs.total_ammo_count(QISHI), 2)
	assert_eq(cs.total_ammo_count(XULI), 2)
	assert_eq(cs.total_ammo_count(DIZENG), 2)
	assert_eq(cs.total_ammo_count(ZHONGSHEN), 2)


func test_pixel_shader_uses_screen_texture() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/character_pixelate.gdshader")
	assert_true("hint_screen_texture" in src)
	assert_true("discard" in src)
	assert_true("render_mode unshaded, blend_mix" in src)


func test_bullet_and_muzzle_colors_from_data() -> void:
	var qishi: Dictionary = DataRegistry.get_ammo(QISHI)
	assert_eq(str(qishi.get("muzzle_color", "")).to_upper(), "#4AE06A")
	assert_eq(str(qishi.get("bullet_color", "")).to_upper(), "#52C76B")
	var xuli: Dictionary = DataRegistry.get_ammo(XULI)
	assert_eq(str(xuli.get("muzzle_color", "")).to_upper(), "#2CC4B4")
	var white_bg: Color = AmmoColors.colors_for(WHITE)["bg"]
	assert_gt(white_bg.r, 0.85)
	assert_almost_eq(white_bg.r, white_bg.g, 0.05)
	var muzzle_q: Color = AmmoColors.muzzle_color(QISHI)
	assert_gt(muzzle_q.g, muzzle_q.r)
	var muzzle_x: Color = AmmoColors.muzzle_color(XULI)
	assert_gt(muzzle_x.g, 0.5)
	assert_gt(muzzle_x.b, muzzle_x.r)
	# 类型色回退：终审没有单独的枪口色时跟子弹红走
	var end_c: Color = AmmoColors.muzzle_color(ZHONGSHEN)
	assert_gt(end_c.r, end_c.g)


func test_muzzle_status_defs_are_data_driven() -> void:
	var q: Dictionary = DataRegistry.muzzle_status_of(QISHI)
	assert_eq(str(q.get("label", "")), "起势")
	assert_eq(str(q.get("duration_type", "")), "rest_of_volley")
	assert_eq(DataRegistry.format_muzzle_status_effect(q), "伤害+10%")
	q["stacks"] = 2
	q["remaining"] = 4
	assert_eq(DataRegistry.format_muzzle_status_effect(q), "伤害+20%")
	assert_eq(DataRegistry.format_muzzle_status_duration(q), "后续 4 发子弹")
	var x: Dictionary = DataRegistry.muzzle_status_of(XULI)
	assert_eq(str(x.get("label", "")), "蓄力")
	assert_eq(str(x.get("duration_type", "")), "until_consumed")
	assert_eq(DataRegistry.format_muzzle_status_effect(x), "下一发×1.5")
	x["stacks"] = 2
	assert_eq(DataRegistry.format_muzzle_status_effect(x), "下一发×2.25")
	assert_eq(DataRegistry.format_muzzle_status_duration(x), "下一发")
	assert_true(DataRegistry.muzzle_status_of(WHITE).is_empty())
	assert_true(DataRegistry.muzzle_status_of(DIZENG).is_empty())


func _ready_fight(seed_v: int) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v, FireResolver.ID_WRATH)
	cs.pace_after_fire = false
	cs.defer_impacts = false
	cs.auto_enemy_advance = false
	while not cs.enemies.is_empty():
		cs.enemies.pop_back()
	cs.dev_spawn_enemy(1, 5)
	cs.enemies[0].hp = 999
	cs.enemies[0].max_hp = 999
	cs.enemies[0].atk = 0
	cs.magazine.clear()
	cs.magazine.start_index = 0
	return cs


func test_qishi_icon_counts_remaining_then_clears() -> void:
	var cs := _ready_fight(44010)
	cs.magazine.set_slot(0, QISHI)
	cs.magazine.set_slot(1, WHITE)
	cs.magazine.set_slot(2, WHITE)
	cs.magazine.set_slot(3, WHITE)
	var first: Array = cs.fire_tap(false)
	assert_eq(first.size(), 1)
	assert_eq(int(first[0].get("planned_damage", -1)), 0)
	assert_eq(int(first[0].get("ammo_id", -1)), QISHI)
	var buffs: Array = cs.volley_muzzle_buffs()
	assert_eq(buffs.size(), 1)
	assert_eq(str(buffs[0].get("label", "")), "起势")
	assert_eq(int(buffs[0].get("remaining", -1)), 3)
	assert_eq(int(buffs[0].get("total", -1)), 3)
	assert_eq(DataRegistry.format_muzzle_status_effect(buffs[0]), "伤害+10%")
	cs.player_fire_gate_remaining = 0.0
	var second: Array = cs.take_volley_shot()
	assert_eq(second.size(), 1)
	assert_eq(int(second[0].get("planned_damage", -1)), 3)
	buffs = cs.volley_muzzle_buffs()
	assert_eq(buffs.size(), 1)
	assert_eq(int(buffs[0].get("remaining", -1)), 2)
	cs.player_fire_gate_remaining = 0.0
	cs.take_volley_shot()
	buffs = cs.volley_muzzle_buffs()
	assert_eq(int(buffs[0].get("remaining", -1)), 1)
	cs.player_fire_gate_remaining = 0.0
	cs.take_volley_shot()
	assert_eq(cs.volley_muzzle_buffs().size(), 0, "连射结束清空状态")
	assert_false(cs.is_volley_pending())


func test_xuli_passes_start_and_consumes_on_white() -> void:
	var cs := _ready_fight(44011)
	cs.magazine.set_slot(0, XULI)
	cs.magazine.set_slot(1, QISHI)
	cs.magazine.set_slot(2, WHITE)
	cs.fire_tap(false)
	var buffs: Array = cs.volley_muzzle_buffs()
	assert_eq(buffs.size(), 1)
	assert_eq(str(buffs[0].get("label", "")), "蓄力")
	assert_eq(int(buffs[0].get("remaining", -1)), 1)
	cs.player_fire_gate_remaining = 0.0
	cs.take_volley_shot()  # 起势：不消耗蓄力，并挂上起势
	buffs = cs.volley_muzzle_buffs()
	assert_eq(buffs.size(), 2)
	var labels: PackedStringArray = PackedStringArray()
	for b in buffs:
		labels.append(str(b.get("label", "")))
	assert_true("蓄力" in labels)
	assert_true("起势" in labels)
	cs.player_fire_gate_remaining = 0.0
	var last: Array = cs.take_volley_shot()
	assert_eq(int(last[0].get("ammo_id", -1)), WHITE)
	assert_eq(cs.volley_muzzle_buffs().size(), 0)


func test_qishi_stacks_and_xuli_multiplies() -> void:
	var cs := _ready_fight(44012)
	cs.magazine.set_slot(0, QISHI)
	cs.magazine.set_slot(1, QISHI)
	cs.magazine.set_slot(2, XULI)
	cs.magazine.set_slot(3, XULI)
	cs.magazine.set_slot(4, WHITE)
	cs.fire_tap(false)
	cs.player_fire_gate_remaining = 0.0
	cs.take_volley_shot()
	var buffs: Array = cs.volley_muzzle_buffs()
	assert_eq(buffs.size(), 1)
	assert_eq(int(buffs[0].get("stacks", 0)), 2)
	assert_eq(DataRegistry.format_muzzle_status_effect(buffs[0]), "伤害+20%")
	cs.player_fire_gate_remaining = 0.0
	cs.take_volley_shot()
	cs.player_fire_gate_remaining = 0.0
	cs.take_volley_shot()
	buffs = cs.volley_muzzle_buffs()
	var xuli_e: Dictionary = {}
	for b in buffs:
		if str(b.get("label", "")) == "蓄力":
			xuli_e = b
	assert_false(xuli_e.is_empty())
	assert_eq(int(xuli_e.get("stacks", 0)), 2)
	assert_eq(DataRegistry.format_muzzle_status_effect(xuli_e), "下一发×2.25")


func test_empty_chamber_does_not_consume_xuli() -> void:
	var cs := _ready_fight(44013)
	cs.magazine.set_slot(0, XULI)
	# slot 1 empty
	cs.magazine.set_slot(2, WHITE)
	cs.fire_tap(false)
	assert_eq(cs.volley_muzzle_buffs().size(), 1)
	cs.player_fire_gate_remaining = 0.0
	# 空仓一拍
	assert_true(cs.volley_port_empty())
	assert_true(cs.take_volley_blank_beat())
	assert_eq(cs.volley_muzzle_buffs().size(), 1)
	assert_eq(int(cs.volley_muzzle_buffs()[0].get("remaining", 0)), 1)
	cs.player_fire_gate_remaining = 0.0
	cs.take_volley_shot()
	assert_eq(cs.volley_muzzle_buffs().size(), 0)


func test_zero_damage_shots_are_puff_only() -> void:
	var qishi_rec := {"ammo_id": QISHI, "planned_damage": 0}
	var white_rec := {"ammo_id": WHITE, "planned_damage": 3}
	var zero_zhong := {"ammo_id": ZHONGSHEN, "planned_damage": 0}
	assert_true(load("res://scripts/combat/combat_ui.gd").shot_is_puff_only(qishi_rec))
	assert_false(load("res://scripts/combat/combat_ui.gd").shot_is_puff_only(white_rec))
	assert_true(load("res://scripts/combat/combat_ui.gd").shot_is_puff_only(zero_zhong))
	# 兜底：没有 planned_damage 时，固定 0 伤害的定义也视为喷火
	assert_true(load("res://scripts/combat/combat_ui.gd").shot_is_puff_only({"ammo_id": XULI}))
