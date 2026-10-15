@tool
extends EditorScenePostImport
## Post-import script for Mixamo kicks done on the spot (exported "with root
## motion", though the hips hardly travel).
##
## Unlike a turn, a kick keeps its hips rotation: the hips swinging into the
## kick is part of its look. The hips are only moved so that they start over
## the origin, which puts the clip in place, facing +Z like the locomotion
## clips. Hips positions are stored in units of the source rig's hip height,
## so one Skeleton3D.motion_scale (the target's hip height) fits every clip.

const HIPS_BONE := "mixamorig_Hips"


func _post_import(scene: Node) -> Object:
	var player := scene.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var skeleton := scene.get_node_or_null("Skeleton3D") as Skeleton3D
	if player == null or skeleton == null:
		push_warning("mixamo_kick_import: no AnimationPlayer/Skeleton3D in %s" % get_source_file())
		return scene

	var clip_name := get_source_file().get_file().get_basename()
	var hips_height := skeleton.get_bone_rest(skeleton.find_bone(HIPS_BONE)).origin.y
	var hips_path := NodePath("%s:%s" % [scene.get_path_to(skeleton), HIPS_BONE])

	for lib_name in player.get_animation_library_list():
		var library := player.get_animation_library(lib_name)
		for anim_name in library.get_animation_list():
			var anim := library.get_animation(anim_name)
			anim.loop_mode = Animation.LOOP_NONE
			_center_hips(anim, hips_path, hips_height)
			library.rename_animation(anim_name, clip_name)
			library.add_animation(clip_name + "_mirror", _mirrored(anim, skeleton, str(scene.get_path_to(skeleton))))
	return scene


## The same kick with the other foot: every bone's pose reflected across the
## body's centre plane (x → −x) in skeleton space, left and right swapped.
## Reflecting global rotations, not local ones, keeps it right whatever the
## bones' own axes. Sampled at 30 fps.
func _mirrored(anim: Animation, skeleton: Skeleton3D, skeleton_path: String) -> Animation:
	var mirror := Animation.new()
	mirror.length = anim.length
	mirror.loop_mode = Animation.LOOP_NONE
	var bones := skeleton.get_bone_count()
	var rotation_tracks := []
	var twin := []
	for b in bones:
		var name := skeleton.get_bone_name(b)
		rotation_tracks.append(anim.find_track(NodePath("%s:%s" % [skeleton_path, name]), Animation.TYPE_ROTATION_3D))
		twin.append(skeleton.find_bone(name.replace("Left", "#").replace("Right", "Left").replace("#", "Right")))
	var out_tracks := []
	for b in bones:
		var track := mirror.add_track(Animation.TYPE_ROTATION_3D)
		mirror.track_set_path(track, NodePath("%s:%s" % [skeleton_path, skeleton.get_bone_name(b)]))
		out_tracks.append(track)
	var hips := skeleton.find_bone(HIPS_BONE)
	var hips_in := anim.find_track(NodePath("%s:%s" % [skeleton_path, HIPS_BONE]), Animation.TYPE_POSITION_3D)
	var hips_out := mirror.add_track(Animation.TYPE_POSITION_3D)
	mirror.track_set_path(hips_out, NodePath("%s:%s" % [skeleton_path, HIPS_BONE]))
	var flip := Basis.FLIP_X
	var count := roundi(anim.length * 30.0) + 1
	for i in count:
		var t := minf(i / 30.0, anim.length)
		# Global rotations of the clip's pose, parents before children.
		var global := []
		global.resize(bones)
		for b in bones:
			var local := skeleton.get_bone_rest(b).basis.get_rotation_quaternion()
			if rotation_tracks[b] != -1:
				local = anim.rotation_track_interpolate(rotation_tracks[b], t)
			var parent := skeleton.get_bone_parent(b)
			global[b] = Basis(local) if parent < 0 else global[parent] * Basis(local)
		# Each bone takes its twin's pose, reflected, then back to local.
		var reflected := []
		reflected.resize(bones)
		for b in bones:
			var source: int = twin[b] if twin[b] != -1 else b
			reflected[b] = flip * (global[source] as Basis) * flip
		for b in bones:
			var parent := skeleton.get_bone_parent(b)
			var local_basis: Basis = reflected[b] if parent < 0 else (reflected[parent] as Basis).inverse() * reflected[b]
			mirror.rotation_track_insert_key(out_tracks[b], t, local_basis.orthonormalized().get_rotation_quaternion())
		if hips_in != -1 and hips != -1:
			var p := anim.position_track_interpolate(hips_in, t)
			mirror.position_track_insert_key(hips_out, t, Vector3(-p.x, p.y, p.z))
	return mirror


func _center_hips(anim: Animation, hips_path: NodePath, hips_height: float) -> void:
	var track := anim.find_track(hips_path, Animation.TYPE_POSITION_3D)
	if track == -1 or anim.track_get_key_count(track) == 0:
		push_warning("mixamo_kick_import: no hips position track in %s" % get_source_file())
		return
	var start: Vector3 = anim.track_get_key_value(track, 0)
	for key in anim.track_get_key_count(track):
		var p: Vector3 = anim.track_get_key_value(track, key)
		anim.track_set_key_value(track, key, Vector3(p.x - start.x, p.y, p.z - start.z) / hips_height)
