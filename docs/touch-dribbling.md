# Branch `ball-interaction`: the ball and touch dribbling

This branch adds a ball. The player picks it up by running onto it, then dribbles it with visible touches timed to the stride. The ball is never glued to the feet, never teleports, and is never lost without a defender. The design spec is [superpowers/specs/2026-10-15-touch-dribbling-design.md](superpowers/specs/2026-10-15-touch-dribbling-design.md). Where the two differ, this document describes the final behaviour.

- **Controls:** arrow keys move and Shift sprints, as before. **B** (debug) knocks the ball loose to roll 3–5 m in a random direction.
- **Movement is unchanged:**
  - `pes_timing.gd` output is identical.
  - The turnback and start benches match the numbers in [initial-movement.md](initial-movement.md) §5.

## Guiding constraint: online play later

The game is meant for about 5–6 friends online, each controlling one player from their own copy. Visuals don't need to match across machines, and the cleanest design wins. There's no network code yet, but these seams are in place:

- **Possession is one value:** `Ball.holder`.
- **The ball and the dribble never read the keyboard.**
  - `player.gd` reads input once per tick into `move_input` and `sprint_held`, and only when `read_input` is on.
  - The dribble reads only the player's state, so a network copy of a player would dribble with the same code.
- **A loose ball's roll is a pure function** of its release position, release velocity and time since release (`Ball.release`). One "released" message is enough to reproduce it on another machine.
- **The pickup rule is one function,** `Dribble.can_take`. Later, the host decides it.

## 1. Contents

```
tavernaball/
  scenes/ball.tscn            Ball (Node3D) + Mesh (SphereMesh r 0.11)
  scripts/ball.gd             loose roll, held integration, rolling spin
  shaders/ball.gdshader       truncated-icosahedron panels (12 black, 20 white, seams)
  scripts/dribble.gd          Dribble node under Player: touches, prediction, bend, pickup
  scripts/debug_keys.gd       B key: knock the ball loose
  scripts/player.gd           + input seam and read-only state (movement unchanged)
  scenes/player.tscn          + Dribble node
  scenes/main.tscn            + Ball on the centre spot, DebugKeys; player starts at (-2, 0, 0)
tools/anim_tests/
  dribble_bench.gd            scenario bench (see §5); `-- only=<name>` runs a subset
  ball_roll_test.gd           roll distance, determinism, no-slip spin
  debug_key_test.gd           real input path: jog onto ball, B, chase, re-pickup
  record_dribble.gd           movie for visual checks (`-- close` for a low follow camera)
  ball_look.gd                close-up render of the ball
  probe_gait_feet.gd          prints the gait loops' toe paths
```

## 2. The ball (`ball.gd`)

- **Not a physics body.** It moves itself in `_physics_process`, at `process_physics_priority` 10, so after the players. It's drawn with physics interpolation and stays on the ground, with its centre at y = 0.11.
- **Loose:**
  - Position is `p0 + û0·(|u0|·t − ½·a·t²)`, held at the stop point once it stops. The deceleration `a` is `roll_deceleration` (1.2 m/s²).
  - `release(at, velocity, by)` starts a roll.
  - `place(at)` teleports the ball and leaves it at rest.
- **Held:** the holder's Dribble sets `acceleration` every tick. `touch(velocity)` changes the velocity outright, and it's only used at a touch.
- **Spin:** the mesh rotates about `up × direction` by distance ÷ radius, so it rolls without slipping.
- **Joins the group `ball`,** which is how the Dribble and DebugKeys find it.

## 3. Dribbling (`dribble.gd`)

### 3.0 Changes wait for the ball
While the player holds the ball, `player.gd` moves on the input the Dribble lets through (`gate_input`, `gate_sprint`), not on the raw keys.

- **What waits:** a new direction, a stop or a sprint change takes effect only at a touch, when a foot is on the ball. Every kind of touch counts: rhythm, early, contact, pickup and "control". Until then, the player keeps the direction and sprint of their last touch.
- **Making the wait short:** the player actively goes for the ball. When a direction change or a stop starts waiting, the next touch moves to the very next foot swing, and the ball is brought back to that foot. A toe within `reach_for_ball` (0.2 m) of the ball, or the ball within `chase_reach` (0.75 m) of the hips, makes the change at once with a "control" touch.
- **Jog touches** come on every step, alternating feet (`jog_touch_steps` 1, `touch_side_offset` 0.02 m). The ball peaks about 0.66 m ahead of the hips (it was 0.83 m with touches every second step). Sprint knocks are unchanged.
- **From a standstill:** if the ball has come to rest out of reach, the player first steps up to it, then turns.
- **The touch that makes the change is planned for it:**
  - **Turnback:** the ball is set down beside where the player will stop (§3.4).
  - **Standing pivot past 100°:** the ball is taken round to the side the body turns toward, not through the feet.
  - **Stop:** the ball is rolled to `rest_distance` in front of where the player will stop.
- **A hint of what's coming (`intent_lean.gd`).** While a change waits, an `IntentLean` modifier on the skeleton gives a clear body cue. The player's path doesn't change: a drift on the approach was tried and looked wrong.
  - **turn:** the shoulders and head turn toward the new direction (torso up to 25°, head up to 15° more), with a 7° lean into the turn
  - **stop:** a 10° lean back
  - **sprint:** a 10° lean forward, and a 5° lean back when easing off
  - It's applied after the animation, to the spine, neck and head only, so the feet are untouched. It eases in and out, and its exports set the angles and the easing.
  - It reads `Dribble.intent_turn()`, `intent_stop()` and `intent_sprint()`. It hasn't been tested yet.
- **Without the ball, nothing is gated.** The movement tests (`pes_timing`, `turnback_bench`, `start_bench`, `motion_test`, `sprint_test`) remove the ball, so they still measure pure movement.

**Effect on the bench:**
- The average bend on 90° turns fell from 2.6 (jog) and 6.8 (sprint) to about 0.3 m/s².
- In the random stress test, the furthest ball distance fell from 2.6 to 1.7 m, the average bend from 5.0 to 1.5 m/s², and the worst touch miss from 24 to 9.5 cm.
- Some §5 rows below were measured before this change. Re-run the bench for current numbers.

### 3.1 Touches on the stride
- **Touch moment:** each foot touches at the stride phase where its toe reaches furthest forward, minus `touch_phase_offset`. This is found in the jog and sprint loops by forward kinematics and blended by the sprint weight.
  - At a jog the toe is about 0.33 m ahead of the hips, a few cm off the ground and moving at about body speed. At a sprint it's about 0.53 m ahead.
- **Contact point:** the toe, plus `toe_tip` + radius forward, plus `touch_side_offset` to the outside of the foot. The feet run almost in line, so this offset keeps the other foot from clipping the ball.
- **Steps between touches:** 2 at a jog (the same foot each time) and 4 at a sprint, blended by speed. While the input points away from the facing, the count drops toward 2. An odd count switches feet.
- **Planning a touch:**
  - The touch aims the ball at the predicted contact point of the next touch, arriving at `arrival_speed_ratio` × the player's speed.
  - That gives a launch of `2·(P1 − P0)/T − V1` and a constant deceleration. At a jog the launch is about 1.55× the player's speed.
  - Touches are capped at `touch_speed_ratio` × the player's speed + `touch_speed_margin`.
- **Prediction:** a small forward copy of the movement rules in 1/60 s steps: steering, acceleration, braking, turnback brake and push-off, and stride rate. It runs again every tick.

### 3.2 Between touches: bending
- **Every tick:** the target is re-predicted, and the acceleration needed to reach it is found by re-solving a cubic Hermite from the ball's current position and velocity.
- **Honest part:** the planned slowing along the ball's path.
- **Free braking:** extra slowing along the path, up to `free_braking` (`turnback_braking` during a turnback brake). It's also counted as honest, because a ball slowing down looks natural.
- **Bend:** everything else (curving, speeding up). It's capped at `max_bend`, and the cap grows at `bend_growth` while the bend is clamped. This guarantees the ball comes back.

### 3.3 Off-rhythm touches
- **Contact:** a foot (a capsule from the ankle through the toe joint to the toe tip) that runs into the ball touches it. The touch pushes the ball away from that foot at least `CONTACT_PUSH` faster than the foot is moving.
- **Early:** once the bend has been clamped, the first toe within `touch_reach` of the ball touches it, starting a new plan.
- **Missed:** a rhythm touch whose foot is more than `miss_distance` from the ball is skipped, and the ball bends toward the next touch instead.
- **Pickup:** a loose ball within `pickup_reach` of the player is taken with an immediate touch. Whoever released it can't take it back until it has been out of reach once.

### 3.4 Stopping and turnbacks
- **Stopping:**
  - The ball is only ever slowed along its own path, never pulled back toward the player.
  - It comes to rest where that path passes `rest_distance` in front of where the player stops, and no further than `rest_max_distance` if braking allows.
  - A ball not heading in front of the player is stopped as soon as possible.
- **Turnback brake:** the ball is braked to rest beside where the player stops: `turnback_ball_ahead` along the old direction and `turnback_ball_side` toward the side the body turns. The push-off then takes it away from that side instead of dragging it back through the legs.
  - The turning side measured clearly better than the other: jog turnback foot overlap dropped from 35 frames (11 cm deep) to 3 frames (2 cm).

### 3.5 Inspector exports

| Node | Export | Value |
|---|---|---|
| Ball | `radius` | 0.11 m |
| Ball | `roll_deceleration` | 1.2 m/s² |
| Dribble | `preferred_foot` | right |
| Dribble | `jog_touch_steps` | 1 |
| Dribble | `sprint_touch_steps` | 4 |
| Dribble | `turn_shorten_angle` | 60° |
| Dribble | `touch_phase_offset` | 0.03 cycles |
| Dribble | `toe_tip` | 0.06 m |
| Dribble | `touch_side_offset` | 0.02 m |
| Dribble | `arrival_speed_ratio` | 0.4 |
| Dribble | `touch_speed_ratio` | 2.0 |
| Dribble | `touch_speed_margin` | 1.5 m/s |
| Dribble | `max_bend` | 3 m/s² |
| Dribble | `bend_growth` | 20 m/s² per second |
| Dribble | `free_braking` | 8 m/s² |
| Dribble | `turnback_braking` | 12 m/s² |
| Dribble | `turnback_ball_ahead` | 0.2 m |
| Dribble | `turnback_ball_side` | 0.25 m |
| Dribble | `touch_reach` | 0.08 m |
| Dribble | `miss_distance` | 0.3 m |
| Dribble | `rest_distance` | 0.5 m |
| Dribble | `rest_max_distance` | 1.0 m |
| Dribble | `pickup_reach` | 0.6 m |
| Dribble | `control_reach` | 0.5 m |

## 4. `player.gd` additions
- **Input seam:** `move_input`, `sprint_held` and `read_input`.
- **Read-only properties:** `yaw`, `ground_velocity`, `gait_phase`, `sprint_weight`, `action`, `action_dir`, `turn_direction` and `skeleton`.
- **Methods:**
  - `turn_rate_at(speed)`, now also used by steering itself
  - `top_speed()`, `current_acceleration()`
  - `phase_rate_at(speed)`, `sprint_weight_at(speed)`
  - `gait_feet_at(phase, weight)`, which returns foot and toe points interpolated between samples
- **`class_name Player`.**

## 5. Measured quality (`dribble_bench.gd`)

Each scenario runs from 3 start offsets.

| Column | Meaning |
|---|---|
| Contact | the median / worst gap between the ball and the touching foot's real toe at rhythm touches |
| Pass | frames with a foot inside the ball, and the deepest |
| Bend | the average / peak steering acceleration between touches |
| Lead | how far ahead of the hips the ball gets |
| Far | how far from the player the ball gets while held |

| Scenario | Touches | Contact (cm) | Off-rhythm | Pass | Bend (m/s²) | Lead (m) | Far (m) |
|---|---|---|---|---|---|---|---|
| steady jog | 18 | 3.1 / 4.9 | 0 | 0 | 0.25 / 3.0 | 0.83 | 0.83 |
| steady sprint | 9 | 2.4 / 4.3 | 0 | 0 | 0.11 / 3.0 | 1.69 | 1.70 |
| move off | 9 | 3.3 / 4.8 | 3 | 0 | 0.63 / 8.0 | 0.97 | 0.97 |
| sprint off | 3 | 0.3 / 0.3 | 3 | 0 | 1.20 / 8.0 | 1.71 | 1.71 |
| 90° jog | 4 | 3.1 / 3.4 | 8 | 16 / 7.6 cm | 2.64 / 17.3 | 0.84 | 0.95 |
| 90° sprint | 3 | 2.4 / 19.5 | 2 | 3 / 10.7 cm | 6.80 / 25.8 | 1.73 | 2.36 |
| turnback jog | 6 | 4.0 / 4.0 | 5 | 3 / 2.1 cm | 0.95 / 8.7 | 1.00 | 1.00 |
| turnback sprint | 6 | 2.2 / 6.9 | 4 | 1 / 1.2 cm | 1.48 / 13.7 | 1.69 | 1.69 |
| stop | 0 | – | 3 | 4 / 1.9 cm | 0.98 / 3.1 | 1.32 | 1.33 |
| pivot + go | 9 | 2.8 / 4.9 | 4 | 8 / 10.0 cm | 0.34 / 5.3 | 0.93 | 0.93 |
| pickups (4 directions) | 5–6 | 2.7–4.3 / ≤5.1 | 0 | 0 | ≈0.23 / 3.0 | ≤0.92 | ≤0.92 |
| random 60 s stress | 34 | 5.5 / 24.1 | 205 | 216 / 13.6 cm (2% of frames) | 4.95 / 36 | 2.60 | 2.64 |

- **Pickups:** 1.6–1.9 s from 3–4.4 m away, including the jog to the ball.
- **Every scenario:** the ball is never dropped, never more than 2.64 m away, and never teleports.
- **The random stress test** changes direction (8 ways or none) and sprint every 0.2–1.2 s from a fixed seed. It's deterministic and much harsher than normal play. Its bend shows the cost of approach A: under constant direction changes, the ball has to cheat often.

## 6. Known limits and next steps
1. **Responsiveness:** with the ball, a change waits for the next step's touch. That's up to about 0.35 s at a jog and 0.7 s at a sprint. This is deliberate (§3.0).
2. **Standing pivots still clip the ball briefly** (up to about 13 cm, a few frames). The ball sits in the sweep of the pivoting feet.
3. **No dribble-specific animation.** Touches use the jog and sprint legs at the moment the swinging foot meets the ball. A Mixamo dribble clip, or soccer clips such as "stall soccerball" for traps, could replace the leg motion around touches without changing the ball logic.
4. **Stopping is a braked roll,** not a sole trap. The ball comes to rest up to about 1.2 m ahead.
5. **The `godot-mcp` live check wasn't possible** because the editor plugin disconnected during this session. `debug_key_test.gd` covers the real input path headlessly instead. Note that headless runs need `root.push_input` for key events; `Input.parse_input_event` doesn't reach `_unhandled_input` there.
6. **Next:** passing and shooting (`Dribble.release` and `Ball.release` already exist), then other players, tackles and steals, and networking.

## 7. Testing

```
./Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path tavernaball --script "<abs path>/tools/anim_tests/<script>.gd" [-- only=<scenario>]
```

| Script | What it checks | Pass line |
|---|---|---|
| `dribble_bench.gd` | the table above | `DRIBBLE_OK`: never dropped, ≤ 3 m away, no teleport, pickups in time |
| `ball_roll_test.gd` | stop distance, determinism, spin | `ROLL_OK` |
| `debug_key_test.gd` | the real input path and B | `KEYS_OK` |

`pes_timing.gd`, `turnback_bench.gd` (with and without `-- sprint`) and `start_bench.gd` must still match [initial-movement.md](initial-movement.md).
