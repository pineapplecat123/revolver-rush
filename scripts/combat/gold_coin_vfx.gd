extends Control
## 掉落金币：先爆开落地，再加速飞向玩家，碰到才回调入账。

var value: int = 1
var drop_id: int = -1
var ground_y: float = 0.0
var player_pos: Callable = Callable()
var collected_cb: Callable = Callable()
var _vel := Vector2.ZERO
var _phase := 0
var _age := 0.0
var _done := false


func setup(id: int, worth: int, ground: float, start: Vector2, player: Callable, cb: Callable) -> void:
	drop_id = id
	value = worth
	ground_y = ground
	player_pos = player
	collected_cb = cb
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(16, 16)
	global_position = start - size * 0.5
	_vel = Vector2(randf_range(-260.0, 260.0), randf_range(-560.0, -220.0))


func _process(delta: float) -> void:
	if _done:
		return
	_age += delta
	if _phase == 0:
		_vel.y += 1500.0 * delta
		global_position += _vel * delta
		if global_position.y >= ground_y:
			global_position.y = ground_y
			_vel = Vector2.ZERO
			_phase = 1
			_age = 0.0
	else:
		var target := global_position
		if player_pos.is_valid():
			target = player_pos.call() - size * 0.5
		var to: Vector2 = target - global_position
		var dist: float = to.length()
		if dist < 22.0:
			_finish()
			return
		var accel: float = 320.0 + _age * 1700.0
		if dist > 0.01:
			_vel += to / dist * accel * delta
		var cap: float = 260.0 + _age * 980.0
		if _vel.length() > cap:
			_vel = _vel.normalized() * cap
		global_position += _vel * delta
	queue_redraw()


func _finish() -> void:
	if _done:
		return
	_done = true
	var at: Vector2 = global_position + size * 0.5
	if collected_cb.is_valid():
		collected_cb.call(drop_id, value, at)
	queue_free()


func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, 7.0, Color(0.55, 0.32, 0.05, 0.9))
	draw_circle(c, 5.6, Color(1.0, 0.84, 0.22, 1.0))
	draw_circle(c + Vector2(-1.5, -1.5), 2.0, Color(1.0, 0.95, 0.7, 0.85))
