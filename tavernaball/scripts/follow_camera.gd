extends Camera3D
## Broadcast-style camera: keeps its height, distance and angle, and slides
## along the pitch's length (X) to follow the target.

@export var target: Node3D
## How quickly the camera catches up with the target (higher = snappier).
@export var follow_sharpness := 4.8


func _ready() -> void:
	# Moved every rendered frame from the target's interpolated position, so the
	# physics interpolation system must not interpolate it a second time.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if target:
		position.x = _target_x()


func _process(delta: float) -> void:
	if target == null:
		return
	var weight := 1.0 - exp(-follow_sharpness * delta)
	position.x = lerpf(position.x, _target_x(), weight)


func _target_x() -> float:
	return target.get_global_transform_interpolated().origin.x
