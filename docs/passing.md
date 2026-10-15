# Branch `passing`: the ground pass

This branch adds a PES-style ground pass and two stand-in teammates to pass to. The player plants, turns and swings. The ball loses pace as it travels, and a hard pass hops slightly. The design came from a question-and-answer session (`passing-answers.md` at the repo root, not committed). Where a choice was left open there, this document says what was chosen.

- **Controls:** arrow keys move, Shift sprints, **S** passes. B (debug) still knocks the ball loose.
- **Movement and dribbling are unchanged:**
  - `pes_timing.gd`, `turnback_bench.gd`, `start_bench.gd` and `dribble_bench.gd` print exactly what they did before.
  - The tests that load `main.tscn` remove the stand-ins, so they measure the player alone.

## Guiding constraint: online play later

These seams stay in place for networking:
- **Passing never reads the keyboard.** `player.gd` reads S into `pass_held`, alongside `move_input` and `sprint_held`. `passing.gd` reads only the player's state.
- **A kick is one event:** `Dribble.release(velocity, hop)` → `Ball.release(at, velocity, by, hop)`. The loose ball, hop included, is a pure function of that release and the time since. One "released" message is enough to reproduce it on another machine.
- **The receiver choice is a static, pure function:** `Passing.choose_target`.

## 1. Contents

```
tavernaball/
  scripts/passing.gd                  Passing node under Player: button, decision, receiver, kick, sound
  scripts/pass_bar.gd                 strength bar under the player's feet (HUD)
  scripts/teammate_ai.gd              stand-in teammate: keeps a ball it receives, passes it back
  scripts/player.gd                   + KICK action (plant, turn, swing), pass_held, team, face()
  scripts/dribble.gd                  + setting the ball for a kick, plant_point, first-time take
  scripts/ball.gd                     + quadratic drag on loose rolls, hop and bounces, roll helpers
  assets/animations/kicks/pass_kick.fbx      Mixamo "kick soccerball (2)": the light, right-footed kick
  assets/animations/mixamo_kick_import.gd    post-import: centres the hips, keeps their rotation
  assets/sfx/pass_1..4.ogg            kick sounds, one at random
  scenes/player.tscn                  + Kick/KickFreeze/KickSeek/KickBlend on top of the tree, Passing node
  scenes/main.tscn                    + Teammates/Near (7, 0, -3) and Teammates/Far (14, 0, -3), Hud/PassBar
  project.godot                       + `pass` action on the physical S key
tools/anim_tests/
  pass_bench.gd                       receiver-choice checks and pass scenarios (see §6)
  record_pass.gd                      movie for visual checks (`-- close` for a low follow camera)
  ball_roll_test.gd                   now checks the drag closed forms and the hop
```

## 2. Deciding the pass (`passing.gd`)

- **Charging:** holding S fills the bar in `charge_time` (0.475 s).
- **Locking:** the pass is decided `lock_delay` (0.2 s) after S is let go. Until then the keys can still change the direction.
- **Direction:** the movement keys at the lock, or the facing if none are held.
- **Receiver:**
  - Teammates (same `team`) within a 60° cone around the direction are ranked by −(distance from the cone's centre line)² − distance.
  - With N of them in the cone, the bar is split into N bands. Priority i gets 2(N − i + 1) / (N(N + 1)) of it, so the top-ranked gets the first and largest band.
  - Where the strength lands picks the receiver: with two, under 2/3 goes to priority 1. With three, the edges are at 1/2 and 5/6.
- **Pace to a receiver:** fixed. The ball arrives at `arrival_speed` (7 m/s) whatever the strength. It is struck as hard as that takes, capped at `max_speed` (18 m/s). It never stops short within about 40 m.
- **Leading:** the pass is aimed at the receiver plus `lead` (0.5) of how far they run while it travels.
- **Nobody in the cone:** the ball goes straight along the direction. It rolls from `min_distance` (8 m) at an empty bar to `max_distance` (30 m) at a full one.
- **Hop:** a pass struck faster than `hop_from` (9 m/s) hops off the ground at `hop_per_speed` (0.25 m/s) per m/s over it, up to `max_hop` (1.2 m/s). A full no-target pass hops about 5 cm, then bounces at `Ball.bounce` (0.35).
- **Queue:** a decided pass waits up to `queue_time` (4 s) for the ball. It is carried out the next time the player is on the ball:
  - at once, if the ball is at their feet
  - when they pick a loose ball up
  - first time, as a ball comes to them (§4)

## 3. Carrying it out: plant, turn, swing (`player.gd` KICK, `dribble.gd`)

From the plant to the end of the follow-through, the player is committed: `Action.KICK` ignores the keys.

1. **The plant.** For turns up to `plant_turn` (100°):
   - The ball is slowed to rest along its own path (rolling plus `free_braking`).
   - The Dribble publishes `plant_point`, the spot where the player should stop so that the kicking foot meets the ball where it comes to rest.
   - The player arrives there, braking at up to `kick_brake` (9 m/s²). A slow player steps up to a ball ahead at `kick_step_speed` (1.2 m/s).
   - The body turns toward the kick at the normal turn rates, pivoting about the planted foot when slow.
2. **Bigger turns** (a pass behind):
   - The player brakes as hard as allowed and turns.
   - The ball comes to rest in front of where the player stops, in the kick's frame. If its way there would pass through the player, it is routed round the side the body turns toward (`kick_clearance`, `kick_side`).
3. **Planted and turned:**
   - The ball is brought the last bit to the foot.
   - A toe within `set_touch_reach` of a ball that isn't in place nudges it there with a "set" touch.
4. **The swing** starts when all of these hold:
   - the player is at or below `kick_entry_speed` (1.4 m/s)
   - they face within `kick_entry_angle` (12°) of the kick
   - the ball, projected to the moment of contact, will be within `set_reach` (0.12 m) of the foot, with the plant still braking

   A plant that runs past `plant_timeout` (1.5 s) swings anyway.
5. **Contact.** The kick clip plays in time, at `kick_rate`. During the swing the Dribble steers the ball, with up to `swing_bend` (30 m/s²), to meet the foot at the clip's contact time (0.133 s). At contact:
   - The ball is released with the pass's velocity from where it actually is.
   - A sound plays: one of the four at random, louder for harder passes, pitch ±5%.
6. **Follow-through.** The clip plays to its end (0.5 s) and fades out over 0.2 s. Then the keys work again.

**Why the angle costs time:** nothing measures the angle. The turn takes longer, and a ball behind has further to come, so execution time grows with it.

## 4. First time

- **Starting early.** A pass decided without the ball starts its plant and turn early. That happens when a loose ball (not one this player released) is predicted to come within `pickup_reach` sooner than the plant would take.
- **Swinging at the ball.** The swing starts at the tick when the coming ball, rolled forward to the moment of contact, is nearest the foot and within `first_time_reach` (0.35 m). At swing start the ball is taken without a touch (`Dribble.take_for_kick`) and steered into the foot at its own pace.
- **Control first.** If the geometry doesn't allow a first-time kick (roughly beyond 45–60° from where the ball came from), the ball reaches the player and is picked up as usual. The kick then follows from the feet.
- **Ball not coming.** If the ball turns out not to be coming, the plant is cancelled and the pass waits again.
- **Holding the keys moves the player.** Keys held while waiting move the player as usual. To meet a pass standing, let go of the keys after the lock.

## 5. The rest

- **Ball roll (`ball.gd`).** A loose ball now obeys dv/dt = −a − k·v², with a = `roll_deceleration` (1.2 m/s²) and k = `roll_drag` (0.025 1/m).
  - That has closed forms for distance, speed, stop distance, launch speed for a stop point or for an arrival speed, and time to cover a distance (see the comment in `ball.gd`).
  - A hard pass loses pace quickly at first, then rolls on. A pass to Near standing 7.4 m away is struck at 9.3 m/s and reaches them at 7.2 m/s 0.73 s later.
  - The B debug knock now uses `speed_to_stop_at`. Its 3–5 m rolls are unchanged.
- **Kick clip:**
  - **Import.** Imported with `mixamo_kick_import.gd`, which centres the hips over the origin and keeps their rotation.
  - **Contact point.** `player.gd` finds the contact by forward kinematics: the moment the kicking toe moves forward fastest (0.133 s).
  - **Strike spot.** The ball's place at contact is that toe, plus `toe_tip` and the ball radius forward: about 0.37 m ahead of the hips and 0.1 m to the right.
  - **Lift.** The clip's rig stands about 4 cm lower than the idle's, so the model is lifted by the difference while the kick shows.
- **Strength bar (`pass_bar.gd`).**
  - **Placement.** A slim strip under the player's feet on screen, shown while S is held and until the pass is decided, then fading out over 0.35 s.
  - **Look.** It fills like a pint: an amber fill with a pale "head" on its leading edge that turns copper when full, inside a chalk outline. Only the human player's bar is drawn.
- **Stand-in teammates (`teammate_ai.gd`).**
  - Two `player.tscn` instances, Near at (7, 0, −3) and Far at (14, 0, −3), with `read_input` off.
  - Each keeps a ball it receives for `hold_time` (2.5 s), then `pass_to`s the player, through the same kick.
  - From the start, after taking the ball, pressing right puts both in the cone: Near is priority 1, and Far needs over 2/3 of the bar.
  - Any player, stand-ins included, takes a loose ball within reach, so a teammate standing in a pass's path takes it.

## 6. Measured quality (`pass_bench.gd`)

Each scenario runs from 3 stride offsets. The stand-ins are placed relative to the player as S goes down: Near 7 m along the aim and 2.5 m to its right, Far 14 m along and 2.5 m to its left.

| Column | Meaning |
|---|---|
| exec | from the decision (0.2 s after S is let go) to the foot meeting the ball, median / worst |
| miss | the gap between the ball and where the foot meets it, at contact, median / worst |
| to | runs where the right player took it |
| overlap | frames with a foot inside the ball while it is being set, and the deepest |
| slip | planted-foot slip during the kick (2 cm planted threshold; the swinging foot is left out) |

| Scenario | exec (s) | miss (cm) | to | arrival | overlap | slip (m/s) |
|---|---|---|---|---|---|---|
| standing, near (30%) | 0.37 / 0.48 | 0.9 / 4.2 | 3/3 | 0.73 s, 7.2 m/s | 0 | 0.49 |
| standing, far (90%) | 0.37 / 0.37 | 0.3 / 0.4 | 3/3 | 1.28 s, 7.2 m/s | 0 | 0.59 |
| jog, straight on | 0.48 / 0.75 | 2.8 / 3.9 | 3/3 | 0.61 s | 1 / 1.4 cm | 0.80 |
| jog, 90° | 0.38 / 0.40 | 0.6 / 0.9 | 3/3 | 0.68 s | 0 | 0.43 |
| jog, back | 0.73 / 0.75 | 4.9 / 6.7 | 3/3 | 0.87 s | 9 / 3.4 cm | 0.61 |
| sprint, straight on | 0.92 / 0.92 | 0.6 / 0.6 | 3/3 | 0.37 s | 0 | 0.97 |
| sprint, 90°, far | 1.25 / 1.28 | 5.8 / 5.8 | 3/3 | 1.57 s | 10 / 8.5 cm | 1.11 |
| nobody, empty bar | 0.35 / 0.38 | 4.1 / 5.3 | – | rolled 8.7 m | 1 / 1.0 cm | 0.57 |
| nobody, full bar | 0.42 / 0.45 | 0.2 / 0.2 | – | rolled 29.8 m | 12 / 3.5 cm | 0.51 |
| first time, back the way it came | – | 7.7 / 7.9 | 3/3, all first time | 0.87 s | 0 | 0.23 |
| first time, 45° | – | 7.5 / 9.0 | 3/3, all first time | 0.92 s | 0 | 0.21 |
| first time, 90° | – | 7.2 / 7.5 | 3/3, 2 first time | 0.93 s | 7 / 7.0 cm | 0.24 |
| give and go (Near returns it) | 0.43 / 0.48 | 0.9 / 3.9 | 3/3 back to the player | 4.15 s round trip | 0 | 0.94 |

- **Sprinting is slower because of the sprint knock.** The ball runs 1.6 m ahead, so the player has to run onto it before planting.
- **The shortest pass rolls 8.7 m, not 8.** The quickest tap of S is one tick, which fills 1/28 of the bar.

## 7. Known limits and tuning by feel

1. **Weight against snappiness.**
   - From S being let go to the ball leaving: about 0.55–0.7 s standing or jogging, and 1.1–1.5 s off a sprint, counting the 0.2 s lock.
   - Knobs: `kick_brake` (plant), `kick_entry_speed` (how early the swing may start), `kick_rate` (swing speed), `lock_delay`.
2. **One kick clip for every pass.** It is a standing instep kick on the right foot. A left-footed or side-foot clip, chosen by where the ball sits, would look better for passes to the left.
3. **The plant's foot slip** (0.4–1.1 m/s) comes from the slow gait while the player closes on the ball. It's the same slip as in slow dribbling.
4. **First-time kicks** meet the ball about 8 cm off the ideal spot: the body is still settling its last few degrees of turn.
5. **Receiving is the dribble's pickup.** A 7 m/s pass is controlled dead with one touch. A heavier first touch, or a "receive"/"stall" clip from `soccer_animations/`, would add weight there.
6. **No goals and no out of play.** A pass to nobody rolls on past the pitch edge.

## 8. Testing

```
./Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path tavernaball --script "<abs path>/tools/anim_tests/pass_bench.gd" [-- only=<scenario>] [verbose] [trace]
```

| Script | Checks | Pass line |
|---|---|---|
| `pass_bench.gd` | receiver choice, plus the table above: right receiver, foot within 15 cm of the ball, no teleports | `PASS_OK` |
| `ball_roll_test.gd` | the drag closed forms against integration, stop distance, determinism, hop, spin | `ROLL_OK` |

- `verbose` prints each run; `trace` prints every tick of each kick (speeds, turn left, ball gap, toe heights).
- **Recording:** `record_pass.gd`, without `--headless`, with `--write-movie out/f.png --fixed-fps 30 --resolution 960x540 [-- close]`.
