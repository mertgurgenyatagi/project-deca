# Handover: Tavernaball player movement & animation

> **Update, branch `ball-interaction` (2026-10-15):** there is now a ball with touch dribbling. See [docs/touch-dribbling.md](docs/touch-dribbling.md).
> - `player.gd` reads input through `move_input` / `sprint_held` (when `read_input` is on), has `class_name Player`, and exposes read-only state for the `Dribble` node. Its movement is unchanged.
> - **The guiding constraint for everything new:** the game will be played online by about 5–6 friends, each on their own copy. Visuals needn't match across machines, the cleanest design wins, and the ball and dribble never read the keyboard.
> - Run `tools/anim_tests/dribble_bench.gd` after any dribble or movement change.

State as of 2026-10-15. Branch `initial-movement` is committed and merged into `development`. The full write-up is in [docs/initial-movement.md](docs/initial-movement.md).

**Since this was written, the whole game was sped up ×1.2 (playback-speed sense).** Speeds, turn rates and blend rates are ×1.2, accelerations ×1.44, fades 0.25 s, and the idle plays at `idle_rate` 1.2. The constants below are the *PES-pace* values. For the current values and benches, see the docs §3.2, §4.5 and §5.

## 1. What exists

A Godot 4.7.2 project in `tavernaball/` with one playable scene:

- **Pitch** (`scenes/pitch.tscn`): a 36.5 × 27.5 m dark-gray concrete floor. The markings are drawn by a shader (`shaders/concrete_pitch.gdshader`): outline, halfway line, centre circle (r 2.75 m), penalty semicircles (r 6 m from the goal-line centre) and penalty spots 6 m out. There is a box collider for the pitch, plus a darker 400 × 400 m concrete surround that also has collision. The scene has a procedural day sky and a sun with shadows. There are no goals.
- **Player** (`scenes/player.tscn` + `scripts/player.gd`): a Mixamo character controlled with the arrow keys, with **Shift** to sprint.
- **Camera** (`scripts/follow_camera.gd`, in `scenes/main.tscn`): a broadcast-style camera that slides along X to follow the player, with exponential smoothing (`follow_sharpness`).
- **Main scene**: `res://scenes/main.tscn` (the pitch, the player and the camera).

Project settings changed from the defaults:
- Input actions `move_left/right/up/down` on the arrow keys and `sprint` on Shift, all physical keys.
- 3D MSAA at 4x.
- Physics interpolation on.
- The main scene set to `main.tscn`.

## 2. Movement model (calibrated to PES 2013, values at PES pace; now run ×1.2)

The user timed PES 2013 movements over 3.7 m. I took one PES frame as 1/30 s, which makes the PES jog 2.47 m/s, exactly the jog clip's natural pace. The game matches all the measurements (run `tools/anim_tests/pes_timing.gd`):

| Test (PES frames) | Game | PES | Constant it pins |
|---|---|---|---|
| Accelerate + move, from standstill | 56 | 56 | `acceleration` 3.36 m/s² |
| Move (flying start) | 45 | 45 | `move_speed` 2.47 m/s |
| Turnback while moving, until full speed the other way | 37.5 | 38 | `turnback_brake` 4.93 m/s² |
| Turnback + move 3.7 m | 79 | 79 | (same) |
| Turnback + move ×3 between edges | 199.5 | 196 | (same; assumes the user pressed ~0.6 m early so the turn happens on the edge) |
| Accelerate + sprint, from standstill | 44 | 44 | `sprint_acceleration` 3.83 m/s² |
| Sprint (flying start) | 29 | 29 | `sprint_speed` 3.83 m/s |

**Turnback model, derived from the data:** when moving and the input points ≥120° away from the travel direction, the player brakes to a stop in a straight line at 4.93 m/s² (0.5 s from jog speed, overshooting about 0.6 m) while the body turns. Then they accelerate from zero exactly like a standing start. The user clarified that all three turnback measurements were *moving* turnbacks.

**Guesses not covered by the PES data** (all are Inspector exports on `Player`):
- `deceleration` 10: stopping with no keys held.
- `pivot_turn_speed` 360°/s and `go_angle` 45°: turning on the spot from standstill, and when to start moving.
- `run_turn_speed` 360°/s: turns short of a turnback while running.
- `sprint_turn_speed` 220°/s: the same at full sprint.
- `sprint_slowdown` 5 m/s²: easing from sprint back to jog speed when Shift is released.
- Sprint turnbacks reuse `turnback_brake`. They were never timed in PES.

Movement otherwise steers: the body turns toward the input and always travels the way it faces.

## 3. Animation system (the hard part)

The user's top requirement is **"extremely seamless" animation**. They tune the constants themselves.

### Clips in use
They live in `assets/animations/`. The originals are at the repo root and in `soccer_animations/`.

| Clip | File | Import script | Role |
|---|---|---|---|
| idle | `locomotion/idle.fbx` ("offensive idle") | `mixamo_loop_import.gd` | standing |
| jog | `locomotion/jog_forward.fbx` | `mixamo_loop_import.gd` | gait loop |
| sprint | `locomotion/sprint.fbx` | `mixamo_loop_import.gd` | gait loop (5.9 m/s natural; played at ~0.65× at 3.83 m/s) |
| walking turn 180 | `turns/turn_180.fbx` | `mixamo_turn_import.gd` | every turnback, at all speeds |
| idle to sprint | `starts/sprint_start.fbx` | `mixamo_turn_import.gd` | sprinting off from a standstill (switch: `use_sprint_start`) |

All clips are Mixamo, exported with root motion ("In Place" unchecked), at 30 fps, without skin. The `.import` files use `importer="animation_library"` with a post-import script. The one-shot clips also set `animation/trimming=false` and `remove_immutable_tracks=false`.

### Import scripts
- **`mixamo_loop_import.gd`:** normalizes the hips position track to *unit hip height*, removes the linear drift so the clip loops in place, sets the loop mode, renames the animation to the file's basename and stores `root_motion_speed` (hip heights per second).
- **`mixamo_turn_import.gd`**, for any one-shot clip:
  - Resamples the hips at 30 fps and takes "facing" as the hips yaw averaged over ±7 samples.
  - Takes the line of motion as the direction to the farthest point the hips reach.
  - Strips the facing rotation and the travel along that line from the hips, but keeps the sideways shift and the height.
  - Stores the metadata `turn_times`, `turn_distance` (cumulative |travel along the line|, so it never decreases), `turn_progress` (facing 0→1), `turn_stop_distance` (the first point where the hips come to rest after having got moving), `turn_total_distance` and `turn_angle`.
- Because every clip is normalized to unit hip height, `player.gd` sets `Skeleton3D.motion_scale` to the character's hip height (about 0.998).

### AnimationTree (`player.tscn`)

```
Idle ───────────────────────────────┐
Jog → JogFreeze(scale 0) → JogSeek ─┐ │
Sprint → SprintFreeze → SprintSeek ─┴ Gait(Blend2) ─┴ Locomotion(Blend2) ─ TurnBlend ─ StartBlend → output
Turn → TurnFreeze → TurnSeek ─────────────────────────────────────────────┘           │
Start → StartFreeze → StartSeek ───────────────────────────────────────────────────────┘
```

Every clip except the idle is frozen (TimeScale 0) and positioned by `seek_request`, which `player.gd` sets every `_process` frame.

### How `player.gd` drives it
- **Gait:**
  - A single `_gait_phase` (0–1, where 0 is the left foot at its furthest forward) drives both the jog and the sprint loop. Each loop has a phase offset found with forward kinematics in `_ready`.
  - The phase advances at ground speed divided by the stride length blended between the two loops (jog about 2.06 m per cycle, sprint about 3.16 m), so the feet stay planted and the stride lengthens with speed.
  - `_sprint_weight` blends the two loops by speed between `move_speed` and `sprint_speed`.
  - While the idle is fully showing, the hidden gait phase is continuously matched to the idle's feet, so moving off blends in from matching feet.
- **One-shot clips** (class `OneShot`):
  - They are positioned by *distance actually travelled*, not by time. During a turnback, clip distance = `stop - v²/(2·turnback_brake)`, so the clip reaches its own stop frame exactly when the player stops. In the push-off, distance = stop + distance travelled since the stop.
  - The body's facing (`_yaw`) follows the clip's facing progress, renormalized from the entry point.
- **Stride-matched crossfades:**
  - The entry point is chosen in `_choose_clip_entry` by predicting the gait's foot positions partway through the fade-in and picking the clip sample that matches best, within `clip_entry_window` of turn progress.
  - On exit, `_sync_gait` re-phases the hidden gait to match the clip halfway through the fade-out.
  - Fades are fixed-time and eased with smoothstep (`clip_fade_in_time` and `clip_fade_out_time`, both 0.3 s).
- **Turn direction:** the walking turn always turns right, so exact 180° reversals always turn right. Turnbacks short of 180° that need a left turn use the **procedural** path: the body rotates without a clip, at up to `turnback_turn_speed`.
- **Standing pivots** are procedural. The turn rate is added to the gait speed (`turn_step_radius`) so the legs step while the body turns.

### Measured quality
Foot slide is measured on planted feet, in m/s. A foot counts as planted when its toe is under 4.5 cm. The benchmarks average 10 turnbacks or 8 starts landing at different stride points; single runs are noisy because they depend on stride phase.

| Situation | Avg slip | Peak |
|---|---|---|
| Steady jog (reference) | 0.12 | ~0.7 |
| Steady sprint (reference; sprint touchdowns inflate this) | 0.46 | ~1.3 |
| Jog turnback (bench) | 0.66 | mean 3.7 |
| Sprint turnback (bench) | 0.81 | mean 3.1 |
| Sprint start from standstill (bench) | 0.79 | mean 2.7 (0.73 / 2.7 with `use_sprint_start` off) |
| Jog start that includes a 90° standing pivot | 0.93 | 5.3 |

Pops (largest per-frame bone acceleration) stay at about 0.03–0.08, close to what the steady loops produce.

### Tried and rejected (with data)
- **"Running To Turn"** (`Running To Turn.fbx` at the repo root): a run that brakes, turns 190° left and stops, with no push-off. Used for sprint turnbacks, with the sprint start as the push-off, it measured clearly worse: 1.27 m/s average and mean peak 9.6 for sprint turnbacks, against 0.81 / 3.1 now. It's removed from the project; the file is still at the root.
- **Sprint start as the push-off after the walking turn:** worse (1.11 average).
- **Entry-point strategies** (earliest, latest, stride-matched): similar averages. Longer fade-ins (0.25–0.3 s) roughly halved the peaks.

## 4. Known limits and the likely next steps

1. **Standing pivots slide.** The idle's feet sit about 19 cm either side of center and get swung round. A Mixamo turn-in-place clip ("Left/Right Turn 90", "Turn 180" standing) would fix this.
2. **Turnback crossfades still produce brief foot slide** (peaks about 3–4 m/s for a few frames). The walking turn's feet sit about 20 cm apart against the jog's 75 cm, so no stride point matches well. The real fix is probably **foot locking with IK** during transitions: lock a planted foot's world position and solve the leg with a two-bone IK. Godot 4.6+ may ship IK `SkeletonModifier3D`s (TwoBoneIK3D etc.), but this is **unverified for 4.7.2**, so check `ClassDB` first.
3. **Turnbacks always turn right** for exact reversals. A **mirrored** download of "Walking Turn 180" (Mixamo's Mirror checkbox) would allow left turns, and turning through facing the camera either way. Wire it as a second `OneShot` and choose by direction.
4. **The turn is a walking clip**, so turns from a jog or sprint have a walking posture. A jogging or running 180° turn clip *with a push-off* would look better. The running turn the user tried has no push-off and measured worse.
5. Several constants are guesses (see §2). Ask the user for PES timings of a stop, a standing 180°, a sprint turnback and a sprint release.
6. No goals, ball or other players yet.

## 5. Testing workflow

Headless test scripts are in `tools/anim_tests/`. Run them from the repo root:

```
./Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path tavernaball --script "<abs path>/tools/anim_tests/<script>.gd" [-- sprint]
```

| Script | What it does |
|---|---|
| `pes_timing.gd` | the 7 PES timing scenarios |
| `motion_test.gd` | jog scenario: per-phase slip and pops |
| `sprint_test.gd` | sprint scenario: per-phase slip and pops |
| `turnback_bench.gd` | 10 turnbacks at varied stride phases (add `-- sprint` to hold sprint) |
| `start_bench.gd` | 8 sprint starts from a standstill |
| `check_clips.gd` | prints the processed clip metadata |
| `inspect_clip.gd` | raw hips path, yaw and toe heights of a clip (`-- res://path.fbx`), via manual forward kinematics |
| `record_turn.gd`, `record_sprint.gd` | drive the player for visual checks; run *without* `--headless`, with `--write-movie out/f.png --fixed-fps 30 --resolution 960x540` |

Notes:
- Ignore the "leaked RID / ObjectDB" errors printed at exit.
- Some private fields the tests poke at (`_action`, `_ground`, `_yaw`, `_gait_phase`, …) are tied to the current `player.gd`.
- Reimport assets headless with `cd tavernaball && ../Godot_v4.7.2-stable_win64_console.exe --headless --path . --import`.

## 6. Tooling gotchas (godot-mcp plugin and environment)

- **`execute_editor_script` and `execute_game_script` only evaluate a single GDScript *Expression*.** There's no `var`, no statements, and no singletons like `ProjectSettings`, `Engine` or `ClassDB`.
  - **To run real code in the editor:** duplicate the MCP plugin's script, `set_source_code(...)`, `reload()`, `.new().run()`, all in one array expression.
  - Find the plugin node with `get_tree().root.find_children("@EditorPlugin@*", "EditorPlugin", true, false)`. Its path changes every time the editor restarts.
- **`set_input_action` does not save to `project.godot`.** Persist input actions through `ProjectSettings.set_setting("input/<name>", {...})` and `ProjectSettings.save()` using the trick above.
- **Don't hand-edit `project.godot` while the editor is open.** The editor may overwrite it.
- **`simulate_action` and `simulate_key` don't reach the running game.** Call `get_node("/root/MCPInputBridge")._apply({"type": "action", "action": "...", "pressed": true})` through `execute_game_script` instead.
- **Screenshot results are too big to return inline.** Read the PNG at `C:/Users/Mert/AppData/Roaming/Godot/app_userdata/Tavernaball/mcp_screenshot_res.png` instead. The first capture after starting the game is sometimes blank.
- **`.tscn` `Transform3D(...)` lists basis rows** (xx, xy, xz, yx, …), not columns.
- **The godot-mcp server disconnects now and then.** Use ToolSearch to reload its tools.
- **The user's global `CLAUDE.md`** says only six tools exist, but godot-mcp and a Blender MCP are also configured.

## 7. Files at the repo root to be aware of
- `Godot_v4.7.2-stable_win64*.exe`: the engine. The console build is used for headless runs.
- `character.fbx`, `soccer_animations/` (54 Mixamo soccer clips), `Sprint.fbx`, `Idle To Sprint.fbx`, `Running To Turn.fbx`, `Walking Turn 180 (1).fbx`: the user's downloads. The project uses copies under `tavernaball/assets/`.
- Consider adding these to `.gitignore`, or moving them, before committing. The Godot exe is about 180 MB.
