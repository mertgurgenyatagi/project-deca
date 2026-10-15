extends SceneTree
## Prints the gait loops' toe paths over one stride (model space, metres):
## forward reach (z), side (x), height (y), and the toe's ground speed as a
## multiple of body speed. Used to place dribble touches.


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var player = main.get_node("Player")
	await process_frame
	var skel: Skeleton3D = player.get_node("Model/Character/Skeleton3D")
	print("skeleton global xform: ", skel.global_transform)
	for gait in [["jog", player._jog_feet, player._jog_cycle], ["sprint", player._sprint_feet, player._sprint_cycle]]:
		var feet: Array = gait[1]
		var cycle: float = gait[2]
		var n := feet.size()
		print("== %s  cycle %.3f m" % [gait[0], cycle])
		print("phase |  L toe x     y     z   gs  |  R toe x     y     z   gs")
		for i in n:
			var line := "%.2f " % (float(i) / n)
			for toe_idx in [1, 3]:
				var p: Vector3 = feet[i][toe_idx]
				var q: Vector3 = feet[(i + 1) % n][toe_idx]
				# Ground speed of the toe relative to body speed: body moves
				# cycle/n per sample forward.
				var gs := ((q.z - p.z) + cycle / n) / (cycle / n)
				line += "| %6.3f %5.3f %6.3f %5.2f " % [p.x, p.y, p.z, gs]
			print(line)
	quit()
