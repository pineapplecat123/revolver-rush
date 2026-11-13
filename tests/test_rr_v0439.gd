extends GutTest
## v0.4.39：pixelfx 随机、命中飚血、角色像素风、按标签自动装填 / 转轮落点。

const PixelFxSpawnScript := preload("res://scripts/combat/pixelfx_spawn.gd")
const CharacterPixelScript := preload("res://scripts/combat/character_pixel.gd")
const WHITE := CombatConstants.WHITE_AMMO_ID
const QISHI := CombatConstants.QISHI_AMMO_ID
const XULI := CombatConstants.XULI_AMMO_ID
const DIZENG := CombatConstants.DIZENG_AMMO_ID
const ZHONGSHEN := CombatConstants.ZHONGSHEN_AMMO_ID


func before_each() -> void:
	DataRegistry.reload()


func test_version_is_0_4_39() -> void:
	assert_eq(GameVersion.STRING, "0.4.39")
	assert_true("0.4.39" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_pixelfx_spawn_varies_and_hit_is_blood() -> void:
	PixelFxSpawnScript.prewarm()
	var host := Node2D.new()
	add_child_autofree(host)
	host.global_position = Vector2(80, 80)
	var seen_seed: Dictionary = {}
	var seen_scale: Dictionary = {}
	var seen_flip := false
	for i in 16:
		var fx = PixelFxSpawnScript.play_hit(host, Vector2(100, 120))
		assert_not_null(fx)
		assert_eq(fx.mode, PixelFx2D.Mode.BAKED)
		assert_true(PixelFxSpawnScript.is_hit_fx(fx))
		seen_seed[fx.seed] = true
		seen_scale[snapped(absf(fx.scale.x), 0.001)] = true
		if fx.scale.x < 0.0:
			seen_flip = true
	assert_gt(seen_seed.size(), 1, "命中应在预烘 seed 里轮换")
	assert_true(seen_flip, "命中允许水平翻转")
	assert_gt(seen_scale.size(), 1, "缩放应有抖动")
	# 枪口不翻转
	var muzzle_flipped := false
	for i in 10:
		var mz = PixelFxSpawnScript.play_muzzle(host, Vector2(40, 80))
		assert_true(PixelFxSpawnScript.is_muzzle_fx(mz))
		if mz.scale.x < 0.0:
			muzzle_flipped = true
	assert_false(muzzle_flipped, "枪口焰保持朝右，不水平翻转")


func test_character_rig_is_pixelated_hp_stays_outside() -> void:
	var player = load("res://scenes/player/skeleton_player.tscn").instantiate()
	add_child_autofree(player)
	var group = player.get_node_or_null("PixelRig")
	assert_not_null(group, "玩家 Rig 应包在 PixelRig 里")
	assert_true(group is CanvasGroup)
	assert_eq(group.get_child(0).name, "Rig")
	assert_true(group.material is ShaderMaterial)
	assert_almost_eq(float((group.material as ShaderMaterial).get_shader_parameter("pixel_size")), CharacterPixelScript.PIXEL_SIZE, 0.01)
	assert_not_null(player.get_node_or_null("HpBadge"), "血条在 CanvasGroup 外，保持清晰")
	var enemy = load("res://scenes/enemy/skeleton_enemy.tscn").instantiate()
	add_child_autofree(enemy)
	enemy.setup(1)
	var eg = enemy.get_node_or_null("PixelRig")
	assert_not_null(eg)
	assert_true(eg is CanvasGroup)
	assert_not_null(enemy.get_node_or_null("HpBadge"))


func test_auto_load_orders_by_type_tag_in_fire_order() -> void:
	var cs := CombatState.new(43901)
	cs.start_rush(43901, FireResolver.ID_WRATH)
	cs.magazine.clear()
	cs.magazine.start_index = 2
	# 手顺序刻意打乱：平庸、终审、递增、起势、平庸、蓄力
	cs.hand.clear()
	cs.hand_temp.clear()
	cs.hand_envy_copy.clear()
	cs.hand_uid.clear()
	for ammo_id in [WHITE, ZHONGSHEN, DIZENG, QISHI, WHITE, XULI]:
		cs._hand_append(ammo_id, 0.0, false)
	var n: int = cs.auto_load_from_hand()
	assert_eq(n, 6)
	assert_true(cs.hand.is_empty())
	# 自击发位 2 起：开始、开始、中间、结束、无标签、无标签
	var fire0: int = cs.magazine.chamber_at_fire_port()
	assert_eq(fire0, 2)
	var got: Array[int] = []
	for k in 6:
		got.append(cs.magazine.slots[(fire0 + k) % 6])
	assert_eq(got, [QISHI, XULI, DIZENG, ZHONGSHEN, WHITE, WHITE] as Array[int])


func test_auto_load_keeps_already_loaded_chambers() -> void:
	var cs := CombatState.new(43902)
	cs.start_rush(43902, FireResolver.ID_WRATH)
	cs.magazine.clear()
	cs.magazine.start_index = 0
	cs.magazine.set_slot(0, WHITE)
	cs.magazine.set_slot(3, ZHONGSHEN)
	cs.hand.clear()
	cs.hand_temp.clear()
	cs.hand_envy_copy.clear()
	cs.hand_uid.clear()
	for ammo_id in [DIZENG, QISHI, WHITE]:
		cs._hand_append(ammo_id, 0.0, false)
	assert_eq(cs.auto_load_from_hand(), 3)
	# 开火顺序空仓是 1,2,4,5；先装开始再中间再平庸；0 和 3 不动
	assert_eq(cs.magazine.slots[0], WHITE)
	assert_eq(cs.magazine.slots[3], ZHONGSHEN)
	assert_eq(cs.magazine.slots[1], QISHI)
	assert_eq(cs.magazine.slots[2], DIZENG)
	assert_eq(cs.magazine.slots[4], WHITE)
	assert_eq(cs.magazine.slots[5], Magazine.EMPTY)
	assert_true(cs.hand.is_empty())


func test_spin_lands_on_random_start_type() -> void:
	var cs := CombatState.new(43903)
	cs.start_rush(43903, FireResolver.ID_WRATH)
	# 满匣：起势在 1、4，其余平庸。反复转必须落在 1 或 4。
	cs.magazine.clear()
	cs.magazine.start_index = 0
	cs.magazine.set_slot(0, WHITE)
	cs.magazine.set_slot(1, QISHI)
	cs.magazine.set_slot(2, WHITE)
	cs.magazine.set_slot(3, WHITE)
	cs.magazine.set_slot(4, XULI)
	cs.magazine.set_slot(5, WHITE)
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	var landed: Dictionary = {}
	for i in 24:
		var steps: int = cs.spin_cylinder_for_volley()
		assert_gt(steps, 0)
		var port: int = cs.magazine.chamber_at_fire_port()
		assert_true(port == 1 or port == 4, "应停在开始弹仓，实际 %d" % port)
		landed[port] = true
	assert_eq(landed.size(), 2, "两个开始仓都应能落到")


func test_spin_without_start_type_keeps_old_behavior() -> void:
	var cs := CombatState.new(43904)
	cs.start_rush(43904, FireResolver.ID_WRATH)
	cs.magazine.clear()
	cs.magazine.start_index = 0
	cs.magazine.set_slot(0, WHITE)
	cs.magazine.set_slot(2, DIZENG)
	cs.magazine.set_slot(4, ZHONGSHEN)
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	for i in 16:
		var steps: int = cs.spin_cylinder_for_volley()
		assert_gt(steps, 0)
		var port: int = cs.magazine.chamber_at_fire_port()
		assert_ne(cs.magazine.slots[port], Magazine.EMPTY, "无开始弹时仍不得停在空仓")
		assert_true(port == 0 or port == 2 or port == 4)


func test_auto_load_button_exists() -> void:
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(2)
	var btn: Button = ui.get_node("%BtnAutoLoad")
	assert_not_null(btn)
	assert_true(btn.visible)
	assert_eq(btn.text, "自动装填")
	ui.state.dump_to_hand()
	ui._refresh()
	assert_false(btn.disabled, "手中有弹且有空仓时应可自动装填")
	ui._on_auto_load()
	assert_eq(ui.state.magazine.loaded_count(), 6)
