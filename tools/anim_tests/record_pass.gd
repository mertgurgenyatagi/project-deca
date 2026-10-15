extends SceneTree
## Drives the player through some passing for visual checks, with the
## stand-in teammates where main.tscn puts them: a pass to the near one while
## jogging, its pass back, a harder pass to the far one, and a first-time
## pass back to the near one as the far one's return comes in. Run without
## --headless, with --write-movie out/f.png --fixed-fps 30 --resolution
## 960x540. Pass "close" as a user arg for a low camera that follows the
## player instead of the broadcast camera.

## [seconds, keys, sprint, pass button]
const SEQUENCE := [
	[0.5, Vector2.ZERO, false, false],
	[1.0, Vector2(1, 0), false, false],
	[0.15, Vector2(1, 0), false, true],
	[0.4, Vector2(1, 0), false, false],
	[4.2, Vector2.ZERO, false, false],
	[0.4, Vector2(1, -0.2), false, true],
	[0.4, Vector2(1, -0.2), false, false],
	[2.6, Vector2.ZERO, false, false],
	[0.1, Vector2(1, -0.5), false, true],
	[0.3, Vector2(1, -0.5), false, false],
	[4.0, Vector2.ZERO, false, false],
]

var player: Player
var camera: Camera3D
var close := false
var t := 0.0
var step := 0
var step_end := 0.0


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	player = main.get_node("Player")
	player.read_input = false
	player.position = Vector3(-2, 0, 0)
	player._yaw = PI / 2
	main.get_node("Ball").place(Vector3(-1.65, 0, -0.08))
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
	player.move_input = SEQUENCE[step][1].normalized()
	player.sprint_held = SEQUENCE[step][2]
	player.pass_held = SEQUENCE[step][3]
	if close:
		var focus := player.global_position
		camera.look_at_from_position(focus + Vector3(1.2, 1.4, 3.4), focus + Vector3(0.3, 0.5, 0))
	return false
