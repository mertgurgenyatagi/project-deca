extends SceneTree
## Samples the turn clip on the real character: hips ground position, facing yaw,
## hips speed, and toe heights over time.

func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null

var pose_pos := {}
var pose_rot := {}

func _global(sk: Skeleton3D, b: int) -> Transform3D:
	var rest := sk.get_bone_rest(b)
	var local := Transform3D(Basis(pose_rot.get(b, rest.basis.get_rotation_quaternion())), pose_pos.get(b, rest.origin))
	var parent := sk.get_bone_parent(b)
	return local if parent < 0 else _global(sk, parent) * local

func _initialize() -> void:
	var src: Node = load(OS.get_cmdline_user_args()[0]).instantiate()
	var ap: AnimationPlayer = _find(src, "AnimationPlayer")
	var anim: Animation = ap.get_animation(ap.get_animation_list()[0])
	var src_sk: Skeleton3D = _find(src, "Skeleton3D")
	print("anim ", ap.get_animation_list(), " len=", anim.length, " tracks=", anim.get_track_count(), " src hips rest ", src_sk.get_bone_rest(0).origin)

	var ch: Node = load("res://assets/characters/player/character.fbx").instantiate()
	root.add_child(ch)
	var sk: Skeleton3D = _find(ch, "Skeleton3D")
	var hips := sk.find_bone("mixamorig_Hips")
	var lt := sk.find_bone("mixamorig_LeftToeBase")
	var rt := sk.find_bone("mixamorig_RightToeBase")
	var prev := Vector3.INF
	var t := 0.0
	var dt := 1.0 / 30.0
	while t <= anim.length + 0.001:
		for tr in anim.get_track_count():
			var path := str(anim.track_get_path(tr))
			var bone := sk.find_bone(path.get_slice(":", 1))
			if bone < 0:
				continue
			match anim.track_get_type(tr):
				Animation.TYPE_POSITION_3D:
					pose_pos[bone] = anim.position_track_interpolate(tr, t)
				Animation.TYPE_ROTATION_3D:
					pose_rot[bone] = anim.rotation_track_interpolate(tr, t)
		var hp := _global(sk, hips)
		var fwd := hp.basis * Vector3(0, 0, 1)
		var yaw := rad_to_deg(atan2(fwd.x, fwd.z))
		var spd := 0.0 if prev == Vector3.INF else Vector2(hp.origin.x - prev.x, hp.origin.z - prev.z).length() / dt
		var vel := Vector2.ZERO if prev == Vector3.INF else Vector2(hp.origin.x - prev.x, hp.origin.z - prev.z) / dt
		prev = hp.origin
		print("f%02d t=%.3f hips=(%.2f, %.2f, %.2f) yaw=%6.1f speed=%.2f vel=(%.2f,%.2f)  toeL=%.3f toeR=%.3f" % [
			roundi(t * 30), t, hp.origin.x, hp.origin.y, hp.origin.z, yaw, spd, vel.x, vel.y,
			_global(sk, lt).origin.y, _global(sk, rt).origin.y])
		t += dt
	quit()
