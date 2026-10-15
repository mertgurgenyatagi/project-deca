extends SceneTree
## Drives the player with scripted input at fixed 60 fps and measures:
##  - planted-foot slip speed (m/s) in world space (0 = perfectly planted)
##  - pops: largest per-frame bone *acceleration* in model space
##    (|p[n+1] - 2 p[n] + p[n-1]|, so fast-but-smooth motion doesn't count)

const SCRIPT := [
	[0.5, "move_right", "start + jog right"],
	[2.0, "move_right+sprint", "jog -> sprint"],
	[3.5, "move_right+sprint", "steady sprint (baseline)"],
	[5.0, "move_right", "sprint -> jog"],
	[6.5, "move_right+sprint", "sprint again"],
	[8.5, "move_left+sprint", "sprint turnback"],
	[11.0, "move_up+sprint", "90 deg sprint turn"],
	[12.5, "", "stop from sprint"],
	[14.0, "", "end"],
]
const TRACE_WINDOWS := []

var player: CharacterBody3D
var skel: Skeleton3D
var tree: AnimationTree
var t := 0.0
var frame := 0
var phase := -1
var prev_feet := {}
var p1 := PackedVector3Array()
var p2 := PackedVector3Array()
var stats := {}
var toes := []


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	# The stand-in teammates are for trying passes; they would only get in the way here.
	main.get_node("Teammates").free()
	root.add_child(main)
	# Movement is measured without the ball (holding it gates turns).
	main.get_node("Ball").free()
	player = main.get_node("Player")
	skel = player.get_node("Model/Character/Skeleton3D")
	tree = player.get_node("AnimationTree")
	toes = [skel.find_bone("mixamorig_LeftToeBase"), skel.find_bone("mixamorig_RightToeBase")]


func _set_phase(i: int) -> void:
	for a in ["move_left", "move_right", "move_up", "move_down", "sprint"]:
		Input.action_release(a)
	for a in SCRIPT[i][1].split("+", false):
		Input.action_press(a)
	phase = i
	stats[i] = {"slip_sum": 0.0, "slip_n": 0, "slip_max": 0.0, "slip_t": 0.0, "pop_max": 0.0, "pop_bone": "", "pop_t": 0.0}


func _process(delta: float) -> bool:
	t += delta
	frame += 1
	var next := phase + 1
	if next < SCRIPT.size() and t >= SCRIPT[next][0]:
		if SCRIPT[next][2] == "end":
			_report()
			return true
		_set_phase(next)
	if phase < 0 or frame < 3:
		return false
	var s: Dictionary = stats[phase]

	var slips := []
	for b in toes:
		var p: Vector3 = skel.global_transform * skel.get_bone_global_pose(b).origin
		if prev_feet.has(b):
			var q: Vector3 = prev_feet[b]
			if p.y < 0.045 and q.y < 0.045:
				var slip := Vector2(p.x - q.x, p.z - q.z).length() / delta
				slips.append(snappedf(slip, 0.01))
				s.slip_sum += slip
				s.slip_n += 1
				if slip > s.slip_max:
					s.slip_max = slip
					s.slip_t = t
		prev_feet[b] = p

	var pose := PackedVector3Array()
	pose.resize(skel.get_bone_count())
	for i in skel.get_bone_count():
		pose[i] = skel.get_bone_global_pose(i).origin
	var frame_pop := 0.0
	var frame_pop_bone := ""
	if p2.size() == pose.size():
		for i in pose.size():
			var a := (pose[i] - 2.0 * p1[i] + p2[i]).length()
			if a > frame_pop:
				frame_pop = a
				frame_pop_bone = skel.get_bone_name(i)
		if frame_pop > s.pop_max:
			s.pop_max = frame_pop
			s.pop_bone = frame_pop_bone
			s.pop_t = t
	p2 = p1
	p1 = pose

	for w in TRACE_WINDOWS:
		if t >= w[0] and t <= w[1]:
			var v := player.get_real_velocity()
			print("  t=%.3f speed=%.2f blend=%.2f rate=%.2f yaw=%.0f pop=%.4f (%s) slips=%s" % [t, Vector2(v.x, v.z).length(),
				tree.get(&"parameters/Locomotion/blend_amount"), tree.get(&"parameters/JogRate/scale"),
				rad_to_deg(player.get_node("Model").rotation.y), frame_pop, frame_pop_bone, slips])
	return false


func _report() -> void:
	for i in stats:
		var s: Dictionary = stats[i]
		print("%-24s slip avg %.3f max %.3f m/s @%.2fs (%d samples) | worst pop %.4f m/frame² (%s @ %.2fs)" % [
			SCRIPT[i][2], s.slip_sum / maxf(s.slip_n, 1), s.slip_max, s.slip_t, s.slip_n, s.pop_max, s.pop_bone, s.pop_t])
