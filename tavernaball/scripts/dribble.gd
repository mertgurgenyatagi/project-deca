class_name Dribble
extends Node
## Possession for the player this node sits under: picking up a loose ball and
## dribbling it with touches timed to the gait.
##
## The ball is never glued to the feet. A touch is the only time its velocity
## changes outright. Each touch sends it rolling to the spot where a foot will
## be at the next touch, arriving just as the foot gets there. Between
## touches, the target is predicted again every tick from the player's state.
## If the player steers, the ball's path bends toward the new target, up to a
## cap. The cap grows while the ball is off its plan, so the ball always comes
## back: possession is never lost without a defender.
##
## The player only changes what they do when a foot is on the ball: a new
## direction, a stop or a sprint change waits for a touch (see gate_input).
## While a change waits, the next touch is brought forward to the next step.
##
## Beyond that rhythm:
## - A foot that runs into the ball touches it, pushing it away from the foot.
## - Off its plan, the ball is touched early by the first toe that comes near.
## - Stopping and turnbacks only ever slow the ball along its path, never pull
##   it back toward the player: it rests in front, or for a turnback, beside
##   where the player stops, on the side the body turns.
##
## Everything here reads the player's state (position, velocity, facing,
## stride, input), never the keyboard. A copy of a player driven by the
## network would dribble with the same code.

enum Foot { LEFT, RIGHT }

@export_group("Touches")
## Foot for the first touch after taking the ball, and the side the ball rests on.
@export var preferred_foot := Foot.RIGHT
## Steps between touches at a jog (2 = one stride, the same foot each time).
@export var jog_touch_steps := 2
## Steps between touches at a full sprint.
@export var sprint_touch_steps := 4
## Input this far off the facing (degrees) halves the knock length.
@export var turn_shorten_angle := 60.0
## Touch this much of a stride before the toe's furthest forward reach.
@export var touch_phase_offset := 0.03
## Toe tip length past the toe joint (m).
@export var toe_tip := 0.06
## Ball sits this far to the outside of the touching foot (m).
@export var touch_side_offset := 0.04
## Ball's speed arriving at the next touch, as a share of the player's.
@export var arrival_speed_ratio := 0.55
## The same at a full sprint (lower = longer knocks).
@export var sprint_arrival_ratio := 0.4
## A touch sends the ball at most this many times the player's speed...
@export var touch_speed_ratio := 2.0
## ...plus this (m/s), so touches from a standstill can still move it.
@export var touch_speed_margin := 1.5

@export_group("Grip")
## At the start of a movement the player keeps the ball at their feet: grip
## is full at a standstill and gone by this share of jog speed, fading
## slowly at first and quickly near the end.
@export var grip_until := 1.0
## Steps between touches at full grip (1 = every step).
@export var grip_touch_steps := 1
## Ball's arrival speed at the next touch, as a share of the player's, at full
## grip: soft touches, so the ball hardly runs ahead.
@export var grip_arrival_ratio := 0.9
## The player's acceleration at full grip, as a share of normal: moving off
## with the ball is more careful than without it.
@export var grip_acceleration := 0.6
## At full grip the ball still counts as at the feet this far from the hips
## (m), so a waiting change is made at once (`control_reach` with no grip).
@export var grip_control_reach := 0.75
## A touch that takes the ball round a corner costs the player this share of
## their speed at a 180° change (proportionally less for smaller ones).
@export var redirect_slowdown := 0.5

@export_group("Control")
## Steering on the ball between touches (m/s²) before the cap starts growing.
@export var max_bend := 3.0
## How fast the cap grows while the ball is off its plan (m/s² per second).
@export var bend_growth := 20.0
## Extra slowing along the ball's path (m/s²) allowed on top of the plan
## without counting as bend: a ball slowing down looks natural, one curving or
## speeding up does not.
@export var free_braking := 8.0
## Free braking during a turnback's brake (m/s²): the ball is stopped hard
## so the player can turn with it.
@export var turnback_braking := 12.0
## Where the ball comes to rest for a turnback, relative to where the player
## stops: this far ahead along the old direction (m)...
@export var turnback_ball_ahead := 0.2
## ...and this far to the side (m), positive toward the side the body turns.
@export var turnback_ball_side := 0.25
## A toe this close to the ball's surface (m) can make an early touch once the
## ball is off its plan; any toe that reaches the ball touches it.
@export var touch_reach := 0.08
## A rhythm touch is skipped if the ball is further than this (m) from the
## touching foot; the ball keeps bending toward the next one instead.
@export var miss_distance := 0.3
## Preferred distance in front of the hips for the ball to come to rest (m).
@export var rest_distance := 0.5
## The ball is braked so it comes to rest no further than this in front (m).
@export var rest_max_distance := 1.0
## A loose ball within this distance of the player (m) is taken.
@export var pickup_reach := 0.6
## A held ball this close to the hips (m) counts as at the feet: a waiting
## change of direction can be made with a touch.
@export var control_reach := 0.5
## While a change waits, a toe this close to the ball's surface (m) reaches
## for it and makes the touch. Kept small: too large and the ball answers the
## keys at once, as if attached.
@export var reach_for_ball := 0.14
const PREDICT_STEP := 1.0 / 60.0
const PREDICT_HORIZON := 2.5
## Below this predicted speed (m/s) at the next touch, the ball is brought to rest instead.
const REST_SPEED := 0.3
## No early touch within this long (s) of the last touch.
const TOUCH_COOLDOWN := 0.2
const MAX_TOUCH_SPEED := 12.0
## Shortest time a touch plans for the ball to reach its target (s).
const MIN_SEGMENT_TIME := 0.15
## Shortest time between a touch and a foot-contact touch (s).
const CONTACT_COOLDOWN := 0.08
## A foot-contact touch sends the ball away from the foot at least this much
## faster than the foot moves (m/s).
const CONTACT_PUSH := 0.4
## Half-thickness of the foot capsule (m).
const FOOT_RADIUS := 0.03
const TOE_BONES := ["mixamorig_LeftToeBase", "mixamorig_RightToeBase"]
const ANKLE_BONES := ["mixamorig_LeftFoot", "mixamorig_RightFoot"]

## Read-outs for tests.
var touch_log: Array[Dictionary] = []
var bend_now := 0.0

var ball: Ball
var _resting := false
## Unwrapped stride phase (whole cycles count up), and the phase of the next touch.
var _phase := 0.0
var _cycles := 0
var _last_raw_phase := 0.0
var _next_touch_phase := 0.0
var _next_foot := Foot.RIGHT
## The current segment's planned (honest) acceleration and the bend cap.
var _planned_accel := Vector3.ZERO
var _bend_cap := 0.0
var _clamped := false
var _since_touch := 0.0
## Set when this player let the ball go; cleared once it has been out of reach.
var _wait_for_clear := false
var _ready_done := false
var _touch_phase_jog := [0.0, 0.0]
var _touch_phase_sprint := [0.0, 0.0]
var _toe_bones := [-1, -1]
var _ankle_bones := [-1, -1]
var _last_toes := [Vector3.INF, Vector3.INF]
var _clock := 0.0
## The keys as pressed, and the direction and sprint the player is allowed to
## act on: with the ball, these only change at a touch.
var _raw_input := Vector2.ZERO
var _raw_sprint := false
var _latched_input := Vector2.ZERO
var _latched_sprint := false
## What the player actually moves on: the latched input, adjusted while a
## change waits (see gate_input).
var _effective_input := Vector2.ZERO
var _was_pending := false

@onready var _player: Player = get_parent()


func _physics_process(delta: float) -> void:
	_clock += delta
	if not _ready_done:
		_late_ready()
	if ball == null:
		return
	# Whole stride cycles plus the player's phase, so it always matches the gait.
	var raw := _player.gait_phase
	if raw - _last_raw_phase < -0.5:
		_cycles += 1
	elif raw - _last_raw_phase > 0.5:
		_cycles -= 1
	_phase = _cycles + raw
	_last_raw_phase = raw
	_since_touch += delta

	if ball.holder == null:
		if can_take(ball):
			ball.holder = _player
			_touch("pickup")
		return
	if ball.holder != _player:
		return
	_steer(delta)


func holding() -> bool:
	return ball != null and ball.holder == _player


## The movement input the player may act on this tick. With the ball, a new
## direction (or stopping) waits until a foot is on the ball: the player keeps
## going the way they last touched it, and the next touch is brought forward
## to the very next step. Standing with the ball out of reach, the player
## first steps up to it.
func gate_input(raw: Vector2) -> Vector2:
	_raw_input = raw
	if not holding():
		_latched_input = raw
		_effective_input = raw
		return raw
	_effective_input = _latched_input
	if _direction_pending() and _player.action == Player.Action.NONE and _latched_input == Vector2.ZERO:
		var to_ball := _ground(ball.position) - _hips()
		_effective_input = Vector2.ZERO if to_ball.length() <= control_reach else to_ball.normalized()
	return _effective_input


## Sprint the player may act on: with the ball, it changes only at a touch.
func gate_sprint(raw: bool) -> bool:
	_raw_sprint = raw
	if not holding():
		_latched_sprint = raw
		return raw
	return _latched_sprint


## What the player wants to do but is waiting for the ball to do, for the
## body to hint at: the signed turn toward the new direction (rad, + left;
## 0 if none), whether a stop is waiting, and a sprint change (+1 start, -1
## ease off, 0 none).
func intent_turn() -> float:
	if not holding() or not _direction_pending() or _raw_input == Vector2.ZERO:
		return 0.0
	return angle_difference(_player.yaw, atan2(_raw_input.x, _raw_input.y))


func intent_stop() -> bool:
	return holding() and _raw_input == Vector2.ZERO and _latched_input != Vector2.ZERO


func intent_sprint() -> int:
	if not holding() or _raw_sprint == _latched_sprint or _raw_input == Vector2.ZERO:
		return 0
	return 1 if _raw_sprint else -1


## Whether a new direction, or a stop or start, is waiting for a touch.
func _direction_pending() -> bool:
	if (_raw_input == Vector2.ZERO) != (_latched_input == Vector2.ZERO):
		return true
	if _raw_input == Vector2.ZERO:
		return false
	return absf(_raw_input.angle_to(_latched_input)) > deg_to_rad(5.0)


## Lets the player act on the keys as they are now.
func _latch() -> void:
	_latched_input = _raw_input
	_latched_sprint = _raw_sprint
	_effective_input = _raw_input


## The pickup rule: a loose ball close enough, unless this player just let it
## go and it hasn't been out of reach since. Later, with networking, this is
## the call the host decides.
func can_take(b: Ball) -> bool:
	var gap := _ground(b.position).distance_to(_hips())
	if _wait_for_clear:
		if gap > pickup_reach:
			_wait_for_clear = false
		return false
	return gap <= pickup_reach


## Lets the ball go from the player's feet (the debug knock, later passes and shots).
func release(velocity: Vector3) -> void:
	if ball and ball.holder == _player:
		_wait_for_clear = true
		ball.release(ball.position, velocity, _player)


## Clears touch state when a test teleports the player or the ball.
func reset_for_test() -> void:
	_wait_for_clear = false
	_resting = false
	_planned_accel = Vector3.ZERO
	_last_raw_phase = _player.gait_phase
	_last_toes = [Vector3.INF, Vector3.INF]


func _late_ready() -> void:
	_ready_done = true
	ball = get_tree().get_first_node_in_group(&"ball") as Ball
	for f in 2:
		_touch_phase_jog[f] = _find_touch_phase(f, 0.0)
		_touch_phase_sprint[f] = _find_touch_phase(f, 1.0)
		_toe_bones[f] = _player.skeleton.find_bone(TOE_BONES[f])
		_ankle_bones[f] = _player.skeleton.find_bone(ANKLE_BONES[f])
	_last_raw_phase = _player.gait_phase
	_next_foot = preferred_foot


## Stride phase at which a foot touches: just before its toe reaches furthest forward.
func _find_touch_phase(foot: int, weight: float) -> float:
	const SAMPLES := 400
	var best := 0.0
	var best_reach := -INF
	for i in SAMPLES:
		var phase := float(i) / SAMPLES
		var reach := _player.gait_feet_at(phase, weight)[foot * 2 + 1].z
		if reach > best_reach:
			best_reach = reach
			best = phase
	return fposmod(best - touch_phase_offset, 1.0)


func _touch_phase(foot: int, weight: float) -> float:
	var jog: float = _touch_phase_jog[foot]
	return jog + angle_difference(jog * TAU, _touch_phase_sprint[foot] * TAU) / TAU * weight


## Model-space centre of the ball where a foot touches it at a stride phase.
func _contact_offset(foot: int, phase: float, weight: float) -> Vector3:
	var toe := _player.gait_feet_at(phase, weight)[foot * 2 + 1]
	var outward := 1.0 if foot == Foot.LEFT else -1.0
	return Vector3(toe.x + outward * touch_side_offset, 0.0, toe.z + toe_tip + ball.radius)


# --- Prediction -------------------------------------------------------------

## A rough forward simulation of the player's movement from the current state
## and input (see player.gd for the real thing).
class Sim:
	var position: Vector2
	var velocity: Vector2
	var yaw: float
	var phase: float
	var time := 0.0
	var action: int
	var speed: float:
		get: return velocity.length()


func _sim_start() -> Sim:
	var s := Sim.new()
	s.position = _hips()
	s.velocity = _player.ground_velocity
	s.yaw = _player.yaw
	s.phase = _phase
	s.action = _player.action
	return s


func _sim_step(s: Sim, dt: float) -> void:
	var p := _player
	var input := _effective_input
	var top := p.sprint_speed if _latched_sprint else p.move_speed
	var speed := s.speed
	var accel := p.sprint_acceleration if _latched_sprint else p.acceleration
	accel *= lerpf(1.0, grip_acceleration, _grip_at(speed))
	match s.action:
		Player.Action.BRAKE:
			speed = move_toward(speed, 0.0, p.turnback_brake * dt)
			s.velocity = s.velocity.normalized() * speed if speed > 0.0 else Vector2.ZERO
			if speed == 0.0:
				s.action = Player.Action.PUSH_OFF
		Player.Action.PUSH_OFF:
			speed = move_toward(speed, top, accel * dt)
			s.velocity = p.action_dir * speed
			s.yaw = atan2(p.action_dir.x, p.action_dir.y)
		_:
			if input == Vector2.ZERO:
				speed = move_toward(speed, 0.0, p.deceleration * dt)
			else:
				var target_yaw := atan2(input.x, input.y)
				var max_step := p.turn_rate_at(speed) * dt
				var step := angle_difference(s.yaw, target_yaw) * (1.0 - exp(-p.turn_sharpness * dt))
				s.yaw = wrapf(s.yaw + clampf(step, -max_step, max_step), -PI, PI)
				var target_speed := 0.0
				if absf(angle_difference(s.yaw, target_yaw)) < deg_to_rad(p.go_angle):
					target_speed = top * input.length()
				var rate := accel
				if target_speed < speed:
					rate = p.sprint_slowdown if target_speed > 0.0 else p.deceleration
				speed = move_toward(speed, target_speed, rate * dt)
			s.velocity = Vector2(sin(s.yaw), cos(s.yaw)) * speed
	s.position += s.velocity * dt
	s.phase += p.phase_rate_at(speed) * dt
	s.time += dt


## Simulates until the stride reaches `phase` (or the horizon). Returns the
## state at that moment.
func _predict_to_phase(phase: float) -> Sim:
	var s := _sim_start()
	while s.phase < phase and s.time < PREDICT_HORIZON:
		var before := s.phase
		_sim_step(s, PREDICT_STEP)
		if s.phase >= phase:
			# Step back to the exact crossing.
			var back := (s.phase - phase) / maxf(s.phase - before, 1e-6) * PREDICT_STEP
			s.position -= s.velocity * back
			s.time -= back
			s.phase = phase
	return s


## Simulates until the player stands still (or the horizon).
func _predict_stop() -> Sim:
	var s := _sim_start()
	while s.speed > 0.0 and s.time < PREDICT_HORIZON:
		_sim_step(s, PREDICT_STEP)
	return s


# --- Planning ---------------------------------------------------------------

## The next touch's phase: the first touch phase of `foot` (or either foot, if
## -1) at least `min_ahead` cycles ahead of now.
func _touch_after(min_ahead: float, foot: int) -> void:
	var weight := _player.sprint_weight
	var best := INF
	for f in 2:
		if foot != -1 and f != foot:
			continue
		var tp := _touch_phase(f, weight)
		var k := ceilf(_phase + min_ahead - tp)
		var candidate := tp + k
		if candidate < best:
			best = candidate
			_next_foot = f
	_next_touch_phase = best


## Steps to the next touch: from the jog count to the sprint count by speed,
## shortened while the input points away from the facing.
func _touch_steps() -> int:
	var steps := lerpf(jog_touch_steps, sprint_touch_steps, _player.sprint_weight)
	steps = lerpf(steps, grip_touch_steps, _grip())
	var input := _latched_input
	if input != Vector2.ZERO:
		var off := absf(angle_difference(_player.yaw, atan2(input.x, input.y)))
		steps *= clampf(1.0 - 0.5 * rad_to_deg(off) / turn_shorten_angle, 0.5, 1.0)
	return maxi(roundi(steps), 1)


## Scale on the player's acceleration: slower moving off while gripping the ball.
func acceleration_scale() -> float:
	if not holding():
		return 1.0
	return lerpf(1.0, grip_acceleration, _grip())


## How firmly the ball is kept at the feet: 1 at a standstill, easing to 0 by
## `grip_until` × jog speed.
func _grip() -> float:
	return _grip_at(_player.ground_velocity.length())


func _grip_at(speed: float) -> float:
	# Eases off gently at first and falls away only near the top, so grip
	# lasts through most of the acceleration.
	var x := clampf(speed / (grip_until * _player.move_speed), 0.0, 1.0)
	return 1.0 - x * x


## Where the ball should next arrive, when, and how fast.
## Returns [target, time_left, arrival_velocity] in world space.
func _target() -> Array:
	if _player.action == Player.Action.BRAKE or _player.would_turn_back(_latched_input):
		return _turnback_target()
	if _pivoting():
		return _pivot_target()
	if not _resting:
		var s := _predict_to_phase(_next_touch_phase)
		if s.time < PREDICT_HORIZON and s.speed >= REST_SPEED:
			var weight := _player.sprint_weight_at(s.speed)
			var offset := _contact_offset(_next_foot, fposmod(_next_touch_phase, 1.0), weight)
			var target := _world(s.position, s.yaw, offset)
			var ratio := lerpf(arrival_speed_ratio, sprint_arrival_ratio, _player.sprint_weight)
			ratio = lerpf(ratio, grip_arrival_ratio, _grip())
			return [target, s.time, Vector3(s.velocity.x, 0.0, s.velocity.y) * ratio]
		_resting = true
	return _rest_target()


## During a turnback's brake: bring the ball to rest beside where the player
## stops, so the push-off can take it away from that side rather than drag
## it back through the legs.
func _turnback_target() -> Array:
	var starting := _player.action != Player.Action.BRAKE
	var s := _sim_start()
	# A turnback about to start (the touch that allows it) brakes from now.
	s.action = Player.Action.BRAKE
	while s.action == Player.Action.BRAKE and s.time < PREDICT_HORIZON:
		_sim_step(s, PREDICT_STEP)
	var old_dir := _player.ground_velocity.normalized()
	if old_dir == Vector2.ZERO:
		old_dir = Vector2(sin(_player.yaw), cos(_player.yaw))
	# The body turns toward `turn` (+1 left, -1 right of the old direction).
	var turn := signf(_player.turn_for(_latched_input) if starting else _player.turn_direction)
	var left := Vector2(old_dir.y, -old_dir.x)
	var at := s.position + old_dir * turnback_ball_ahead + left * turn * turnback_ball_side
	return [Vector3(at.x, ball.radius, at.y), maxf(s.time, PREDICT_STEP), Vector3.ZERO]


## Turning far round on the spot (not fast enough for a turnback).
func _pivoting() -> bool:
	if _latched_input == Vector2.ZERO or _player.action != Player.Action.NONE:
		return false
	if _player.ground_velocity.length() > _player.turnback_min_speed:
		return false
	return absf(angle_difference(_player.yaw, atan2(_latched_input.x, _latched_input.y))) > deg_to_rad(100.0)


## A pivot on the spot takes the ball round to the side the body turns
## toward, rather than through the feet.
func _pivot_target() -> Array:
	var facing := Vector2(sin(_player.yaw), cos(_player.yaw))
	var turn := _player.turn_for(_latched_input)
	var left := Vector2(facing.y, -facing.x)
	var new_dir := _latched_input.normalized()
	var at := _hips() + left * signf(turn) * turnback_ball_side + new_dir * 0.15
	var time := absf(turn) / _player.turn_rate_at(0.0) + 0.1
	return [Vector3(at.x, ball.radius, at.y), time, Vector3.ZERO]


## Where the ball should come to rest when the player stops: `rest_distance`
## in front of where the player is predicted to stop. Used to aim the touch
## that stops it; afterwards it only brakes.
func _rest_point() -> Array:
	var stop := _predict_stop()
	var at := _world(stop.position, stop.yaw, Vector3(0.0, 0.0, rest_distance))
	return [at, stop.time + 0.25, Vector3.ZERO]


## Bringing the ball to rest: it only ever slows down along its own path, never
## steers back toward the player. It stops where that path comes nearest
## `rest_distance` in front of where the player stops, no further than
## `rest_max_distance`, within what rolling plus free braking allows.
func _rest_target() -> Array:
	var v := ball.velocity
	var speed := v.length()
	if speed < 0.05:
		return [ball.position, PREDICT_STEP, Vector3.ZERO]
	var stop := _predict_stop()
	var facing := Vector2(sin(stop.yaw), cos(stop.yaw))
	var along := _ground(v) / speed
	# Forward distance (in front of the stopped player) of the ball after rolling s metres.
	var ahead_now := (_ground(ball.position) - stop.position).dot(facing)
	var ahead_rate := along.dot(facing)
	var shortest := speed * speed / (2.0 * (ball.roll_deceleration + free_braking))
	var longest := speed * speed / (2.0 * ball.roll_deceleration)
	# A ball not heading in front of the player is stopped as soon as it can be.
	var roll := shortest
	if ahead_rate > 0.01:
		var wanted := (rest_distance - ahead_now) / ahead_rate
		var furthest := (rest_max_distance - ahead_now) / ahead_rate
		roll = minf(maxf(wanted, 0.0), maxf(furthest, 0.0))
	roll = clampf(roll, shortest, longest)
	var target := ball.position + v / speed * roll
	return [target, 2.0 * roll / speed, Vector3.ZERO]


## Leaves rest once the player is predicted to be moving at the next touch.
func _update_resting() -> void:
	if not _resting:
		return
	var input := _latched_input
	if input == Vector2.ZERO:
		return
	_touch_after(0.3, -1)
	var s := _predict_to_phase(_next_touch_phase)
	if s.time < PREDICT_HORIZON and s.speed >= REST_SPEED:
		_resting = false
		_clamped = true


## A touch: the ball's velocity changes outright, starting a new segment.
func _touch(kind: String, contact := {}) -> void:
	var error := _contact_error()
	# Taking the ball round a corner costs pace (a turnback brakes anyway).
	if _latched_input != Vector2.ZERO and _raw_input != Vector2.ZERO and not _player.would_turn_back(_raw_input):
		var share := absf(_latched_input.angle_to(_raw_input)) / PI
		_player.scale_speed(1.0 - redirect_slowdown * share)
	# A foot is on the ball: the player may now act on the keys as they are.
	_latch()
	if kind == "regular":
		_touch_after(_touch_steps() * 0.5 - 0.25, _next_foot if _touch_steps() % 2 == 0 else 1 - _next_foot)
	else:
		_resting = false
		_touch_after(jog_touch_steps * 0.5 - 0.25, -1)
	var plan := _target()
	if _resting:
		# The stopping touch rolls the ball to just in front of where the player stops.
		plan = _rest_point()
	var target: Vector3 = plan[0]
	var time: float = maxf(plan[1], PREDICT_STEP)
	var arrival: Vector3 = plan[2]
	time = maxf(time, MIN_SEGMENT_TIME)
	var launch := 2.0 * (target - ball.position) / time - arrival
	launch.y = 0.0
	# A touch is never much harder than the player's own pace calls for.
	var pace := maxf(_player.ground_velocity.length(), arrival.length() / maxf(arrival_speed_ratio, 0.1))
	launch = launch.limit_length(minf(touch_speed_ratio * pace + touch_speed_margin, MAX_TOUCH_SPEED))
	if not contact.is_empty():
		# The foot pushes the ball away from itself, faster than the foot moves.
		var normal: Vector3 = contact.normal
		var least: float = contact.speed + CONTACT_PUSH
		var away := launch.dot(normal)
		if away < least:
			launch += normal * (least - away)
	ball.touch(launch)
	# The acceleration that reaches the target from this launch. Only its
	# slowing along the launch is honest (a rolling ball can't speed up or curve
	# by itself); anything else is left to the capped bend.
	var accel := 2.0 * (target - ball.position - launch * time) / (time * time)
	accel.y = 0.0
	var along := launch.normalized()
	_planned_accel = along * minf(accel.dot(along), 0.0)
	_bend_cap = max_bend
	_clamped = false
	_since_touch = 0.0
	touch_log.append({"time": _clock, "kind": kind, "foot": _next_foot, "error": error})


## Each held tick: touch on rhythm, or steer the ball toward its target.
func _steer(delta: float) -> void:
	_update_resting()
	var contact := _foot_contact(delta)
	if not _resting and _phase >= _next_touch_phase:
		if _contact_error() <= miss_distance:
			_touch("regular")
		else:
			# Missed: the ball isn't at the foot. Aim it at the next touch instead.
			_touch_after(0.25, -1)
			_clamped = true
	elif contact.gap < 0.0 and _since_touch > CONTACT_COOLDOWN:
		# A foot ran into the ball: that is a touch, and it pushes the ball away.
		_touch("contact", contact)
	elif _direction_pending() and _since_touch > CONTACT_COOLDOWN \
			and (contact.gap < reach_for_ball or _ground(ball.position).distance_to(_hips()) <= lerpf(control_reach, grip_control_reach, _grip())):
		# The player reaches for the ball: make the waiting change with this touch.
		_touch("control")
	elif _clamped and contact.gap < touch_reach and _since_touch > TOUCH_COOLDOWN:
		_touch("early")

	var pending := _direction_pending()
	if pending and not _was_pending and not _resting:
		# A change is waiting: the player goes for the ball. The next touch
		# moves to the very next foot swing, and a toe reaching for the ball
		# can make it sooner still.
		_touch_after(0.25, -1)
		_clamped = true
	_was_pending = pending

	var plan := _target()
	var target: Vector3 = plan[0]
	var time: float = maxf(plan[1], delta)
	var arrival: Vector3 = plan[2]
	var v := ball.velocity
	var needed := (6.0 * (target - ball.position) - 2.0 * time * (2.0 * v + arrival)) / (time * time)
	needed.y = 0.0
	# The segment's planned slowing, always against the ball's current motion
	# (if steering has turned the ball round, slowing must not push it on).
	var honest := Vector3.ZERO
	if v.length() > 0.01:
		honest = v.normalized() * minf(_planned_accel.dot(v.normalized()), 0.0)
	if _resting:
		# A resting plan's honest motion is just the ball rolling to a stop.
		honest = -v.normalized() * ball.roll_deceleration if v.length() > 0.01 else Vector3.ZERO
	var bend := needed - honest
	if v.length() > 0.01:
		# Slowing along the path, up to free_braking, is not bend.
		var back := -v.normalized()
		var free := turnback_braking if _player.action == Player.Action.BRAKE else free_braking
		var braking := clampf(bend.dot(back), 0.0, free)
		honest += back * braking
		bend -= back * braking
	if bend.length() > _bend_cap:
		bend = bend.normalized() * _bend_cap
		_bend_cap += bend_growth * delta
		_clamped = true
	bend_now = bend.length()
	ball.acceleration = honest + bend
	if _resting and v.length() < 0.05:
		ball.velocity = Vector3.ZERO
		ball.acceleration = Vector3.ZERO


# --- Geometry ---------------------------------------------------------------

func _hips() -> Vector2:
	return _ground(_player.global_position)


func _ground(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


func _world(at: Vector2, yaw: float, offset: Vector3) -> Vector3:
	var rotated := Basis(Vector3.UP, yaw) * offset
	return Vector3(at.x + rotated.x, ball.radius, at.y + rotated.z)


func _toe_world(foot: int) -> Vector3:
	var skel := _player.skeleton
	return skel.global_transform * skel.get_bone_global_pose(_toe_bones[foot]).origin


## The foot nearest the ball, each foot modelled as a capsule from the ankle
## through the toe joint to the toe tip: {gap (m, negative = inside the ball),
## foot, normal (ground direction from the foot to the ball), speed (the
## foot's ground speed along that normal, m/s)}.
func _foot_contact(delta: float) -> Dictionary:
	var skel := _player.skeleton
	var nearest := {"gap": INF, "foot": 0, "normal": Vector3.ZERO, "speed": 0.0}
	for f in 2:
		var ankle := skel.global_transform * skel.get_bone_global_pose(_ankle_bones[f]).origin
		var toe := _toe_world(f)
		var tip := toe + (toe - ankle).normalized() * toe_tip
		var foot_velocity: Vector3 = (toe - _last_toes[f]) / delta if _last_toes[f] != Vector3.INF else Vector3.ZERO
		_last_toes[f] = toe
		for segment in [[ankle, toe], [toe, tip]]:
			var closest := Geometry3D.get_closest_point_to_segment(ball.position, segment[0], segment[1])
			var gap := closest.distance_to(ball.position) - ball.radius - FOOT_RADIUS
			if gap < nearest.gap:
				var normal := ball.position - closest
				normal.y = 0.0
				normal = normal.normalized()
				nearest = {"gap": gap, "foot": f, "normal": normal, "speed": maxf(foot_velocity.dot(normal), 0.0)}
	return nearest


## How far the ball is from where the touching foot's real toe says it should be (m).
func _contact_error() -> float:
	var toe := _toe_world(_next_foot)
	var outward := 1.0 if _next_foot == Foot.LEFT else -1.0
	var ideal := toe + Basis(Vector3.UP, _player.yaw) * Vector3(outward * touch_side_offset, 0.0, toe_tip + ball.radius)
	return _ground(ideal).distance_to(_ground(ball.position))
