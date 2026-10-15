extends SceneTree
## Dribbling bench. Drives the player (through `move_input`/`sprint_held`, not
## the keyboard) through scripted scenarios with the ball, each from several
## start offsets so events land at different stride phases, and reports:
## - contact: gap between the ball and where the real touching toe says it
##   should be, at each regular touch (cm)
## - early: touches made off-rhythm (early touches and pickups)
## - pass: frames with a foot inside the ball, and the deepest (cm)
## - bend: steering acceleration on the ball between touches, avg / peak (m/s²)
## - lead: furthest the ball gets ahead of the hips along the facing (m)
## - far: furthest the ball gets from the player while held (m)
## - jump: largest per-tick move beyond |v|·dt (cm), a teleport check
## Ends with DRIBBLE_OK or DRIBBLE_FAIL.

const TICK := 1.0 / 60.0
const OFFSETS := [0.0, 0.23, 0.47]
const RIGHT := Vector2(1, 0)
const LEFT := Vector2(-1, 0)
const DOWN := Vector2(0, 1)

var player: Player
var ball: Ball
var dribble: Node
var skel: Skeleton3D
var feet := []
var failures := []


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	# The stand-in teammates are for trying passes; they would only get in the way here.
	main.get_node("Teammates").free()
	root.add_child(main)
	player = main.get_node("Player")
	ball = main.get_node("Ball")
	dribble = player.get_node_or_null("Dribble")
	skel = player.get_node("Model/Character/Skeleton3D")
	for side in ["Left", "Right"]:
		feet.append([skel.find_bone("mixamorig_%sFoot" % side), skel.find_bone("mixamorig_%sToeBase" % side)])
	player.read_input = false
	_run.call_deferred()


## Each scenario: a lead-in (seconds of jog/sprint to the right before the
## event, plus the start offset), then phases of [duration, input, sprint].
## `measure_from` is when (after the lead-in) measuring starts.
func _scenarios() -> Array:
	return [
		{"name": "steady jog", "lead": 0.0, "phases": [[6.0, RIGHT, false]], "measure_from": 2.0},
		{"name": "steady sprint", "lead": 0.0, "phases": [[6.0, RIGHT, true]], "measure_from": 2.5},
		{"name": "move off", "lead": 0.0, "phases": [[2.5, RIGHT, false]], "measure_from": 0.0},
		{"name": "sprint off", "lead": 0.0, "phases": [[2.5, RIGHT, true]], "measure_from": 0.0},
		{"name": "90 jog", "lead": 2.0, "phases": [[2.5, DOWN, false]], "measure_from": 0.0},
		{"name": "90 sprint", "lead": 2.5, "sprint": true, "phases": [[2.5, DOWN, true]], "measure_from": 0.0},
		{"name": "turnback jog", "lead": 2.0, "phases": [[2.5, LEFT, false]], "measure_from": 0.0},
		{"name": "turnback sprint", "lead": 2.5, "sprint": true, "phases": [[3.0, LEFT, true]], "measure_from": 0.0},
		{"name": "stop", "lead": 2.0, "phases": [[2.0, Vector2.ZERO, false]], "measure_from": 0.0},
		{"name": "pivot + go", "lead": 0.0, "phases": [[2.5, LEFT, false]], "measure_from": 0.0},
		{"name": "pickup ahead", "pickup": Vector2(3, 0)},
		{"name": "pickup left", "pickup": Vector2(0, -3)},
		{"name": "pickup right", "pickup": Vector2(0, 3)},
		{"name": "pickup behind", "pickup": Vector2(-3, 0)},
		{"name": "random 60s", "random": 60.0},
		{"name": "rapid taps", "taps": true},
	]


## Rapid arrow presses: a new direction (of 8) every 0.15-0.35 s for 12 s,
## after a 2 s jog. Prints how long changes wait for a touch and how far the
## ball sits from the hips; the end goal is the ball at the feet and near
## instant changes.
func _taps(offset: float) -> Dictionary:
	await _start_holding()
	var r := _new_result()
	await _drive(r, 2.0, RIGHT, false, INF)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99 + int(offset * 100.0)
	var t := 0.0
	var waits := []
	var facings := []
	var dist_sum := 0.0
	var dist_n := 0
	var slip_sum := 0.0
	var slip_n := 0
	var last_toes := {}
	var current := RIGHT
	while t < 12.0:
		var next := current
		while next.is_equal_approx(current):
			next = Vector2.from_angle(rng.randi_range(0, 7) * PI / 4.0).round().normalized()
		current = next
		var hold := rng.randf_range(0.15, 0.35)
		player.move_input = current
		var waited := -1.0
		var faced := -1.0
		var h := 0.0
		while h < hold:
			await physics_frame
			h += TICK
			if waited < 0.0 and not dribble._direction_pending():
				waited = h
			if faced < 0.0 and absf(angle_difference(player.yaw, atan2(current.x, current.y))) < deg_to_rad(15.0):
				faced = h
			for f in feet:
				var toe: Vector3 = skel.global_transform * skel.get_bone_global_pose(f[1]).origin
				if last_toes.has(f[1]) and toe.y < 0.02 and last_toes[f[1]].y < 0.02:
					slip_sum += Vector2(toe.x - last_toes[f[1]].x, toe.z - last_toes[f[1]].z).length() / TICK
					slip_n += 1
				last_toes[f[1]] = toe
			var rel := Vector2(ball.position.x - player.global_position.x, ball.position.z - player.global_position.z)
			dist_sum += rel.length()
			dist_n += 1
			r.far = maxf(r.far, rel.length())
		waits.append(waited if waited >= 0.0 else hold)
		facings.append(faced if faced >= 0.0 else hold)
		t += hold
	waits.sort()
	facings.sort()
	var facing_done := facings.filter(func(f): return f < 0.149).size() * 100 / facings.size()
	print("   taps offset %.2f: change wait median %.2f s, 90%% %.2f s; facing new way median %.2f s (%d%% within 0.15 s); ball from hips avg %.2f m, max %.2f m; planted slip %.2f m/s" % [offset, waits[waits.size() / 2], waits[int(waits.size() * 0.9)], facings[facings.size() / 2], facing_done, dist_sum / dist_n, r.far, slip_sum / maxf(slip_n, 1)])
	return r


## Random inputs (8 directions or none, sprint on or off) held for 0.2-1.2 s
## each, from a fixed seed per start offset: the "never lose it" stress test.
func _random(s: Dictionary, offset: float) -> Dictionary:
	await _start_holding()
	var r := _new_result()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234 + int(offset * 100.0)
	var t := 0.0
	while t < s.random:
		var input := Vector2.ZERO
		if rng.randf() > 0.15:
			input = Vector2.from_angle(rng.randi_range(0, 7) * PI / 4.0).round().normalized()
		var hold := rng.randf_range(0.2, 1.2)
		await _drive(r, hold, input, rng.randf() < 0.4, 0.0)
		t += hold
	return r


func _run() -> void:
	if dribble == null:
		print("FAIL  no Dribble node on the player\nDRIBBLE_FAIL")
		quit(1)
		return
	print("%-16s %6s %13s %6s %11s %13s %5s %5s %6s %7s" % ["scenario", "touch", "contact cm", "early", "pass", "bend", "lead", "far", "jump", "pickup"])
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("only="):
			only = arg.substr(5)
	for s in _scenarios():
		if only != "" and not s.name.contains(only):
			continue
		var agg := {}
		for offset in OFFSETS:
			var r: Dictionary
			if s.has("pickup"):
				r = await _pickup(s, offset)
			elif s.has("random"):
				r = await _random(s, offset)
			elif s.has("taps"):
				r = await _taps(offset)
			else:
				r = await _scenario(s, offset)
			_merge(agg, r)
		_report(s.name, agg)
	print("DRIBBLE_OK" if failures.is_empty() else "DRIBBLE_FAIL  " + ", ".join(failures))
	quit()


func _reset(at: Vector2, facing: Vector2) -> void:
	player.move_input = Vector2.ZERO
	player.sprint_held = false
	player.global_position = Vector3(at.x, 0, at.y)
	player.velocity = Vector3.ZERO
	player._ground = Vector2.ZERO
	player._action = 0
	for clip in player._one_shots:
		clip.playing = false
		clip.fade = 0.0
	player._yaw = atan2(facing.x, facing.y)
	player.reset_physics_interpolation()


## Puts the player at the origin facing +X with the ball resting at its feet,
## lets it settle and take the ball.
func _start_holding() -> void:
	_reset(Vector2.ZERO, RIGHT)
	ball.place(Vector3(0.35, 0, -0.08))
	dribble.reset_for_test()
	for i in 30:
		await physics_frame


func _scenario(s: Dictionary, offset: float) -> Dictionary:
	await _start_holding()
	var r := _new_result()
	var lead_time: float = s.lead + (offset if s.lead > 0.0 else 0.0)
	if s.lead == 0.0:
		# Vary the stride phase at the event by waiting a little first.
		for i in int(offset / TICK):
			await physics_frame
	var lead_sprint: bool = s.get("sprint", false)
	await _drive(r, lead_time, RIGHT, lead_sprint, INF)
	for phase in s.phases:
		await _drive(r, phase[0], phase[1], phase[2], s.measure_from)
	return r


func _pickup(s: Dictionary, offset: float) -> Dictionary:
	_reset(Vector2.ZERO, RIGHT)
	var at: Vector2 = s.pickup * (1.0 + offset)
	ball.place(Vector3(at.x, 0, at.y))
	dribble.reset_for_test()
	await physics_frame
	var r := _new_result()
	var t := 0.0
	while ball.holder != player and t < 5.0:
		var to_ball := Vector2(ball.position.x - player.global_position.x, ball.position.z - player.global_position.z)
		player.move_input = to_ball.normalized()
		await physics_frame
		t += TICK
	r.pickup = t
	# Then carry it on in the same direction for a bit.
	await _drive(r, 1.5, player.move_input, false, 0.0)
	return r


func _new_result() -> Dictionary:
	return {"touch": 0, "contact": [], "early": 0, "pass_frames": 0, "pass_depth": 0.0,
			"bend_sum": 0.0, "bend_n": 0, "bend_peak": 0.0, "lead": 0.0, "far": 0.0,
			"jump": 0.0, "dropped": 0, "pickup": -1.0}


## Holds an input for `duration`, measuring once `measure_from` seconds in.
func _drive(r: Dictionary, duration: float, input: Vector2, sprint: bool, measure_from: float) -> void:
	player.move_input = input
	player.sprint_held = sprint
	var t := 0.0
	var log_start: int = dribble.touch_log.size()
	var prev := ball.position
	while t < duration:
		await physics_frame
		t += TICK
		var moved := ball.position - prev
		prev = ball.position
		if t < measure_from:
			log_start = dribble.touch_log.size()
			continue
		if ball.holder != player:
			r.dropped += 1
			continue
		r.jump = maxf(r.jump, moved.length() - ball.velocity.length() * TICK)
		var hips := Vector2(player.global_position.x, player.global_position.z)
		var rel := Vector2(ball.position.x, ball.position.z) - hips
		var facing := Vector2(sin(player.yaw), cos(player.yaw))
		r.lead = maxf(r.lead, rel.dot(facing))
		r.far = maxf(r.far, rel.length())
		var bend: float = dribble.bend_now
		r.bend_sum += bend
		r.bend_n += 1
		r.bend_peak = maxf(r.bend_peak, bend)
		var depth := _foot_depth()
		if depth > 0.0:
			r.pass_frames += 1
			r.pass_depth = maxf(r.pass_depth, depth)
	for i in range(log_start, dribble.touch_log.size()):
		var e: Dictionary = dribble.touch_log[i]
		if e.kind == "regular":
			r.touch += 1
			r.contact.append(e.error)
		else:
			r.early += 1


## How deep any foot is inside the ball (m), the foot modelled as a 3 cm
## capsule from the ankle through the toe joint to the toe tip.
func _foot_depth() -> float:
	var deepest := 0.0
	for f in feet:
		var ankle: Vector3 = skel.global_transform * skel.get_bone_global_pose(f[0]).origin
		var toe: Vector3 = skel.global_transform * skel.get_bone_global_pose(f[1]).origin
		var tip := toe + (toe - ankle).normalized() * 0.06
		for seg in [[ankle, toe], [toe, tip]]:
			var closest := Geometry3D.get_closest_point_to_segment(ball.position, seg[0], seg[1])
			deepest = maxf(deepest, ball.radius + 0.03 - closest.distance_to(ball.position))
	return deepest


func _merge(agg: Dictionary, r: Dictionary) -> void:
	if agg.is_empty():
		agg.merge(r, true)
		agg.contact = r.contact.duplicate()
		agg.pickups = [] if r.pickup < 0.0 else [r.pickup]
		return
	agg.touch += r.touch
	agg.contact.append_array(r.contact)
	agg.early += r.early
	agg.pass_frames += r.pass_frames
	agg.pass_depth = maxf(agg.pass_depth, r.pass_depth)
	agg.bend_sum += r.bend_sum
	agg.bend_n += r.bend_n
	agg.bend_peak = maxf(agg.bend_peak, r.bend_peak)
	agg.lead = maxf(agg.lead, r.lead)
	agg.far = maxf(agg.far, r.far)
	agg.jump = maxf(agg.jump, r.jump)
	agg.dropped += r.dropped
	if r.pickup >= 0.0:
		agg.pickups.append(r.pickup)


func _report(name: String, a: Dictionary) -> void:
	var contact := "-"
	if not a.contact.is_empty():
		var sorted: Array = a.contact.duplicate()
		sorted.sort()
		contact = "%4.1f / %4.1f" % [sorted[sorted.size() / 2] * 100.0, sorted[-1] * 100.0]
	var pickup := "-"
	if not a.pickups.is_empty():
		pickup = "%.2f" % a.pickups.max()
	print("%-16s %6d %13s %6d %4d/%4.1fcm %6.2f/%6.2f %5.2f %5.2f %6.2f %7s" % [name, a.touch, contact, a.early,
			a.pass_frames, a.pass_depth * 100.0, a.bend_sum / maxf(a.bend_n, 1), a.bend_peak, a.lead, a.far,
			a.jump * 100.0, pickup])
	if a.dropped > 0:
		failures.append("%s: held ball dropped for %d ticks" % [name, a.dropped])
	if a.far > 3.0:
		failures.append("%s: ball %.2f m away" % [name, a.far])
	if a.jump > 0.01:
		failures.append("%s: ball jumped %.1f cm" % [name, a.jump * 100.0])
	if not a.pickups.is_empty() and a.pickups.max() > 1.5 + 3.0 * 1.47 / 2.964:
		failures.append("%s: pickup took %.2f s" % [name, a.pickups.max()])
