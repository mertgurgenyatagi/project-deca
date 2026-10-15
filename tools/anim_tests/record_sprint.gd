extends SceneTree
## Sprints off from a standstill to the right, then turns back left.
var frame := 0
var player: Node3D
func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	# The stand-in teammates are for trying passes; they would only get in the way here.
	main.get_node("Teammates").free()
	root.add_child(main)
	player = main.get_node("Player")
	player._yaw = PI / 2
func _process(_d: float) -> bool:
	frame += 1
	if frame == 10:
		Input.action_press("sprint")
		Input.action_press("move_right")
	if frame == 70:
		Input.action_release("move_right")
		Input.action_press("move_left")
	return frame >= 125
