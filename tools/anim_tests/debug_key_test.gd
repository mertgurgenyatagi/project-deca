extends SceneTree
## Plays the main scene through the real input path (keyboard actions, not
## move_input): jogs onto the ball, presses B to knock it loose, then chases
## it and checks it is picked up again. Prints KEYS_OK / KEYS_FAIL.

var player: Player
var ball: Ball


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	# The stand-in teammates are for trying passes; they would only get in the way here.
	main.get_node("Teammates").free()
	root.add_child(main)
	player = main.get_node("Player")
	ball = main.get_node("Ball")
	_run.call_deferred()


func _wait(seconds: float) -> void:
	for i in int(seconds * 60.0):
		await physics_frame


func _run() -> void:
	var ok := true
	Input.action_press("move_right")
	await _wait(1.5)
	print("held after jogging onto it: %s" % [ball.holder == player])
	ok = ok and ball.holder == player
	Input.action_release("move_right")
	await _wait(0.8)

	var key := InputEventKey.new()
	key.physical_keycode = KEY_B
	key.pressed = true
	root.push_input(key)
	await _wait(0.1)
	print("loose after B: %s  speed %.2f m/s" % [ball.holder == null, ball.velocity.length()])
	ok = ok and ball.holder == null and ball.velocity.length() > 1.0
	await _wait(0.6)
	print("not taken straight back: %s" % [ball.holder == null])
	ok = ok and ball.holder == null

	# Chase it.
	var t := 0.0
	while ball.holder != player and t < 6.0:
		var to_ball := Vector2(ball.position.x - player.global_position.x, ball.position.z - player.global_position.z)
		for a in ["move_left", "move_right", "move_up", "move_down"]:
			Input.action_release(a)
		if to_ball.x > 0.2: Input.action_press("move_right")
		if to_ball.x < -0.2: Input.action_press("move_left")
		if to_ball.y > 0.2: Input.action_press("move_down")
		if to_ball.y < -0.2: Input.action_press("move_up")
		await physics_frame
		t += 1.0 / 60.0
	print("picked up again: %s after %.2f s" % [ball.holder == player, t])
	ok = ok and ball.holder == player
	print("KEYS_OK" if ok else "KEYS_FAIL")
	quit()
