class_name SkeletonEnemy
extends Node2D
## 纯表现：把棋盘怪画成 Q 版小动物（Skeleton2D）。玩法数值不动。
## 动画：idle / walk（循环）/ attack / hurt / death。
## 用法：setup(def_id) 建外形；set_moving / play_attack / play_hurt / play_death；set_hp。

const ANIM_IDLE := &"idle"
const ANIM_WALK := &"walk"
const ANIM_ATTACK := &"attack"
const ANIM_HURT := &"hurt"
const ANIM_DEATH := &"death"
const ANIM_RESET := &"RESET"

## def_id → 物种
const SPECIES := {
	1: "rabbit",       ## 平民
	2: "raccoon",      ## 强盗
	3: "bear",         ## 熊
	4: "bat",          ## 僵尸
	5: "pig",          ## 超级僵尸（Boss）
	900: "dummy",      ## 木桩
}

var species: String = "rabbit"
var is_boss: bool = false
var is_dummy: bool = false
var is_dead: bool = false
var moving: bool = false

var rig: Node2D
var skeleton: Skeleton2D
var anim: AnimationPlayer
var bones: Dictionary = {}
var status_anchor: Marker2D
var head_anchor: Marker2D
var _hp_label: Label
var _hp_fill: ColorRect
var _hp_box: Node2D
var _flash_mod: Color = Color(1, 1, 1, 1)
var _eye_open: Node2D
var _eye_x: Node2D
var _scale_mul: float = 1.0
## v0.4.26 朝向：-1 = 面朝左（玩家方向，敌人默认行进方向）；+1 = 面朝右。
## 画法原生朝右（口鼻/高光在 +x），所以朝左 = Rig.scale.x 取反；整体 scale（Boss×1.55 / 熊×1.25）不动。
var facing: int = -1
var _walk_rate: float = 1.0

## 配色（按物种填）
var col_fur: Color
var col_fur2: Color
var col_belly: Color
var col_outline: Color
var col_accent: Color
var col_eye: Color = Color(0.08, 0.09, 0.12)

## 静止姿态：短腿大头
const REST := {
	"Hip": [Vector2(0, -22), 0.0],
	"Torso": [Vector2(0, -1), 0.0],
	"Head": [Vector2(0, -16), 0.0],
	"UpperArmF": [Vector2(5, -12), 0.55],
	"ForearmF": [Vector2(7, 0), 0.4],
	"HandF": [Vector2(6, 0), 0.0],
	"UpperArmB": [Vector2(-4, -12), 2.4],
	"ForearmB": [Vector2(7, 0), -0.5],
	"HandB": [Vector2(5, 0), 0.0],
	"ThighF": [Vector2(4, 0), -0.1],
	"ShinF": [Vector2(0, 10), 0.1],
	"ThighB": [Vector2(-3, 0), 0.12],
	"ShinB": [Vector2(0, 10), -0.08],
	"Tail1": [Vector2(-6, -1), -2.4],
	"Tail2": [Vector2(7, 0), 0.4],
	"WingF": [Vector2(4, -14), -0.4],
	"WingB": [Vector2(-3, -14), -2.6],
}


func _init() -> void:
	name = "SkeletonEnemy"


func setup(def_id: int) -> void:
	species = str(SPECIES.get(def_id, "rabbit"))
	is_boss = def_id == CombatConstants.SUPER_ZOMBIE_ENEMY_ID
	is_dummy = def_id == CombatConstants.DUMMY_ENEMY_ID or species == "dummy"
	_apply_palette()
	_scale_mul = 1.55 if is_boss else (1.25 if species == "bear" else (1.05 if species == "dummy" else 1.0))
	scale = Vector2(_scale_mul, _scale_mul)
	_build_rig()
	set_facing(-1)
	_build_hp_badge()
	_build_animations()
	if anim:
		anim.play(ANIM_IDLE)


func _ready() -> void:
	if anim and anim.current_animation == "":
		anim.play(ANIM_IDLE)


# ---------------------------------------------------------------- 外部接口

func set_facing(dir: int) -> void:
	## 面向 dir（<0 左 / >0 右）。只翻 Rig，不碰根节点 scale，也不翻血条文字。
	if is_dummy:
		dir = -1
	var d: int = -1 if dir < 0 else 1
	facing = d
	if rig != null:
		rig.scale = Vector2(float(d), 1.0)


func set_walk_rate(rate: float) -> void:
	## 走路动画播放倍率（跟滑行速度同比，脚不打滑）。
	_walk_rate = maxf(rate, 0.05)
	_apply_anim_rate()


func _apply_anim_rate() -> void:
	if anim == null:
		return
	anim.speed_scale = _walk_rate if anim.current_animation == ANIM_WALK else 1.0


func set_moving(on: bool) -> void:
	if is_dead or is_dummy:
		return
	if moving == on:
		return
	moving = on
	if anim.current_animation in [ANIM_ATTACK, ANIM_HURT, ANIM_DEATH]:
		return
	anim.play(ANIM_WALK if on else ANIM_IDLE, 0.08)
	_apply_anim_rate()


func play_attack() -> void:
	if is_dead or is_dummy:
		return
	set_facing(-1)  # 攻击时面向玩家
	anim.play(ANIM_ATTACK, 0.04)
	_apply_anim_rate()


func play_hurt() -> void:
	if is_dead:
		return
	if anim.current_animation == ANIM_HURT:
		anim.seek(0.0, true)
	else:
		anim.play(ANIM_HURT, 0.02)
	_apply_anim_rate()


func play_death() -> void:
	if is_dead:
		return
	is_dead = true
	moving = false
	anim.play(ANIM_DEATH, 0.05)
	_apply_anim_rate()


func set_hp(hp: int, max_hp: int) -> void:
	if _hp_label == null:
		return
	_hp_label.text = str(maxi(hp, 0))
	var r := clampf(float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0)
	_hp_fill.size.x = 30.0 * r
	_hp_fill.color = Color(0.95, 0.35, 0.3) if r > 0.35 else Color(0.95, 0.55, 0.2)


func current_animation() -> StringName:
	return StringName(anim.current_animation) if anim else &""


func status_anchor_global_position() -> Vector2:
	return status_anchor.global_position if status_anchor else global_position


# ---------------------------------------------------------------- 配色

func _apply_palette() -> void:
	match species:
		"rabbit":
			col_fur = Color(0.96, 0.92, 0.88)
			col_fur2 = Color(0.88, 0.78, 0.72)
			col_belly = Color(1.0, 0.98, 0.95)
			col_outline = Color(0.45, 0.32, 0.28)
			col_accent = Color(1.0, 0.7, 0.75)  # 耳内
		"raccoon":
			col_fur = Color(0.55, 0.5, 0.48)
			col_fur2 = Color(0.35, 0.32, 0.3)
			col_belly = Color(0.85, 0.82, 0.78)
			col_outline = Color(0.18, 0.15, 0.14)
			col_accent = Color(0.12, 0.1, 0.1)  # 面罩
		"bear":
			col_fur = Color(0.55, 0.38, 0.22)
			col_fur2 = Color(0.4, 0.26, 0.14)
			col_belly = Color(0.85, 0.7, 0.5)
			col_outline = Color(0.22, 0.12, 0.06)
			col_accent = Color(0.9, 0.55, 0.35)
		"bat":
			col_fur = Color(0.42, 0.48, 0.38)  # 病绿灰
			col_fur2 = Color(0.28, 0.32, 0.26)
			col_belly = Color(0.55, 0.6, 0.48)
			col_outline = Color(0.14, 0.16, 0.12)
			col_accent = Color(0.7, 0.35, 0.45)  # 翼膜
		"pig":
			col_fur = Color(0.95, 0.62, 0.7)
			col_fur2 = Color(0.78, 0.42, 0.5)
			col_belly = Color(1.0, 0.82, 0.85)
			col_outline = Color(0.4, 0.18, 0.22)
			col_accent = Color(0.85, 0.35, 0.4)  # 鼻头
		_:
			col_fur = Color(0.82, 0.7, 0.5)
			col_fur2 = Color(0.55, 0.4, 0.25)
			col_belly = Color(0.95, 0.88, 0.75)
			col_outline = Color(0.35, 0.22, 0.12)
			col_accent = Color(0.7, 0.45, 0.25)


# ---------------------------------------------------------------- 死亡碎块（v0.4.27）

func gore_pieces() -> Array:
	## 死亡飙血瞬间飞出去的「肢体」：按物种配色的耳朵/爪子/腿/尾巴/半个脑袋 + 两块肉。
	## 每块 = {"layers": [[pts, col], ...]}，外描边在前、填充在后；以原点为中心，已乘体型倍率。
	var out: Array = []
	var ol: Color = col_outline
	var meat := Color(0.86, 0.2, 0.24)
	var meat_ol := Color(0.45, 0.06, 0.1)
	if is_dummy:
		var wood := Color(0.78, 0.6, 0.38)
		var wood_ol := Color(0.38, 0.24, 0.12)
		for sz in [Vector2(9, 4), Vector2(7, 3.5), Vector2(10, 3), Vector2(6, 5)]:
			out.append(_gore([[_rect(-sz, sz), wood_ol], [_rect(-sz + Vector2(1, 1), sz - Vector2(1, 1)), wood]]))
		var straw := Color(0.95, 0.85, 0.45)
		for _i in 3:
			out.append(_gore([[_rect(Vector2(-6, -1), Vector2(6, 1)), straw]]))
		for pc in out:
			pc["trail"] = Color(0.86, 0.72, 0.46, 0.9)  # 木屑
		return out
	# 耳朵 ×2
	for _i in 2:
		match species:
			"rabbit":
				var ear := PackedVector2Array([Vector2(-4, 9), Vector2(0, -11), Vector2(4, 9)])
				var cen := Vector2(0, 2.3)
				var inner := PackedVector2Array()
				for v in ear:
					inner.append(cen + (v - cen) * 0.5)
				out.append(_gore([[_grow(ear, 1.1), ol], [ear, col_fur], [inner, col_accent]]))
			"bat":
				var ear2 := PackedVector2Array([Vector2(-4, 6), Vector2(0, -8), Vector2(4, 6)])
				out.append(_gore([[_grow(ear2, 1.0), ol], [ear2, col_fur]]))
			"pig":
				var ear3 := PackedVector2Array([Vector2(-5, 4), Vector2(-2, -6), Vector2(5, 2)])
				out.append(_gore([[_grow(ear3, 1.0), ol], [ear3, col_fur]]))
			"bear":
				out.append(_gore([[_circle(Vector2.ZERO, 5.0), ol], [_circle(Vector2.ZERO, 4.0), col_fur], [_circle(Vector2.ZERO, 2.0), col_accent]]))
			_:
				out.append(_gore([[_circle(Vector2.ZERO, 4.2), ol], [_circle(Vector2.ZERO, 3.2), col_fur]]))
	# 爪子 ×2
	for _i in 2:
		out.append(_gore([[_ellipse(Vector2.ZERO, 5.0, 3.0), ol], [_ellipse(Vector2.ZERO, 4.0, 2.2), col_belly]]))
	# 一条小腿
	out.append(_gore([[_capsule(Vector2(0, -5), Vector2(0, 5), 3.8), ol], [_capsule(Vector2(0, -5), Vector2(0, 5), 2.8), col_fur]]))
	# 尾巴 / 翅膀
	match species:
		"rabbit":
			out.append(_gore([[_circle(Vector2.ZERO, 5.5), ol], [_circle(Vector2.ZERO, 4.5), col_belly]]))
		"raccoon":
			out.append(_gore([
				[_capsule(Vector2(-7, 0), Vector2(7, 0), 3.2), ol],
				[_capsule(Vector2(-7, 0), Vector2(7, 0), 2.4), col_fur],
				[_rect(Vector2(-3, -2.4), Vector2(-1, 2.4)), col_fur2],
				[_rect(Vector2(2, -2.4), Vector2(4, 2.4)), col_fur2]]))
		"bat":
			var wing := PackedVector2Array([Vector2(-9, -3), Vector2(7, -9), Vector2(9, -1), Vector2(1, 3), Vector2(-9, 1)])
			out.append(_gore([[_grow(wing, 1.0), ol], [wing, col_accent]]))
		"pig":
			out.append(_gore([[_circle(Vector2.ZERO, 3.5), ol], [_circle(Vector2.ZERO, 2.5), col_fur]]))
		_:
			out.append(_gore([[_circle(Vector2.ZERO, 4.0), ol], [_circle(Vector2.ZERO, 3.0), col_fur]]))
	# 半个脑袋（带一只 X 眼）
	var half := PackedVector2Array()
	for k in 9:
		var a: float = PI + PI * float(k) / 8.0
		half.append(Vector2(cos(a) * 9.0, sin(a) * 8.0 + 2.0))
	var half_in := PackedVector2Array()
	for v in half:
		half_in.append(v * 0.86 + Vector2(0, 0.3))
	out.append(_gore([[half, ol], [half_in, col_fur], [_rect(Vector2(-4, -3), Vector2(-1, -2)), col_eye], [_rect(Vector2(-3, -4.5), Vector2(-2, -0.5)), col_eye]]))
	# 肉块 ×2（卡通粉红，不写实）
	for r in [4.0, 3.2]:
		var blob := _ellipse(Vector2.ZERO, r * 1.25, r, 10)
		out.append(_gore([[_grow(blob, 1.0), meat_ol], [blob, meat], [_circle(Vector2(-r * 0.3, -r * 0.3), r * 0.3, 6), Color(1, 0.6, 0.62)]]))
	return out


func _gore(layers: Array) -> Dictionary:
	var scaled: Array = []
	for L in layers:
		var pts: PackedVector2Array = L[0]
		var sp := PackedVector2Array()
		for v in pts:
			sp.append(v * _scale_mul)
		scaled.append([sp, L[1]])
	return {"layers": scaled}


# ---------------------------------------------------------------- 搭骨架

func _build_rig() -> void:
	rig = Node2D.new()
	rig.name = "Rig"
	rig.z_index = 1
	add_child(rig)
	skeleton = Skeleton2D.new()
	skeleton.name = "Skeleton"
	rig.add_child(skeleton)

	var hip := _bone("Hip", skeleton, 6)
	var torso := _bone("Torso", hip, 16)
	var head := _bone("Head", torso, 28)
	var ua_f := _bone("UpperArmF", torso, 7)
	var fa_f := _bone("ForearmF", ua_f, 6)
	var hand_f := _bone("HandF", fa_f, 4)
	var ua_b := _bone("UpperArmB", torso, 7)
	var fa_b := _bone("ForearmB", ua_b, 6)
	var hand_b := _bone("HandB", fa_b, 4)
	var th_f := _bone("ThighF", hip, 10)
	var sh_f := _bone("ShinF", th_f, 10)
	var th_b := _bone("ThighB", hip, 10)
	var sh_b := _bone("ShinB", th_b, 10)
	var t1 := _bone("Tail1", hip, 7)
	var t2 := _bone("Tail2", t1, 6)
	var wing_f := _bone("WingF", torso, 14)
	var wing_b := _bone("WingB", torso, 14)

	if species == "dummy":
		_build_dummy_parts(hip, torso, head)
	else:
		_build_tail(t1, t2)
		if species == "bat":
			_build_wings(wing_f, wing_b)
		_build_limbs(ua_b, fa_b, hand_b, th_b, sh_b, false)
		_build_limbs(ua_f, fa_f, hand_f, th_f, sh_f, true)
		_build_body(torso)
		_build_head(head)
	# 非蝙蝠隐藏翅膀骨上的可见部件（骨仍在，方便动画轨统一）
	if species != "bat":
		wing_f.visible = false
		wing_b.visible = false
	if species == "bat":
		# 蝙蝠走路用翅膀，手臂藏一点
		ua_f.modulate.a = 0.0
		ua_b.modulate.a = 0.0
		fa_f.modulate.a = 0.0
		fa_b.modulate.a = 0.0
		hand_f.modulate.a = 0.0
		hand_b.modulate.a = 0.0

	head_anchor = Marker2D.new()
	head_anchor.name = "HeadAnchor"
	head_anchor.position = Vector2(0, -34)
	head.add_child(head_anchor)


func _build_dummy_parts(hip: Bone2D, torso: Bone2D, head: Bone2D) -> void:
	## 木桩：短木柱 + 布偶熊头（不走路不攻击，只有 idle 微晃 / hurt / death）
	_part(hip, _rect(Vector2(-7, -2), Vector2(7, 20)), col_outline, 1)
	_part(hip, _rect(Vector2(-6, -1), Vector2(6, 19)), Color(0.55, 0.38, 0.2), 1)
	_part(hip, _rect(Vector2(-6, 4), Vector2(6, 6)), Color(0.4, 0.25, 0.12), 1)
	_part(hip, _rect(Vector2(-6, 12), Vector2(6, 14)), Color(0.4, 0.25, 0.12), 1)
	_part(torso, _ellipse(Vector2(0, -8), 11, 10), col_outline, 2)
	_part(torso, _ellipse(Vector2(0, -8), 9.5, 8.5), col_fur, 2)
	_part(torso, _ellipse(Vector2(1, -6), 5, 5), col_belly, 2)
	# 钮扣
	_part(torso, _circle(Vector2(0, -10), 1.2), col_outline, 2)
	_part(torso, _circle(Vector2(0, -5), 1.2), col_outline, 2)
	_part(head, _ellipse(Vector2(0, -12), 13, 12), col_outline, 2)
	_part(head, _ellipse(Vector2(0, -12), 11.5, 10.5), col_fur, 2)
	# 圆耳
	_part(head, _circle(Vector2(-9, -22), 4.5), col_outline, 2)
	_part(head, _circle(Vector2(-9, -22), 3.5), col_fur, 2)
	_part(head, _circle(Vector2(9, -22), 4.5), col_outline, 2)
	_part(head, _circle(Vector2(9, -22), 3.5), col_fur, 2)
	_part(head, _circle(Vector2(-9, -22), 1.8), col_accent, 2)
	_part(head, _circle(Vector2(9, -22), 1.8), col_accent, 2)
	_build_face(head, Vector2(0, -12), false)


func _build_tail(t1: Bone2D, t2: Bone2D) -> void:
	match species:
		"rabbit":
			_part(t1, _circle(Vector2(3, 0), 5.5), col_outline, -1)
			_part(t1, _circle(Vector2(3, 0), 4.5), col_belly, -1)
			t2.visible = false
		"raccoon":
			_part(t1, _capsule(Vector2.ZERO, Vector2(7, 0), 3.2), col_outline, -1)
			_part(t1, _capsule(Vector2.ZERO, Vector2(7, 0), 2.4), col_fur, -1)
			_part(t2, _capsule(Vector2.ZERO, Vector2(6, 0), 3.0), col_outline, -1)
			_part(t2, _capsule(Vector2.ZERO, Vector2(6, 0), 2.2), col_fur2, -1)
			_part(t2, _rect(Vector2(1, -2.2), Vector2(3, 2.2)), col_belly, -1)
		"bear":
			_part(t1, _circle(Vector2(2, 0), 4.0), col_outline, -1)
			_part(t1, _circle(Vector2(2, 0), 3.0), col_fur, -1)
			t2.visible = false
		"bat":
			_part(t1, _capsule(Vector2.ZERO, Vector2(5, 0), 2.0), col_outline, -1)
			_part(t1, _capsule(Vector2.ZERO, Vector2(5, 0), 1.4), col_fur2, -1)
			t2.visible = false
		"pig":
			_part(t1, _circle(Vector2(2, 0), 3.5), col_outline, -1)
			_part(t1, _circle(Vector2(2, 0), 2.5), col_fur, -1)
			t2.visible = false


func _build_wings(wf: Bone2D, wb: Bone2D) -> void:
	var wing := PackedVector2Array([Vector2(0, 0), Vector2(16, -6), Vector2(18, 2), Vector2(10, 6), Vector2(0, 4)])
	_part(wb, _grow(wing, 1.0), col_outline, 0)
	_part(wb, wing, col_accent.darkened(0.25), 0)
	_part(wf, _grow(wing, 1.0), col_outline, 3)
	_part(wf, wing, col_accent, 3)


func _build_limbs(ua: Bone2D, fa: Bone2D, hand: Bone2D, th: Bone2D, sh: Bone2D, front: bool) -> void:
	var z: int = 3 if front else 0
	var fur: Color = col_fur if front else col_fur2
	_part(ua, _capsule(Vector2.ZERO, Vector2(7, 0), 3.6), col_outline, z)
	_part(ua, _capsule(Vector2.ZERO, Vector2(7, 0), 2.7), fur, z)
	_part(fa, _capsule(Vector2.ZERO, Vector2(6, 0), 3.4), col_outline, z)
	_part(fa, _capsule(Vector2.ZERO, Vector2(6, 0), 2.5), fur, z)
	_part(hand, _circle(Vector2(1, 0), 3.4), col_outline, z)
	_part(hand, _circle(Vector2(1, 0), 2.6), col_belly if front else col_belly.darkened(0.1), z)
	_part(th, _capsule(Vector2.ZERO, Vector2(0, 10), 4.2), col_outline, z)
	_part(th, _capsule(Vector2.ZERO, Vector2(0, 10), 3.2), fur, z)
	_part(sh, _capsule(Vector2.ZERO, Vector2(0, 9), 3.8), col_outline, z)
	_part(sh, _capsule(Vector2.ZERO, Vector2(0, 9), 2.8), fur, z)
	_part(sh, _ellipse(Vector2(1.5, 9), 5.0, 3.0), col_outline, z)
	_part(sh, _ellipse(Vector2(1.5, 9), 4.0, 2.2), col_belly if front else col_belly.darkened(0.1), z)


func _build_body(torso: Bone2D) -> void:
	var body: PackedVector2Array
	if is_boss or species == "bear" or species == "pig":
		body = PackedVector2Array([
			Vector2(-10, 3), Vector2(-12, -4), Vector2(-10, -14), Vector2(-5, -18),
			Vector2(5, -18), Vector2(10, -14), Vector2(12, -4), Vector2(10, 3), Vector2(0, 5)])
	else:
		body = PackedVector2Array([
			Vector2(-8, 2), Vector2(-9.5, -4), Vector2(-8, -13), Vector2(-5, -17),
			Vector2(5, -17), Vector2(8, -13), Vector2(9.5, -4), Vector2(8, 2), Vector2(0, 4)])
	_part(torso, _grow(body, 1.1), col_outline, 2)
	_part(torso, body, col_fur, 2)
	_part(torso, _ellipse(Vector2(2, -5), 5.0, 6.0), col_belly, 2)
	if species == "raccoon":
		_part(torso, _rect(Vector2(-9, -10), Vector2(-6, -8)), col_fur2, 2)
		_part(torso, _rect(Vector2(-9.5, -5), Vector2(-6.5, -3)), col_fur2, 2)
	if species == "pig" and is_boss:
		# Boss 小刺/伤疤，显得凶一点但仍可爱
		_part(torso, PackedVector2Array([Vector2(-2, -17), Vector2(0, -21), Vector2(2, -17)]), col_outline, 2)
		_part(torso, _rect(Vector2(4, -8), Vector2(8, -7)), Color(0.55, 0.2, 0.25, 0.7), 2)


func _build_head(head: Bone2D) -> void:
	var hc := Vector2(0, -12)
	match species:
		"rabbit":
			# 长耳
			for ear in [
				[Vector2(-8, -18), Vector2(-11, -38), Vector2(-2, -22)],
				[Vector2(2, -22), Vector2(11, -38), Vector2(8, -18)]]:
				var e := PackedVector2Array(ear)
				_part(head, _grow(e, 1.1), col_outline, 2)
				_part(head, e, col_fur, 2)
				var cen: Vector2 = (ear[0] + ear[1] + ear[2]) / 3.0
				var inner := PackedVector2Array()
				for v in ear:
					inner.append(cen + (v - cen) * 0.5)
				_part(head, inner, col_accent, 2)
			_part(head, _ellipse(hc, 13.5, 12.5), col_outline, 2)
			_part(head, _ellipse(hc, 12.2, 11.2), col_fur, 2)
		"raccoon":
			_part(head, _ellipse(hc, 13.5, 12.0), col_outline, 2)
			_part(head, _ellipse(hc, 12.2, 10.8), col_fur, 2)
			# 圆耳
			_part(head, _circle(Vector2(-10, -22), 4.2), col_outline, 2)
			_part(head, _circle(Vector2(-10, -22), 3.2), col_fur, 2)
			_part(head, _circle(Vector2(10, -22), 4.2), col_outline, 2)
			_part(head, _circle(Vector2(10, -22), 3.2), col_fur, 2)
			# 强盗面罩
			_part(head, PackedVector2Array([
				Vector2(-12, -16), Vector2(12, -16), Vector2(11, -8), Vector2(-11, -8)]), col_accent, 2)
		"bear":
			_part(head, _ellipse(hc, 14.5, 13.0), col_outline, 2)
			_part(head, _ellipse(hc, 13.2, 11.8), col_fur, 2)
			_part(head, _circle(Vector2(-10, -22), 5.0), col_outline, 2)
			_part(head, _circle(Vector2(-10, -22), 4.0), col_fur, 2)
			_part(head, _circle(Vector2(10, -22), 5.0), col_outline, 2)
			_part(head, _circle(Vector2(10, -22), 4.0), col_fur, 2)
			_part(head, _circle(Vector2(-10, -22), 2.0), col_accent, 2)
			_part(head, _circle(Vector2(10, -22), 2.0), col_accent, 2)
			_part(head, _ellipse(Vector2(5, -8), 5.5, 4.0), col_belly, 2)  # 口鼻
		"bat":
			# 尖耳
			for ear in [
				[Vector2(-9, -18), Vector2(-7, -32), Vector2(-1, -20)],
				[Vector2(1, -20), Vector2(7, -32), Vector2(9, -18)]]:
				var e2 := PackedVector2Array(ear)
				_part(head, _grow(e2, 1.0), col_outline, 2)
				_part(head, e2, col_fur, 2)
			_part(head, _ellipse(hc, 12.5, 11.5), col_outline, 2)
			_part(head, _ellipse(hc, 11.2, 10.2), col_fur, 2)
		"pig":
			_part(head, _ellipse(hc, 14.0, 12.5), col_outline, 2)
			_part(head, _ellipse(hc, 12.7, 11.2), col_fur, 2)
			# 三角小耳
			_part(head, PackedVector2Array([Vector2(-11, -18), Vector2(-14, -28), Vector2(-4, -22)]), col_outline, 2)
			_part(head, PackedVector2Array([Vector2(-10.5, -19), Vector2(-12.5, -26), Vector2(-5, -22)]), col_fur, 2)
			_part(head, PackedVector2Array([Vector2(4, -22), Vector2(14, -28), Vector2(11, -18)]), col_outline, 2)
			_part(head, PackedVector2Array([Vector2(5, -22), Vector2(12.5, -26), Vector2(10.5, -19)]), col_fur, 2)
			# 猪鼻子
			_part(head, _ellipse(Vector2(6, -8), 5.5, 4.0), col_outline, 3)
			_part(head, _ellipse(Vector2(6, -8), 4.5, 3.2), col_accent, 3)
			_part(head, _circle(Vector2(4.5, -8), 1.0), col_outline, 3)
			_part(head, _circle(Vector2(7.5, -8), 1.0), col_outline, 3)
		_:
			_part(head, _ellipse(hc, 13, 12), col_outline, 2)
			_part(head, _ellipse(hc, 11.5, 10.5), col_fur, 2)
	_build_face(head, hc, species == "raccoon")


func _build_face(head: Bone2D, hc: Vector2, masked: bool) -> void:
	_eye_open = Node2D.new()
	_eye_open.name = "Eyes"
	_eye_open.position = hc + Vector2(0, -1)
	_eye_open.z_index = 3
	head.add_child(_eye_open)
	var eye_col := Color(1, 1, 1) if masked else col_eye
	var pupil := col_eye if masked else Color(1, 1, 1)
	for ex in [-4.5, 5.0]:
		if masked:
			_part(_eye_open, _ellipse(Vector2(ex, 0), 3.2, 3.6), Color(1, 1, 1), 0)
			_part(_eye_open, _circle(Vector2(ex, 0.3), 1.8), col_eye, 0)
			_part(_eye_open, _circle(Vector2(ex + 0.7, -0.8), 0.7), Color(1, 1, 1), 0)
		else:
			_part(_eye_open, _ellipse(Vector2(ex, 0), 3.0, 3.6), col_eye, 0)
			_part(_eye_open, _circle(Vector2(ex + 0.9, -1.2), 1.1), Color(1, 1, 1), 0)
	_eye_x = Node2D.new()
	_eye_x.name = "XEyes"
	_eye_x.position = hc + Vector2(0, -1)
	_eye_x.z_index = 3
	_eye_x.visible = false
	head.add_child(_eye_x)
	for xe in [[-4.5, 1.0], [5.0, -1.0]]:
		var ex: float = xe[0]
		var d: float = xe[1]
		_part(_eye_x, _capsule(Vector2(ex - 2.2 * d, -2.2), Vector2(ex + 2.0 * d, 0), 0.8, 3), col_eye, 0)
		_part(_eye_x, _capsule(Vector2(ex + 2.0 * d, 0), Vector2(ex - 2.2 * d, 2.2), 0.8, 3), col_eye, 0)
	if species != "pig":
		_part(head, _ellipse(hc + Vector2(5, 3), 4.5, 3.0), col_belly, 2)
		_part(head, PackedVector2Array([
			hc + Vector2(5, 1), hc + Vector2(7.5, 1), hc + Vector2(6.2, 2.6)]), Color(0.95, 0.5, 0.55), 3)
	# 腮红
	_part(head, _ellipse(hc + Vector2(-6, 3), 2.2, 1.4), Color(1.0, 0.55, 0.6, 0.45), 2)
	_part(head, _ellipse(hc + Vector2(9, 2), 1.6, 1.2), Color(1.0, 0.55, 0.6, 0.45), 2)


func _build_hp_badge() -> void:
	_hp_box = Node2D.new()
	_hp_box.name = "HpBadge"
	_hp_box.position = Vector2(-15, -100 if is_boss else -88)
	_hp_box.z_index = 5
	add_child(_hp_box)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09, 0.85)
	bg.position = Vector2(-1, 13)
	bg.size = Vector2(32, 6)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_box.add_child(bg)
	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.95, 0.35, 0.3)
	_hp_fill.position = Vector2(0, 14)
	_hp_fill.size = Vector2(30, 4)
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_box.add_child(_hp_fill)
	_hp_label = Label.new()
	_hp_label.position = Vector2(-5, -6)
	_hp_label.size = Vector2(40, 18)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.add_theme_font_size_override("font_size", 12)
	_hp_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_hp_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hp_label.add_theme_constant_override("outline_size", 4)
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_label.text = "0"
	_hp_box.add_child(_hp_label)
	status_anchor = Marker2D.new()
	status_anchor.name = "StatusAnchor"
	status_anchor.position = Vector2(0, -112 if is_boss else -100)
	add_child(status_anchor)


# ---------------------------------------------------------------- 几何 / 骨

func _bone(bname: String, parent: Node, length: float) -> Bone2D:
	var b := Bone2D.new()
	b.name = bname
	var r: Array = REST[bname]
	b.position = r[0]
	b.rotation = r[1]
	b.set_autocalculate_length_and_angle(false)
	b.set_length(length)
	b.set_bone_angle(0.0)
	parent.add_child(b)
	b.rest = b.transform
	bones[bname] = b
	return b


func _part(parent: Node, pts: PackedVector2Array, col: Color, z: int) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = pts
	p.color = col
	p.z_index = z
	parent.add_child(p)
	return p


static func _circle(c: Vector2, r: float, n: int = 14) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


static func _ellipse(c: Vector2, rx: float, ry: float, n: int = 16) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out


static func _capsule(a: Vector2, b: Vector2, r: float, n: int = 5) -> PackedVector2Array:
	var ang := (b - a).angle()
	var out := PackedVector2Array()
	for i in n + 1:
		var t := ang - PI * 0.5 + PI * float(i) / float(n)
		out.append(b + Vector2(cos(t), sin(t)) * r)
	for i in n + 1:
		var t := ang + PI * 0.5 + PI * float(i) / float(n)
		out.append(a + Vector2(cos(t), sin(t)) * r)
	return out


static func _rect(a: Vector2, b: Vector2) -> PackedVector2Array:
	return PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)])


static func _grow(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var res := Geometry2D.offset_polygon(pts, d)
	return res[0] if res.size() > 0 else pts


# ---------------------------------------------------------------- 动画

func _bone_path(bn: String) -> String:
	return String(get_path_to(bones[bn]))


func _r(bn: String) -> String:
	return "%s:rotation" % _bone_path(bn)


func _track_paths() -> Array:
	var out: Array = []
	for bn in REST.keys():
		if not bones.has(bn):
			continue
		out.append(["%s:rotation" % _bone_path(bn), REST[bn][1]])
	out.append(["%s:position" % _bone_path("Hip"), REST["Hip"][0]])
	out.append(["Rig:modulate", Color(1, 1, 1, 1)])
	out.append(["Rig:position", Vector2.ZERO])
	return out


func _make_anim(length: float, keys: Dictionary, loop: bool = false, hold_end: bool = false) -> Animation:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	for tp in _track_paths():
		var path: String = tp[0]
		var rest_v = tp[1]
		var ti := a.add_track(Animation.TYPE_VALUE)
		a.track_set_path(ti, NodePath(path))
		a.track_set_interpolation_type(ti, Animation.INTERPOLATION_CUBIC if loop else Animation.INTERPOLATION_LINEAR)
		a.value_track_set_update_mode(ti, Animation.UPDATE_CONTINUOUS)
		if keys.has(path):
			var arr: Array = keys[path]
			var has0 := false
			for k in arr:
				if is_zero_approx(float(k[0])):
					has0 = true
			if not has0:
				a.track_insert_key(ti, 0.0, rest_v)
			for k in arr:
				a.track_insert_key(ti, float(k[0]), k[1])
			if not hold_end and float(arr[arr.size() - 1][0]) < length - 0.001:
				a.track_insert_key(ti, length, rest_v)
		else:
			a.track_insert_key(ti, 0.0, rest_v)
			a.track_insert_key(ti, length, rest_v)
	return a


func _vis_track(a: Animation, node: Node, keys: Array) -> void:
	if node == null:
		return
	var ti := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(ti, NodePath("%s:visible" % String(get_path_to(node))))
	a.value_track_set_update_mode(ti, Animation.UPDATE_DISCRETE)
	for k in keys:
		a.track_insert_key(ti, float(k[0]), k[1])


func _build_animations() -> void:
	anim = AnimationPlayer.new()
	anim.name = "Anim"
	add_child(anim)
	anim.root_node = NodePath("..")
	var lib := AnimationLibrary.new()
	var hip_p := "%s:position" % _bone_path("Hip")
	var hip0: Vector2 = REST["Hip"][0]
	var t1r: float = REST["Tail1"][1]
	var t2r: float = REST["Tail2"][1]
	var wfr: float = REST["WingF"][1]
	var wbr: float = REST["WingB"][1]

	var reset := _make_anim(0.001, {})
	_vis_track(reset, _eye_open, [[0.0, true]])
	_vis_track(reset, _eye_x, [[0.0, false]])
	lib.add_animation(ANIM_RESET, reset)

	# idle
	var idle_keys := {
		hip_p: [[0.0, hip0], [0.9, hip0 + Vector2(0, 0.8)], [1.8, hip0]],
		_r("Torso"): [[0.0, 0.0], [0.9, -0.03], [1.8, 0.0]],
		_r("Head"): [[0.0, 0.0], [0.9, 0.05], [1.8, 0.0]],
		_r("Tail1"): [[0.0, t1r], [0.9, t1r + 0.15], [1.8, t1r]],
		_r("Tail2"): [[0.0, t2r], [0.9, t2r + 0.2], [1.8, t2r]],
	}
	if species == "bat":
		idle_keys[_r("WingF")] = [[0.0, wfr], [0.9, wfr - 0.2], [1.8, wfr]]
		idle_keys[_r("WingB")] = [[0.0, wbr], [0.9, wbr + 0.2], [1.8, wbr]]
	var idle := _make_anim(1.8, idle_keys, true)
	_vis_track(idle, _eye_open, [[0.0, true]])
	_vis_track(idle, _eye_x, [[0.0, false]])
	lib.add_animation(ANIM_IDLE, idle)

	# walk
	var walk_keys := {
		hip_p: [[0.0, hip0], [0.15, hip0 + Vector2(0, -2)], [0.3, hip0], [0.45, hip0 + Vector2(0, -2)], [0.6, hip0]],
		_r("ThighF"): [[0.0, -0.1], [0.15, 0.45], [0.3, -0.1], [0.45, -0.55], [0.6, -0.1]],
		_r("ShinF"): [[0.0, 0.1], [0.15, 0.35], [0.3, 0.1], [0.45, 0.5], [0.6, 0.1]],
		_r("ThighB"): [[0.0, 0.12], [0.15, -0.5], [0.3, 0.12], [0.45, 0.4], [0.6, 0.12]],
		_r("ShinB"): [[0.0, -0.08], [0.15, 0.45], [0.3, -0.08], [0.45, 0.3], [0.6, -0.08]],
		_r("UpperArmF"): [[0.0, 0.55], [0.15, 0.2], [0.3, 0.55], [0.45, 0.9], [0.6, 0.55]],
		_r("UpperArmB"): [[0.0, 2.4], [0.15, 2.7], [0.3, 2.4], [0.45, 2.1], [0.6, 2.4]],
		_r("Torso"): [[0.0, 0.0], [0.15, 0.04], [0.3, 0.0], [0.45, -0.04], [0.6, 0.0]],
		_r("Head"): [[0.0, 0.0], [0.15, -0.04], [0.45, 0.04], [0.6, 0.0]],
		_r("Tail1"): [[0.0, t1r], [0.15, t1r - 0.2], [0.45, t1r + 0.25], [0.6, t1r]],
	}
	if species == "bat":
		walk_keys[_r("WingF")] = [[0.0, wfr], [0.15, wfr - 0.7], [0.3, wfr], [0.45, wfr - 0.7], [0.6, wfr]]
		walk_keys[_r("WingB")] = [[0.0, wbr], [0.15, wbr + 0.5], [0.3, wbr], [0.45, wbr + 0.5], [0.6, wbr]]
		walk_keys[hip_p] = [[0.0, hip0 + Vector2(0, -4)], [0.15, hip0 + Vector2(0, -7)], [0.3, hip0 + Vector2(0, -4)], [0.45, hip0 + Vector2(0, -7)], [0.6, hip0 + Vector2(0, -4)]]
	var walk := _make_anim(0.6, walk_keys, true)
	_vis_track(walk, _eye_open, [[0.0, true]])
	_vis_track(walk, _eye_x, [[0.0, false]])
	lib.add_animation(ANIM_WALK, walk)

	# attack：往前一扑 + 前爪抡
	var atk := _make_anim(0.32, {
		"Rig:position": [[0.0, Vector2.ZERO], [0.08, Vector2(-6, 0)], [0.18, Vector2(-10, -1)], [0.32, Vector2.ZERO]],
		_r("Torso"): [[0.0, 0.0], [0.1, 0.2], [0.32, 0.0]],
		_r("Head"): [[0.0, 0.0], [0.1, 0.15], [0.32, 0.0]],
		_r("UpperArmF"): [[0.0, 0.55], [0.08, -0.4], [0.16, -0.9], [0.32, 0.55]],
		_r("ForearmF"): [[0.0, 0.4], [0.1, 0.1], [0.32, 0.4]],
		_r("WingF"): [[0.0, wfr], [0.1, wfr - 1.0], [0.32, wfr]],
		hip_p: [[0.0, hip0], [0.12, hip0 + Vector2(-2, 0)], [0.32, hip0]],
	})
	_vis_track(atk, _eye_open, [[0.0, true]])
	_vis_track(atk, _eye_x, [[0.0, false]])
	lib.add_animation(ANIM_ATTACK, atk)

	# hurt
	var hurt := _make_anim(0.28, {
		_r("Torso"): [[0.0, 0.0], [0.05, -0.25], [0.28, 0.0]],
		_r("Head"): [[0.0, 0.0], [0.05, -0.2], [0.28, 0.0]],
		"Rig:position": [[0.0, Vector2.ZERO], [0.05, Vector2(4, 0)], [0.28, Vector2.ZERO]],
		"Rig:modulate": [[0.0, Color(1, 1, 1)], [0.04, Color(1.5, 0.55, 0.55)], [0.2, Color(1, 1, 1)]],
		_r("Tail1"): [[0.0, t1r], [0.05, t1r + 0.4], [0.28, t1r]],
	})
	_vis_track(hurt, _eye_open, [[0.0, true]])
	_vis_track(hurt, _eye_x, [[0.0, false]])
	lib.add_animation(ANIM_HURT, hurt)

	# death：往后仰再趴下
	var death := _make_anim(0.85, {
		_r("Torso"): [[0.0, 0.0], [0.15, -0.4], [0.45, 0.3], [0.85, 1.45]],
		_r("Head"): [[0.0, 0.0], [0.15, -0.3], [0.85, -0.2]],
		_r("ThighF"): [[0.0, -0.1], [0.45, -0.8], [0.85, 1.4]],
		_r("ShinF"): [[0.0, 0.1], [0.85, -0.4]],
		_r("ThighB"): [[0.0, 0.12], [0.45, -0.6], [0.85, 1.3]],
		_r("ShinB"): [[0.0, -0.08], [0.85, -0.5]],
		_r("UpperArmF"): [[0.0, 0.55], [0.85, -1.0]],
		_r("UpperArmB"): [[0.0, 2.4], [0.85, -0.8]],
		_r("WingF"): [[0.0, wfr], [0.85, wfr - 1.2]],
		_r("Tail1"): [[0.0, t1r], [0.85, -1.6]],
		hip_p: [[0.0, hip0], [0.2, hip0 + Vector2(2, 2)], [0.5, hip0 + Vector2(4, 10)], [0.85, hip0 + Vector2(6, 14)]],
		"Rig:modulate": [[0.0, Color(1, 1, 1)], [0.08, Color(1.4, 0.55, 0.55)], [0.85, Color(0.65, 0.65, 0.7)]],
	}, false, true)
	_vis_track(death, _eye_open, [[0.0, true], [0.12, false]])
	_vis_track(death, _eye_x, [[0.0, false], [0.12, true]])
	lib.add_animation(ANIM_DEATH, death)

	anim.add_animation_library(&"", lib)
	anim.animation_finished.connect(_on_anim_finished)


func _on_anim_finished(n: StringName) -> void:
	if is_dead:
		return
	if n == ANIM_ATTACK or n == ANIM_HURT:
		anim.play(ANIM_WALK if moving else ANIM_IDLE, 0.1)
		_apply_anim_rate()
