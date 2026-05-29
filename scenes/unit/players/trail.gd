extends Line2D
class_name Trail

@export var player: Player
@export var trail_length := 25
@export var trail_duration := 1.0


@onready var trail_timer: Timer = %TrailTimer

var points_array: Array[Vector2] = []
var is_active := false

func _process(_delta: float) -> void:
	if not is_active:
		return

	var anchor := player.sprite.global_position
	points_array.append(anchor)
	if points_array.size() > trail_length:
		points_array.pop_front()

	global_position = anchor
	var local_points := PackedVector2Array()
	local_points.resize(points_array.size())
	for i in points_array.size():
		local_points[i] = to_local(points_array[i])
	points = local_points

func start_trail() -> void:
	is_active = true
	clear_points()
	points_array.clear()
	global_position = player.sprite.global_position
	trail_timer.start(trail_duration)
	

func _on_trail_timer_timeout() -> void:
	is_active = false
	clear_points()
	points_array.clear()
