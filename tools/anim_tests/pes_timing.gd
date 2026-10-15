extends SceneTree
## Times the real player through the PES 2013 test runs (reported in PES frames at 30 fps).

const D := 3.7
const TICK := 1.0 / 60.0
var player: CharacterBody3D


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	# The stand-in teammates are for trying passes; they would only get in the way here.
	main.get_node("Teammates").free()
	root.add_child(main)
	# Movement is measured without the ball (holding it gates turns).
	main.get_node("Ball").free()
	player = main.get_node("Player")
	_run.call_deferred()


func _reset(x: float, yaw: float) -> void:
	_release()
	player.global_position = Vector3(x, 0, 0)
	player.velocity = Vector3.ZERO
	player._ground = Vector2.ZERO
	player._action = 0
	player._yaw = yaw


func _release() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)


func _until(action: String, cond: Callable) -> float:
	_release()
	Input.action_press(action)
	var t := 0.0
	while t < 20.0:
		await physics_frame
		t += TICK
		if cond.call():
			return t
	return INF


func _x() -> float:
	return player.global_position.x


func _run() -> void:
	for i in 5:
		await physics_frame
	var r := {}
	_reset(0, PI / 2)
	r["acc+move"] = await _until("move_right", func(): return _x() >= D)

	_reset(-12, PI / 2)
	await _until("move_right", func(): return _x() >= -6.0)
	r["move"] = await _until("move_right", func(): return _x() >= -6.0 + D)

	# Moving turnbacks: run up from x=-12 so the player is at full speed by x=0.
	var v: float = player.move_speed
	_reset(-12, PI / 2)
	await _until("move_right", func(): return _x() >= 0.0)
	r["turnback"] = await _until("move_left", func(): return player._ground.x <= -0.99 * v)

	_reset(-12, PI / 2)
	await _until("move_right", func(): return _x() >= 0.0)
	r["turnback+move"] = await _until("move_left", func(): return _x() <= -D)

	# Edges at x=0 and x=-D; each turnback is started early so it turns on the edge.
	var over: float = v * v / (2.0 * player.turnback_brake)
	_reset(-12, PI / 2)
	await _until("move_right", func(): return _x() >= -over)
	var t: float = await _until("move_left", func(): return _x() <= -D + over)
	t += await _until("move_right", func(): return _x() >= -over)
	t += await _until("move_left", func(): return _x() <= -D)
	r["chain x3"] = t

	Input.action_press("sprint")
	_reset(0, PI / 2)
	r["accsprint+sprint"] = await _until("move_right", func(): return _x() >= D)
	_reset(-14, PI / 2)
	await _until("move_right", func(): return _x() >= -6.0)
	r["sprint"] = await _until("move_right", func(): return _x() >= -6.0 + D)
	Input.action_release("sprint")

	var pes := {"acc+move": 56, "move": 45, "turnback": 38, "turnback+move": 79, "chain x3": 196, "accsprint+sprint": 44, "sprint": 29}
	for k in pes:
		print("  %-14s game %6.1f   PES %d" % [k, r[k] * 30.0, pes[k]])
	quit()
