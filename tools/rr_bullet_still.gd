extends SceneTree
## 弹道特写：飞行到一半截图并裁剪。OUT=路径
var _ui = null
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var cs_script: GDScript = load("res://scripts/combat/combat_state.gd")
	cs_script.set("boot_sandbox", true)
	change_scene_to_file("res://scenes/combat.tscn")
	for _i in 90:
		await process_frame
		_ui = current_scene
		if _ui != null and _ui.get("state") != null and _ui.state.sandbox_mode:
			break
	await create_timer(0.5).timeout
	if _ui.get("_dev_open") == true:
		_ui._toggle_dev()
	_ui.state.sandbox_clear_enemies()
	_ui._refresh()
	await create_timer(0.2).timeout
	var from_g: Vector2 = _ui._player_shot_origin_global()
	var cols := [1, 16, 26, 24, 22]
	var ys := [0.0, 0.0, 0.0, 0.0, 0.0]
	for i in cols.size():
		var c: Color = _ui._ammo_colors(cols[i]).get("bg", Color.WHITE)
		var f: Vector2 = from_g + Vector2(0, -40 + i * 22)
		var to: Vector2 = f + Vector2(600, 0)
		var outl: Array[Color] = []
		if i == 1:
			outl.append(_ui._ammo_colors(16).get("bg", Color.RED))
		if _ui._animate_shot_projectile.get_argument_count() >= 7:
			_ui._animate_shot_projectile(f, to, c, outl, [], 2.0, i == 4)
		else:
			_ui._animate_shot_projectile(f, to, c, outl, [], 2.0)
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	var cx: int = int(from_g.x + 300)
	var rect := Rect2i(maxi(cx - 260, 0), int(from_g.y) - 70, 360, 130)
	var crop: Image = img.get_region(rect)
	crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_NEAREST)
	crop.save_png(OS.get_environment("OUT"))
	print("BULLET_STILL ", OS.get_environment("OUT"))
	quit(0)
