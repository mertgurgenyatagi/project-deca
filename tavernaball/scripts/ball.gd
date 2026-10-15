class_name Ball
extends Node3D
## The match ball. It is not a physics body; it moves itself so that it
## behaves the same on every machine:
## - Loose, it rolls along the ground from its last release, slowing at a
##   constant rate plus a drag that grows with the square of its speed, so a
##   hard pass loses pace quickly at first and then rolls on. Its position is a
##   pure function of the release (where, how fast, how much hop) and the time
##   since, so a release is all another machine needs.
## - Held, whoever holds it (the holder's Dribble) sets its acceleration each
##   tick, and changes its velocity outright only at a touch.
## It sits on the ground except for the small hop a hard kick can give it, and
## spins as it rolls so it never slides.

## Ball radius (m). A size-5 ball is 0.11.
@export var radius := 0.11
## How quickly a loose ball slows down at any speed (m/s²).
@export var roll_deceleration := 1.2
## Extra slowing of a loose ball per (m/s)² of speed (1/m): 0.025 adds
## 2.5 m/s² at 10 m/s and hardly anything at a dribble's pace.
@export var roll_drag := 0.025
## Share of its vertical speed a hopping ball keeps at each bounce.
@export var bounce := 0.35

const GRAVITY := 9.8
## A bounce slower than this (m/s) settles the ball on the ground.
const SETTLE_SPEED := 0.3

## Who has the ball (a player), or null when it is loose. Taking it ends any
## pass meant for someone.
var holder: Node = null:
	set(value):
		holder = value
		if value != null:
			intended = null
## Whom the ball was last passed to, until someone takes it (null: nobody).
var intended: Node = null
## Who last let the ball go, and so may not take it straight back.
var last_releaser: Node = null
var velocity := Vector3.ZERO
## Set by the holder each tick; unused while loose.
var acceleration := Vector3.ZERO

var _release_position := Vector3.ZERO
var _release_velocity := Vector3.ZERO
var _release_hop := 0.0
var _roll_time := 0.0

@onready var _mesh: Node3D = $Mesh


func _ready() -> void:
	process_physics_priority = 10
	add_to_group(&"ball")
	position.y = radius
	release(position, Vector3.ZERO)


## Lets the ball roll freely from `at` with velocity `vel` (only its ground
## part counts), hopping off the ground at `hop` m/s. `by` is whoever let it
## go, `to` whom it is passed to, if anyone.
func release(at: Vector3, vel: Vector3, by: Node = null, hop := 0.0, to: Node = null) -> void:
	holder = null
	intended = to
	last_releaser = by
	_release_position = Vector3(at.x, radius, at.z)
	_release_velocity = Vector3(vel.x, 0.0, vel.z)
	_release_hop = maxf(hop, 0.0)
	_roll_time = 0.0
	velocity = _release_velocity
	acceleration = Vector3.ZERO


## A touch while held: the ball's velocity changes outright.
func touch(vel: Vector3) -> void:
	velocity = Vector3(vel.x, 0.0, vel.z)


## Puts a loose, still ball at `at` without it travelling there.
func place(at: Vector3) -> void:
	position = Vector3(at.x, radius, at.z)
	release(position, Vector3.ZERO)
	reset_physics_interpolation()


## Seconds since the ball was last released (meaningful while loose).
func time_since_release() -> float:
	return _roll_time


## Where a loose ball is `t` seconds after its last release.
func roll_position_at(t: float) -> Vector3:
	var speed := _release_velocity.length()
	var at := _release_position
	if speed > 0.0:
		at += _release_velocity / speed * roll_distance(speed, t)
	at.y = radius + hop_height(_release_hop, t)
	return at


## Ground velocity of a loose ball `t` seconds after its last release.
func roll_velocity_at(t: float) -> Vector3:
	var speed := _release_velocity.length()
	if speed == 0.0:
		return Vector3.ZERO
	return _release_velocity / speed * roll_speed(speed, t)


# --- Rolling with drag --------------------------------------------------------
# Speed obeys dv/dt = -a - k·v² (a: roll_deceleration, k: roll_drag), which
# has closed forms: with s = √(a/k), w = √(a·k) and θ0 = atan(v0/s),
# v(t) = s·tan(θ0 − w·t) and x(t) = ln(cos(θ0 − w·t) / cos θ0) / k, until the
# ball stops at t = θ0/w. Along the path, a + k·v² = (a + k·v0²)·e^(−2k·x).

## Distance rolled `t` seconds after starting at `speed`.
func roll_distance(speed: float, t: float) -> float:
	var a := roll_deceleration
	var k := roll_drag
	if k <= 1e-6:
		var time := minf(t, speed / a)
		return speed * time - 0.5 * a * time * time
	var w := sqrt(a * k)
	var theta := atan(speed / sqrt(a / k))
	var time := minf(t, theta / w)
	return log(cos(theta - w * time) / cos(theta)) / k


## Speed `t` seconds after starting at `speed`.
func roll_speed(speed: float, t: float) -> float:
	var a := roll_deceleration
	var k := roll_drag
	if k <= 1e-6:
		return maxf(speed - a * t, 0.0)
	var s := sqrt(a / k)
	var theta := atan(speed / s) - sqrt(a * k) * t
	return s * tan(theta) if theta > 0.0 else 0.0


## How far a ball starting at `speed` rolls before it stops.
func stop_distance(speed: float) -> float:
	var a := roll_deceleration
	var k := roll_drag
	if k <= 1e-6:
		return speed * speed / (2.0 * a)
	return log(1.0 + k * speed * speed / a) / (2.0 * k)


## Starting speed that rolls the ball `distance` before it stops.
func speed_to_stop_at(distance: float) -> float:
	var a := roll_deceleration
	var k := roll_drag
	if k <= 1e-6:
		return sqrt(2.0 * a * distance)
	return sqrt(a * (exp(2.0 * k * distance) - 1.0) / k)


## Starting speed that brings the ball `distance` away still moving at `arrival`.
func speed_to_arrive(distance: float, arrival: float) -> float:
	var a := roll_deceleration
	var k := roll_drag
	if k <= 1e-6:
		return sqrt(arrival * arrival + 2.0 * a * distance)
	return sqrt(((a + k * arrival * arrival) * exp(2.0 * k * distance) - a) / k)


## Time a ball starting at `speed` takes to roll `distance` (INF if it stops short).
func time_to_roll(speed: float, distance: float) -> float:
	if distance <= 0.0:
		return 0.0
	if distance > stop_distance(speed):
		return INF
	var a := roll_deceleration
	var k := roll_drag
	if k <= 1e-6:
		return (speed - sqrt(maxf(speed * speed - 2.0 * a * distance, 0.0))) / a
	var theta := atan(speed / sqrt(a / k))
	return (theta - acos(minf(cos(theta) * exp(k * distance), 1.0))) / sqrt(a * k)


## Height above resting of a ball that left the ground at `hop` m/s, `t`
## seconds later: a hop, then smaller and smaller bounces.
func hop_height(hop: float, t: float) -> float:
	var up := hop
	while up >= SETTLE_SPEED:
		var flight := 2.0 * up / GRAVITY
		if t < flight:
			return up * t - 0.5 * GRAVITY * t * t
		t -= flight
		up *= bounce
	return 0.0


func _physics_process(delta: float) -> void:
	var previous := position
	if holder == null:
		_roll_time += delta
		position = roll_position_at(_roll_time)
		velocity = roll_velocity_at(_roll_time)
	else:
		velocity += Vector3(acceleration.x, 0.0, acceleration.z) * delta
		position += velocity * delta
		position.y = radius
	_spin(position - previous)


## Rolls the ball's look through the distance it just moved, without slipping.
func _spin(step: Vector3) -> void:
	step.y = 0.0
	var distance := step.length()
	if distance < 1e-6:
		return
	var axis := Vector3.UP.cross(step / distance)
	_mesh.basis = (Basis(axis, distance / radius) * _mesh.basis).orthonormalized()
