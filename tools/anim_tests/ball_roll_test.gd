extends SceneTree
## Checks the loose ball's roll: it stops where the drag model says, the
## closed forms agree with each other and with a step-by-step integration,
## identical releases roll identically (what networking will rely on), a hop
## lands and settles, and the ball spins without slipping. Prints PASS/FAIL
## lines and a final ROLL_OK/ROLL_FAIL.

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		failures += 1


func _run() -> void:
	var scene: PackedScene = load("res://scenes/ball.tscn") if ResourceLoader.exists("res://scenes/ball.tscn") else null
	if scene == null:
		print("FAIL  ball scene missing\nROLL_FAIL")
		quit(1)
		return
	var a: Node3D = scene.instantiate()
	var b: Node3D = scene.instantiate()
	root.add_child(a)
	root.add_child(b)
	var r: float = a.radius
	_check_closed_forms(a)
	a.place(Vector3(0, r, 0))
	b.place(Vector3(0, r, 0))
	await physics_frame
	a.release(Vector3(0, r, 0), Vector3(3, 0, 0))
	b.release(Vector3(0, r, 0), Vector3(3, 0, 0))

	var mesh: Node3D = a.get_node("Mesh")
	var prev_basis := mesh.basis
	var prev_pos := a.position
	var rolled := 0.0
	var travelled := 0.0
	var worst_axis := 0.0
	var worst_match := 0.0
	for i in 300:
		await physics_frame
		worst_match = maxf(worst_match, a.position.distance_to(b.position))
		var step: Vector3 = a.position - prev_pos
		var q := Quaternion(prev_basis.inverse() * mesh.basis)
		if step.length() > 1e-5:
			rolled += q.get_angle()
			travelled += step.length()
			# The spin axis (in world space) must be perpendicular to the motion.
			var axis := (prev_basis * q.get_axis()).normalized()
			worst_axis = maxf(worst_axis, absf(axis.dot(step.normalized())))
		prev_basis = mesh.basis
		prev_pos = a.position

	var expected: float = a.stop_distance(3.0)
	_check("stop distance", absf(a.position.x - expected) < 0.001, "x=%.4f expected %.4f" % [a.position.x, expected])
	_check("stopped", a.velocity.length() < 1e-6, "v=%.6f" % a.velocity.length())
	_check("on ground", absf(a.position.y - r) < 1e-6, "y=%.4f" % a.position.y)
	_check("deterministic", worst_match < 1e-6, "max gap %.9f m" % worst_match)
	_check("rolls without slip", absf(rolled - travelled / r) < 0.01 * travelled / r, "angle %.3f vs %.3f" % [rolled, travelled / r])
	_check("spin axis", worst_axis < 0.01, "worst |axis·dir| %.4f" % worst_axis)

	# A hard kick with a hop: both copies agree, the ball leaves the ground, and
	# it is back on it and still once it stops.
	a.release(Vector3(0, r, 0), Vector3(0, 0, 12), null, 1.0)
	b.release(Vector3(0, r, 0), Vector3(0, 0, 12), null, 1.0)
	var highest := 0.0
	worst_match = 0.0
	for i in 900:
		await physics_frame
		highest = maxf(highest, a.position.y - r)
		worst_match = maxf(worst_match, a.position.distance_to(b.position))
	_check("hop rises", highest > 0.04 and highest < 0.06, "peak %.3f m (1 m/s up: %.3f)" % [highest, 1.0 / (2.0 * 9.8)])
	_check("hop settles", absf(a.position.y - r) < 1e-6 and a.velocity.length() < 1e-6, "y=%.4f v=%.4f" % [a.position.y, a.velocity.length()])
	_check("hop deterministic", worst_match < 1e-6, "max gap %.9f m" % worst_match)
	print("ROLL_OK" if failures == 0 else "ROLL_FAIL")
	quit()


## The closed forms against a fine step-by-step integration of
## dv/dt = -a - k·v², and against each other.
func _check_closed_forms(ball: Node3D) -> void:
	var dec: float = ball.roll_deceleration
	var k: float = ball.roll_drag
	for v0: float in [3.0, 8.0, 14.0]:
		var v := v0
		var x := 0.0
		var t := 0.0
		const DT := 1.0 / 20000.0
		var x_at_1 := -1.0
		while v > 0.0:
			v = maxf(v - (dec + k * v * v) * DT, 0.0)
			x += v * DT
			t += DT
			if x_at_1 < 0.0 and t >= 1.0:
				x_at_1 = x
		var closed: float = ball.stop_distance(v0)
		_check("stop distance %.0f m/s" % v0, absf(closed - x) < 0.01 * x, "closed %.3f vs integrated %.3f m" % [closed, x])
		if x_at_1 > 0.0:
			_check("distance after 1 s at %.0f m/s" % v0, absf(ball.roll_distance(v0, 1.0) - x_at_1) < 0.01 * x_at_1,
					"closed %.3f vs integrated %.3f m" % [ball.roll_distance(v0, 1.0), x_at_1])
	var launch: float = ball.speed_to_arrive(12.0, 6.0)
	var time: float = ball.time_to_roll(launch, 12.0)
	_check("arrival round trip", absf(ball.roll_speed(launch, time) - 6.0) < 0.01 and absf(ball.roll_distance(launch, time) - 12.0) < 0.01,
			"launch %.2f m/s, 12 m in %.3f s at %.2f m/s" % [launch, time, ball.roll_speed(launch, time)])
	_check("stop round trip", absf(ball.stop_distance(ball.speed_to_stop_at(20.0)) - 20.0) < 0.001, "%.4f m" % ball.stop_distance(ball.speed_to_stop_at(20.0)))
