extends GutTest
## v0.4.45：主菜单后台预热 pixelfx / 像素着色器，预载战斗场景；网页 worklet 随 hash 复制。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CombatState.boot_sandbox = false


func test_version_is_at_least_0_4_45() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.45") >= 0)
	assert_true("0.4.45" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_pixelfx_prewarm_is_cached_on_second_call() -> void:
	var Spawn: GDScript = load("res://scripts/combat/pixelfx_spawn.gd")
	Spawn.prewarm()
	assert_true(Spawn.is_prewarmed())
	var t0 := Time.get_ticks_msec()
	Spawn.prewarm()
	var second: int = Time.get_ticks_msec() - t0
	assert_lte(second, 30, "second prewarm should be a cache hit, got %d ms" % second)


func test_main_menu_starts_background_warmup_and_exposes_flag() -> void:
	var menu = add_child_autofree(load("res://scenes/main.tscn").instantiate())
	assert_true(menu.has_method("is_warmup_done"))
	assert_true(menu.has_method("_begin_background_warmup"))
	# 等后台预热跑完（分帧烘焙，桌面上通常数秒内）
	var guard := 0
	while not menu.is_warmup_done() and guard < 180:
		await wait_process_frames(1)
		guard += 1
	assert_true(menu.is_warmup_done(), "warmup should finish, frames=%d" % guard)
	var Spawn: GDScript = load("res://scripts/combat/pixelfx_spawn.gd")
	assert_true(Spawn.is_prewarmed())
