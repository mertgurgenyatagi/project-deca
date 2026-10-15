class_name IntentLean
extends SkeletonModifier3D
## The faintest body hint of what the player is about to do while that change
## waits for a foot to reach the ball: the shoulders and head start to turn
## toward a new direction (leaning slightly into it), the body leans back for
## a stop, forward for a sprint, and settles slightly back on easing off.
##
## Applied after the animation, to the spine, neck and head only, so the feet
## (and their planting) are untouched. Eases in on the key press and back out
## once the touch makes the change for real.

## Torso twist toward a new direction (degrees), reached at a 90° turn or more.
@export var turn_twist := 10.0
## Extra twist of the head on top of the torso (degrees).
@export var head_twist := 8.0
## Sideways lean into the turn (degrees).
@export var turn_lean := 2.5
## Lean back when a stop is waiting (degrees).
@export var stop_lean := 4.0
## Lean forward when a sprint is waiting (degrees).
@export var sprint_lean := 4.0
## Lean back when easing off a sprint is waiting (degrees).
@export var ease_lean := 2.0
## How quickly the hint follows the intent (higher = snappier).
@export var sharpness := 10.0

const TORSO_BONES := ["mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2"]
const HEAD_BONES := ["mixamorig_Neck", "mixamorig_Head"]

var _dribble: Dribble
var _torso := []
var _head := []
## Smoothed twist (+ left), forward pitch (+ forward) and roll (+ toward the
## player's right), in radians.
var _twist := 0.0
var _pitch := 0.0
var _roll := 0.0


func _ready() -> void:
	var node := get_parent()
	while node and not node is Player:
		node = node.get_parent()
	if node:
		_dribble = node.get_node_or_null(^"Dribble")
	var skeleton := get_skeleton()
	for bone_name in TORSO_BONES:
		_torso.append(skeleton.find_bone(bone_name))
	for bone_name in HEAD_BONES:
		_head.append(skeleton.find_bone(bone_name))


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var twist := 0.0
	var pitch := 0.0
	var roll := 0.0
	if _dribble:
		var turn := _dribble.intent_turn()
		var share := clampf(turn / (PI * 0.5), -1.0, 1.0)
		twist = share * deg_to_rad(turn_twist)
		# Leaning into a left turn tilts the body to its left (-roll).
		roll = -share * deg_to_rad(turn_lean)
		if _dribble.intent_stop():
			pitch -= deg_to_rad(stop_lean)
		match _dribble.intent_sprint():
			1:
				pitch += deg_to_rad(sprint_lean)
			-1:
				pitch -= deg_to_rad(ease_lean)
	var weight := 1.0 - exp(-sharpness * get_process_delta_time())
	_twist = lerpf(_twist, twist, weight)
	_pitch = lerpf(_pitch, pitch, weight)
	_roll = lerpf(_roll, roll, weight)
	if absf(_twist) + absf(_pitch) + absf(_roll) < 1e-4:
		return

	# Spread over the spine, each bone adding its share in skeleton space
	# (+Y up, +Z forward, +X the player's left); the head adds its own twist.
	var torso_step := _rotation(_twist, _pitch, _roll, _torso.size())
	for bone in _torso:
		_rotate_bone(skeleton, bone, torso_step)
	var head_ratio := head_twist / maxf(turn_twist, 0.001)
	var head_step := _rotation(_twist * head_ratio, 0.0, 0.0, _head.size())
	for bone in _head:
		_rotate_bone(skeleton, bone, head_step)


func _rotation(twist: float, pitch: float, roll: float, parts: int) -> Basis:
	var n := float(maxi(parts, 1))
	return Basis(Vector3.UP, twist / n) * Basis(Vector3.RIGHT, pitch / n) * Basis(Vector3.BACK, roll / n)


func _rotate_bone(skeleton: Skeleton3D, bone: int, rotation: Basis) -> void:
	if bone < 0:
		return
	var pose := skeleton.get_bone_global_pose(bone)
	pose.basis = rotation * pose.basis
	skeleton.set_bone_global_pose(bone, pose)
