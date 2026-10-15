extends Node
## Debug keys for testing in the running game. The ball and the dribble never
## read the keyboard themselves; this does it for them.
## - B: knock the ball loose in a random direction, to roll 3-5 m.


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or KEY_B not in [key.physical_keycode, key.keycode]:
		return
	var ball := get_tree().get_first_node_in_group(&"ball") as Ball
	if ball == null:
		return
	var distance := randf_range(3.0, 5.0)
	var velocity := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU) * ball.speed_to_stop_at(distance)
	if ball.holder:
		ball.holder.get_node("Dribble").release(velocity)
	else:
		ball.release(ball.position, velocity)
