extends GutTest
## v0.4.79：入库尾加倍弹；同步已有子弹的游戏内描述和枪口颜色。


const QISHI := CombatConstants.QISHI_AMMO_ID
const XULI := CombatConstants.XULI_AMMO_ID
const BAIBAN := CombatConstants.BAIBAN_AMMO_ID
const MOFANG := CombatConstants.MOFANG_AMMO_ID
const CHONGFU := CombatConstants.CHONGFU_KAISHI_AMMO_ID
const WEIJIA := CombatConstants.WEIJIABEI_AMMO_ID
const EMPTY := Magazine.EMPTY


func before_each() -> void:
	DataRegistry.reload()
	CombatState.boot_sandbox = false


func test_version_is_at_least_0_4_79() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.79") >= 0)
	assert_true("0.4.79" in FileAccess.get_file_as_string("res://data/changelog.json"))
	assert_true("尾加倍弹" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_weijiabei_in_registry_and_reward_pool() -> void:
	var def: Dictionary = DataRegistry.get_ammo(WEIJIA)
	assert_eq(str(def.get("name")), "尾加倍弹")
	assert_eq(FireResolver.type_tag(WEIJIA), "开始")
	assert_eq(FireResolver.base_damage_for(WEIJIA, [], 0), 0)
	assert_eq(int(def.get("base_damage", -1)), 0)
	assert_eq(str(def.get("school")), "清算")
	assert_true(bool(def.get("enabled_in_combat", false)))
	assert_true(DataRegistry.is_ammo_reward_eligible(WEIJIA))
	assert_eq(str(def.get("bullet_color", "")).to_upper(), "#BFFF00")
	assert_eq(str(def.get("muzzle_color", "")).to_upper(), "#BFFF00")
	assert_true(str(def.get("game_description")).begins_with("给最后一发子弹蓄力..."))
	assert_eq(DataRegistry.all_ammo().size(), 28)
	var status: Dictionary = DataRegistry.muzzle_status_of(WEIJIA)
	assert_eq(str(status.get("id")), "weijiabei")
	assert_eq(str(status.get("duration_type")), "until_last")
	assert_eq(str(status.get("effect_kind")), "damage_mult")
	assert_almost_eq(float(status.get("effect_per_stack", 0.0)), 1.5, 0.0001)
	assert_eq(DataRegistry.format_muzzle_status_duration(status), "【火焰层数】1")
	assert_eq(DataRegistry.format_muzzle_status_effect(status), "最后一发×1.5")
	status["stacks"] = 2
	assert_eq(DataRegistry.format_muzzle_status_effect(status), "最后一发×2.25")


func test_weijiabei_multiplies_only_last_actual_damaging_shot() -> void:
	# 最后一发白板：3×1.5=4.5；中间白板不被加强。
	var one: Array[float] = FireResolver.compute_volley_damages([WEIJIA, BAIBAN, BAIBAN])
	assert_almost_eq(one[0], 0.0, 0.0001)
	assert_almost_eq(one[1], 3.0, 0.0001)
	assert_almost_eq(one[2], 4.5, 0.0001)
	# 空仓不算子弹，最后一发仍是后面那颗白板。
	var gap: Array[float] = FireResolver.compute_volley_damages([WEIJIA, BAIBAN, EMPTY, BAIBAN, EMPTY])
	assert_almost_eq(gap[1], 3.0, 0.0001)
	assert_almost_eq(gap[3], 4.5, 0.0001)
	# 两颗连乘：3×1.5×1.5=6.75
	var two: Array[float] = FireResolver.compute_volley_damages([WEIJIA, WEIJIA, BAIBAN])
	assert_almost_eq(two[2], 6.75, 0.0001)
	var rounded: Array[int] = FireResolver.compute_shot_damages([WEIJIA, WEIJIA, BAIBAN])
	assert_eq(rounded[2], 7)


func test_weijiabei_preserves_zero_damage_last_shots() -> void:
	# 尾加倍自身零伤害，不是开始类型豁免。
	var self_last: Array[float] = FireResolver.compute_volley_damages([BAIBAN, WEIJIA])
	assert_almost_eq(self_last[0], 3.0, 0.0001)
	assert_almost_eq(self_last[1], 0.0, 0.0001)
	# 最后一发加伤弹自身零伤害，所以不吃尾加倍。
	var last_start: Array[float] = FireResolver.compute_volley_damages([WEIJIA, BAIBAN, QISHI])
	assert_almost_eq(last_start[1], 3.0, 0.0001)
	assert_almost_eq(last_start[2], 0.0, 0.0001)


func test_weijiabei_multiplies_with_qishi_and_xuli() -> void:
	# 加伤三层、倍伤一层、尾加倍一层：3×1.5⁵=22.78125
	var d: Array[float] = FireResolver.compute_volley_damages([QISHI, XULI, WEIJIA, BAIBAN])
	assert_almost_eq(d[3], 22.78125, 0.0001)
	# 中间还有一发白板时，蓄力给中间那发，尾加倍给最后一发。
	var split: Array[float] = FireResolver.compute_volley_damages([XULI, WEIJIA, BAIBAN, BAIBAN])
	assert_almost_eq(split[2], 4.5, 0.0001)
	assert_almost_eq(split[3], 4.5, 0.0001)


func test_weijiabei_copied_by_chongfu_and_mofang() -> void:
	# 重复开始弹复制尾加倍，最后一发仍 ×1.5
	var copy: Array[float] = FireResolver.compute_volley_damages([WEIJIA, CHONGFU, BAIBAN])
	assert_almost_eq(copy[2], 6.75, 0.0001)
	# 模仿弹拿到尾加倍技能后自己仍打 3，并把尾倍留给最后一发。
	var mimic: Array[float] = FireResolver.compute_volley_damages([WEIJIA, MOFANG, BAIBAN])
	assert_almost_eq(mimic[1], 3.0, 0.0001)
	assert_almost_eq(mimic[2], 6.75, 0.0001)


func _ready_cs(seed: int) -> CombatState:
	var cs := CombatState.new(seed)
	cs.start_rush(seed, FireResolver.ID_WRATH)
	cs.pace_after_fire = false
	cs.defer_impacts = false
	cs.auto_enemy_advance = false
	while not cs.enemies.is_empty():
		cs.enemies.pop_back()
	cs.dev_spawn_enemy(CombatConstants.DUMMY_ENEMY_ID, 3)
	cs.enemies[cs.enemies.size() - 1].hp = 99
	cs.enemies[cs.enemies.size() - 1].max_hp = 99
	cs.enemies[cs.enemies.size() - 1].atk = 0
	cs.dev_clear_bag()
	cs.magazine.clear()
	cs.magazine.start_index = 0
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	return cs


func _weijia_stacks(cs: CombatState) -> int:
	for b in cs.volley_muzzle_buffs():
		if str(b.get("id", "")) == "weijiabei":
			return int(b.get("stacks", 0))
	return 0


func test_weijiabei_muzzle_status_and_planned_damage() -> void:
	var cs := _ready_cs(47901)
	cs.magazine.set_slot(0, WEIJIA)
	cs.magazine.set_slot(1, BAIBAN)
	cs.magazine.set_slot(2, BAIBAN)
	cs._volley_session = true
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	assert_eq(cs.last_shot_planned_damage, 0)
	assert_eq(cs.last_shot_dealt, 0)
	assert_eq(_weijia_stacks(cs), 0) # t658: not generated until last bullet turn
	var mid: Dictionary = cs.sandbox_damage_modifiers()
	assert_almost_eq(float(mid.get("weijia_mult", 1.0)), 1.0, 0.0001)
	assert_false(str(mid.get("text", "")).contains("留给最后一发"))
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	assert_eq(cs.last_shot_planned_damage, 3)
	assert_eq(cs.last_shot_dealt, 3)
	assert_eq(_weijia_stacks(cs), 1)
	var last: Dictionary = cs.sandbox_damage_modifiers()
	assert_almost_eq(float(last.get("weijia_mult", 1.0)), 1.5, 0.0001)
	assert_true(str(last.get("text", "")).contains("最后一发"), str(last.get("text", "")))
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	assert_eq(cs.last_shot_planned_damage, 5)  # 4.5 → 5
	assert_eq(cs.last_shot_dealt, 5)
	assert_eq(_weijia_stacks(cs), 0)
	cs._volley_session = false
	cs._reset_volley_plan()
	assert_eq(_weijia_stacks(cs), 0)


func test_synced_editor_game_descriptions() -> void:
	assert_true(str(DataRegistry.get_ammo(QISHI).get("game_description")).begins_with("给之后的子弹加伤害"))
	assert_true(str(DataRegistry.get_ammo(XULI).get("game_description")).begins_with("创造蓄力火焰"))
	assert_eq(str(DataRegistry.get_ammo(QISHI).get("muzzle_color", "")).to_upper(), "#52C76B")
	assert_eq(str(DataRegistry.get_ammo(XULI).get("muzzle_color", "")).to_upper(), "#52C76B")
	# 传递弹使用已确认的全额超额逐次减1规则。
	var chuandi: Dictionary = DataRegistry.get_ammo(CombatConstants.CHUANDI_AMMO_ID)
	assert_true(str(chuandi.get("special", "")).contains("【火焰层数】"))
	assert_true(str(chuandi.get("special", "")).contains("+9、+8、+7"))
