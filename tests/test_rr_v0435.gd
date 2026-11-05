extends GutTest
## v0.4.35：燃烧改为篝火式大火焰软斑。

func test_version_is_0_4_35() -> void:
	assert_eq(GameVersion.STRING, "0.4.35")
	assert_true("0.4.35" in FileAccess.get_file_as_string("res://data/changelog.json"))


func test_burn_vfx_is_blob_mass_not_lines() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/combat/burn_vfx.gd")
	assert_false("draw_line" in src, "no thin line streaks")
	assert_true("_make_radial_blob" in src)
	assert_true("_make_teardrop_blob" in src)
	assert_true("烟" in src)
	var fx = load("res://scripts/combat/burn_vfx.gd").new()
	add_child_autofree(fx)
	fx.configure(56, 110, 1.55)
	assert_gt(fx.body_w, 40.0)
	assert_gt(fx.body_h, 100.0)
	fx.set_burn_active(true)
	fx.queue_redraw()
	await get_tree().process_frame
	# 静态软斑纹理应已生成
	assert_not_null(fx._blob_tex)
	assert_not_null(fx._tear_tex)


func test_burn_still_pooled_in_combat_ui() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/combat/combat_ui.gd")
	assert_true("_burn_vfx_pool" in src)
	assert_true("_acquire_burn_vfx" in src)
