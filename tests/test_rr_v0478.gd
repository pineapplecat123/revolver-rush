extends GutTest
## v0.4.78：子弹「游戏内描述」字段贯穿编辑器/同步/游戏内文案；不改机制数值。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CampaignRules.reload()
	CombatState.boot_campaign = false
	CombatState.boot_sandbox = false


func after_each() -> void:
	CombatState.boot_campaign = false
	CombatState.boot_sandbox = false


func test_version_is_0_4_78() -> void:
	assert_eq(GameVersion.STRING, "0.4.78")
	assert_true("0.4.78" in FileAccess.get_file_as_string("res://data/changelog.json"))
	assert_true("游戏内描述" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_default_literal_is_exact_ascii_periods() -> void:
	var expected := "普通的一个子弹..."
	assert_eq(DataRegistry.DEFAULT_AMMO_GAME_DESCRIPTION, expected)
	assert_eq(expected.length(), 10)
	assert_eq(expected.substr(expected.length() - 3, 3), "...")
	assert_false(expected.contains("…"))


func test_accessor_uses_field_and_respects_empty() -> void:
	var white_id := CombatConstants.WHITE_AMMO_ID
	var text := DataRegistry.ammo_game_description(white_id)
	assert_true(text.contains("没特殊效果") or text.contains("基本"), text)
	assert_eq(DataRegistry.ammo_display_name(white_id), "白板弹")

	assert_eq(DataRegistry.ammo_game_description(CombatConstants.INVALID_AMMO_ID), str(CombatConstants.INVALID_AMMO_SPECIAL))


func test_migrated_ammo_keeps_user_facing_text_not_new_default() -> void:
	var default_text := DataRegistry.DEFAULT_AMMO_GAME_DESCRIPTION
	var stamped := 0
	var with_field := 0
	for def in DataRegistry.all_ammo():
		if typeof(def) != TYPE_DICTIONARY:
			continue
		if not bool(def.get("enabled_in_combat", false)):
			continue
		assert_true(def.has("game_description"), "ammo %s missing game_description" % str(def.get("id")))
		with_field += 1
		var gd := str(def.get("game_description", ""))
		var special := str(def.get("special", "")).strip_edges()
		if gd == default_text and special != default_text and special != "" and special != "无":
			stamped += 1
		# 名称仍在
		assert_false(str(def.get("name", "")).is_empty())
	assert_gt(with_field, 0)
	assert_eq(stamped, 0, "existing ammo must not be overwritten with the new-bullet default")


func test_detail_and_reward_use_game_description_not_notes() -> void:
	var id := CombatConstants.WHITE_AMMO_ID
	var desc := DataRegistry.ammo_game_description(id)
	var detail := DataRegistry.format_ammo_detail_text(id)
	assert_true(detail.contains("名称：白板弹"))
	assert_true(detail.contains("基础伤害："))
	assert_true(detail.contains(desc), detail)
	assert_false(detail.contains("策划") and detail.contains("备注"))
	var blurb := DataRegistry.format_ammo_reward_blurb(id)
	assert_true(blurb.contains("伤") or blurb.contains("3"))
	assert_lte(blurb.length(), 48)
	# 伤害数字仍来自数值字段
	var def: Dictionary = DataRegistry.get_ammo(id)
	assert_eq(int(def.get("base_damage", -1)), 3)


func test_consumers_do_not_change_mechanics() -> void:
	assert_eq(CampaignRules.gumball_price(), 5)
	var cs := CombatState.new(47801)
	cs.start_rush(47801)
	cs.bag.clear()
	for _i in 6:
		cs.bag.append(CombatConstants.WHITE_AMMO_ID)
	assert_true(cs.do_load())
	var white: Dictionary = DataRegistry.get_ammo(CombatConstants.WHITE_AMMO_ID)
	assert_eq(int(white.get("base_damage", -1)), 3)
	assert_eq(str(white.get("name", "")), "白板弹")
	# 弹袋数量与上弹不因文案改变
	assert_eq(cs.magazine.loaded_count(), CombatConstants.MAGAZINE_SIZE)


func test_accessor_falls_back_when_field_absent() -> void:
	var id := CombatConstants.WHITE_AMMO_ID
	var def: Dictionary = DataRegistry.get_ammo(id)
	var saved_gd = def.get("game_description")
	var saved_blurb = def.get("blurb")
	def.erase("game_description")
	def["blurb"] = "回退摘要文案XYZ"
	var got := DataRegistry.ammo_game_description(id)
	if saved_gd != null:
		def["game_description"] = saved_gd
	else:
		def.erase("game_description")
	if saved_blurb == null:
		def.erase("blurb")
	else:
		def["blurb"] = saved_blurb
	assert_eq(got, "回退摘要文案XYZ")
	assert_true(str(DataRegistry.ammo_game_description(id)).contains("没特殊效果") or str(DataRegistry.ammo_game_description(id)).contains("基本"))
