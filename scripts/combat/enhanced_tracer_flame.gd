class_name EnhancedTracerFlame
extends Node2D
## Batched burning tracer, capped visual shells; no particles or per-layer nodes.
var colors: Array[Color] = []
var size_factor := 1.0
var age := 0.0

func _process(delta: float) -> void:
	age += delta
	queue_redraw()

func _draw() -> void:
	for layer in mini(colors.size(), 8):
		var col := colors[layer]
		col.a = 0.8
		for i in 5:
			var x := -float(i) * 8.0 * size_factor
			var h := (4.0 + float(layer) * 1.1) * size_factor
			var wob := sin(age * 30.0 + float(i + layer)) * 3.0 * size_factor
			draw_colored_polygon(PackedVector2Array([Vector2(x + 5, wob), Vector2(x - 10, -h + wob), Vector2(x - 4, wob), Vector2(x - 11, h + wob)]), col)
