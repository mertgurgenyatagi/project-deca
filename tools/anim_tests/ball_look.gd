extends SceneTree
## Close-up render of the ball for checking its panels. Run without
## --headless, with --write-movie out/ball.png --fixed-fps 30.

var frame := 0
var ball: Node3D


func _initialize() -> void:
	var pitch: Node = load("res://scenes/pitch.tscn").instantiate()
	root.add_child(pitch)
	ball = load("res://scenes/ball.tscn").instantiate()
	root.add_child(ball)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0.35, 0.3, 0.55), Vector3(0, 0.11, 0))
	cam.fov = 40
	cam.current = true


func _process(_delta: float) -> bool:
	frame += 1
	ball.get_node("Mesh").rotate_y(0.15)
	ball.get_node("Mesh").rotate_x(0.07)
	return frame >= 12
