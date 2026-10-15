# Touch Dribbling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A ball the player picks up automatically and dribbles with visible touches timed to the gait, never glued and never lost. The spec is [2026-10-15-touch-dribbling-design.md](../specs/2026-10-15-touch-dribbling-design.md).

**Architecture:**
- `Ball` is a `Node3D` that moves itself: an analytic loose roll, or held and driven by acceleration.
- `Dribble` is a child node of `Player` that plans the touches from the player's read-only state.
- `player.gd` gains an input seam and accessors. Its movement is unchanged.

**Tech Stack:** Godot 4.7.2 GDScript, plus headless SceneTree test scripts in `tools/anim_tests/`.

**Execution note:** the author executes this plan inline, with full autonomy granted by the user. So the steps give interfaces, behaviour and acceptance numbers rather than duplicating every line of code; the spec holds the formulas.

## Global Constraints

- The movement behaviour must not change: `pes_timing.gd` output stays identical (46.5 / 37.5 / 31.5 / 66.0 / 167.0 / 36.5 / 24.5).
- The ball never reads input. The dribble never reads input: it reads `player.move_input` and `player.sprint_held`.
- Ball radius 0.11 m. The floor is at y = 0, so the ball's centre sits at y = 0.11.
- Test command pattern (from the repo root):
  `./Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path tavernaball --script "C:/Users/Mert/Desktop/repos/project-deca/tools/anim_tests/<script>.gd"`

---

### Task 1: Player input seam and read-only API

**Files:** Modify `tavernaball/scripts/player.gd`.

**Produces:**

| Member | Type / signature | Notes |
|---|---|---|
| `move_input` | `Vector2` | |
| `sprint_held` | `bool` | |
| `read_input` | `bool = true` | when false, the player doesn't read the keyboard (the network seam) |
| `yaw` | `float` | getter only |
| `ground_velocity` | `Vector2` | |
| `gait_phase` | `float` | |
| `sprint_weight` | `float` | |
| `action` | `Action` | |
| `action_dir` | `Vector2` | |
| `phase_rate_at(speed: float) -> float` | | |
| `gait_feet_at(phase: float, sprint_weight: float) -> PackedVector3Array` | | foot and toe points in model space, ordered [L foot, L toe, R foot, R toe] |
| `top_speed() -> float` | | |
| `current_acceleration() -> float` | | |
| `turn_rate_at(speed: float) -> float` | | radians per second |
| `skeleton` | `Skeleton3D` | |

- [ ] Run `pes_timing.gd` and record the baseline.
- [ ] Replace the `Input` reads with `move_input` / `sprint_held`, filled at the top of `_physics_process` when `read_input` is true. Factor `turn_rate_at` out of `_step_steering`. Add the getters.
- [ ] Run `pes_timing.gd` again. It must match the baseline exactly. Commit.

### Task 2: The Ball

**Files:**
- Create `tavernaball/scripts/ball.gd`, `tavernaball/shaders/ball.gdshader`, `tavernaball/scenes/ball.tscn`
- Test with `tools/anim_tests/ball_roll_test.gd`

**Produces:** `class_name Ball`.

| Member | Type / signature | Notes |
|---|---|---|
| `radius` | `float` | export |
| `roll_deceleration` | `float` | export |
| `holder` | `Node` | |
| `velocity` | `Vector3` | |
| `acceleration` | `Vector3` | used while held |
| `release(at: Vector3, vel: Vector3, by: Node = null) -> void` | | |
| `touch(vel: Vector3) -> void` | | |
| `place(at: Vector3) -> void` | | teleport for setup; resets interpolation |
| `last_releaser` | `Node` | |
| `roll_position_at(t: float) -> Vector3` | | analytic |
| `released_signal` | | not needed (YAGNI) |

- [ ] Write `ball_roll_test.gd`:
  1. Release at (0, r, 0) with (3, 0, 0). After 5 s the ball sits at x = 9/(2·1.2) = 3.75 within 1 mm, and its velocity is 0.
  2. Two balls released identically match each other's positions to 1e-6 every tick.
  3. The spin's axis is perpendicular to the velocity, and the rolled angle equals distance ÷ r within 1%.
- [ ] Run it. It fails (no Ball yet).
- [ ] Implement `ball.gd`:
  - Loose: the position comes from `roll_position_at(time since release)`.
  - Held: `velocity += acceleration·dt; position += velocity·dt`.
  - Spin applies to the child `Mesh` basis.
  - `process_physics_priority = 10`.
- [ ] Implement the shader (truncated-icosahedron face test, per the spec) and the scene: `Ball` Node3D with a `Mesh` MeshInstance3D (SphereMesh r 0.11, 32×16).
- [ ] Run the test. It passes. Commit.

### Task 3: Dribble: touch geometry, prediction and planning

**Files:**
- Create `tavernaball/scripts/dribble.gd`
- Add a `Dribble` node to `tavernaball/scenes/player.tscn`
- Add the Ball to `main.tscn`: ball at (0, 0.11, 0), player at (−2, 0, 0)
- Test with `tools/anim_tests/dribble_bench.gd`

**Consumes:** Tasks 1 and 2.

**Produces:**
- exports per the spec defaults
- `ball: Ball` (a NodePath export, `ball_path`)
- `can_take(b: Ball) -> bool`
- debug read-outs for the bench:
  - `touch_count: int`
  - `last_contact_error: float`
  - `bend_now: float`
  - `segment_clamped: bool`
  - `touch_log: Array` (each entry: time, foot, contact error)

- [ ] Write `dribble_bench.gd`:
  - The scenario runner drives `player.read_input = false` and sets `move_input` / `sprint_held` directly.
  - Scenarios: steady jog, steady sprint, start, 90° jog, 90° sprint, jog turnback, sprint turnback, stop, standing pivot, pickup ×4.
  - Each scenario is repeated at 3 start offsets.
  - Metrics as in the spec.
  - It prints a table and a final `DRIBBLE_OK` / `DRIBBLE_FAIL` line based on:
    - the ball is never more than 3.0 m from the hips while held
    - the holder never drops
    - pickups complete within 1.5 s
    - no per-tick jump above `|v|·dt` + 1 cm except at touches
- [ ] Run it. It fails (no Dribble).
- [ ] Implement the Dribble:
  - The touch phase per foot comes from `gait_feet_at` scanning for the maximum forward toe z, minus `touch_phase_offset`.
  - `contact_offset(foot, phase, sprint_weight) -> Vector3` gives the model-space contact point.
  - `predict(tau) -> Dictionary` returns {pos: Vector2, vel: Vector2, yaw, phase}.
  - `time_to_touch(foot, cycles) -> float` searches the predicted phase.
  - Segment planning, bending with the growing cap, early touches from the real toes, the rest point, and pickup, all per the spec.
- [ ] Run the bench. It passes. Commit.

### Task 4: Debug knock-loose key

**Files:**
- Create `tavernaball/scripts/debug_keys.gd`
- Attach it to `Main` in `main.tscn`

- [ ] The B key calls `ball.release(ball.position, random_dir · sqrt(2·a·d), holder)` with d in [3, 5] m.
- [ ] Verify live via godot-mcp: play, dribble, press B, walk to the ball, and it's picked up. Commit.

### Task 5: Tuning, regression, visuals and docs

**Files:**
- Create `tools/anim_tests/record_dribble.gd`
- Create `docs/touch-dribbling.md`
- Update `HANDOVER.md` and `docs/initial-movement.md` §6

- [ ] Run the regressions: `pes_timing`, `turnback_bench` (jog and sprint) and `start_bench`. They must match the earlier numbers.
- [ ] Tune the defaults with `dribble_bench`, aiming for:
  - median contact error under 3 cm
  - no pass-through at a steady jog
  - jog lead ≤ about 0.9 m ahead of the hips; sprint 1.4–2.0 m
- [ ] Record a movie and look at the frames: touches meet the foot, and no visible bend at a steady pace.
- [ ] Write the docs with the measured numbers. Commit.
