extends Node
## A stand-in teammate for trying passes: stands where it is put, keeps a ball
## it receives, and after `hold_time` passes it back to `pass_back_to`.
## Driven through the player's state, like a network copy would be.

@export var pass_back_to: NodePath
## How long it keeps the ball before passing it back (s).
@export var hold_time := 2.5
## Which way it faces at the start (degrees around Y; 0 faces +Z).
@export var facing := 0.0

var _held_for := 0.0

@onready var _player: Player = get_parent()
@onready var _passing: Passing = get_parent().get_node(^"Passing")
@onready var _dribble: Dribble = get_parent().get_node(^"Dribble")


func _ready() -> void:
	_player.read_input = false
	# After the player's own _ready.
	_player.face.call_deferred(deg_to_rad(facing))


func _physics_process(delta: float) -> void:
	if not _dribble.holding() or _passing.waiting() or _player.action == Player.Action.KICK:
		_held_for = 0.0
		return
	_held_for += delta
	var target := get_node_or_null(pass_back_to) as Player
	if _held_for >= hold_time and target:
		_passing.pass_to(target)
		_held_for = 0.0
