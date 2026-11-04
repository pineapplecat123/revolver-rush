extends Control
## 经验粒子：飞进经验条。经验数值在发出时已经入账，这里只做表现。

var target_pos: Callable = Callable()
var _vel := Vector2.ZERO
var _age := 0.0
var _done := false


func setup(start: Vector2, target: Callable) -> void:
	target_pos = target
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(10, 10)
	global_position = start - size * 0.5
	_vel = Vector2(randf_range(-180.0, 180.0), randf_range(-220.0, -40.0))


func _process(delta: float) -> void:
	if _done:
		return
	_age += delta
	var dest := global_position
	if target_pos.is_valid():
		dest = target_pos.call() - size * 0.5
	var to: Vector2 = dest - global_position
	var dist: float = to.length()
	if dist < 16.0 or _age > 1.6:
		_done = true
		queue_free()
		return
	# 先散开再加速吸进经验条
	var pull: float = 180.0 + _age * _age * 2200.0
	if dist > 0.01:
		_vel += to / dist * pull * delta
	_vel *= 0.92
	global_position += _vel * delta
	queue_redraw()


func _draw() -> void:
	draw_circle(size * 0.5, 4.2, Color(0.45, 0.9, 1.0, 0.95))
	draw_circle(size * 0.5, 2.0, Color(0.9, 1.0, 1.0, 1.0))
