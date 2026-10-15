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
	return scene


func _center_hips(anim: Animation, hips_path: NodePath, hips_height: float) -> void:
	var track := anim.find_track(hips_path, Animation.TYPE_POSITION_3D)
	if track == -1 or anim.track_get_key_count(track) == 0:
		push_warning("mixamo_kick_import: no hips position track in %s" % get_source_file())
		return
	var start: Vector3 = anim.track_get_key_value(track, 0)
	for key in anim.track_get_key_count(track):
		var p: Vector3 = anim.track_get_key_value(track, key)
		anim.track_set_key_value(track, key, Vector3(p.x - start.x, p.y, p.z - start.z) / hips_height)
