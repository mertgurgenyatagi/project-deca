extends SceneTree
## Runs right, turns back left, and quits; meant to be used with --write-movie.
var frame := 0
func _initialize() -> void:
	root.add_child(load("res://scenes/main.tscn").instantiate())
func _process(_d: float) -> bool:
	frame += 1
	if frame == 5:
		Input.action_press("move_right")
	if frame == 50:
		Input.action_release("move_right")
		Input.action_press("move_left")
	return frame >= 95
