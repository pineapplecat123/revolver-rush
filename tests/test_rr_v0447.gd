extends GutTest
## v0.4.47：加载转轮去掉红圈；战斗转轮同一套样式；击发指示圈浅白并轻微闪光。


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CombatState.boot_sandbox = false


func test_version_is_at_least_0_4_47() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.47") >= 0)
	assert_true("0.4.47" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_web_shell_and_boot_splash_have_no_red_ring() -> void:
	var shell := FileAccess.get_file_as_string("res://misc/web_shell.html")
	assert_true("rr-cylinder-spin" in shell)
	assert_true('id="status-progress"' in shell)
	assert_false("rr-fire-ring" in shell)
	assert_false("FF261F" in shell)
	assert_true(FileAccess.file_exists("res://assets/boot/loading_cylinder.png"))
	var tex: Texture2D = load("res://assets/boot/loading_cylinder.png")
	assert_not_null(tex, "boot splash png should import as a texture")
	var img: Image = tex.get_image()
	assert_not_null(img, "boot splash texture should provide image data")
	var reds := 0
	var w: int = img.get_width()
	var h: int = img.get_height()
	var step: int = 2
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c: Color = img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			if c.r > 0.75 and c.g < 0.35 and c.b < 0.35:
				reds += 1
	assert_eq(reds, 0, "boot splash should not contain the red fire ring, got %d red pixels" % reds)


func test_ingame_cylinder_matches_loading_art_and_keeps_gameplay() -> void:
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(2)
	var disk: Node = ui.mag_wheel.get_node("Disk")
	assert_not_null(disk.get_node_or_null("DiskBg"))
	assert_not_null(disk.get_node_or_null("Groove"))
	assert_not_null(disk.get_node_or_null("Hub"))
	assert_not_null(disk.get_node_or_null("HubPin"))
	# Gameplay fire marker stays; silver-white with a soft glow, same 12 o'clock seat.
	var fire_ring: Panel = ui.mag_wheel.get_node_or_null("FireRing") as Panel
	var glow: Panel = ui.mag_wheel.get_node_or_null("FireRingGlow") as Panel
	assert_not_null(fire_ring)
	assert_not_null(glow)
	assert_true(fire_ring.visible)
	assert_true(glow.visible)
	var ring_st := fire_ring.get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(ring_st)
	assert_gt(ring_st.border_color.r, 0.75)
	assert_gt(ring_st.border_color.g, 0.75)
	assert_gt(ring_st.border_color.b, 0.75)
	assert_true(ring_st.border_color.g > 0.6, "must not be the old red fire ring")
	var ring_sz: float = ui.CHAMBER_SIZE + 10.0
	var expect_pos := Vector2(ui.WHEEL_SIZE, ui.WHEEL_SIZE) * 0.5 + Vector2(0.0, -ui.WHEEL_RADIUS) - Vector2(ring_sz, ring_sz) * 0.5
	assert_almost_eq(fire_ring.position.x, expect_pos.x, 0.6)
	assert_almost_eq(fire_ring.position.y, expect_pos.y, 0.6)
	assert_not_null(ui._fire_ring_shimmer)
	assert_true(ui._fire_ring_shimmer.is_valid())
	assert_eq(ui._chamber_panels.size(), CombatConstants.MAGAZINE_SIZE)
	var center := Vector2(ui.WHEEL_SIZE, ui.WHEEL_SIZE) * 0.5
	for i in ui._chamber_panels.size():
		var panel: Panel = ui._chamber_panels[i]
		var well: Panel = panel.get_node_or_null("Well") as Panel
		assert_not_null(well)
		assert_not_null(panel.get_node_or_null("Info"))
		var local_c: Vector2 = panel.position + panel.size * 0.5
		var dist: float = local_c.distance_to(center)
		assert_almost_eq(dist, ui.WHEEL_RADIUS, 0.6)
		assert_almost_eq(panel.size.x, ui.CHAMBER_SIZE, 0.01)
		assert_almost_eq(well.size.x, 40.0, 0.01)
	# Empty chambers show the dark well and no "empty" label; loaded ones hide the well.
	ui.state.magazine.clear()
	ui.state.magazine.start_index = 0
	ui.state.magazine.set_slot(0, CombatConstants.WHITE_AMMO_ID)
	ui._apply_disk_rotation(0.0)
	ui._paint_mag_chambers()
	var empty_panel: Panel = ui._chamber_panels[1]
	var loaded_panel: Panel = ui._chamber_panels[0]
	assert_true((empty_panel.get_node("Well") as Control).visible)
	assert_eq(str((empty_panel.get_node("Info") as Label).text), "")
	assert_false((loaded_panel.get_node("Well") as Control).visible)
	assert_false(str((loaded_panel.get_node("Info") as Label).text).is_empty())
	var loaded_st := loaded_panel.get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(loaded_st)
	# Slot 0 starts at the fire port, so its rim should also be the pale fire color.
	assert_gt(loaded_st.border_color.g, 0.7)
	# Drag / snap still resolve to the same chamber centers.
	var c0: Vector2 = ui.chamber_visual_center(0)
	assert_ne(c0, Vector2.ZERO)
