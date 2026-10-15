extends SceneTree
## Repeated sprint starts from a standstill (all heading +X), with
## irregular rest times so idle phases differ. Reports foot slip and pops
## over the first WINDOW seconds of each start.

const TRIALS := 8
const WINDOW := 1.2

var player: CharacterBody3D
var skel: Skeleton3D
var toes := []
var t := 0.0
var dir := 1
var trial := -1
var moving := false
var next_event := 1.0
var trial_start := 0.0
var prev_feet := {}
var p1 := PackedVector3Array()
var p2 := PackedVector3Array()
var results := []
var cur := {}


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	player = main.get_node("Player")
	skel = player.get_node("Model/Character/Skeleton3D")
	toes = [skel.find_bone("mixamorig_LeftToeBase"), skel.find_bone("mixamorig_RightToeBase")]
	Input.action_press("sprint")


func _process(delta: float) -> bool:
	t += delta
	if t >= next_event:
		if moving:
			Input.action_release("move_right" if dir > 0 else "move_left")
			moving = false
			next_event = t + 1.3 + 0.111 * trial
		else:
			if trial >= 0:
				results.append(cur)
			trial += 1
			if trial >= TRIALS:
				_report()
				return true
			Input.action_press("move_right" if dir > 0 else "move_left")
			moving = true
			trial_start = t
			next_event = t + 2.0
			cur = {"slip_sum": 0.0, "slip_n": 0, "slip_max": 0.0, "pop_max": 0.0}

	var in_window := moving and t - trial_start <= WINDOW
	for b in toes:
		var p: Vector3 = skel.global_transform * skel.get_bone_global_pose(b).origin
		if prev_feet.has(b) and in_window:
			var q: Vector3 = prev_feet[b]
			if p.y < 0.045 and q.y < 0.045:
				var slip := Vector2(p.x - q.x, p.z - q.z).length() / delta
				cur.slip_sum += slip
				cur.slip_n += 1
				cur.slip_max = maxf(cur.slip_max, slip)
		prev_feet[b] = p
	var pose := PackedVector3Array()
	pose.resize(skel.get_bone_count())
	for i in skel.get_bone_count():
		pose[i] = skel.get_bone_global_pose(i).origin
	if p2.size() == pose.size() and in_window:
		for i in pose.size():
			cur.pop_max = maxf(cur.pop_max, (pose[i] - 2.0 * p1[i] + p2[i]).length())
	p2 = p1
	p1 = pose
	return false


func _report() -> void:
	var avg := 0.0
	var mx := 0.0
	var worst := 0.0
	var pop := 0.0
	for r in results:
		avg += r.slip_sum / maxf(r.slip_n, 1)
		mx += r.slip_max
		worst = maxf(worst, r.slip_max)
		pop = maxf(pop, r.pop_max)
	var n := results.size()
	print("BENCH starts=%d  slip avg %.3f  mean peak %.2f  worst peak %.2f m/s  worst pop %.4f" % [n, avg / n, mx / n, worst, pop])
