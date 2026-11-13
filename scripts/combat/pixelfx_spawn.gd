extends RefCounted
## 所有 pixelfx 生成走这里：加载时预烘 4 个 seed 变体（Web 必须 BAKED），
## 播放时再叠加节点级随机（翻转/旋转/缩放/速度/色相亮度/位移），不触发新的烘焙。

const SCALE := 1.75
const MUZZLE_ID := "projectiles/muzzle-pistol"
const HIT_SCRIPT := preload("res://scripts/effects/pixelfx_blood_hit.gd")
const MUZZLE_HEIGHT := 26.0
const HIT_HEIGHT := 24.0
const Z_SHOT_VFX := 42
const VARIANT_SEEDS: Array[int] = [3, 11, 19, 29]
const SCALE_JITTER := 0.15
const SPEED_JITTER := 0.15
const POS_JITTER := 3.0
const ROT_MUZZLE := 0.10
const ROT_HIT := 0.40
const HUE_JITTER := 0.035
const BRIGHT_JITTER := 0.10

static var _rng: RandomNumberGenerator


static func rng() -> RandomNumberGenerator:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	return _rng


static func prewarm() -> void:
	if not ResourceLoader.exists("res://addons/pixelfx/nodes/pixel_fx_2d.gd"):
		return
	for s in VARIANT_SEEDS:
		var opts := {"seed": float(s)}
		PixelFx2D.prebake(MUZZLE_ID, opts)
		PixelFx2D.prebake(HIT_SCRIPT, opts)


static func play_muzzle(host: Node, world_pos: Vector2) -> Node:
	return play(host, "muzzle", world_pos, MUZZLE_HEIGHT)


static func play_hit(host: Node, world_pos: Vector2) -> Node:
	return play(host, "hit", world_pos, HIT_HEIGHT)


static func play(host: Node, kind: String, world_pos: Vector2, lift_px: float) -> Node:
	if host == null or world_pos == Vector2.ZERO:
		return null
	if not ResourceLoader.exists("res://addons/pixelfx/nodes/pixel_fx_2d.gd"):
		return null
	if kind == "muzzle" and not ResourceLoader.exists("res://addons/pixelfx/fx/%s.gd" % MUZZLE_ID):
		return null
	var r := rng()
	var fx := PixelFx2D.new()
	fx.mode = PixelFx2D.Mode.BAKED
	fx.free_when_done = true
	fx.autoplay = true
	fx.z_index = Z_SHOT_VFX
	fx.seed = VARIANT_SEEDS[r.randi_range(0, VARIANT_SEEDS.size() - 1)]
	if kind == "hit":
		fx.effect_script = HIT_SCRIPT
	else:
		fx.effect = MUZZLE_ID
	var sc: float = SCALE * r.randf_range(1.0 - SCALE_JITTER, 1.0 + SCALE_JITTER)
	# 枪口焰朝右，不水平翻转；命中血雾可以翻
	var flip_x: float = -1.0 if kind == "hit" and r.randf() < 0.5 else 1.0
	fx.scale = Vector2(sc * flip_x, sc)
	fx.speed_scale = r.randf_range(1.0 - SPEED_JITTER, 1.0 + SPEED_JITTER)
	var rot: float = ROT_HIT if kind == "hit" else ROT_MUZZLE
	fx.rotation = r.randf_range(-rot, rot)
	fx.modulate = _jitter_modulate(r, kind)
	host.add_child(fx)
	var offset := Vector2(r.randf_range(-POS_JITTER, POS_JITTER), r.randf_range(-POS_JITTER, POS_JITTER))
	fx.global_position = world_pos + Vector2(0.0, lift_px * SCALE) + offset
	return fx


static func is_hit_fx(fx: Node) -> bool:
	if fx == null or not (fx is PixelFx2D):
		return false
	var script: Script = (fx as PixelFx2D).effect_script
	return script != null and str(script.resource_path).ends_with("pixelfx_blood_hit.gd")


static func is_muzzle_fx(fx: Node) -> bool:
	return fx is PixelFx2D and (fx as PixelFx2D).effect == MUZZLE_ID


static func _jitter_modulate(r: RandomNumberGenerator, kind: String) -> Color:
	var hue: float = r.randf_range(-HUE_JITTER, HUE_JITTER)
	var val: float = r.randf_range(-BRIGHT_JITTER, BRIGHT_JITTER)
	# 命中偏血红，只做轻微明暗/冷暖抖动，避免漂成别的色相
	if kind == "hit":
		hue *= 0.35
	var c := Color(1, 1, 1, 1)
	var h := c.h + hue
	if h < 0.0:
		h += 1.0
	elif h > 1.0:
		h -= 1.0
	return Color.from_hsv(h, clampf(c.s, 0.0, 1.0), clampf(c.v + val, 0.7, 1.15), 1.0)
