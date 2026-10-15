extends SceneTree
## Drives the player through a dribbling sequence for visual checks. Run
## without --headless, with --write-movie out/f.png --fixed-fps 30
## --resolution 960x540. Pass "close" as a user arg for a low, close camera
## that follows the ball instead of the broadcast camera.

const SEQUENCE := [
	[0.6, Vector2.ZERO, false],
	[2.5, Vector2(1, 0), false],
	[2.0, Vector2(1, 0), true],
	[1.5, Vector2(0, 1), false],
	[1.6, Vector2(0, -1), false],
	[1.2, Vector2.ZERO, false],
	[1.6, Vector2(-1, 0), false],
	[1.0, Vector2(1, 0), false],
	[1.0, Vector2.ZERO, false],
]

var player: Player
var ball: Ball
var camera: Camera3D
var close := false
var t := 0.0
var step := 0
var step_end := 0.0


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	player = main.get_node("Player")
	ball = main.get_node("Ball")
	player.read_input = false
	player.global_position = Vector3(-2, 0, 0)
	player._yaw = PI / 2
	ball.place(Vector3(-1.65, 0, -0.08))
	close = "close" in OS.get_cmdline_user_args()
	if close:
		camera = Camera3D.new()
		camera.fov = 45
		main.add_child(camera)
		camera.current = true
	step_end = SEQUENCE[0][0]


func _process(delta: float) -> bool:
	t += delta
	if t >= step_end:
		step += 1
		if step >= SEQUENCE.size():
			return true
		step_end += SEQUENCE[step][0]
	player.move_input = SEQUENCE[step][1]
	player.sprint_held = SEQUENCE[step][2]
	if close:
		var focus := ball.global_position.lerp(player.global_position, 0.5)
		camera.look_at_from_position(focus + Vector3(0.0, 1.6, 3.2), focus + Vector3(0, 0.3, 0))
	return false
