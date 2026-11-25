class_name EnhancedTracerFlame
extends Node2D
## Batched burning tracer, capped visual shells; no particles or per-layer nodes.
var colors: Array[Color] = []
var size_factor := 1.0
var age := 0.0

func _process(delta: float) -> void:
	age += delta
	queue_redraw()

static func flame_outline(t: float) -> PackedVector2Array:
	# Rounded fireball head and three independently licking, forked tails.
	var a := sin(t * 31.0) * 3.0
	var b := sin(t * 23.0 + 1.7) * 3.0
	return PackedVector2Array([Vector2(11,0),Vector2(9,-6),Vector2(4,-11),Vector2(-6,-12),Vector2(-17,-10),Vector2(-33,-18+a),Vector2(-27,-6),Vector2(-55,-13+b),Vector2(-43,-2),Vector2(-72,-4+a),Vector2(-53,5),Vector2(-68,17+b),Vector2(-35,9),Vector2(-39,19+a),Vector2(-17,11),Vector2(-4,12),Vector2(5,9),Vector2(10,4)])

func _draw() -> void:
	var unit := clampf(size_factor * 0.55, 0.7, 1.2)
	for layer in range(mini(colors.size(), 8) - 1, -1, -1):
		var col := colors[layer]
		var shell := unit * (1.0 + float(layer) * 0.25)
		var pts := flame_outline(age + float(layer) * 0.07)
		for i in pts.size():
			pts[i] *= shell
		draw_colored_polygon(pts, col)
		draw_circle(Vector2(3,0), 4.5 * unit, col.lightened(0.7))
