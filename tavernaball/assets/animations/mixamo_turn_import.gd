@tool
extends EditorScenePostImport
## Post-import script for Mixamo one-shot clips (turns, starts) exported
## "with root motion".
##
## Strips the clip's own facing rotation and its travel along the line of
## motion from the hips, leaving an in-place pose that faces +Z like the
## locomotion clips, so it can be crossfaded with them. Sideways hip shift
## (e.g. swinging over the pivot foot) stays in the pose. What was stripped is
## stored as metadata, sampled at SAMPLE_FPS, for gameplay code to drive the clip:
## - turn_times: clip time of each sample.
## - turn_distance: hips travel along the clip's line of motion up to each
##   sample (in hip heights), counting travel in either direction, so it
##   never decreases.
## - turn_progress: facing turned so far, 0 at the start to 1 at the end.
## - turn_stop_distance, turn_total_distance: distance at the stop (where the
##   hips first come to rest after having got moving, or the end if they never
##   do) and at the end.
## - turn_angle: total facing change (radians, signed around +Y).
##
## Hips positions are stored in units of the source rig's hip height, so one
## Skeleton3D.motion_scale (the target's hip height) fits every clip.

const HIPS_BONE := "mixamorig_Hips"
const SAMPLE_FPS := 30.0
## Facing is the hips yaw averaged over this many samples either side, which
## cancels the side-to-side twist of each stride.
const FACING_SMOOTHING := 7
## Hips speed along the line of motion (hip heights/s) below which they count as stopped.
const STOP_SPEED := 0.15


func _post_import(scene: Node) -> Object:
	var player := scene.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var skeleton := scene.get_node_or_null("Skeleton3D") as Skeleton3D
	if player == null or skeleton == null:
		push_warning("mixamo_turn_import: no AnimationPlayer/Skeleton3D in %s" % get_source_file())
		return scene

	var clip_name := get_source_file().get_file().get_basename()
	var hips_height := skeleton.get_bone_rest(skeleton.find_bone(HIPS_BONE)).origin.y
	var hips_path := NodePath("%s:%s" % [scene.get_path_to(skeleton), HIPS_BONE])

	for lib_name in player.get_animation_library_list():
		var library := player.get_animation_library(lib_name)
		for anim_name in library.get_animation_list():
			var anim := library.get_animation(anim_name)
			anim.loop_mode = Animation.LOOP_NONE
			_extract_turn(anim, hips_path, hips_height)
			library.rename_animation(anim_name, clip_name)
	return scene


func _extract_turn(anim: Animation, hips_path: NodePath, hips_height: float) -> void:
	var pos_track := anim.find_track(hips_path, Animation.TYPE_POSITION_3D)
	var rot_track := anim.find_track(hips_path, Animation.TYPE_ROTATION_3D)
	if pos_track == -1 or rot_track == -1:
		push_warning("mixamo_turn_import: no hips tracks in %s" % get_source_file())
		return

	var count := roundi(anim.length * SAMPLE_FPS) + 1
	var times := PackedFloat32Array()
	var positions := PackedVector3Array()
	var rotations: Array[Quaternion] = []
	var yaws := PackedFloat32Array()
	for i in count:
		var t := minf(i / SAMPLE_FPS, anim.length)
		var rotation := anim.rotation_track_interpolate(rot_track, t)
		var forward := Basis(rotation) * Vector3.BACK
		var yaw := atan2(forward.x, forward.z)
		if i > 0:
			yaw = yaws[i - 1] + angle_difference(yaws[i - 1], yaw)
		times.append(t)
		positions.append(anim.position_track_interpolate(pos_track, t) / hips_height)
		rotations.append(rotation)
		yaws.append(yaw)

	var facing := PackedFloat32Array()
	for i in count:
		var total := 0.0
		for j in range(i - FACING_SMOOTHING, i + FACING_SMOOTHING + 1):
			total += yaws[clampi(j, 0, count - 1)]
		facing.append(total / (2 * FACING_SMOOTHING + 1))

	# Line of motion: towards the furthest point the hips reach from the start.
	var start := Vector2(positions[0].x, positions[0].z)
	var furthest := start
	for p in positions:
		if start.distance_to(Vector2(p.x, p.z)) > start.distance_to(furthest):
			furthest = Vector2(p.x, p.z)
	var axis := (furthest - start).normalized()
	var along := PackedFloat32Array()
	for i in count:
		along.append(Vector2(positions[i].x, positions[i].z).dot(axis))

	# The stop: where the hips first come to rest after having got moving.
	var stop := count - 1
	var moving := false
	for i in count - 1:
		var speed := absf(along[i + 1] - along[i]) * SAMPLE_FPS
		if speed > 3.0 * STOP_SPEED:
			moving = true
		elif moving and speed < STOP_SPEED:
			stop = i
			break

	var distance := PackedFloat32Array()
	var progress := PackedFloat32Array()
	var turn_angle := facing[count - 1] - facing[0]
	for i in count:
		var d := 0.0 if i == 0 else distance[i - 1] + absf(along[i] - along[i - 1])
		var p := clampf((facing[i] - facing[0]) / turn_angle, 0.0, 1.0)
		if i > 0:
			p = maxf(p, progress[i - 1])
		distance.append(d)
		progress.append(p)
	progress[count - 1] = 1.0

	# Rewrite the hips in place, facing +Z, keeping their height and sideways shift.
	for key in range(anim.track_get_key_count(pos_track) - 1, -1, -1):
		anim.track_remove_key(pos_track, key)
	for key in range(anim.track_get_key_count(rot_track) - 1, -1, -1):
		anim.track_remove_key(rot_track, key)
	for i in count:
		var side := Vector2(positions[i].x, positions[i].z) - axis * along[i]
		var local := Vector3(side.x, 0.0, side.y).rotated(Vector3.UP, -facing[i])
		anim.position_track_insert_key(pos_track, times[i], Vector3(local.x, positions[i].y, local.z))
		anim.rotation_track_insert_key(rot_track, times[i], Quaternion(Vector3.UP, -facing[i]) * rotations[i])

	anim.set_meta(&"turn_times", times)
	anim.set_meta(&"turn_distance", distance)
	anim.set_meta(&"turn_progress", progress)
	anim.set_meta(&"turn_stop_distance", distance[stop])
	anim.set_meta(&"turn_total_distance", distance[count - 1])
	anim.set_meta(&"turn_angle", turn_angle)
