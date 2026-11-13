extends "res://addons/pixelfx/core/effect.gd"
## 命中飚血：暗红到亮红的液滴向外抛出，受重力下坠，大小不一。用 seed 做出不同变体。

const Px := preload("res://addons/pixelfx/core/px.gd")

static var meta := {
	"name": "Blood spray",
	"desc": "A blood-red hit: a dark-to-bright splat, then droplets that arc out and fall under gravity.",
	"tags": ["impact", "blood", "hit", "one-shot"],
	"size": [128, 112],
	"origin": [64, 84],
	"duration": 0.85,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#14040a", "#3a0a14", "#6a101c", "#a01824", "#d42a30", "#ff5a50", "#ff9a8a"],
		"height": 24,
		"seed": 6,
	},
}

var C: Array
var R: Px.Rng
var Y: float
var t := 0.0
var drops: Array = []


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 7)
	R = Px.Rng.new(o.seed)
	Y = -float(o.height)
	t = 0.0
	drops.clear()
	var n := int(R.range(16, 26))
	for i in n:
		var a := R.range(-2.6, -0.55)  # 上半圈偏外抛
		if R.chance(0.28):
			a = R.range(-0.4, 0.55)  # 少数往下/侧喷
		var sp := R.range(70.0, 260.0)
		var sz := R.range(0.9, 3.4)
		if i < 4:
			sz = R.range(2.6, 4.2)
		var life := R.range(0.35, 0.8)
		var col: int = C[int(R.range(2, 7))]
		drops.append({
			"x": R.range(-2.0, 2.0),
			"y": Y + R.range(-1.5, 1.5),
			"vx": cos(a) * sp * R.range(0.75, 1.15),
			"vy": sin(a) * sp - R.range(20.0, 80.0),
			"life": life,
			"max": life,
			"size": sz,
			"col": col,
			"hi": C[mini(6, int(R.range(4, 7)))],
		})


func update(dt: float) -> void:
	t += dt
	for d: Dictionary in drops:
		if d.life <= 0.0:
			continue
		d.life -= dt
		d.vy += 950.0 * dt
		d.vx -= d.vx * 0.55 * dt
		d.x += d.vx * dt
		d.y += d.vy * dt


func draw(p: Px.Painter) -> void:
	# 撞击瞬间的血红爆点
	var pop := exp(-t / 0.05)
	if pop > 0.02:
		p.glow(0.0, Y, 16.0 + 10.0 * pop, C[4], 0.55 * pop)
		p.glow(0.0, Y, 6.0, C[6], 0.45 * pop)
		p.disc(0.0, Y, 3.2 + 2.0 * pop, C[5], 0.85 * pop)
	# 一小摊裂开的血花
	if t < 0.12:
		var u := t / 0.12
		var fade := 1.0 - u
		for k in 7:
			var a := -2.4 + float(k) * 0.55 + 0.08
			var r := 3.0 + 9.0 * u
			p.dot(cos(a) * r, Y + sin(a) * r * 0.7, C[5] if k % 2 == 0 else C[3], fade)
	for d: Dictionary in drops:
		if d.life <= 0.0:
			continue
		var k: float = d.life / d.max
		var a: float = 1.0 if k > 0.25 else k / 0.25
		var sz: float = d.size * (0.85 + 0.2 * k)
		# 速度方向拖一小段尾巴，看起来像甩出去的血滴
		var sp := Px.hypot(d.vx, d.vy)
		if sp > 40.0:
			var ux: float = d.vx / sp
			var uy: float = d.vy / sp
			var tail := minf(5.0, sp * 0.018) * sz
			p.dot(d.x - ux * tail, d.y - uy * tail, d.col, a * 0.45)
		p.disc(d.x, d.y, sz, d.col, a)
		if sz > 1.6:
			p.dot(d.x - sz * 0.25, d.y - sz * 0.3, d.hi, a * 0.8)
		p.dot(d.x, d.y, d.hi if k > 0.55 else d.col, a)
