extends SceneTree
func _initialize() -> void:
	for path in ["res://assets/animations/locomotion/sprint.fbx", "res://assets/animations/turns/turn_180.fbx", "res://assets/animations/starts/sprint_start.fbx"]:
		var lib: AnimationLibrary = load(path)
		for n in lib.get_animation_list():
			var a: Animation = lib.get_animation(n)
			print(n, " len=", a.length, " loop=", a.loop_mode, " tracks=", a.get_track_count())
			for m in a.get_meta_list():
				var v = a.get_meta(m)
				if v is PackedFloat32Array:
					var parts := []
					for i in range(0, v.size(), 4):
						parts.append("%.2f" % v[i])
					print("  ", m, " (every 4th) ", ", ".join(parts))
				else:
					print("  ", m, " = ", v)
			var ht := a.find_track(NodePath("Skeleton3D:mixamorig_Hips"), Animation.TYPE_POSITION_3D)
			print("  hips pos first ", a.track_get_key_value(ht, 0), " key count ", a.track_get_key_count(ht))
	quit()
