extends SceneTree
## Passing bench. Drives the player through its state (`move_input`,
## `sprint_held`, `pass_held`), never the keyboard, with the two stand-in
## teammates placed for each scenario. Each scenario runs from several start
## offsets, so the press lands at different stride phases, and reports:
## - exec: from the pass being decided to the foot meeting the ball (s),
##   median / worst
## - miss: gap between the ball and where the foot meets it, at contact (cm),
##   median / worst
## - to: who took the pass, against who should have (hits / runs)
## - arrive: from contact to the receiver taking it (s), and the ball's speed
##   as it got there (m/s); for a pass to nobody, how far it rolled (m)
## - overlap: frames with a foot inside the ball while it is set for the kick,
##   and the deepest (cm)
## - slip: planted-foot slip during the kick (m/s, 2 cm planted threshold)
## - jump: largest per-tick ball move beyond |v|·dt (cm), a teleport check
## First, the receiver choice itself is checked. Ends with PASS_OK or PASS_FAIL.

const TICK := 1.0 / 60.0
const OFFSETS := [0.0, 0.23, 0.47]
const RIGHT := Vector2(1, 0)
const LEFT := Vector2(-1, 0)
const DOWN := Vector2(0, 1)

var player: Player
var ball: Ball
var near: Player
var far: Player
var passing: Passing
var dribble: Dribble
var skel: Skeleton3D
var feet := []
var failures := []


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	player = main.get_node("Player")
	ball = main.get_node("Ball")
	near = main.get_node("Teammates/Near")
	far = main.get_node("Teammates/Far")
	passing = player.get_node("Passing")
	dribble = player.get_node("Dribble")
	skel = player.get_node("Model/Character/Skeleton3D")
	for side in ["Left", "Right"]:
		feet.append([skel.find_bone("mixamorig_%sFoot" % side), skel.find_bone("mixamorig_%sToeBase" % side)])
	player.read_input = false
	_run.call_deferred()


func _check(name: String, ok: bool, detail := "") -> void:
	print("%s  %s  %s" % ["ok  " if ok else "FAIL", name, detail])
	if not ok:
		failures.append(name)


func _run() -> void:
	_choice_checks()
	print()
	print("%-18s %13s %13s %8s %15s %12s %6s %6s %s" % ["scenario", "exec s", "miss cm", "to", "arrive", "overlap", "slip", "jump", "kick"])
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("only="):
			only = arg.substr(5)
	var verbose := "verbose" in OS.get_cmdline_user_args()
	for s in _scenarios():
		if only != "" and not s.name.contains(only):
			continue
		var runs := []
		for offset in OFFSETS:
			var r: Dictionary = await _scenario(s, offset)
			runs.append(r)
			if verbose:
				print("   offset %.2f: exec %.2f miss %.1f cm to %s first %s strike %.1f moving %.1f stride %s overlap %d/%.1fcm slip %.2f" % [offset,
						r.exec, r.miss * 100.0, r.to, r.first, r.speed, r.contact_speed, r.in_stride, r.overlap, r.depth * 100.0, r.slip_sum / maxf(r.slip_n, 1)])
		_report(s, runs)
	print("PASS_OK" if failures.is_empty() else "PASS_FAIL  " + ", ".join(failures))
	quit()


# --- Receiver choice ----------------------------------------------------------

func _choice_checks() -> void:
	var a := Node.new()
	var b := Node.new()
	var c := Node.new()
	a.name = "a"
	b.name = "b"
	c.name = "c"
	var pick := func(power: float, mates: Array, aim := RIGHT) -> String:
		var chosen: Node = Passing.choose_target(Vector2.ZERO, aim, power, mates, 60.0)
		return "none" if chosen == null else str(chosen.name)
	var one := [[a, Vector2(10, 1)]]
	_check("one in the cone always gets it", pick.call(0.0, one) == "a" and pick.call(1.0, one) == "a")
	var two := [[b, Vector2(14, -3)], [a, Vector2(7, -3)]]
	_check("two: under 2/3 goes to the top-ranked", pick.call(0.6, two) == "a", pick.call(0.6, two))
	_check("two: over 2/3 goes to the second", pick.call(0.7, two) == "b", pick.call(0.7, two))
	var three := [[c, Vector2(20, 0)], [a, Vector2(6, 0)], [b, Vector2(12, 0)]]
	_check("three: under 1/2 to the first", pick.call(0.49, three) == "a", pick.call(0.49, three))
	_check("three: 1/2 to 5/6 to the second", pick.call(0.51, three) == "b" and pick.call(0.83, three) == "b")
	_check("three: over 5/6 to the third", pick.call(0.84, three) == "c" and pick.call(1.0, three) == "c")
	var edge := [[a, Vector2.from_angle(deg_to_rad(29.0)) * 8.0], [b, Vector2.from_angle(deg_to_rad(31.0)) * 8.0]]
	_check("cone: 29 degrees in, 31 out", pick.call(0.0, edge) == "a" and pick.call(1.0, edge) == "a")
	# Off the centre line counts squared: a far mate on the line outranks a
	# near one 3 m off it (-10 against -9 - 5.8).
	var ranked := [[a, Vector2(5, 3)], [b, Vector2(10, 0)]]
	_check("ranking: off-line distance squared", pick.call(0.0, ranked) == "b", pick.call(0.0, ranked))
	_check("nobody in the cone", pick.call(0.5, [[a, Vector2(-5, 0)]]) == "none")
	a.free()
	b.free()
	c.free()


# --- Scenarios ----------------------------------------------------------------

## Each scenario: a lead-in [seconds, keys, sprint] with the ball, then the
## pass: keys held to aim, bar strength, and where the teammates stand
## relative to the player as the button goes down ("ahead": near 7 m along
## the aim and 3 m to its right, far 14 m; "none": behind, out of the cone).
func _scenarios() -> Array:
	return [
		{"name": "stand near", "lead": [0.0, Vector2.ZERO, false], "aim": RIGHT, "power": 0.3, "mates": "ahead", "expect": "near"},
		{"name": "stand far", "lead": [0.0, Vector2.ZERO, false], "aim": RIGHT, "power": 0.9, "mates": "ahead", "expect": "far"},
		{"name": "jog ahead", "lead": [1.5, RIGHT, false], "aim": RIGHT, "power": 0.3, "mates": "ahead", "expect": "near"},
		{"name": "jog 90", "lead": [1.5, RIGHT, false], "aim": DOWN, "power": 0.3, "mates": "ahead", "expect": "near"},
		{"name": "jog back", "lead": [1.5, RIGHT, false], "aim": LEFT, "power": 0.3, "mates": "ahead", "expect": "near"},
		{"name": "sprint ahead", "lead": [2.0, RIGHT, true], "aim": RIGHT, "power": 0.3, "mates": "ahead", "expect": "near", "sprint": true},
		{"name": "sprint 90", "lead": [2.0, RIGHT, true], "aim": DOWN, "power": 0.9, "mates": "ahead", "expect": "far", "sprint": true},
		{"name": "nobody, empty", "lead": [0.0, Vector2.ZERO, false], "aim": RIGHT, "power": 0.0, "mates": "none", "expect": "none"},
		{"name": "nobody, full", "lead": [0.0, Vector2.ZERO, false], "aim": RIGHT, "power": 1.0, "mates": "none", "expect": "none"},
		{"name": "first time back", "first_time": 0.0, "expect": "near"},
		{"name": "first time 45", "first_time": 45.0, "expect": "far"},
		{"name": "first time 90", "first_time": 90.0, "expect": "far"},
		{"name": "give and go", "give_and_go": true, "expect": "player"},
	]


func _scenario(s: Dictionary, offset: float) -> Dictionary:
	if s.has("first_time"):
		return await _first_time(s, offset)
	if s.has("give_and_go"):
		return await _give_and_go(offset)
	var r := _new_result()
	await _start_holding(Vector2.ZERO, RIGHT)
	for i in int(offset / TICK):
		await physics_frame
	await _hold(s.lead[0], s.lead[1], s.lead[2], r)
	var at := _hips(player)
	var aim: Vector2 = s.aim
	_place_mates(at, aim, s.mates)
	await _press(aim, s.power, s.get("sprint", false), r)
	await _follow(r)
	return r


## Without the ball, the player has decided a pass (aimed at a mate placed
## `angle` degrees off straight back) as Near passes to it; it should be
## struck first time where it can be.
func _first_time(s: Dictionary, offset: float) -> Dictionary:
	var r := _new_result()
	_reset(player, Vector2.ZERO, RIGHT)
	var from := Vector2(8, -3)
	_reset(near, from, -from)
	var back := from.normalized()
	var aim := back.rotated(deg_to_rad(s.first_time))
	_reset(far, aim * 9.0 if s.first_time > 0.0 else Vector2(-12, 8), -aim)
	ball.place(Vector3(from.x + 0.4, 0, from.y))
	_reset_ball_state()
	for i in 20 + int(offset / TICK):
		await physics_frame
	near.get_node("Passing").pass_to(player)
	await _press(aim, 0.2, false, r, false)
	await _follow(r)
	return r


## Pass to Near, who keeps it for its hold time and plays it back.
func _give_and_go(offset: float) -> Dictionary:
	var r := _new_result()
	await _start_holding(Vector2.ZERO, RIGHT)
	for i in int(offset / TICK):
		await physics_frame
	_place_mates(Vector2.ZERO, RIGHT, "ahead")
	await _press(RIGHT, 0.3, false, r)
	player.move_input = Vector2.ZERO
	var t := 0.0
	while ball.holder != player and t < 10.0:
		await physics_frame
		t += TICK
	r.to = "player" if ball.holder == player else "none"
	r.arrive = t
	return r


## Presses the pass button for `power` of a full bar with the keys on `aim`,
## lets go, and runs until the foot meets the ball (or 4 s), measuring.
func _press(aim: Vector2, power: float, sprint: bool, r: Dictionary, keys_move := true) -> void:
	var kicks := passing.kick_log.size()
	player.move_input = aim
	player.sprint_held = sprint
	player.pass_held = true
	var ticks := maxi(roundi(power * passing.charge_time / TICK), 1)
	for i in ticks:
		await physics_frame
		_measure(r)
	player.pass_held = false
	# The keys stay on the aim until the ball goes (a kick ignores them
	# anyway), or, waiting for a ball (`keys_move` off), until the pass is
	# decided: then the player stands and waits.
	var t := 0.0
	while passing.kick_log.size() == kicks and t < 6.0:
		await physics_frame
		t += TICK
		if not keys_move and t > passing.lock_delay + TICK:
			player.move_input = Vector2.ZERO
		_measure(r)
	if passing.kick_log.size() == kicks:
		r.kicked = false
		return
	r.exec = t - passing.lock_delay
	r.contact_speed = player.ground_velocity.length()
	r.in_stride = player._kick_layer > 0.5
	var kick: Dictionary = passing.kick_log[-1]
	r.miss = kick.error
	r.first = kick.first_time
	r.speed = kick.speed


## After the kick: who takes the ball, how soon, how fast it is going.
func _follow(r: Dictionary) -> void:
	player.move_input = Vector2.ZERO
	var start := ball.position
	var t := 0.0
	var last_speed := ball.velocity.length()
	while t < 8.0:
		await physics_frame
		t += TICK
		_measure(r)
		if ball.holder != null and ball.holder != player:
			break
		if ball.holder == null and ball.velocity.length() == 0.0 and t > 0.5:
			break
		last_speed = ball.velocity.length()
	r.to = _who(ball.holder)
	r.arrive = t
	r.arrive_speed = last_speed
	r.rolled = Vector2(ball.position.x - start.x, ball.position.z - start.z).length()


func _hold(duration: float, input: Vector2, sprint: bool, r: Dictionary) -> void:
	player.move_input = input
	player.sprint_held = sprint
	var t := 0.0
	while t < duration:
		await physics_frame
		t += TICK
		_measure(r)


var _last_toes := {}
var _last_ball := Vector3.INF


## Per tick: ball teleport check, foot inside the ball while the player is
## setting it for a kick, planted-foot slip during the kick.
func _measure(r: Dictionary) -> void:
	if _last_ball != Vector3.INF:
		var moved := ball.position - _last_ball
		moved.y = 0.0
		r.jump = maxf(r.jump, moved.length() - ball.velocity.length() * TICK)
	_last_ball = ball.position
	var kicking := player.action == Player.Action.KICK
	if kicking and "trace" in OS.get_cmdline_user_args():
		var spot: Vector3 = dribble.strike_point(_hips(player), player.kick_yaw)
		var rel := Vector2(ball.position.x - player.global_position.x, ball.position.z - player.global_position.z)
		var toes := ""
		for f in feet:
			var toe: Vector3 = skel.global_transform * skel.get_bone_global_pose(f[1]).origin
			var slide := 0.0
			if _last_toes.has(f[1]):
				slide = Vector2(toe.x - _last_toes[f[1]].x, toe.z - _last_toes[f[1]].z).length() / TICK
			toes += "  toe y %.3f v %.2f" % [toe.y, slide]
		print("      speed %.2f yaw err %5.1f  ball gap %.2f  ball v %.2f  ball rel (%.2f, %.2f) swing %s ready %s%s" % [
				player.ground_velocity.length(), rad_to_deg(angle_difference(player.yaw, player.kick_yaw)),
				Vector2(ball.position.x - spot.x, ball.position.z - spot.z).length(), ball.velocity.length(),
				rel.x, rel.y, player.kick_swinging, player.kick_ready(), toes + "  plan %s  acc %s holder %s first %s  due %s meets %s next %.2f phase %.2f" % [str(dribble._target()) if ball.holder == player else "-", ball.acceleration.snapped(Vector3(0.1,0.1,0.1)), ball.holder != null, dribble._first_time, dribble.kick_touch_due(), dribble.ball_meets_foot(passing.run_reach), dribble._next_touch_phase, dribble._phase]])
	if kicking and ball.holder == player:
		var depth := _foot_depth()
		if depth > 0.0 and not player.kick_swinging:
			r.overlap += 1
			r.depth = maxf(r.depth, depth)
	for f in feet:
		var toe: Vector3 = skel.global_transform * skel.get_bone_global_pose(f[1]).origin
		# The kicking (right) foot starts its swing low: that is not a slide.
		var swinging_foot: bool = player.kick_swinging and f == feet[player.kick_foot]
		if kicking and not swinging_foot and _last_toes.has(f[1]) and toe.y < 0.02 and _last_toes[f[1]].y < 0.02:
			r.slip_sum += Vector2(toe.x - _last_toes[f[1]].x, toe.z - _last_toes[f[1]].z).length() / TICK
			r.slip_n += 1
		_last_toes[f[1]] = toe


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


# --- Setup ----------------------------------------------------------------------

func _start_holding(at: Vector2, facing: Vector2) -> void:
	_reset(player, at, facing)
	_place_mates(Vector2(200, 200), RIGHT, "ahead")
	ball.place(Vector3(at.x + 0.35, 0, at.y - 0.08))
	_reset_ball_state()
	for i in 30:
		await physics_frame


func _reset_ball_state() -> void:
	for p in [player, near, far]:
		p.get_node("Dribble").reset_for_test()
		p.get_node("Passing").reset_for_test()
	_last_ball = Vector3.INF
	_last_toes = {}


func _reset(p: Player, at: Vector2, facing: Vector2) -> void:
	p.move_input = Vector2.ZERO
	p.sprint_held = false
	p.pass_held = false
	p.global_position = Vector3(at.x, 0, at.y)
	p.velocity = Vector3.ZERO
	p._ground = Vector2.ZERO
	p._action = 0
	p._kick_time = -1.0
	p._kick_layer = 0.0
	for clip in p._one_shots:
		clip.playing = false
		clip.fade = 0.0
	p.face(atan2(facing.x, facing.y))
	p.reset_physics_interpolation()
	var ai := p.get_node_or_null("TeammateAI")
	if ai:
		ai._held_for = 0.0


func _place_mates(at: Vector2, aim: Vector2, how: String) -> void:
	var right := Vector2(aim.y, -aim.x)
	if how == "ahead":
		# On either side of the aim, so neither stands in the way of a pass to the other.
		_reset(near, at + aim * 7.0 + right * 2.5, -aim)
		_reset(far, at + aim * 14.0 - right * 2.5, -aim)
	else:
		_reset(near, at - aim * 10.0 + right * 5.0, aim)
		_reset(far, at - aim * 10.0 - right * 5.0, aim)


func _who(node: Node) -> String:
	if node == near:
		return "near"
	if node == far:
		return "far"
	if node == player:
		return "player"
	return "none"


func _hips(p: Node3D) -> Vector2:
	return Vector2(p.global_position.x, p.global_position.z)


# --- Results --------------------------------------------------------------------

func _new_result() -> Dictionary:
	return {"kicked": true, "exec": 0.0, "contact_speed": 0.0, "in_stride": false, "miss": 0.0, "first": false, "speed": 0.0, "to": "none",
			"arrive": 0.0, "arrive_speed": 0.0, "rolled": 0.0, "overlap": 0, "depth": 0.0,
			"slip_sum": 0.0, "slip_n": 0, "jump": 0.0}


func _report(s: Dictionary, runs: Array) -> void:
	var execs := []
	var misses := []
	var hits := 0
	var overlap := 0
	var depth := 0.0
	var slip_sum := 0.0
	var slip_n := 0
	var jump := 0.0
	var arrive := []
	var speeds := []
	var rolled := []
	var firsts := 0
	var kick_speeds := []
	var contact_speeds := []
	var strides := 0
	for r in runs:
		if not r.kicked:
			failures.append("%s: no kick" % s.name)
			continue
		execs.append(r.exec)
		misses.append(r.miss)
		if r.to == s.expect:
			hits += 1
		overlap += r.overlap
		depth = maxf(depth, r.depth)
		slip_sum += r.slip_sum
		slip_n += r.slip_n
		jump = maxf(jump, r.jump)
		arrive.append(r.arrive)
		speeds.append(r.arrive_speed)
		rolled.append(r.rolled)
		kick_speeds.append(r.speed)
		contact_speeds.append(r.contact_speed)
		if r.in_stride:
			strides += 1
		if r.first:
			firsts += 1
	if execs.is_empty():
		print("%-18s no kick" % s.name)
		return
	execs.sort()
	misses.sort()
	var arrival := "rolled %4.1f m" % _avg(rolled) if s.expect == "none" else "%4.2fs %4.1fm/s" % [_avg(arrive), _avg(speeds)]
	var kind := ""
	if s.has("first_time"):
		kind = "first time %d/%d" % [firsts, runs.size()]
	print("%-18s %5.2f / %5.2f %5.1f / %5.1f %4d/%d %15s %4d/%4.1fcm %6.2f %6.2f %s strike %4.1fm/s, moving %3.1fm/s, %d/%d in stride" % [s.name, execs[execs.size() / 2], execs[-1],
			misses[misses.size() / 2] * 100.0, misses[-1] * 100.0, hits, runs.size(), arrival, overlap, depth * 100.0,
			slip_sum / maxf(slip_n, 1), jump * 100.0, kind, _avg(kick_speeds), _avg(contact_speeds), strides, runs.size()])
	if hits < runs.size():
		failures.append("%s: went to the wrong player" % s.name)
	if jump > 0.01:
		failures.append("%s: ball jumped %.1f cm" % [s.name, jump * 100.0])
	if misses[-1] > 0.15:
		failures.append("%s: foot missed the ball by %.0f cm" % [s.name, misses[-1] * 100.0])


func _avg(values: Array) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total / maxf(values.size(), 1)
