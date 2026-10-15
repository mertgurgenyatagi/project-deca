@tool
extends EditorScenePostImport
## Post-import script for Mixamo clips exported "with root motion".
##
## Turns each clip into a seamless in-place loop named after its source file:
## the straight-line drift of the hips is removed (side sway and bob are kept),
## and the removed travel speed is stored as metadata so gameplay code can
## match playback rate to ground speed.
##
## Hips positions are stored in units of the source rig's hip height, so one
## Skeleton3D.motion_scale (the target's hip height) fits every clip.

const HIPS_BONE := "mixamorig_Hips"


func _post_import(scene: Node) -> Object:
	var player := scene.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var skeleton := scene.get_node_or_null("Skeleton3D") as Skeleton3D
	if player == null or skeleton == null:
		push_warning("mixamo_loop_import: no AnimationPlayer/Skeleton3D in %s" % get_source_file())
		return scene

	var clip_name := get_source_file().get_file().get_basename()
	var hips_height := skeleton.get_bone_rest(skeleton.find_bone(HIPS_BONE)).origin.y
	var hips_path := NodePath("%s:%s" % [scene.get_path_to(skeleton), HIPS_BONE])

	for lib_name in player.get_animation_library_list():
		var library := player.get_animation_library(lib_name)
		for anim_name in library.get_animation_list():
			var anim := library.get_animation(anim_name)
			anim.loop_mode = Animation.LOOP_LINEAR
			anim.set_meta(&"root_motion_speed", _remove_root_drift(anim, hips_path, hips_height))
			library.rename_animation(anim_name, clip_name)
	return scene


## Normalizes hips positions to unit hip height, removes their linear
## horizontal travel and returns its speed (hip heights per second).
func _remove_root_drift(anim: Animation, hips_path: NodePath, hips_height: float) -> float:
	var track := anim.find_track(hips_path, Animation.TYPE_POSITION_3D)
	if track == -1 or anim.track_get_key_count(track) < 2:
		return 0.0

	var last := anim.track_get_key_count(track) - 1
	var start_time := anim.track_get_key_time(track, 0)
	var duration := anim.track_get_key_time(track, last) - start_time
	for key in anim.track_get_key_count(track):
		anim.track_set_key_value(track, key, anim.track_get_key_value(track, key) / hips_height)
	var drift: Vector3 = anim.track_get_key_value(track, last) - anim.track_get_key_value(track, 0)
	drift.y = 0.0

	for key in anim.track_get_key_count(track):
		var t := (anim.track_get_key_time(track, key) - start_time) / duration
		var position: Vector3 = anim.track_get_key_value(track, key)
		anim.track_set_key_value(track, key, position - drift * t)
	return drift.length() / duration
