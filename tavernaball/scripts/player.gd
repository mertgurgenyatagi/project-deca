class_name Player
extends CharacterBody3D
## Arrow-key controlled player, timed against PES 2013 at jog and sprint
## pace, then run 20% faster than PES: speeds, turn rates and blend rates are
## PES x1.2, accelerations x1.44 (1.2²) and times /1.2, so every movement keeps
## its PES shape and distances but takes 1/1.2 of the time. Holding the sprint
## action raises the top speed.
##
## Turning works two ways:
## - Turnback (as measured in PES): when moving and the input points back
##   against the motion, the player brakes to a stop while turning to face
##   the input, then accelerates away as from a standstill.
## - Pivot: from a standstill, the body turns on the spot and starts moving
##   once it nearly faces the new direction.
## Otherwise the body curves toward the input and travels the way it faces.
##
## With the ball, the Dribble child gates the input: a change of direction,
## a stop or a sprint change takes effect only when a foot is on the ball.
##
## Kicking (the Passing child starts it): the player plants, braking in a
## straight line while turning to face the kick, then swings once slow enough
## and facing the right way. From the plant to the end of the follow-through
## the keys are ignored. The more the body has to turn, the longer it takes.
##
## Animation:
## - Gait: idle blends into a jog/sprint gait by ground speed. The jog and
##   sprint loops share one stride phase (aligned on the left foot's forward
##   reach), which advances by ground distance over the blended stride length,
##   so the feet stay planted and the stride lengthens as speed rises.
## - One-shot clips (the turn, the sprint start) are positioned by the
##   distance actually travelled, so their planted feet stay planted, and
##   their own turning curves drive the body's facing. Turnbacks in the turn
##   clip's direction play it (others turn procedurally); sprints from a
##   standstill play the sprint start.
## - Crossfades are stride-matched: a turn clip is entered where its feet best
##   match the gait's, and the gait is re-phased to match a clip before it
##   fades back in.

enum Action { NONE, BRAKE, PUSH_OFF, START, KICK }

## Which side the player is on: passes go to teammates (same team).
@export var team := 0

@export_group("Movement")
## Top ground speed (m/s). PES: 3.7 m in 45 frames at jog (2.47 m/s).
@export var move_speed := 2.964
## Acceleration from a standstill (m/s²). PES: full jog speed after 22 frames (3.36 m/s²).
@export var acceleration := 7.0
## Braking when no key is held (m/s²). Not measured in PES.
@export var deceleration := 18.0
## Turn rate when standing (degrees/s). Not measured in PES; matches the turnback's 180° in 0.5 s at PES pace.
@export var pivot_turn_speed := 540.0
## Turn rate at full speed (degrees/s), for turns short of a turnback. Not measured in PES.
@export var run_turn_speed := 540.0
## How softly turns settle into the final heading (higher = harder stop).
@export var turn_sharpness := 16.0
## Start moving once the turn left to make is below this angle (degrees).
@export var go_angle := 45.0

@export_group("Sprint")
## Top ground speed while sprinting (m/s). PES: 3.7 m in 29 frames (3.83 m/s).
@export var sprint_speed := 4.596
## Acceleration while sprinting (m/s²). PES: full sprint speed after 30 frames from a standstill (3.83 m/s²).
@export var sprint_acceleration := 7.98
## Slowing back to jog speed when sprint is released (m/s²). Not measured in PES.
@export var sprint_slowdown := 7.2
## Turn rate at full sprint (degrees/s), for turns short of a turnback. Not measured in PES.
@export var sprint_turn_speed := 330.0
## At sprint pace the heading turns in notches of this many degrees, PES
## style (0 = smooth turning).
@export var sprint_notch := 22.5
## Shortest time on each notch before the next (s).
@export var sprint_notch_hold := 0.08
## Play the sprint-start clip when sprinting off from a standstill. Off, the
## gait blends straight in, which slides the feet slightly less but has no
## sprint-start posture.
@export var use_sprint_start := true

@export_group("Turnback")
## Input at least this far from the direction of travel (degrees) triggers a turnback.
@export var turnback_angle := 120.0
## Above this speed (m/s), reversing is a turnback; below it, a pivot.
@export var turnback_min_speed := 0.6
## Braking during a turnback (m/s²). PES: a jog brakes to a stop in 15 frames,
## overshooting ~0.6 m, then accelerates away at `acceleration` (4.93 m/s²).
@export var turnback_brake := 7.099
## Fastest the body turns during a procedural turnback (degrees/s). A
## full-speed turnback needs 432; slower ones are capped here and finish as a pivot.
@export var turnback_turn_speed := 480.0

@export_group("Agility")
## At low speed the player is agile, with or without the ball: full agility at
## a standstill, gone by this share of jog speed (fading slowly at first and
## quickly near the end).
@export var agile_until := 1.0
## Acceleration at full agility, as a share of normal: a careful first step.
@export var agile_acceleration := 0.6
## Turn rate multiplier at full agility.
@export var agile_turn_boost := 2.0
## How many times more sharply turns settle at full agility (a crisp finish,
## not a glide).
@export var agile_turn_snap := 3.0
## Share of the way the direction of travel jumps toward a new direction at
## once at full agility, while the body catches up: a cut, not a carve.
@export var agile_cut := 0.5
## At full agility, turns pivot about the planted foot by this share (1 = the
## foot stays put as the body swings round it; 0 = turn about the centre).
@export var agile_pivot := 1.0
## At full agility, reversing below this speed (m/s) is a quick pivot rather
## than a full turnback (brake, turn, push off).
@export var agile_turnback_speed := 2.0
## Changing direction costs this share of speed at a 180° change
## (proportionally less for smaller ones; turnbacks brake instead).
@export var redirect_slowdown := 0.5
## Jog strides are this share of the clips' own length at the same speed:
## quicker, shorter steps (the sprint keeps its stride).
@export var jog_stride := 0.75
## Without the ball, speeds and accelerations are this many times those with it.
@export var off_ball_boost := 1.15

@export_group("Kick")
## A kick on the run: a player at least this fast (m/s), kicking within this
## many degrees of where they face, kicks in stride...
@export var kick_run_min_speed := 1.0
@export var kick_run_turn := 100.0
## ...easing to no faster than this meanwhile (m/s)...
@export var kick_run_speed := 2.6
## ...and swings once facing within this many degrees of the kick. The kicking
## leg plays the kick over the running legs, and the kick is over at this
## point in the clip (s), with the leg coming back down.
@export var kick_run_angle := 30.0
@export var kick_run_end := 0.36
## Otherwise the player plants for the kick, braking (and stepping) at this
## (m/s²), timed to stop beside the ball (see Dribble.plant_point).
@export var kick_brake := 9.0
## A player slower than this steps up to a ball ahead at it (m/s).
@export var kick_step_speed := 1.2
## The swing can start once the player is this slow (m/s); the plant goes on
## braking through the swing...
@export var kick_entry_speed := 1.4
## ...and faces within this many degrees of the kick.
@export var kick_entry_angle := 12.0
## Playback rate of the kick clip (below 1 = a slower, heavier swing).
@export var kick_rate := 1.0
## How long the kick clip takes to fade in and back out (s).
@export var kick_fade_in := 0.1
@export var kick_fade_out := 0.2

@export_group("Animation")
## Ground speed (m/s) at which the gait has fully replaced the idle.
@export var jog_blend_speed := 1.44
## How quickly the idle/gait and jog/sprint blends follow speed (higher = snappier).
@export var blend_sharpness := 12.0
## Lowest jog playback rate while blending in from idle, so the legs never freeze.
@export var min_jog_rate := 0.72
## Turning counts as this much ground speed (m) per rad/s, so the legs keep
## stepping while the body pivots or turns back (0 = off).
@export var turn_step_radius := 0.3
## How long one-shot clips take to fade in (s). Shorter keeps the gait's
## stance foot from being swung round as a turn starts; too short pops.
@export var clip_fade_in_time := 0.25
## How long one-shot clips take to fade back out to the gait (s).
@export var clip_fade_out_time := 0.25
## Latest point to enter a turn clip, as the share of its turn already made
## past the earliest point the braking allows.
@export var clip_entry_window := 0.15
## Playback rate of the idle loop (1 = the clip's own pace).
@export var idle_rate := 1.2

const IDLE_ANIMATION := &"idle/idle"
const JOG_ANIMATION := &"jog_forward/jog_forward"
const SPRINT_ANIMATION := &"sprint/sprint"
## The kick with each foot (index into LEG_CHAINS: 0 = left, 1 = right). The
## clip kicks with the right; the left is its mirror (mixamo_kick_import.gd).
const KICK_ANIMATIONS := [&"pass_kick/pass_kick_mirror", &"pass_kick/pass_kick"]
## Per foot, the AnimationTree blends showing the whole kick and the kicking leg alone.
const KICK_BLENDS := [&"parameters/KickLBlend/blend_amount", &"parameters/KickBlend/blend_amount"]
const KICK_LEG_BLENDS := [&"parameters/KickLegLBlend/blend_amount", &"parameters/KickLegBlend/blend_amount"]
const KICK_SEEKS := [&"parameters/KickLSeek/seek_request", &"parameters/KickSeek/seek_request"]
const KICK_LEG_SEEKS := [&"parameters/KickLegLSeek/seek_request", &"parameters/KickLegSeek/seek_request"]
const HIPS_BONE := "mixamorig_Hips"
## Leg chains below the hips; the foot and toe of each are compared when
## matching strides, and the left foot's forward reach marks stride phase 0.
const LEG_CHAINS := [
	["mixamorig_LeftUpLeg", "mixamorig_LeftLeg", "mixamorig_LeftFoot", "mixamorig_LeftToeBase"],
	["mixamorig_RightUpLeg", "mixamorig_RightLeg", "mixamorig_RightFoot", "mixamorig_RightToeBase"],
]
## Stride samples per gait loop, used for matching.
const GAIT_SAMPLES := 50


## A one-shot clip driven by distance travelled (see mixamo_turn_import.gd).
## Its node in the AnimationTree is "<name>Seek", blended in by "<name>Blend".
class OneShot:
	var seek_param: StringName
	var blend_param: StringName
	## Per sample: clip time, distance along the clip (m), facing progress 0-1,
	## and foot positions.
	var times: PackedFloat32Array
	var distances: PackedFloat32Array
	var progress: PackedFloat32Array
	var feet: Array[PackedVector3Array] = []
	var stop := 0.0
	var total := 0.0
	## Direction the clip turns: +1 left, -1 right.
	var turn_sign := 1.0
	## Where the clip is, as distance along it (m), and whether it should show.
	var distance := 0.0
	var playing := false
	## Linear fade position, 0 to 1; eased when applied.
	var fade := 0.0

	func _init(node_name: String, anim: Animation, hip_height: float) -> void:
		seek_param = StringName("parameters/%sSeek/seek_request" % node_name)
		blend_param = StringName("parameters/%sBlend/blend_amount" % node_name)
		times = anim.get_meta(&"turn_times")
		progress = anim.get_meta(&"turn_progress")
		distances = anim.get_meta(&"turn_distance")
		for i in distances.size():
			distances[i] *= hip_height
		stop = float(anim.get_meta(&"turn_stop_distance")) * hip_height
		total = float(anim.get_meta(&"turn_total_distance")) * hip_height
		turn_sign = signf(float(anim.get_meta(&"turn_angle")))

	## Interpolates per-sample data at a distance along the clip.
	func sample(values: PackedFloat32Array, at: float) -> float:
		var last := distances.size() - 1
		if at >= distances[last]:
			return values[last]
		if at <= 0.0:
			return values[0]
		var i := maxi(distances.bsearch(at, false) - 1, 0)
		var span := distances[i + 1] - distances[i]
		var t := 0.0 if span <= 0.0 else (at - distances[i]) / span
		return lerpf(values[i], values[i + 1], clampf(t, 0.0, 1.0))

	## Index of the sample nearest a distance along the clip.
	func index(at: float) -> int:
		var i := clampi(distances.bsearch(at), 0, distances.size() - 1)
		if i > 0 and at - distances[i - 1] < distances[i] - at:
			i -= 1
		return i


## Movement input and sprint, read from the keyboard each physics tick while
## `read_input` is on. Turn it off to drive the player from elsewhere (a test,
## or later a network copy).
var move_input := Vector2.ZERO
var sprint_held := false
## The pass button, read with the movement keys.
var pass_held := false
var read_input := true

## Read-only state for the dribble (and anything else watching the player).
var yaw: float:
	get: return _yaw
## Ground velocity: x is world X, y is world Z.
var ground_velocity: Vector2:
	get: return _ground
var gait_phase: float:
	get: return _gait_phase
var sprint_weight: float:
	get: return _sprint_weight
var action: Action:
	get: return _action
var action_dir: Vector2:
	get: return _action_dir
## Signed turn of the current turnback (+ left, − right); 0 when none.
var turn_direction: float:
	get: return _action_turn if _action in [Action.BRAKE, Action.PUSH_OFF] else 0.0
var skeleton: Skeleton3D:
	get: return _skeleton

## Facing angle around Y; 0 faces +Z, the model's forward axis.
var _yaw := 0.0
var _yaw_rate := 0.0
## Ground velocity: x is world X, y is world Z.
var _ground := Vector2.ZERO
var _sprinting := false

var _action := Action.NONE
var _action_dir := Vector2.ZERO
var _action_yaw := 0.0
## Signed turn the turnback makes, start to finish.
var _action_turn := 0.0
var _action_speed := 0.0
## Clip the turnback plays (null: procedural), and the clip whose fade back
## to the gait has been stride-matched.
var _turn_clip: OneShot = null
var _synced_clip: OneShot = null
## Where the turn clip is entered, and its facing progress there.
var _clip_entry := 0.0
var _clip_entry_progress := 0.0
## The push-off's distance so far.
var _push_distance := 0.0

var _walk_turn: OneShot
var _sprint_start: OneShot
var _one_shots: Array[OneShot] = []

## Gait: stride phase (0-1, 0 = left foot furthest forward), each loop's
## length, phase offset and stride length (m per cycle), and foot samples.
var _gait_phase := 0.0
var _jog_length := 1.0
var _sprint_length := 1.0
var _jog_offset := 0.0
var _sprint_offset := 0.0
var _jog_cycle := 1.0
var _sprint_cycle := 1.0
var _jog_feet: Array[PackedVector3Array] = []
var _sprint_feet: Array[PackedVector3Array] = []
var _idle_anim: Animation
var _idle_feet := PackedVector3Array()
var _blend := 0.0
var _sprint_weight := 0.0
## Smoothed turning contribution to leg speed (m/s); turn rate can change
## abruptly, the legs must not.
var _turn_motion := 0.0
## Stride length as a share of the clips' own (smoothed): below 1 with the
## ball at a jog, for quicker, shorter steps. The leg swing is shrunk to match
## by mixing in some of the idle pose, so planted feet stay planted.
var _stride := 1.0
## The input acted on last tick, to notice changes of direction.
var _last_input := Vector2.ZERO
## Sprint notch steering: [active, notch heading, hold timer].
var _notch := [false, 0.0, -1.0]

## Current stride share (1 = the clips' own stride).
var stride: float:
	get: return _stride

## Kick: the way it faces, where the swing is (clip time; -1 before the
## swing), and the clip's fade.
var _kick_yaw := 0.0
var _kick_time := -1.0
## Kicking on the run (rather than planted), and how much the kick shows as
## just the kicking leg over the running legs (1) rather than whole (0).
var _kick_running := false
var _kick_layer := 0.0
var _kick_shown := 0.0
var _kick_fade := 0.0
var _kick_length := 0.0
## Clip time when the kicking foot meets the ball, and that foot's ankle and
## toe then (model space).
var _kick_contact := 0.0
## Per foot, the kicking foot's ankle and toe as it meets the ball.
var _kick_ankle := [Vector3.ZERO, Vector3.ZERO]
var _kick_toe := [Vector3.ZERO, Vector3.ZERO]
## The foot the kick is made with (0 left, 1 right).
var _kick_foot := 1
## How much lower the kick clip's feet stand than the idle's (it comes from a
## different rig); the model is lifted by this while the kick shows.
var _kick_lift := 0.0

## Whether the kick's swing is under way, and the clip time it has reached.
var kick_swinging: bool:
	get: return _action == Action.KICK and _kick_time >= 0.0
var kick_time: float:
	get: return _kick_time
## Clip time at which the foot meets the ball.
var kick_contact_time: float:
	get: return _kick_contact
var kick_foot: int:
	get: return _kick_foot
var kick_yaw: float:
	get: return _kick_yaw
var kick_running: bool:
	get: return _action == Action.KICK and _kick_running

@onready var _model: Node3D = $Model
@onready var _skeleton: Skeleton3D = $Model/Character/Skeleton3D
@onready var _anim_tree: AnimationTree = $AnimationTree
@onready var _dribble: Dribble = get_node_or_null(^"Dribble")
@onready var _passing: Passing = get_node_or_null(^"Passing")


func _ready() -> void:
	# Clips store hips positions in hip heights; scale them to this character.
	var hip_height := _skeleton.get_bone_rest(_skeleton.find_bone(HIPS_BONE)).origin.y
	_skeleton.motion_scale = hip_height

	_idle_anim = _anim_tree.get_animation(IDLE_ANIMATION)
	var jog := _anim_tree.get_animation(JOG_ANIMATION)
	var sprint := _anim_tree.get_animation(SPRINT_ANIMATION)
	_jog_length = jog.length
	_sprint_length = sprint.length
	_jog_cycle = float(jog.get_meta(&"root_motion_speed")) * hip_height * _jog_length
	_sprint_cycle = float(sprint.get_meta(&"root_motion_speed")) * hip_height * _sprint_length
	_jog_offset = _stride_offset(jog)
	_sprint_offset = _stride_offset(sprint)
	for i in GAIT_SAMPLES:
		var phase := float(i) / GAIT_SAMPLES
		_jog_feet.append(_feet_at(jog, fposmod(phase + _jog_offset, 1.0) * _jog_length))
		_sprint_feet.append(_feet_at(sprint, fposmod(phase + _sprint_offset, 1.0) * _sprint_length))

	_idle_feet = _feet_at(_idle_anim, 0.0)
	_walk_turn = _make_one_shot("Turn", &"turn_180/turn_180", hip_height)
	_sprint_start = _make_one_shot("Start", &"sprint_start/sprint_start", hip_height)
	for foot in 2:
		_find_kick_contact(_anim_tree.get_animation(KICK_ANIMATIONS[foot]), foot)
	_yaw = _model.rotation.y
	add_to_group(&"players")


## Where a kick clip's foot meets the ball: the moment the kicking toe moves
## forward fastest, early in the swing.
func _find_kick_contact(anim: Animation, foot: int) -> void:
	const STEP := 1.0 / 240.0
	_kick_length = anim.length
	var stance := _feet_at(anim, 0.0)
	var idle := _feet_at(_idle_anim, 0.0)
	_kick_lift = minf(idle[1].y, idle[3].y) - minf(stance[1].y, stance[3].y)
	var best := -INF
	var last := _feet_at(anim, 0.0)[foot * 2 + 1]
	var t := STEP
	while t < anim.length * 0.5:
		var feet := _feet_at(anim, t)
		var toe := feet[foot * 2 + 1]
		var forward := (toe.z - last.z) / STEP
		if forward > best:
			best = forward
			_kick_contact = t
			_kick_ankle[foot] = feet[foot * 2]
			_kick_toe[foot] = toe
		last = toe
		t += STEP


## Model-space ankle and toe of a foot (the kick's, by default) as it meets the ball.
func kick_contact_feet(foot := -1) -> Array[Vector3]:
	var f := _kick_foot if foot < 0 else foot
	return [_kick_ankle[f], _kick_toe[f]]


## Kicks with `foot` (0 left, 1 right); only before the swing.
func set_kick_foot(foot: int) -> void:
	if _kick_time < 0.0:
		_kick_foot = foot


func _make_one_shot(node_name: String, animation: StringName, hip_height: float) -> OneShot:
	var anim := _anim_tree.get_animation(animation)
	var clip := OneShot.new(node_name, anim, hip_height)
	for t in clip.times:
		clip.feet.append(_feet_at(anim, t))
	_one_shots.append(clip)
	return clip


## Stride phase offset of a loop: where its left foot reaches furthest forward.
func _stride_offset(anim: Animation) -> float:
	const SAMPLES := 120
	var best := 0
	var best_reach := -INF
	for i in SAMPLES:
		var reach := _feet_at(anim, anim.length * i / SAMPLES)[0].z
		if reach > best_reach:
			best_reach = reach
			best = i
	return float(best) / SAMPLES


func _physics_process(delta: float) -> void:
	if read_input:
		move_input = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
		sprint_held = Input.is_action_pressed(&"sprint")
		pass_held = InputMap.has_action(&"pass") and Input.is_action_pressed(&"pass")
	var input := move_input
	_sprinting = sprint_held
	if _dribble:
		# With the ball, changes of direction or pace wait for a touch.
		input = _dribble.gate_input(move_input)
		_sprinting = _dribble.gate_sprint(sprint_held)
	var receiving := _passing.receive_run() if _passing else []
	if not receiving.is_empty():
		# A pass is on its way to this player: they go to meet it, whatever the keys say.
		input = receiving[0]
		_sprinting = receiving[1]
	if _action == Action.KICK:
		# Committed to the kick: the keys wait until it is over.
		input = Vector2.ZERO
	var previous_yaw := _yaw
	# Changing direction costs pace (a turnback brakes instead). With the ball
	# this happens at the touch that makes the change.
	if _action == Action.NONE and input != Vector2.ZERO and _last_input != Vector2.ZERO \
			and not input.is_equal_approx(_last_input) and not _should_turn_back(input):
		_ground *= 1.0 - redirect_slowdown * absf(_last_input.angle_to(input)) / PI
	_last_input = input

	# An action carries on only while its direction is held.
	if _action not in [Action.NONE, Action.KICK] and (input == Vector2.ZERO or input.normalized().dot(_action_dir) < 0.7):
		_end_action()
	if _action == Action.NONE and _should_turn_back(input):
		_begin_turnback(input)
	match _action:
		Action.BRAKE:
			_step_brake(delta)
		Action.PUSH_OFF:
			_step_push_off(delta)
		Action.KICK:
			_step_kick(delta)
		_:
			var previous_speed := _ground.length()
			_step_steering(input, delta)
			if _action == Action.START:
				_step_start(previous_speed * delta)
			elif use_sprint_start and _sprinting and previous_speed == 0.0 and _ground.length() > 0.0:
				_begin_start(input)

	velocity.x = _ground.x
	velocity.z = _ground.y
	var pivot := _pivot_offset(previous_yaw, _yaw)
	velocity.x += pivot.x / delta
	velocity.z += pivot.y / delta
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()

	_model.rotation.y = _yaw
	_yaw_rate = absf(angle_difference(previous_yaw, _yaw)) / delta


func _process(delta: float) -> void:
	_update_animation(delta)


## When agile, steering turns pivot about the planted foot rather than the
## body's centre: the body shifts so that foot stays where it is, as in a real
## plant-and-turn, instead of being dragged round (skating). Returns the
## ground shift (x: world X, y: world Z) for this tick.
func _pivot_offset(from_yaw: float, to_yaw: float) -> Vector2:
	if from_yaw == to_yaw:
		return Vector2.ZERO
	var weight := _pivot_share()
	if weight <= 0.0:
		return Vector2.ZERO
	# The planted foot: the lower toe.
	var left := _skeleton.get_bone_global_pose(_skeleton.find_bone(LEG_CHAINS[0][3])).origin
	var right := _skeleton.get_bone_global_pose(_skeleton.find_bone(LEG_CHAINS[1][3])).origin
	var foot := left if left.y < right.y else right
	foot.y = 0.0
	var before := Basis(Vector3.UP, from_yaw) * foot
	var after := Basis(Vector3.UP, to_yaw) * foot
	return Vector2(before.x - after.x, before.z - after.z) * weight


func _pivot_share() -> float:
	return agile_pivot * agility_at(_ground.length()) if _action in [Action.NONE, Action.KICK] else 0.0


## Starts a kick facing `yaw`, ignoring the keys until it is over. A player
## on the move kicking not far off where they face (and `on_the_run` allowed)
## kicks in stride; otherwise they plant and turn. The swing waits for
## `start_swing`.
func begin_kick(yaw: float, foot: int, on_the_run := true) -> void:
	if _action != Action.NONE and _action != Action.KICK:
		_end_action()
	_action = Action.KICK
	_kick_yaw = yaw
	_kick_time = -1.0
	_kick_foot = foot
	_kick_running = on_the_run and _ground.length() >= kick_run_min_speed \
			and absf(angle_difference(_yaw, yaw)) <= deg_to_rad(kick_run_turn)


## Turns the kick toward a new direction (until the swing starts).
func aim_kick(yaw: float) -> void:
	if _action == Action.KICK and _kick_time < 0.0:
		_kick_yaw = yaw


## Whether the swing may start: facing the kick, and planted (slow enough)
## unless kicking on the run.
func kick_ready() -> bool:
	if _action != Action.KICK or _kick_time >= 0.0:
		return false
	var off := absf(angle_difference(_yaw, _kick_yaw))
	if _kick_running:
		return off <= deg_to_rad(kick_run_angle)
	return _ground.length() <= kick_entry_speed and off <= deg_to_rad(kick_entry_angle)


## Where the hips will be (ground x/z) `t` seconds into a kick from now:
## running on, or braking to a stop when planted.
func kick_hips_after(t: float) -> Vector2:
	var at := Vector2(global_position.x, global_position.z)
	var speed := _ground.length()
	if speed == 0.0:
		return at
	if _kick_running:
		return at + _ground * t
	var travel := speed * speed / (2.0 * kick_brake) if speed < kick_brake * t else speed * t - 0.5 * kick_brake * t * t
	return at + _ground / speed * travel


## Speed a kick on the run eases to from `speed`.
func kick_run_pace(speed: float) -> float:
	return minf(speed, kick_run_speed)


## Roughly how long until the foot would meet the ball if a kick facing `yaw`
## started now (s): braking (as hard as allowed) and turning, then the swing.
func kick_lead_time(yaw: float) -> float:
	var speed := _ground.length()
	var brake := maxf(speed - kick_entry_speed, 0.0) / kick_brake
	var turn := maxf(absf(angle_difference(_yaw, yaw)) - deg_to_rad(kick_entry_angle), 0.0) / turn_rate_at(speed * 0.5)
	return maxf(brake, turn) + _kick_contact / kick_rate


func start_swing() -> void:
	if _action == Action.KICK and _kick_time < 0.0:
		_kick_time = 0.0
		_kick_layer = 1.0 if _kick_running else 0.0


## Abandons a kick before its swing (the ball never came).
func cancel_kick() -> void:
	if _action == Action.KICK and _kick_time < 0.0:
		_action = Action.NONE


## Faces `yaw` at once (setting up a scene).
func face(yaw: float) -> void:
	_yaw = yaw
	_model.rotation.y = yaw


## Into the kick, then the swing:
## - On the run: steering toward the kick at the usual turn rates, easing off
##   to `kick_run_speed`.
## - Planted: braking in a straight line while turning to face the kick
##   (about the planted foot when slow, see `_pivot_offset`). Where the Dribble
##   says the plant should be, the braking is timed to stop level with it.
func _step_kick(delta: float) -> void:
	if _kick_running:
		_step_kick_run(delta)
		return
	var plant := _dribble.plant_point if _dribble else Vector2.INF
	var to := plant - Vector2(global_position.x, global_position.z) if plant != Vector2.INF else Vector2.ZERO
	var facing := Vector2(sin(_yaw), cos(_yaw))
	if to.length() > 0.02 and to.dot(facing) > 0.0:
		# Arrive at the plant: as fast as braking still stops there, no faster
		# than now, though a slow player steps up to a ball ahead.
		var arrive := minf(sqrt(2.0 * kick_brake * to.length()), maxf(_ground.length(), kick_step_speed))
		_ground = _ground.move_toward(to.normalized() * arrive, kick_brake * delta)
	else:
		_ground = _ground.move_toward(Vector2.ZERO, kick_brake * delta)
	var speed := _ground.length()
	var max_step := turn_rate_at(speed) * delta
	var step := _turn_toward(_yaw, _kick_yaw) * (1.0 - exp(-turn_sharpness_at(speed) * delta))
	_yaw = wrapf(_yaw + clampf(step, -max_step, max_step), -PI, PI)
	_advance_swing(delta, _kick_length)


func _step_kick_run(delta: float) -> void:
	var speed := move_toward(_ground.length(), kick_run_pace(_ground.length()), kick_brake * delta)
	var max_step := turn_rate_at(speed) * delta
	var step := _turn_toward(_yaw, _kick_yaw) * (1.0 - exp(-turn_sharpness_at(speed) * delta))
	_yaw = wrapf(_yaw + clampf(step, -max_step, max_step), -PI, PI)
	var travel := _yaw + _turn_toward(_yaw, _kick_yaw) * cut_at(speed)
	_ground = Vector2(sin(travel), cos(travel)) * speed
	_advance_swing(delta, kick_run_end)


func _advance_swing(delta: float, end: float) -> void:
	if _kick_time >= 0.0:
		_kick_time += kick_rate * delta
		if _kick_time >= end:
			_action = Action.NONE
			_kick_time = -1.0


func _end_action() -> void:
	_action = Action.NONE
	for clip in _one_shots:
		clip.playing = false
	_sync_gait()


func _should_turn_back(input: Vector2) -> bool:
	return input != Vector2.ZERO \
			and _ground.length() > turnback_threshold() \
			and absf(_ground.angle_to(input)) >= deg_to_rad(turnback_angle)


func _begin_turnback(input: Vector2) -> void:
	_action = Action.BRAKE
	_action_speed = _ground.length()
	_action_yaw = _yaw
	_action_dir = input.normalized()
	_synced_clip = null

	_action_turn = angle_difference(_yaw, atan2(input.x, input.y))
	# A full about-face goes the clip's way; other turnbacks use the clip only
	# if they already turn that way.
	if absf(_action_turn) > deg_to_rad(179.0):
		_action_turn = absf(_action_turn) * _walk_turn.turn_sign
	_turn_clip = _walk_turn if signf(_action_turn) == _walk_turn.turn_sign else null
	if _turn_clip:
		_choose_clip_entry()


## Picks where to enter the turn clip: wherever, partway into its fade-in,
## the gait's feet (predicted from its current stride) best match the clip's.
## Entering later just means braking a little longer on the gait first.
func _choose_clip_entry() -> void:
	var clip := _turn_clip
	var speed := _ground.length()
	var braking_left := speed * speed / (2.0 * _turnback_brake())
	var earliest := maxf(clip.stop - braking_left, 0.0)
	var latest_progress := clip.sample(clip.progress, earliest) + clip_entry_window
	var best := INF
	_clip_entry = earliest
	for i in clip.distances.size():
		var entry := clip.distances[i]
		if entry < earliest:
			continue
		if entry > clip.stop or clip.progress[i] > latest_progress:
			break
		var before_entry := braking_left - (clip.stop - entry)
		var entry_speed := sqrt(maxf(speed * speed - 2.0 * _turnback_brake() * before_entry, 0.0))
		var into_fade := _travel(entry_speed, -_turnback_brake(), clip_fade_in_time * 0.5)
		var phase := _gait_phase + _gait_advance(speed, -_turnback_brake(), before_entry + into_fade)
		var gait := _gait_feet(phase, _sprint_weight_at(maxf(entry_speed - _turnback_brake() * clip_fade_in_time * 0.5, 0.0)))
		var gap := _feet_gap(gait, clip.feet[clip.index(entry + into_fade)])
		if gap < best:
			best = gap
			_clip_entry = entry
	_clip_entry_progress = clip.sample(clip.progress, _clip_entry)
	clip.distance = _clip_entry


## Brakes along the old direction while the body turns toward the new one.
func _step_brake(delta: float) -> void:
	_ground = _ground.move_toward(Vector2.ZERO, _turnback_brake() * delta)
	var speed := _ground.length()
	if _turn_clip:
		# Follow the clip once the braking left matches its run-in to its stop.
		var clip := _turn_clip
		clip.distance = clip.stop - speed * speed / (2.0 * _turnback_brake())
		clip.playing = clip.distance >= _clip_entry
		_yaw = wrapf(_action_yaw + _action_turn * _turn_share(clip.distance), -PI, PI)
	else:
		var progress := 1.0 - speed / _action_speed
		var desired := _action_yaw + _action_turn * progress
		var max_step := deg_to_rad(turnback_turn_speed) * delta
		_yaw = wrapf(_yaw + clampf(angle_difference(_yaw, desired), -max_step, max_step), -PI, PI)
	if speed == 0.0:
		if _turn_clip:
			_action = Action.PUSH_OFF
			_push_distance = 0.0
		else:
			_action = Action.NONE


## Share of the turnback's turn made by a point along the turn clip.
func _turn_share(distance: float) -> float:
	if distance <= _clip_entry:
		return 0.0
	return clampf(inverse_lerp(_clip_entry_progress, 1.0, _turn_clip.sample(_turn_clip.progress, distance)), 0.0, 1.0)


## Accelerates away in the new direction while the turn clip finishes the turn.
func _step_push_off(delta: float) -> void:
	var speed := move_toward(_ground.length(), _top_speed(), _acceleration() * delta)
	_ground = _action_dir * speed
	_push_distance += speed * delta
	var clip := _turn_clip
	clip.distance = clip.stop + _push_distance
	_yaw = wrapf(_action_yaw + _action_turn * _turn_share(clip.distance), -PI, PI)
	_play_until_exit(clip, speed)
	if clip.distance >= clip.total:
		_action = Action.NONE


## Sprinting off from a standstill plays the sprint start.
func _begin_start(input: Vector2) -> void:
	_action = Action.START
	_action_dir = input.normalized()
	_synced_clip = null
	_sprint_start.distance = 0.0
	_sprint_start.playing = true


func _step_start(distance: float) -> void:
	var clip := _sprint_start
	clip.distance += distance
	_play_until_exit(clip, _ground.length())
	if clip.distance >= clip.total:
		_action = Action.NONE


## Keeps a clip showing until there is just enough of it left to fade back
## to the gait, then stride-matches the gait to it for that fade.
func _play_until_exit(clip: OneShot, speed: float) -> void:
	var exit_point := clip.total - maxf(speed, 0.6) * clip_fade_out_time
	clip.playing = clip.distance < exit_point
	if not clip.playing and _synced_clip != clip:
		_sync_gait()


## PES-style sprint steering: at sprint pace the heading moves in notches of
## `sprint_notch` degrees (world-aligned), one notch at a time, each held at
## least `sprint_notch_hold` seconds, instead of curving smoothly. Returns the
## heading to steer for this tick.
func _sprint_heading(wanted: float, speed: float, delta: float) -> float:
	return notch_heading(_notch, _yaw, wanted, speed, _sprinting, delta)


## One tick of notch steering on `state` ([notching, notch yaw, hold timer],
## updated in place), for a body at `yaw` wanting `wanted`. Shared with the
## Dribble's prediction so both step through the same notches.
func notch_heading(state: Array, yaw: float, wanted: float, speed: float, sprinting: bool, delta: float) -> float:
	if not sprinting or speed < move_speed or sprint_notch <= 0.0:
		state[0] = false
		return wanted
	var notch := deg_to_rad(sprint_notch)
	if not state[0]:
		state[0] = true
		state[1] = roundf(yaw / notch) * notch
		state[2] = -1.0
	# The hold starts once the body has arrived on its notch (-1: not yet).
	if state[2] < 0.0 and absf(angle_difference(yaw, state[1])) < notch * 0.25:
		state[2] = sprint_notch_hold
	if state[2] >= 0.0:
		state[2] = maxf(state[2] - delta, 0.0)
	var goal := roundf(wanted / notch) * notch
	var left := _turn_toward(state[1], goal)
	if absf(left) > notch * 0.5 and state[2] == 0.0:
		state[1] = wrapf(state[1] + signf(left) * notch, -PI, PI)
		state[2] = -1.0
	return state[1]


## A copy of the current notch steering state (for prediction).
func notch_state() -> Array:
	return _notch.duplicate()


func _step_steering(input: Vector2, delta: float) -> void:
	if input == Vector2.ZERO:
		_ground = _ground.move_toward(Vector2.ZERO, deceleration * delta)
		return

	var speed := _ground.length()
	var target_yaw := _sprint_heading(atan2(input.x, input.y), speed, delta)
	var max_step := turn_rate_at(speed) * delta
	# Agile turns snap round rather than glide.
	var step := _turn_toward(_yaw, target_yaw) * (1.0 - exp(-turn_sharpness_at(speed) * delta))
	_yaw = wrapf(_yaw + clampf(step, -max_step, max_step), -PI, PI)
	# Travel follows the facing, except that when agile it cuts part of the way
	# to the new direction at once while the body catches up.
	var travel_yaw := _yaw + _turn_toward(_yaw, target_yaw) * cut_at(speed)

	var target_speed := 0.0
	if absf(angle_difference(_yaw, target_yaw)) < deg_to_rad(go_angle):
		target_speed = _top_speed() * input.length()
	var rate := _acceleration()
	if target_speed < speed:
		# Easing off a sprint into a jog is gentler than stopping.
		rate = sprint_slowdown if target_speed > 0.0 else deceleration
	speed = move_toward(speed, target_speed, rate * delta)
	_ground = Vector2(sin(travel_yaw), cos(travel_yaw)) * speed


## Steering turn rate (rad/s) at a ground speed: pivot rate standing, run
## rate at jog speed, sprint rate at full sprint.
func turn_rate_at(speed: float) -> float:
	var turn_speed := lerpf(pivot_turn_speed, run_turn_speed, clampf(speed / move_speed, 0.0, 1.0))
	if speed > move_speed:
		turn_speed = lerpf(run_turn_speed, sprint_turn_speed, inverse_lerp(move_speed, sprint_speed, minf(speed, sprint_speed)))
	# Nimbler when agile.
	turn_speed *= lerpf(1.0, agile_turn_boost, agility_at(speed))
	return deg_to_rad(turn_speed)


## Speed above which reversing is a turnback rather than a pivot (higher
## with the ball at the feet).
func turnback_threshold() -> float:
	return lerpf(turnback_min_speed, maxf(turnback_min_speed, agile_turnback_speed), agility_at(_ground.length()))


## How agile the player is at a ground speed: 1 at a standstill, easing to 0
## by `agile_until` × jog speed.
func agility_at(speed: float) -> float:
	var x := clampf(speed / (agile_until * move_speed), 0.0, 1.0)
	return 1.0 - x * x


## Acceleration at a speed (sprint or not): a careful first step when agile.
func acceleration_at(speed: float, sprinting: bool) -> float:
	var rate := sprint_acceleration if sprinting else acceleration
	return rate * _pace() * lerpf(1.0, agile_acceleration, agility_at(speed))


## Without the ball the player is quicker: speeds, accelerations and turnback
## braking all scale by `off_ball_boost`, so turns take the same time.
func _pace() -> float:
	return 1.0 if _dribble and _dribble.holding() else off_ball_boost


func _turnback_brake() -> float:
	return turnback_brake * _pace()


## How sharply turns settle at a speed (crisper when agile).
func turn_sharpness_at(speed: float) -> float:
	var agility := agility_at(speed)
	return turn_sharpness * lerpf(1.0, agile_turn_boost, agility) * lerpf(1.0, agile_turn_snap, agility)


## Share of a turn the direction of travel takes at once at a speed (a cut).
func cut_at(speed: float) -> float:
	return agile_cut * agility_at(speed)


## Whether this input, applied now, would start a turnback.
func would_turn_back(input: Vector2) -> bool:
	return _action == Action.NONE and _should_turn_back(input)


## Signed turn (+ left, − right) the body would make toward this input: as a
## turnback would make it, or else as steering would.
func turn_for(input: Vector2) -> float:
	var target := atan2(input.x, input.y)
	if would_turn_back(input):
		var turn := angle_difference(_yaw, target)
		if absf(turn) > deg_to_rad(179.0):
			turn = absf(turn) * _walk_turn.turn_sign
		return turn
	return _turn_toward(_yaw, target)


func top_speed() -> float:
	return _top_speed()


func current_acceleration() -> float:
	return _acceleration()


## Stride phase advance per second at a ground speed, with the jog/sprint
## blend that speed settles to.
func phase_rate_at(speed: float) -> float:
	return _phase_rate(speed, _sprint_weight_at(speed))


## Model-space foot and toe points of the idle pose (as `gait_feet_at`).
func idle_feet() -> PackedVector3Array:
	return _feet_at(_idle_anim, 0.0)


## Jog/sprint blend the gait settles to at a ground speed.
func sprint_weight_at(speed: float) -> float:
	return _sprint_weight_at(speed)


## Model-space foot and toe points of the gait at a stride phase:
## [left foot, left toe, right foot, right toe]. Interpolated between samples.
func gait_feet_at(phase: float, weight: float) -> PackedVector3Array:
	var at := fposmod(phase, 1.0) * GAIT_SAMPLES
	var i := int(at) % GAIT_SAMPLES
	var j := (i + 1) % GAIT_SAMPLES
	var t := at - floorf(at)
	var feet := PackedVector3Array()
	for k in _jog_feet[i].size():
		var jog := _jog_feet[i][k].lerp(_jog_feet[j][k], t)
		var sprint := _sprint_feet[i][k].lerp(_sprint_feet[j][k], t)
		feet.append(jog.lerp(sprint, weight))
	return feet


func _top_speed() -> float:
	return (sprint_speed if _sprinting else move_speed) * _pace()


func _acceleration() -> float:
	return acceleration_at(_ground.length(), _sprinting)


## Signed turn from one yaw to another. A full about-face turns through the
## side facing the camera (+Z), so the player's front stays in view.
func _turn_toward(from: float, to: float) -> float:
	var turn := angle_difference(from, to)
	if absf(turn) > deg_to_rad(179.0):
		var other := turn - signf(turn) * TAU
		if absf(angle_difference(from + other * 0.5, 0.0)) < absf(angle_difference(from + turn * 0.5, 0.0)):
			turn = other
	return turn


## Distance covered in `time` from `speed` at constant `accel`, stopping at zero speed.
func _travel(speed: float, accel: float, time: float) -> float:
	if accel < 0.0:
		time = minf(time, speed / -accel)
	return speed * time + 0.5 * accel * time * time


func _sprint_weight_at(speed: float) -> float:
	return clampf(inverse_lerp(move_speed * _pace(), sprint_speed * _pace(), speed), 0.0, 1.0)


## Stride phase advance per second at a ground speed and jog/sprint weight.
## Shorter strides (with the ball) turn the legs over faster.
func _phase_rate(speed: float, sprint_weight: float) -> float:
	var cycle := lerpf(_jog_cycle, _sprint_cycle, sprint_weight) * _stride
	return maxf(speed / cycle, min_jog_rate / _jog_length)


## How far the stride phase advances while the player covers `distance` from
## `speed` at constant `accel`.
func _gait_advance(speed: float, accel: float, distance: float) -> float:
	const STEP := 1.0 / 240.0
	var advance := 0.0
	var covered := 0.0
	while covered < distance and speed > 0.0:
		advance += _phase_rate(speed, _sprint_weight_at(speed)) * STEP
		covered += speed * STEP
		speed = minf(speed + accel * STEP, _top_speed())
	return advance


## Gait foot points at a phase, as they show: shorter strides mix in the idle
## pose (see `jog_stride`), which the stride matching must allow for.
func _gait_feet(phase: float, sprint_weight: float) -> PackedVector3Array:
	var i := posmod(roundi(fposmod(phase, 1.0) * GAIT_SAMPLES), GAIT_SAMPLES)
	var stride_share := lerpf(jog_stride, 1.0, sprint_weight)
	var feet := PackedVector3Array()
	for j in _jog_feet[i].size():
		feet.append(_idle_feet[j].lerp(_jog_feet[i][j].lerp(_sprint_feet[i][j], sprint_weight), stride_share))
	return feet


func _feet_gap(a: PackedVector3Array, b: PackedVector3Array) -> float:
	var gap := 0.0
	for i in a.size():
		gap += a[i].distance_to(b[i])
	return gap


## Re-phases the gait (hidden under the clip on top) so its feet match that
## clip's halfway through the fade back to the gait.
func _sync_gait() -> void:
	var clip: OneShot = null
	for c in _one_shots:
		if c.fade > 0.0:
			clip = c
	if clip == null:
		return
	_synced_clip = clip
	var speed := _ground.length()
	var accel := _acceleration() if _action != Action.NONE else 0.0
	var into_fade := _travel(speed, accel, clip_fade_out_time * 0.5)
	var target := clip.feet[clip.index(clip.distance + into_fade)]
	var weight := _sprint_weight_at(speed + accel * clip_fade_out_time * 0.5)
	_gait_phase = _best_phase(target, weight, _gait_advance(speed, accel, into_fade))


## Stride phase whose gait feet, `advance` later, best match `target`.
func _best_phase(target: PackedVector3Array, sprint_weight: float, advance: float) -> float:
	var best := INF
	var best_phase := 0.0
	for i in GAIT_SAMPLES:
		var phase := float(i) / GAIT_SAMPLES
		var gap := _feet_gap(_gait_feet(phase + advance, sprint_weight), target)
		if gap < best:
			best = gap
			best_phase = phase
	return best_phase


## Foot and toe positions in model space for a clip at a time, by forward
## kinematics from the clip's tracks and this character's bone rests.
func _feet_at(anim: Animation, time: float) -> PackedVector3Array:
	var hips_track := anim.find_track(NodePath("Skeleton3D:" + HIPS_BONE), Animation.TYPE_POSITION_3D)
	var hips := Transform3D(Basis(_bone_rotation(anim, HIPS_BONE, time)),
			anim.position_track_interpolate(hips_track, time) * _skeleton.motion_scale)
	var points := PackedVector3Array()
	for chain in LEG_CHAINS:
		var xform := hips
		for bone_name in chain:
			var rest := _skeleton.get_bone_rest(_skeleton.find_bone(bone_name))
			xform *= Transform3D(Basis(_bone_rotation(anim, bone_name, time)), rest.origin)
			if bone_name == chain[2] or bone_name == chain[3]:
				points.append(xform.origin)
	return points


func _bone_rotation(anim: Animation, bone_name: String, time: float) -> Quaternion:
	var track := anim.find_track(NodePath("Skeleton3D:" + bone_name), Animation.TYPE_ROTATION_3D)
	if track == -1:
		return _skeleton.get_bone_rest(_skeleton.find_bone(bone_name)).basis.get_rotation_quaternion()
	return anim.rotation_track_interpolate(track, time)


func _update_animation(delta: float) -> void:
	var weight := 1.0 - exp(-blend_sharpness * delta)
	_stride = lerpf(_stride, lerpf(jog_stride, 1.0, _sprint_weight), weight)
	# Turning makes the legs step (so pivots don't freeze them), except while
	# pivoting about a planted foot: then that foot holds and the body swings
	# round it, and stepping on the spot would only make the feet skate.
	var stepping := 1.0 - _pivot_share()
	_turn_motion = lerpf(_turn_motion, _yaw_rate * turn_step_radius * stepping, weight)
	var real := get_real_velocity()
	var ground_speed := Vector2(real.x, real.z).length()
	var speed := maxf(ground_speed, _turn_motion)
	_blend = lerpf(_blend, smoothstep(0.0, jog_blend_speed, speed), weight)
	_sprint_weight = lerpf(_sprint_weight, _sprint_weight_at(ground_speed), weight)
	if _blend < 0.02:
		# While the idle shows, hold the hidden gait where its feet match the
		# idle's, so moving off blends in from matching feet.
		var idle_time := float(_anim_tree.get(&"parameters/Idle/current_position"))
		_gait_phase = _best_phase(_feet_at(_idle_anim, idle_time), 0.0, 0.0)
	else:
		_gait_phase = fposmod(_gait_phase + _phase_rate(speed, _sprint_weight) * delta, 1.0)
	_anim_tree.set(&"parameters/IdleRate/scale", idle_rate)
	# Shorter strides: shrink the leg swing to match by mixing in the idle.
	_anim_tree.set(&"parameters/Locomotion/blend_amount", _blend * _stride)
	_anim_tree.set(&"parameters/Gait/blend_amount", _sprint_weight)
	_anim_tree.set(&"parameters/JogSeek/seek_request", fposmod(_gait_phase + _jog_offset, 1.0) * _jog_length)
	_anim_tree.set(&"parameters/SprintSeek/seek_request", fposmod(_gait_phase + _sprint_offset, 1.0) * _sprint_length)

	for clip in _one_shots:
		var fade_time := clip_fade_in_time if clip.playing else clip_fade_out_time
		clip.fade = move_toward(clip.fade, 1.0 if clip.playing else 0.0, delta / fade_time)
		_anim_tree.set(clip.blend_param, smoothstep(0.0, 1.0, clip.fade))
		if clip.fade > 0.0 or clip.playing:
			_anim_tree.set(clip.seek_param, clip.sample(clip.times, clip.distance))

	# The kick plays in time once the swing starts, over everything else; after
	# the follow-through it holds its last pose while fading back out.
	var swinging := kick_swinging
	if swinging:
		_kick_shown = _kick_time
	_kick_fade = move_toward(_kick_fade, 1.0 if swinging else 0.0, delta / (kick_fade_in if swinging else kick_fade_out))
	var shown := smoothstep(0.0, 1.0, _kick_fade)
	for foot in 2:
		var on := shown if foot == _kick_foot else 0.0
		_anim_tree.set(KICK_BLENDS[foot], on * (1.0 - _kick_layer))
		_anim_tree.set(KICK_LEG_BLENDS[foot], on * _kick_layer)
	_model.position.y = _kick_lift * shown * (1.0 - _kick_layer)
	if _kick_fade > 0.0:
		_anim_tree.set(KICK_SEEKS[_kick_foot], _kick_shown)
		_anim_tree.set(KICK_LEG_SEEKS[_kick_foot], _kick_shown)
