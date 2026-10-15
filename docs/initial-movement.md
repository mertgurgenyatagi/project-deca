# Branch `initial-movement`: player movement and animation

This branch sets up the Tavernaball Godot project. It adds a pitch, one controllable player and a broadcast camera. Movement is timed against PES 2013 and then run 20% faster. Animation is built so the feet stay planted. This document covers what the branch contains, how it works, how it was measured, and what's still open.

- **Engine:** Godot 4.7.2 (Forward+, Jolt Physics, D3D12 on Windows)
- **Project:** `tavernaball/`
- **Main scene:** `res://scenes/main.tscn`
- **Controls:** arrow keys move, Shift sprints

---

## 1. Contents

```
tavernaball/
  project.godot                  input actions, main scene, MSAA, physics interpolation, Jolt
  scenes/
    main.tscn                    Pitch + Player + Camera3D
    pitch.tscn                   floor, colliders, sky, sun
    player.tscn                  CharacterBody3D, Mixamo model, AnimationTree
  scripts/
    player.gd                    movement model + animation driver (≈600 lines)
    follow_camera.gd             broadcast camera
  shaders/
    concrete_pitch.gdshader      concrete floor and pitch markings
  assets/
    characters/player/character.fbx
    animations/
      mixamo_loop_import.gd      post-import script for gait loops
      mixamo_turn_import.gd      post-import script for one-shot clips
      locomotion/idle.fbx, jog_forward.fbx, sprint.fbx
      turns/turn_180.fbx
      starts/sprint_start.fbx
  addons/godot_mcp/              editor plugin + runtime bridges used by the godot-mcp server
tools/anim_tests/                headless timing, foot-slide and recording scripts
docs/initial-movement.md         this document
HANDOVER.md                      working notes for the next session
.mcp.json                        godot-mcp server config for Claude Code
```

Not committed (see `.gitignore`):
- **The Godot executables.** Download Godot 4.7.2 from godotengine.org and put `Godot_v4.7.2-stable_win64*.exe` at the repo root. The test commands below expect them there.
- **The raw Mixamo downloads at the repo root:** `character.fbx`, `Sprint.fbx`, `Idle To Sprint.fbx`, `Running To Turn.fbx`, `Walking Turn 180 (1).fbx` and `soccer_animations/` (54 soccer clips). The game uses copies under `tavernaball/assets/`. The originals exist only on the original machine.
- **`.godot/`.** It's regenerated on the first editor open or headless `--import`.

### Project settings changed from the defaults
| Setting | Value |
|---|---|
| Input actions | `move_left/right/up/down` on the arrow keys, `sprint` on Shift. All physical keys, deadzone 0.2. |
| `physics/common/physics_interpolation` | on |
| `physics/3d/physics_engine` | Jolt Physics |
| `rendering/anti_aliasing/quality/msaa_3d` | 4x |
| `application/run/main_scene` | `res://scenes/main.tscn` |
| Autoloads | `MCPRuntimeBridge`, `MCPInputBridge`, `MCPScreenshotBridge` (from the godot-mcp addon) |

---

## 2. Scene

### Pitch (`pitch.tscn`, `concrete_pitch.gdshader`)
- A **36.5 × 27.5 m** dark-gray concrete playing surface with a box collider.
- The shader draws all the markings, so there is no line geometry:
  - the outline and the halfway line
  - the centre circle, radius 2.75 m
  - a penalty semicircle at each end, radius 6 m from the goal-line centre
  - a penalty spot 6 m out at each end
- Around it is a darker **400 × 400 m** concrete surround, which also has collision.
- Procedural day sky, and a directional sun with shadows.
- No goals, no ball.

### Camera (`follow_camera.gd`)
- A fixed-height, fixed-angle broadcast camera (FOV 34°, about 10 m up and 24 m back).
- It slides along the pitch's length (X) to follow the player.
- Smoothing is exponential: `follow_sharpness` = 4.8.
- It reads the player's *interpolated* transform each rendered frame, and has physics interpolation turned off for itself so it isn't interpolated twice.

---

## 3. Movement model

### 3.1 Calibration
The user timed PES 2013 movements over a 3.7 m distance, counting video frames. One PES frame is taken as 1/30 s. On that basis the PES jog is 2.47 m/s, which is exactly the natural pace of the jog clip. The constants were first fitted to match every measurement.

Then the whole game was sped up **×1.2**, in the sense of playback speed: each movement keeps its PES shape and distances but takes 1/1.2 of the time. That means:
- speeds, turn rates, blend rates and smoothing rates are multiplied by **1.2**
- accelerations are multiplied by **1.44** (1.2²), so the distance covered while speeding up or braking stays the same; for example, turnbacks still overshoot about 0.6 m
- times, such as fade durations, are divided by **1.2**

| Test (PES frames) | PES | Game at PES pace | Game now (×1.2) | Constant it pins |
|---|---|---|---|---|
| Accelerate + move 3.7 m, from standstill | 56 | 56 | 46.5 | `acceleration` |
| Move 3.7 m, flying start | 45 | 45 | 37.5 | `move_speed` |
| Turnback while moving, until full speed the other way | 38 | 37.5 | 31.5 | `turnback_brake` |
| Turnback + move 3.7 m | 79 | 79 | 66.0 | (same) |
| Turnback + move ×3 between edges | 196 | 199.5 | 167.0 | (same) |
| Accelerate + sprint 3.7 m, from standstill | 44 | 44 | 36.5 | `sprint_acceleration` |
| Sprint 3.7 m, flying start | 29 | 29 | 24.5 | `sprint_speed` |

The "×3" test assumes the user pressed about 0.6 m early, so that each turn happens on the edge. Reproduce the table with `tools/anim_tests/pes_timing.gd`. It now reports the ×1.2 times against the original PES numbers.

### 3.2 Constants (`Player` Inspector exports)

| Export | Now | PES pace | Source |
|---|---|---|---|
| `move_speed` (m/s) | 2.964 | 2.47 | measured |
| `acceleration` (m/s²) | 7.0 | 3.36 | measured; base raised from 4.838 to refit the PES tests once the agile careful first step (§3.4) was added |
| `sprint_speed` (m/s) | 4.596 | 3.83 | measured |
| `sprint_acceleration` (m/s²) | 7.98 | 3.83 | measured; refitted the same way (was 5.515) |
| `turnback_brake` (m/s²) | 7.099 | 4.93 | measured |
| `deceleration` (m/s²), no keys held | 18 | 10 | guess (raised from 14.4 for snappier play) |
| `sprint_slowdown` (m/s²), Shift released | 7.2 | 5 | guess |
| `pivot_turn_speed` (°/s), standing | 540 | 360 | guess (raised from 432 for snappier play) |
| `run_turn_speed` (°/s), turns short of a turnback | 540 | 360 | guess (raised from 432) |
| `sprint_turn_speed` (°/s), same at full sprint | 330 | 220 | guess (raised from 264) |
| `turnback_turn_speed` (°/s), cap for procedural turnbacks | 480 | 400 | guess |
| `turn_sharpness` | 16 | 10 | feel (raised from 12) |
| `go_angle` (°), start moving once within this of the target heading | 45 | 45 | guess |
| `turnback_angle` (°), input this far from travel = turnback | 120 | 120 | design |
| `turnback_min_speed` (m/s), slower reversals pivot instead | 0.6 | 0.5 | design |
| `use_sprint_start` | true | | switch |

### 3.3 Behaviour
- **Steering.** With input held, the body turns toward the input at a rate that blends with speed: pivot rate standing still, run rate at jog speed, sprint rate at full sprint. The turn eases into the final heading (`turn_sharpness`). The player always travels the way the body faces.
- **Pivot from standstill.** The body turns on the spot and starts accelerating once it is within `go_angle` of the input direction.
- **Turnback** (derived from the PES data). It triggers when the player is moving faster than `turnback_min_speed` and the input points at least `turnback_angle` away from the direction of travel. It runs in two phases:
  1. *Brake*: the player decelerates in a straight line along the old direction at `turnback_brake` while the body turns. From jog speed this takes 0.5 s at PES pace and overshoots about 0.6 m.
  2. *Push-off*: once stopped, the player accelerates in the new direction exactly like a standing start.

  An action carries on only while its direction is still held; releasing or changing the input ends it. The user confirmed that all three PES turnback measurements were moving turnbacks. Sprint turnbacks reuse `turnback_brake` and were never timed in PES.
- **Sprint.** Holding Shift raises the top speed and the acceleration. On release, speed eases back to jog speed at `sprint_slowdown`.
- **Exact 180° reversals** turn through the side facing the camera (+Z) for procedural turns, so the player's front stays in view. Turns that play the clip go the clip's way (right).

---

### 3.4 Agility (added on branch `ball-interaction`)
At low speed the player is agile, with or without the ball. These rules were developed for dribbling and then made general, so that movement with and without the ball is the same; the ball only changes *when* a change happens (at a touch).

- **Agility curve:** agility is `1 − (speed ÷ (agile_until × jog speed))²`. That's 1 at a standstill, easing slowly, and 0 at jog speed.
- **What full agility changes:**

| Export | Default | Effect at full agility |
|---|---|---|
| `agile_acceleration` | 0.6 | a careful first step. The base accelerations were refitted so the PES tests still match. |
| `agile_turn_boost` | 2× | turn rate |
| `agile_turn_snap` | 3× | how sharply turns settle (with the boost): crisp, not gliding |
| `agile_cut` | 0.5 | the direction of travel jumps half way to the new direction at once: a cut, not a carve |
| `agile_pivot` | 1.0 | steering turns pivot about the planted (lower) toe, with turn-driven leg stepping off, so the stance foot holds instead of skating |
| `agile_turnback_speed` | 2 m/s | reversals below this are quick pivots, not full turnbacks |

- **Always on, at any agility:**
  - `redirect_slowdown` (0.5): changing direction costs that share of speed at 180°, proportionally less for smaller changes. Turnbacks brake instead.
  - `jog_stride` (0.75): jog strides are 75% of the clips' own length at the same speed, for quicker, shorter steps. The swing is shrunk by mixing the idle pose into the gait (the Locomotion blend), and the stride-matched crossfades allow for it. The sprint keeps its stride.

**PES check after the refit** (game frames ×1.2 against the targets):

| Test | Now | Target |
|---|---|---|
| acc+move | 47.0 | 46.5 |
| move | 37.5 | 37.5 |
| turnback | 31.0 | 31.5 |
| turnback+move | 66.0 | 66.0 |
| chain ×3 | 168.5 | 167.0 |
| accsprint+sprint | 36.5 | 36.5 |
| sprint | 24.0 | 24.5 |

**Foot slip:** the benches' 4.5 cm "planted" threshold now counts low swinging feet, because the idle mix lowers the swing, so their slip figures read high. With a strict 2 cm threshold, jog turnbacks slip 0.60 m/s on average (mean peak 2.6), slightly better than with full strides (0.62 / 3.2).

## 4. Animation

The top requirement is **extremely seamless** animation. The system is built around one rule: **every clip except the idle is positioned by distance travelled, never by time.** As a result the feet stay planted at any speed, and the ×1.2 speed-up needed no animation changes beyond the idle's playback rate.

### 4.1 Clips
All clips are Mixamo, exported at 30 fps with root motion ("In Place" unchecked) and no skin. Each `.import` uses `importer="animation_library"` with a post-import script. The one-shot clips also set `animation/trimming=false` and `remove_immutable_tracks=false`.

| Clip | File | Import script | Role |
|---|---|---|---|
| idle ("offensive idle") | `locomotion/idle.fbx` | loop | standing; plays in time at `idle_rate` (1.2) |
| jog | `locomotion/jog_forward.fbx` | loop | gait loop, about 2.06 m per stride cycle |
| sprint | `locomotion/sprint.fbx` | loop | gait loop, about 3.16 m per cycle (natural pace 5.9 m/s) |
| walking turn 180 | `turns/turn_180.fbx` | turn | every clip-driven turnback, at all speeds |
| idle to sprint | `starts/sprint_start.fbx` | turn | sprinting off from a standstill (`use_sprint_start`) |

### 4.2 Import scripts
**`mixamo_loop_import.gd`** (gait loops):
- normalizes the hips position track to *unit hip height*
- removes the linear forward drift so the clip loops in place
- sets the loop mode and renames the animation to the file's basename
- stores `root_motion_speed` in the metadata, in hip heights per second

**`mixamo_turn_import.gd`** (any one-shot clip):
- resamples the hips at 30 fps
- takes *facing* as the hips yaw averaged over ±7 samples
- takes the *line of motion* as the direction to the farthest point the hips reach
- strips the facing rotation and the travel along that line from the hips, keeping the sideways shift and the height
- stores this metadata:
  - `turn_times`
  - `turn_distance`: cumulative |travel along the line|, so it never decreases
  - `turn_progress`: facing, from 0 to 1
  - `turn_stop_distance`: the first point where the hips come to rest after having got moving
  - `turn_total_distance`
  - `turn_angle`

Because every clip is normalized to unit hip height, `player.gd` sets `Skeleton3D.motion_scale` to the character's hip height (about 0.998 m).

### 4.3 AnimationTree (`player.tscn`)
```
Idle → IdleRate ─────────────────────────────┐
Jog → JogFreeze(scale 0) → JogSeek ────┐     │
Sprint → SprintFreeze → SprintSeek ────┴ Gait(Blend2) ─┴ Locomotion(Blend2) ─ TurnBlend ─ StartBlend → output
Turn → TurnFreeze → TurnSeek ───────────────────────────────────────────────────┘           │
Start → StartFreeze → StartSeek ─────────────────────────────────────────────────────────────┘
```
Every clip except the idle is frozen (TimeScale 0) and positioned through `seek_request`. `player.gd` sets the seek positions and blend amounts every `_process` frame.

### 4.4 How `player.gd` drives it
**Gait (jog and sprint):**
- A single `_gait_phase` (0–1, where 0 is the left foot at its furthest forward) drives both loops. Each loop's offset to that reference point is found with forward kinematics in `_ready`.
- The phase advances at ground speed ÷ stride length, with the stride length blended between jog and sprint. The feet therefore stay planted, and the stride lengthens as speed rises. `min_jog_rate` keeps the legs from freezing at very low speed.
- `_sprint_weight` blends the jog and sprint loops by speed, between `move_speed` and `sprint_speed`.
- Turning adds to the speed the legs see (`turn_step_radius`, metres per rad/s), so the legs keep stepping during pivots.
- While the idle is fully showing, the hidden gait phase is continuously matched to the idle's feet, so moving off blends in from matching feet.

**One-shot clips (`OneShot`):**
- **Positioned by distance.** During a turnback brake, the clip's position is `stop − v²/(2·turnback_brake)`, so the clip reaches its own stop frame exactly when the player stops. During the push-off, the position is `stop` plus the distance travelled since the stop. The sprint start simply accumulates the distance travelled.
- **Facing.** The body's facing (`_yaw`) follows the clip's facing progress, renormalized from the point where the clip was entered.

**Stride-matched crossfades:**
- *Entry:* `_choose_clip_entry` predicts where the gait's feet will be partway through the fade-in and picks the clip sample that matches best, within `clip_entry_window` of turn progress.
- *Exit:* `_sync_gait` re-phases the hidden gait so it matches the clip halfway through the fade-out.
- Fades are fixed-time and eased with smoothstep: `clip_fade_in_time` = `clip_fade_out_time` = 0.25 s (0.3 s at PES pace).

**Turn direction:** the walking turn always turns right. Exact 180° reversals therefore play the clip turning right. Turnbacks short of 180° that need a left turn use the **procedural** path: the body rotates without a clip, at up to `turnback_turn_speed`.

### 4.5 Animation exports
| Export | Now | PES pace |
|---|---|---|
| `jog_blend_speed` (m/s), speed at which the gait fully replaces the idle | 1.44 | 1.2 |
| `blend_sharpness` | 12 | 10 |
| `min_jog_rate` | 0.72 | 0.6 |
| `turn_step_radius` (m per rad/s) | 0.3 | 0.3 |
| `clip_fade_in_time` / `clip_fade_out_time` (s) | 0.25 / 0.25 | 0.3 / 0.3 |
| `clip_entry_window` (turn progress) | 0.15 | 0.15 |
| `idle_rate` | 1.2 | 1.0 |

---

## 5. Measured quality

**Foot slip** is the horizontal speed of planted feet, in m/s. A foot counts as planted when its toe is below 4.5 cm. **Pop** is the largest per-frame bone acceleration.

The benches average 10 turnbacks, or 8 starts, landing at different points in the stride. Single runs are noisy because the result depends on the stride phase. Slip is a speed, so at ×1.2 pace some rise is expected even if the motion is unchanged.

| Situation | PES pace (avg / mean peak) | ×1.2 (avg / mean peak) |
|---|---|---|
| Steady jog (reference, single-run max) | 0.12 / ~0.7 | 0.10 / 0.53 |
| Steady sprint (reference, single-run max; sprint touchdowns inflate it) | 0.46 / ~1.3 | 0.53 / 1.44 |
| Jog turnback (`turnback_bench`) | 0.66 / 3.7 | 0.76 / 4.05 |
| Sprint turnback (`turnback_bench -- sprint`) | 0.81 / 3.1 | 0.85 / 4.11 |
| Sprint start from standstill (`start_bench`) | 0.79 / 2.7 | 0.79 / 2.92 |

Pops stay at about 0.03–0.10, close to what the steady loops produce.

### Tried and rejected
- **"Running To Turn"**, a run that brakes, turns 190° left and stops, with no push-off. It was used for sprint turnbacks, with the sprint start as the push-off. It measured 1.27 average and a mean peak of 9.6, against 0.81 / 3.1 for the walking turn, so it was removed.
- **The sprint start as the push-off after the walking turn.** Worse: 1.11 average.
- **Entry-point strategies** (earliest, latest, stride-matched). Similar averages. Longer fade-ins (0.25–0.3 s at PES pace) roughly halved the peaks.

---

## 6. Known limits and next steps
1. **Standing pivots slide.** The idle's feet sit about 19 cm either side of center and get swung round when the body turns. Fix: a Mixamo turn-in-place clip ("Left/Right Turn 90", "Turn 180" standing).
2. **Turnback crossfades still slide briefly,** with peaks of 3–4 m/s for a few frames. The walking turn's feet sit about 20 cm apart against the jog's 75 cm, so no stride point matches well. Likely fix: **IK foot locking** during transitions, where the planted foot's world position is locked and the leg is solved with two-bone IK. Check `ClassDB` for TwoBoneIK3D-style `SkeletonModifier3D`s in 4.7.2 first.
3. **Exact reversals always turn right.** A mirrored "Walking Turn 180" (Mixamo's Mirror checkbox), wired as a second `OneShot` and chosen by direction, would allow left turns.
4. **The turn clip is a walking turn,** so jog and sprint turnbacks have a walking posture. A jogging or running 180° turn clip *with a push-off* would look better.
5. **Several constants are guesses** (§3.2). Useful PES timings to collect: a stop, a standing 180°, a sprint turnback and a sprint release.
6. **No goals or other players yet.** The ball and touch dribbling came next, on branch `ball-interaction`. See [touch-dribbling.md](touch-dribbling.md).

---

## 7. Testing

Headless scripts are in `tools/anim_tests/`. Run them from the repo root:

```
./Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path tavernaball --script "<abs path>/tools/anim_tests/<script>.gd" [-- sprint]
```

| Script | Purpose |
|---|---|
| `pes_timing.gd` | the 7 PES timing scenarios |
| `motion_test.gd` | jog scenario: per-phase slip and pops |
| `sprint_test.gd` | sprint scenario: per-phase slip and pops |
| `turnback_bench.gd` | 10 turnbacks at varied stride phases (`-- sprint` holds sprint) |
| `start_bench.gd` | 8 sprint starts from a standstill |
| `check_clips.gd` | prints the processed clip metadata |
| `inspect_clip.gd` | raw hips path, yaw and toe heights of a clip (`-- res://path.fbx`), via manual forward kinematics |
| `record_turn.gd`, `record_sprint.gd` | drive the player for visual checks. Run without `--headless`, with `--write-movie out/f.png --fixed-fps 30 --resolution 960x540` |

Notes:
- Ignore the "leaked RID / ObjectDB" errors printed at exit.
- Some tests poke private fields of `player.gd` (`_action`, `_ground`, `_yaw`, `_gait_phase`, …), so they need updating when those change.
- Reimport assets headless with `cd tavernaball && ../Godot_v4.7.2-stable_win64_console.exe --headless --path . --import`.
- Judge animation changes with the averaged benches, not single runs.

## 8. Tooling notes (godot-mcp)
- `execute_editor_script` and `execute_game_script` evaluate a single GDScript *Expression* only: no `var` and no singletons. To run real code, duplicate the MCP plugin's script, `set_source_code(...)`, `reload()`, then `.new().run()`, all in one array expression.
- `set_input_action` doesn't save to `project.godot`. Use `ProjectSettings.set_setting` and `save()` through the trick above. Don't hand-edit `project.godot` while the editor is open.
- `simulate_action` and `simulate_key` don't reach the running game. Use `get_node("/root/MCPInputBridge")._apply({...})` through `execute_game_script`.
- Screenshots are too big to return inline. Read `%APPDATA%/Godot/app_userdata/Tavernaball/mcp_screenshot_res.png` instead.
- `.tscn` `Transform3D(...)` lists basis rows, not columns.
