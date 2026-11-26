extends SceneTree
## v0.4.90 native 720x1280 stills: small icons ×N only; large flame unchanged.
##   godot --path . --resolution 720x1280 --quit-after 800 -s res://tools/rr_v0490_icon_stills.gd
const OUT := "/workspace/rr-v0490-verification"
const SHOTS := "res://docs/shots"

func _initialize() -> void:
	call_deferred("_run")

func _stamp(name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	var docs := ProjectSettings.globalize_path("%s/%s.png" % [SHOTS, name])
	DirAccess.make_dir_recursive_absolute(OUT)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	img.save_png("%s/%s.png" % [OUT, name])
	img.save_png(docs)
	print("saved ", name, " ", img.get_width(), "x", img.get_height())

func _run() -> void:
	var cs_script: GDScript = load("res://scripts/combat/combat_state.gd")
	cs_script.set("boot_sandbox", true)
	cs_script.set("boot_campaign", false)
	if change_scene_to_file("res://scenes/combat.tscn") != OK:
		push_error("scene")
		quit(1)
		return
	var ui = null
	for _i in 180:
		await process_frame
		ui = current_scene
		if ui != null and ui.get("state") != null and ui.state.sandbox_mode:
			break
	if ui == null or ui.state == null:
		push_error("no ui")
		quit(1)
		return
	DisplayServer.window_set_size(Vector2i(720, 1280))
	if ui.has_method("_fit_combat_viewport"):
		ui._fit_combat_viewport(Vector2(720, 1280))
	ui.state.spawn_paused = true
	ui.state.auto_enemy_advance = false
	if ui.get("_dev_open") == true:
		ui._toggle_dev()
	var FR: GDScript = load("res://scripts/combat/fire_resolver.gd")
	var a: Dictionary = FR.make_flame(52, 0, 3, 1.0)
	var b: Dictionary = FR.make_flame(52, 1, 2, 1.0)
	var c: Dictionary = FR.make_flame(41, 2, 1, 1.0)
	var d: Dictionary = FR.make_flame(40, 3, 4, 1.0)
	print("flames kinds=", [a.get("effect_kind"), b.get("effect_kind"), c.get("effect_kind"), d.get("effect_kind")],
		" names=", [a.get("name"), c.get("name"), d.get("name")],
		" remaining=", [a.get("remaining"), b.get("remaining"), c.get("remaining"), d.get("remaining")])
	ui.state._volley_muzzle_buffs = [a, b, c, d]
	if ui._muzzle_status_hud != null:
		ui._muzzle_status_hud._process(0.0)
	ui._refresh()
	for _j in 12:
		await process_frame
	var icons: Array = []
	if ui._muzzle_status_hud != null:
		for ic in ui._muzzle_status_hud._icons:
			icons.append([ic.stack_count, ic.count_text()])
	print("ICONS_MIXED ", icons, " flame_visible=", ui._muzzle_status_hud._flame.visible,
		" envelope=", ui._muzzle_status_hud._flame.envelope)
	await _stamp("rr_v0490_icons_stacked")

	ui.state._volley_muzzle_buffs = FR.consume_flame_layers(ui.state._volley_muzzle_buffs, 3.0)
	if ui._muzzle_status_hud != null:
		ui._muzzle_status_hud._process(0.0)
	ui._refresh()
	for _k in 8:
		await process_frame
	icons.clear()
	if ui._muzzle_status_hud != null:
		for ic in ui._muzzle_status_hud._icons:
			icons.append([ic.stack_count, ic.count_text()])
	print("ICONS_CONSUMED ", icons)
	await _stamp("rr_v0490_icons_consumed")
	quit(0)
