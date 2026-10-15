extends Control
## The pass strength bar, drawn just under the player's feet on screen while
## the pass button is held. A slim chalk-edged strip that fills like a pint:
## amber with a pale head on its leading edge, turning copper when full. It
## holds its level until the pass is decided, then fades.

@export var player_path: NodePath
## Bar size and gap below the feet, as shares of the screen height.
@export var bar_size := Vector2(0.06, 0.008)
@export var gap := 0.018
## How long the bar takes to fade once the pass is decided (s).
@export var fade_time := 0.35

const TRACK := Color("15171ab8")
const CHALK := Color("ece7dad9")
const AMBER := Color("e3a21a")
const COPPER := Color("c8641c")
const HEAD := Color("f6efd9")

var _player: Player
var _passing: Passing
var _shown := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_player = get_node_or_null(player_path) as Player
	if _player:
		_passing = _player.get_node_or_null(^"Passing") as Passing


func _process(delta: float) -> void:
	if _passing == null:
		return
	var active := _passing.charging or _passing.locking()
	_shown = 1.0 if active else move_toward(_shown, 0.0, delta / fade_time)
	queue_redraw()


func _draw() -> void:
	var camera := get_viewport().get_camera_3d()
	if _shown <= 0.0 or camera == null:
		return
	var feet := _player.get_global_transform_interpolated().origin
	if camera.is_position_behind(feet):
		return
	var height := get_viewport_rect().size.y
	var size := bar_size * height
	var at := camera.unproject_position(feet) + Vector2(-size.x * 0.5, gap * height)
	var level := _passing.strength
	var fade := Color(1, 1, 1, _shown)
	var outline := maxf(1.0, roundf(height / 540.0))
	draw_rect(Rect2(at, size), TRACK * fade)
	if level > 0.0:
		var fill := Rect2(at, Vector2(size.x * level, size.y))
		draw_rect(fill, AMBER.lerp(COPPER, smoothstep(0.85, 1.0, level)) * fade)
		var head := minf(outline * 2.0, fill.size.x)
		draw_rect(Rect2(fill.end.x - head, at.y, head, size.y), HEAD * fade)
	draw_rect(Rect2(at, size).grow(outline * 0.5), CHALK * fade, false, outline)
