class_name Ball
extends Node3D
## The match ball. It is not a physics body; it moves itself so that it
## behaves the same on every machine:
## - Loose, it rolls along the ground from its last release, slowing at a
##   constant rate. Its position is a pure function of the release (where, how
##   fast) and the time since, so a release is all another machine needs.
## - Held, whoever holds it (the holder's Dribble) sets its acceleration each
##   tick, and changes its velocity outright only at a touch.
## It always sits on the ground, and spins as it rolls so it never slides.

## Ball radius (m). A size-5 ball is 0.11.
@export var radius := 0.11
## How quickly a loose ball slows down (m/s²).
@export var roll_deceleration := 1.2

## Who has the ball (a player), or null when it is loose.
var holder: Node = null
## Who last let the ball go, and so may not take it straight back.
var last_releaser: Node = null
var velocity := Vector3.ZERO
## Set by the holder each tick; unused while loose.
var acceleration := Vector3.ZERO

var _release_position := Vector3.ZERO
var _release_velocity := Vector3.ZERO
var _roll_time := 0.0

@onready var _mesh: Node3D = $Mesh


func _ready() -> void:
	process_physics_priority = 10
	position.y = radius
	release(position, Vector3.ZERO)


## Lets the ball roll freely from `at` with velocity `vel` (only its ground
## part counts). `by` is whoever let it go.
func release(at: Vector3, vel: Vector3, by: Node = null) -> void:
	holder = null
	last_releaser = by
	_release_position = Vector3(at.x, radius, at.z)
	_release_velocity = Vector3(vel.x, 0.0, vel.z)
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


## Where a loose ball is `t` seconds after its last release.
func roll_position_at(t: float) -> Vector3:
	var speed := _release_velocity.length()
	if speed == 0.0:
		return _release_position
	var time := minf(t, speed / roll_deceleration)
	var distance := speed * time - 0.5 * roll_deceleration * time * time
	return _release_position + _release_velocity / speed * distance


func _physics_process(delta: float) -> void:
	var previous := position
	if holder == null:
		_roll_time += delta
		position = roll_position_at(_roll_time)
		var speed := maxf(_release_velocity.length() - roll_deceleration * _roll_time, 0.0)
		velocity = _release_velocity.normalized() * speed
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
