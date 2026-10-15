class_name Passing
extends Node
## Ground passes, PES style, for the player this node sits under.
##
## Holding the pass button fills the strength bar (full after `charge_time`).
## `lock_delay` after the button is let go, the pass is decided, from the
## movement keys as they are then (or the facing, with no keys held):
## - Teammates inside a `cone_angle` cone around that direction are ranked by
##   −(distance from the cone's centre line)² − distance. With N of them, the
##   bar is split into N bands, the first going to the top-ranked, each band
##   `band_ratio` times the next (60/40 for two, 47/32/21 for three). Where
##   the strength lands picks the receiver. The ball is played to them at a
##   pace set by the distance alone, √distance ÷ `pace_constant`, partly
##   leading a running receiver.
## - With nobody in the cone, the ball goes straight along it, as far as the
##   strength says.
## The decision is carried out the next time the player is on the ball: at
## once with the ball at their feet, or first time when a ball comes to them,
## for up to `queue_time`. Kicking takes a plant and a turn (player.gd), so a
## pass far from where the player was heading takes longer.
##
## Everything here reads the player's state and buttons (never the keyboard),
## so a network copy of a player would pass with the same code.

@export_group("Button")
## Time to fill the strength bar (s).
@export var charge_time := 0.3
## The pass is decided this long after the button is let go (s; 0 = as it
## is let go); the direction can still change until then.
@export var lock_delay := 0.0
## A decided pass waits this long for the ball (s).
@export var queue_time := 4.0

@export_group("Aim")
## Teammates within this cone (degrees, full width) around the aim can receive.
@export var cone_angle := 90.0
## Each receiver's band of the strength bar is this many times the next one's.
@export var band_ratio := 1.5
## Share of a running receiver's motion over the ball's travel time that the
## pass leads them by (1 = into their stride, 0 = to where they are).
@export var lead := 0.5

@export_group("Pace")
## A pass to a teammate is struck at √distance ÷ this (m/s, distance in m),
## whatever the strength: 0.1556 strikes a 3 m pass at 11.1 m/s, 10 m at 20.
@export var pace_constant := 0.1556
## With nobody to receive it, the ball rolls this far at an empty bar (m)...
@export var min_distance := 8.0
## ...and this far at a full one (m).
@export var max_distance := 30.0
## Passes struck faster than this (m/s) hop off the ground...
@export var hop_from := 13.0
## ...by this much hop (m/s up) per m/s over it...
@export var hop_per_speed := 0.25
## ...up to this (m/s up).
@export var max_hop := 1.2

@export_group("Kick")
## The swing starts once the ball is this close to where the foot will meet it (m)...
@export var set_reach := 0.12
## ...or, kicking on the run, this close (the ball is steered in during the swing).
@export var run_reach := 0.25
## A plant that takes longer than this (s) swings anyway; the ball is steered in.
@export var plant_timeout := 1.5
## First time: the swing starts if the coming ball will be this close to the
## foot as it meets it (m). Otherwise the ball is controlled first.
@export var first_time_reach := 0.2

@export_group("Sound")
## Kick sounds, one picked at random each time.
@export var sounds: Array[AudioStream] = []

## The strength bar, 0 to 1, and whether it is filling.
var strength := 0.0
var charging := false
## Read-out for tests: one entry per kick that sent the ball away.
var kick_log: Array[Dictionary] = []

var _was_held := false
## Time left before the decision locks (-1: none coming).
var _lock_in := -1.0
## A decided pass waiting for the ball: {target (Player or null), direction,
## strength, left (s)}.
var _decision := {}
## The pass being carried out: the decision plus {first_time, released, plant}.
var _kick := {}
var _clock := 0.0
var _sound: AudioStreamPlayer3D

@onready var _player: Player = get_parent()
@onready var _dribble: Dribble = get_parent().get_node(^"Dribble")


func _ready() -> void:
	_sound = AudioStreamPlayer3D.new()
	_sound.unit_size = 8.0
	add_child(_sound)


func _physics_process(delta: float) -> void:
	_clock += delta
	if _dribble.ball == null:
		return
	_read_button(delta)
	if _kick.is_empty():
		_wait_for_ball(delta)
	if not _kick.is_empty():
		_carry_out(delta)


## Whether a decided pass is waiting for the ball.
func waiting() -> bool:
	return not _decision.is_empty()


## Whether the button has been let go and the pass is about to be decided.
func locking() -> bool:
	return _lock_in >= 0.0


## A pass to `target` straight away, with no button (the stand-in teammates).
func pass_to(target: Player) -> void:
	var to := _ground(target.global_position) - _hips()
	_decision = {"target": target, "direction": to.normalized(), "strength": 0.0, "left": queue_time}


## While a pass meant for this player is on its way, the run that meets it,
## as [movement input, sprint]; empty otherwise. The player goes for the ball
## whatever the keys say (player.gd). They aim for where their current run
## meets the ball's path, since the pass was played there, at the pace that
## gets them there in time; if that can't be made, for the first point of the
## path they can reach at a sprint. There, they wait for it, facing it.
func receive_run() -> Array:
	var ball := _dribble.ball
	if ball == null or ball.holder != null or ball.intended != _player:
		return []
	var hips := _hips()
	var run := _player.ground_velocity
	var jog := _player.move_speed * _player.off_ball_boost
	var sprint := _player.sprint_speed * _player.off_ball_boost
	var reach := _dribble.pickup_reach * 0.5
	var t0 := ball.time_since_release()
	var meet := Vector2.INF
	var meet_time := 0.0
	var closest := INF
	var earliest := Vector2.INF
	var earliest_time := 0.0
	var t := 0.0
	while t <= 4.0:
		var at := _ground(ball.roll_position_at(t0 + t))
		var gap := at.distance_to(hips + run * t)
		if gap < closest:
			closest = gap
			meet = at
			meet_time = t
		if earliest == Vector2.INF and hips.distance_to(at) - reach <= sprint * t:
			earliest = at
			earliest_time = t
		t += 1.0 / 30.0
	if (meet.distance_to(hips) - reach) > sprint * meet_time and earliest != Vector2.INF:
		meet = earliest
		meet_time = earliest_time
	var to := meet - hips
	if to.length() <= reach:
		var facing := _ground(ball.position) - hips
		return [facing.normalized() * 0.001, false]
	var need := (to.length() - reach) / maxf(meet_time, 0.05)
	return [to.normalized() * clampf(need / jog, 0.3, 1.0), need > jog]


## Forgets any pass under way (a test resetting the scene).
func reset_for_test() -> void:
	_decision = {}
	_kick = {}
	charging = false
	strength = 0.0
	_lock_in = -1.0
	_was_held = false


## The direction (yaw) the decided pass will go.
func planned_yaw() -> float:
	return _aim_yaw(_decision) if not _decision.is_empty() else _player.yaw


## The receiver for a pass from `from` aimed along `direction` at `power`
## (0-1), or null with nobody in the cone. `mates` holds [player, ground
## position] pairs.
static func choose_target(from: Vector2, direction: Vector2, power: float, mates: Array, cone: float, ratio := 1.5) -> Node:
	var ranked := []
	for mate in mates:
		var to: Vector2 = mate[1] - from
		if to.length() < 0.01 or absf(direction.angle_to(to)) > deg_to_rad(cone) * 0.5:
			continue
		var off_line := absf(direction.normalized().cross(to))
		ranked.append([-off_line * off_line - to.length(), mate[0]])
	if ranked.is_empty():
		return null
	ranked.sort_custom(func(a, b): return a[0] > b[0])
	var n := ranked.size()
	# Band i is ratio^(N - 1 - i) parts of the bar: each `ratio` times the next.
	var parts := 0.0
	for i in n:
		parts += pow(ratio, i)
	var edge := 0.0
	for i in n:
		edge += pow(ratio, n - 1 - i) / parts
		if power < edge:
			return ranked[i][1]
	return ranked[n - 1][1]


func _read_button(delta: float) -> void:
	var held := _player.pass_held
	if held and not _was_held:
		charging = true
		strength = 0.0
		_lock_in = -1.0
	if charging and held:
		strength = minf(strength + delta / charge_time, 1.0)
	elif charging:
		charging = false
		if lock_delay <= 0.0:
			_decide()
		else:
			_lock_in = lock_delay
	elif _lock_in >= 0.0:
		_lock_in -= delta
		if _lock_in <= 0.0:
			_lock_in = -1.0
			_decide()
	_was_held = held


func _decide() -> void:
	var direction := _player.move_input
	if direction == Vector2.ZERO:
		direction = Vector2(sin(_player.yaw), cos(_player.yaw))
	direction = direction.normalized()
	var target := choose_target(_hips(), direction, strength, _mates(), cone_angle, band_ratio)
	_decision = {"target": target, "direction": direction, "strength": strength, "left": queue_time}


## Teammates as [player, ground position] pairs.
func _mates() -> Array:
	var mates := []
	for p in get_tree().get_nodes_in_group(&"players"):
		if p != _player and p is Player and p.team == _player.team:
			mates.append([p, _ground(p.global_position)])
	return mates


## A decided pass waits for the ball: with it at the feet, the kick starts;
## with one coming, it starts in time to meet it first time.
func _wait_for_ball(delta: float) -> void:
	if _decision.is_empty():
		return
	if _dribble.holding():
		_begin(false)
		return
	var ball := _dribble.ball
	if ball.holder == null and ball.last_releaser != _player \
			and _ball_arrival() <= _player.kick_lead_time(planned_yaw()) + 0.1:
		_begin(true)
		return
	_decision.left -= delta
	if _decision.left <= 0.0:
		_decision = {}


func _begin(first_time: bool) -> void:
	_kick = _decision.duplicate()
	_kick.first_time = first_time
	_kick.released = false
	_kick.plant = 0.0
	_decision = {}
	# A first-time kick plants to meet the ball; with it at the feet, the
	# player kicks in stride if they can.
	var yaw := _aim_yaw(_kick)
	_player.begin_kick(yaw, _dribble.foot_for_kick(yaw), not first_time)


func _carry_out(delta: float) -> void:
	if _player.action != Player.Action.KICK:
		# The kick is over.
		_kick = {}
		return
	if _kick.released:
		return
	if _player.kick_swinging:
		# Contact on the tick nearest the clip's own contact time.
		if _player.kick_time >= _player.kick_contact_time - 0.5 * _player.kick_rate * delta:
			_release()
		return
	_player.aim_kick(_aim_yaw(_kick))
	_kick.plant += delta
	var ball := _dribble.ball
	if _dribble.holding():
		if _player.kick_running:
			# In stride: swing so the foot meets the ball at its next touch.
			if _player.kick_ready() and _dribble.kick_touch_due() \
					and (_dribble.ball_meets_foot(run_reach) or _kick.plant > plant_timeout):
				_player.start_swing()
		elif _player.kick_ready() and (_dribble.ball_meets_foot(set_reach) or _kick.plant > plant_timeout):
			_player.start_swing()
	elif ball.holder == null and _kick.first_time:
		if _player.kick_ready() and _first_time_now():
			_player.start_swing()
			_dribble.take_for_kick()
			_kick.struck_first_time = true
		elif _ball_arrival() > 1.5:
			# The ball isn't coming after all: wait for it again, free to move.
			_player.cancel_kick()
			_decision = _kick
			_kick = {}
	else:
		# The ball is gone (knocked loose, or someone else has it).
		_player.cancel_kick()
		_kick = {}


## First time: whether swinging now meets the coming ball best (it will be
## close to the foot at contact, and closer than if the swing waited a tick).
func _first_time_now() -> bool:
	var ball := _dribble.ball
	var contact := _player.kick_contact_time / _player.kick_rate
	var spot := _ground(_dribble.strike_point(_player.kick_hips_after(contact), _player.kick_yaw))
	# Contact comes on the tick nearest the clip's contact time (see _carry_out),
	# and the ball's position then is the one after that many more ticks.
	var tick := get_physics_process_delta_time()
	var t := ball.time_since_release() + ceilf(contact / tick - 0.5) * tick
	var now := _ground(ball.roll_position_at(t)).distance_to(spot)
	var later := _ground(ball.roll_position_at(t + tick)).distance_to(spot)
	return now <= first_time_reach and now <= later


## How long until the loose ball comes within reach of the player (INF if it
## doesn't within 2 s), assuming the player stays where they are.
func _ball_arrival() -> float:
	var ball := _dribble.ball
	var hips := _hips()
	var t0 := ball.time_since_release()
	var t := 0.0
	while t <= 2.0:
		if _ground(ball.roll_position_at(t0 + t)).distance_to(hips) <= _dribble.pickup_reach:
			return t
		t += 1.0 / 60.0
	return INF


## Contact: the ball leaves the foot.
func _release() -> void:
	_kick.released = true
	if not _dribble.holding():
		return
	var ball := _dribble.ball
	var from := _ground(ball.position)
	var target: Node = _kick.target if is_instance_valid(_kick.target) else null
	var speed: float
	var direction: Vector2 = _kick.direction
	if target:
		var aim := _aim_point(from, target)
		direction = (aim - from).normalized()
		speed = pass_speed(from.distance_to(aim))
	else:
		speed = ball.speed_to_stop_at(lerpf(min_distance, max_distance, _kick.strength))
	var hop := clampf((speed - hop_from) * hop_per_speed, 0.0, max_hop)
	var spot := _ground(_dribble.strike_point(_hips(), _player.yaw))
	kick_log.append({"time": _clock, "target": target, "speed": speed, "direction": direction,
			"first_time": _kick.get("struck_first_time", false), "error": from.distance_to(spot)})
	_dribble.release(Vector3(direction.x, 0.0, direction.y) * speed, hop, target)
	_play_sound(ball.position, speed)


## How hard a pass to a teammate `distance` away is struck (m/s).
func pass_speed(distance: float) -> float:
	return sqrt(distance) / pace_constant


## Where to play the ball for `target`: where they are plus `lead` of how far
## they run while it travels.
func _aim_point(from: Vector2, target: Node) -> Vector2:
	var ball := _dribble.ball
	var at := _ground(target.global_position)
	var run: Vector2 = target.ground_velocity
	var aim := at
	for i in 3:
		var distance := from.distance_to(aim)
		var travel := ball.time_to_roll(pass_speed(distance), distance)
		if travel == INF:
			break
		aim = at + run * travel * lead
	return aim


## The direction (yaw) a decision sends the ball.
func _aim_yaw(decision: Dictionary) -> float:
	var direction: Vector2 = decision.direction
	if is_instance_valid(decision.target):
		var from := _ground(_dribble.ball.position) if _dribble.holding() else _hips()
		var to := _aim_point(from, decision.target) - from
		if to.length() > 0.01:
			direction = to
	return atan2(direction.x, direction.y)


func _play_sound(at: Vector3, speed: float) -> void:
	if sounds.is_empty():
		return
	_sound.stream = sounds[randi() % sounds.size()]
	_sound.global_position = at
	_sound.volume_db = linear_to_db(clampf(0.4 + speed / 20.0, 0.5, 1.0))
	_sound.pitch_scale = randf_range(0.95, 1.05)
	_sound.play()


func _hips() -> Vector2:
	return _ground(_player.global_position)


func _ground(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)
