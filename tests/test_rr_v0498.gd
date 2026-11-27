extends GutTest
## v0.4.98：同步子弹编辑器更名、短描述和回味弹颜色；加伤弹层叠规则仍保持逐层相乘。


func test_version_is_0_4_98() -> void:
	assert_eq(GameVersion.STRING, "0.4.98")


func test_renames_copy_and_color_follow_the_editor() -> void:
	assert_eq(str(DataRegistry.get_ammo(CombatConstants.MOFANG_AMMO_ID).get("name")), "技能镜像")
	assert_eq(str(DataRegistry.get_ammo(CombatConstants.HUIWEI_AMMO_ID).get("name")), "超级增强弹")
	assert_eq(str(DataRegistry.get_ammo(CombatConstants.CHUANDI_AMMO_ID).get("name")), "懂得分享")
	assert_eq(str(DataRegistry.get_ammo(CombatConstants.QISHI_AMMO_ID).get("name")), "加伤弹")
	assert_eq(str(DataRegistry.get_ammo(CombatConstants.XULI_AMMO_ID).get("name")), "倍伤弹")
	assert_eq(str(DataRegistry.get_ammo(CombatConstants.HUIWEI_AMMO_ID).get("bullet_color")), "#FF6F00")
	assert_eq(str(DataRegistry.get_ammo(CombatConstants.HUIWEI_AMMO_ID).get("muzzle_color")), "#FF6F00")
	assert_eq(str(DataRegistry.get_ammo(CombatConstants.MOFANG_AMMO_ID).get("game_description")), "纯粹的模仿者...")
	assert_eq(str(DataRegistry.get_ammo(CombatConstants.HUIWEI_AMMO_ID).get("game_description")), "把实际伤害加给后续子弹！")
	assert_eq(str(DataRegistry.get_ammo(CombatConstants.CHUANDI_AMMO_ID).get("game_description")), "自己的强化量分给别人...")
	assert_eq(str(DataRegistry.get_ammo(CombatConstants.XULI_AMMO_ID).get("game_description")), "给后一发子弹乘伤")
	assert_eq(str(DataRegistry.get_ammo(CombatConstants.QISHI_AMMO_ID).get("game_description")), "给后续子弹加伤害")


func test_jia_shang_stacking_is_still_multiplicative() -> void:
	var special := str(DataRegistry.get_ammo(CombatConstants.QISHI_AMMO_ID).get("special", ""))
	assert_true("多层逐层相乘" in special, special)
	assert_false("多层逐层相加" in special)
	var ms: Dictionary = DataRegistry.muzzle_status_of(CombatConstants.QISHI_AMMO_ID)
	assert_almost_eq(float(ms.get("effect_per_stack", 0)), 0.5, 0.001)
	assert_true("多层逐层相乘" in str(ms.get("effect_description", "")), str(ms.get("effect_description", "")))
	# 运行时仍是 (1+0.5)^层数，不是 1+0.5×层数。第一发白板吃两层：3×1.5×1.5=6.75→7；若改相加则是 3×2.0=6。
	var dmg: Array[int] = FireResolver.compute_shot_damages(
		[CombatConstants.QISHI_AMMO_ID, CombatConstants.BAIBAN_AMMO_ID, CombatConstants.BAIBAN_AMMO_ID]
	)
	assert_eq(int(dmg[1]), 7)
	assert_eq(int(dmg[2]), 5)


func test_editor_marks_synced_rows_in_game_and_holds_jia_shang_stacking() -> void:
	var raw := FileAccess.get_file_as_string("res://companion/bullet-editor/data.json")
	var data: Dictionary = JSON.parse_string(raw)
	var by_id := {}
	for b in data.get("bullets", []):
		by_id[str(b.get("id"))] = b
	assert_true(bool(by_id["b20261113-133535-ztag"].get("in_game")))
	assert_true(bool(by_id["b20261116-175020-j9oh"].get("in_game")))
	assert_true(bool(by_id["b20261116-175416-pjui"].get("in_game")))
	assert_true(bool(by_id["b20261118-190327-0ad8"].get("in_game")))
	assert_eq(str(by_id["b20261116-175020-j9oh"].get("name")), "技能镜像")
	assert_eq(str(by_id["b20261116-175416-pjui"].get("name")), "超级增强弹")
	assert_eq(str(by_id["b20261118-190327-0ad8"].get("name")), "懂得分享")
	# 加伤弹层叠规则尚未拍板，编辑器行先保持未入库。
	assert_false(bool(by_id["b20261113-133057-zror"].get("in_game")))
	assert_true("多层逐层相加" in str(by_id["b20261113-133057-zror"].get("effect")))
