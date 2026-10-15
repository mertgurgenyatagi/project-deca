# Touch dribbling: design

Branch `ball-interaction`, 2026-10-15.

> **Implemented.** Bench and visual testing added several rules that this spec doesn't cover: foot-contact touches, missed touches, free braking, braking-only stops, turnback rest beside the player, and touch speed caps. Some defaults also changed. [docs/touch-dribbling.md](../../touch-dribbling.md) describes the final behaviour.

## Goal

The player can pick up a ball and dribble it with visible, timed touches. The ball is never glued to the feet and never teleports. Possession is guaranteed: with no defender, the player never loses the ball.

## Guiding constraints

- **Online play with friends comes later** (about 5–6 people, each running their own copy). Visuals don't have to match across machines, and the cleanest design wins. This design adds no network code, but it keeps these seams:
  - Possession is a single value: `Ball.holder`.
  - The dribble reads only the player's state, never the keyboard.
  - A loose ball's roll depends only on its release position, release velocity and time since release.
  - The pickup decision sits in one function.
- **Movement is untouched.** The PES-calibrated movement is unchanged, and `pes_timing.gd` gives the same numbers.
- **"Approach A": the ball does the cheating.** When the player steers between touches, the ball's path bends. The player never bends toward the ball.

## Out of scope

Passing, shooting, tackles and steals, other players, a ball in the air, out of play, goals, network code, and dribble-specific animation.

## Units

### `Ball` (`scenes/ball.tscn`, `scripts/ball.gd`, `shaders/ball.gdshader`)

The ball's state: position, velocity, `holder` (a player or null) and spin. It knows nothing about feet.

- **Not a physics body.** It's a `Node3D` moved by its own `_physics_process` and drawn with physics interpolation. Its `process_physics_priority` runs it after the players.
- **Size-5 ball:** radius 0.11 m. It always sits on the ground, with its centre at y = radius.
- **Loose roll:** an analytic constant-deceleration roll from the last release. Position at time `t` after a release at `p0` with velocity `u0`:
  `p0 + û0 · (|u0|·t − ½·a·t²)`, held at the stop point once `t ≥ |u0|/a`. The deceleration `a` is `roll_deceleration` (1.2 m/s²).
  - `release(position, velocity)` starts a roll. This is the future "ball released" network event.
- **Held:** each tick the dribble sets the ball's acceleration, and the ball integrates it. The dribble may also change the velocity instantly, but only at a touch: `touch(velocity)`.
- **Spin:** the mesh rotates about `up × v̂` by distance covered ÷ radius, so it rolls without slipping.
- **Look:** a SphereMesh drawn by a shader as a truncated icosahedron: 12 black pentagons and 20 white hexagons with thin dark seams. It casts a shadow.
  - Each point on the sphere takes the colour of the face its ray hits first: the largest `dot(p, n)/d` over all 32 face normals.
  - The face distances are `d_pent` = 2.3274 and `d_hex` = 2.2673 (for edge length 1).
  - A seam is drawn where the best two faces are nearly tied.

### `Dribble` (`scripts/dribble.gd`, a child node of `Player`)

Does all the possession logic: the touch rhythm, prediction, bending, early touches and pickup. It reads the player's state through a small read-only API. It writes to the ball only through `Ball.touch()`, the ball's acceleration and `Ball.holder`.

### `player.gd` changes (movement behaviour unchanged)

- Input is read once per physics tick into `move_input` and `sprint_held`, and the movement code uses those. This is the seam where a network copy will later feed input instead.
- A read-only API for the dribble:

| Member | What it gives |
|---|---|
| `yaw` | facing |
| `ground_velocity` | ground velocity |
| `gait_phase` | current stride phase |
| `sprint_weight` | jog/sprint blend |
| `phase_rate_at(speed)` | stride rate at a speed |
| `gait_feet_at(phase, sprint_weight)` | model-space foot and toe points |
| `action`, `action_dir` | the current action and its direction |
| `top_speed()`, `current_acceleration()`, `turn_rate_at(speed)` | movement constants for prediction |

  The stride code already does these things internally; they only need exposing.
- The movement constants stay as they are.

### Debug (`scripts/debug_keys.gd`, on `Main`)

The B key releases the ball in a random direction with enough speed to roll 3–5 m. The ball never reads the keyboard itself.

## Dribbling

### Touch geometry (measured from the gait loops with `probe_gait_feet.gd`)

- In model space, +Z is forward and +X is the player's left.
- The jog toe reaches furthest forward about 0.33 m ahead of the hips, 6–8 cm off the ground and moving at about body speed. The sprint toe reaches about 0.53 m.
- The feet track nearly in line, only 8–15 cm apart sideways.
- **The touch moment for each foot** is the stride phase where that toe is furthest forward, minus `touch_phase_offset` (0.03 cycles). It's found once in `_ready` by forward kinematics.
- **The contact point** is the toe at that phase:
  - plus `(toe_tip + radius)` forward, where `toe_tip` is 0.06 m
  - plus `touch_side_offset` (0.04 m) toward the outside of the touching foot, so the other foot swings past the ball rather than through it
  - at height = radius

### Rhythm

- At each touch, the number of steps to the next touch is chosen as `round(lerp(jog_touch_steps, sprint_touch_steps, sprint_weight) × straightness)`, with a minimum of 2.
  - `jog_touch_steps` is 2 (one stride cycle, so always the same foot). `sprint_touch_steps` is 4.
  - `straightness` = `clamp(1 − input_angle / turn_shorten_angle, 0.5, 1)`, where `turn_shorten_angle` is 60°. So turning shortens knocks.
- An even step count keeps the same foot and an odd count switches foot.
- The first touch after a pickup uses `preferred_foot` (right).

### Planning a touch segment

- A touch at time 0, from contact point `P0`, aims at `P1`: the predicted contact point of the next touch, at `T` seconds ahead.
- The ball arrives with velocity `V1` = `arrival_speed_ratio` (0.4) × the player's predicted velocity at T.
- Under constant deceleration, the launch velocity is `U0 = 2·(P1 − P0)/T − V1`, and the planned acceleration is `A = (V1 − U0)/T`.
  - At a jog this gives a launch speed of about 1.6× the player's speed. The ball peaks about 0.3 m past the contact point, then slows into the next touch.
  - At a sprint (T ≈ 1.4 s) the ball gets about 1.6 m ahead of the hips.

### Prediction

- `predict(τ)` steps a simplified copy of the movement forward in 1/60 s steps:
  - The yaw turns toward the input heading at `turn_rate_at(speed)`.
  - The speed moves toward `top_speed()` (or 0 with no input) at `current_acceleration()` or `deceleration`.
  - A turnback brakes along its current direction at `turnback_brake` to zero, then accelerates along `action_dir`.
  - The stride phase advances at `phase_rate_at(speed)`.
- The time to the next touch is however long the predicted stride phase takes to reach the touch phase, `n` steps later.
- The contact point is the predicted position, plus the predicted yaw applied to the model-space contact offset.
- It's rough, and re-run every tick.

### Bending

- Every tick, the target `P1` and the time left `τ` are predicted again.
- The acceleration needed to reach the target is found by re-solving a cubic Hermite curve from the ball's current position `p` and velocity `v`:
  `a_cmd = (6·(P1 − p) − 2τ·(2v + V1)) / τ²`
  With an unchanged plan, this equals the planned `A` exactly.
- The **bend** is `a_cmd − A`. It's clamped to `max_bend`:
  - `max_bend` starts at 3 m/s² and grows at `bend_growth` (20 m/s² per second) for as long as the clamp is active, then resets at the next touch. This is the safety net that guarantees the ball always comes back.
- When `τ` is below one tick, the touch fires.

### Early touches

- If the bend has been clamped this segment, an early touch happens when any real toe (from the skeleton's pose) comes within `touch_reach` (0.08 m) of the ball's surface.
- An early touch starts a new segment from the ball's current position. Because it works off real toes, it also works during the turn and sprint-start clips.

### Stopping and standing

- If the predicted speed at the next touch is below 0.3 m/s, the segment aims at the rest point instead:
  - the predicted stop position, plus `rest_distance` (0.35 m) along the predicted facing, on the `preferred_foot` side
  - arrival velocity 0, arrival time = the predicted time to stop + 0.25 s
- Once it arrives, the ball sits still.
- A standing pivot moves the rest point, so the ball goes through bending and early touches like any other plan change. The rest point uses the input heading, so the ball heads for the new front.

### Pickup

- A loose ball is taken when its centre is within `pickup_reach` (0.6 m) of the player on the ground plane.
- The player who last released the ball can't take it back until it has been beyond `pickup_reach` once.
- Taking the ball is an immediate early touch: a new segment from the ball's current state.
- The rule lives in `Dribble.can_take(ball)`.

## Testing

- **`tools/anim_tests/dribble_bench.gd`** (headless) runs these scenarios, each started at several stride phases:
  - steady jog and steady sprint
  - moving off from a standstill
  - 90° turns at a jog and at a sprint
  - turnbacks at a jog and at a sprint
  - stop
  - standing pivot
  - pickup from 4 directions

  It reports per scenario:
  - contact error: ball surface to the nearest toe at a touch, in cm
  - pass-through: frames with a toe inside the ball, and the worst depth
  - bend: average and peak
  - the largest lead ahead of the hips
  - the largest ball–player distance while held
  - pickup time
  - the largest per-tick position jump minus `|v|·dt`
- **`tools/anim_tests/ball_roll_test.gd`** checks that a release stops at `|u0|²/(2a)` and that two identical releases give the same positions.
- **Regression checks:** `pes_timing.gd`, `turnback_bench.gd` and `start_bench.gd` give the same numbers as before.
- **Visual:** `record_dribble.gd` writes a movie, and the game is also checked live through godot-mcp.

## Defaults (all Inspector exports)

| Node | Export | Default |
|---|---|---|
| Ball | `radius` | 0.11 m |
| Ball | `roll_deceleration` | 1.2 m/s² |
| Dribble | `preferred_foot` | right |
| Dribble | `jog_touch_steps` | 2 |
| Dribble | `sprint_touch_steps` | 4 |
| Dribble | `turn_shorten_angle` | 60° |
| Dribble | `touch_phase_offset` | 0.03 |
| Dribble | `toe_tip` | 0.06 m |
| Dribble | `touch_side_offset` | 0.04 m |
| Dribble | `arrival_speed_ratio` | 0.4 |
| Dribble | `max_bend` | 3 m/s² |
| Dribble | `bend_growth` | 20 m/s² per second |
| Dribble | `touch_reach` | 0.08 m |
| Dribble | `rest_distance` | 0.35 m |
| Dribble | `pickup_reach` | 0.6 m |
