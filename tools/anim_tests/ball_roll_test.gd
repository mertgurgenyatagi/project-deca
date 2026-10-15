extends SceneTree
## Checks the loose ball's roll: it stops where constant deceleration says,
## identical releases roll identically (what networking will rely on), and it
## spins without slipping. Prints PASS/FAIL lines and a final ROLL_OK/ROLL_FAIL.

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
	var decel: float = a.roll_deceleration
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

	var expected := 9.0 / (2.0 * decel)
	_check("stop distance", absf(a.position.x - expected) < 0.001, "x=%.4f expected %.4f" % [a.position.x, expected])
	_check("stopped", a.velocity.length() < 1e-6, "v=%.6f" % a.velocity.length())
	_check("on ground", absf(a.position.y - r) < 1e-6, "y=%.4f" % a.position.y)
	_check("deterministic", worst_match < 1e-6, "max gap %.9f m" % worst_match)
	_check("rolls without slip", absf(rolled - travelled / r) < 0.01 * travelled / r, "angle %.3f vs %.3f" % [rolled, travelled / r])
	_check("spin axis", worst_axis < 0.01, "worst |axis·dir| %.4f" % worst_axis)
	print("ROLL_OK" if failures == 0 else "ROLL_FAIL")
	quit()
