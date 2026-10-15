# Notes

What isn't in [docs/initial-movement.md](docs/initial-movement.md) (movement and animation), [docs/touch-dribbling.md](docs/touch-dribbling.md) (ball and dribbling) or [docs/passing.md](docs/passing.md) (passing). Read those three first.

## Direction and preferences

- **End goal: online play with friends.** About 5–6 people, each controlling one player from their own copy of the game.
  - Visuals don't need to match across machines; whatever works cleanest wins.
  - Only outcomes have to agree: positions, ball, goals.
  - There's no network code yet. The seams are listed in touch-dribbling.md.
- **Movement is the same with or without the ball.** Any movement change applies to both. The ball only changes *when* a change is acted on (at a touch).
- **Prefer emergent behaviour over special cases.** Example: close control under rapid key presses comes from "turning costs pace", "slow means agile" and "agile means control". Nothing detects rapid input.
- **The owner tunes by feel.** They describe what's wrong ("ice skater", "pinned in front", "too transitiony") and expect a diagnosis, a change, and the knob to tune it. If a change feels wrong, find out why and roll it back with a revert commit.
- **Animation must be seamless.** No pops, no teleports, feet planted where possible.

## Gotchas

- **The godot-mcp plugin edits `project.godot`.** It adds its three bridge autoloads when the editor opens and removes them when the editor closes. A diff that only drops the `[autoload]` block is that, not a real change: restore the file, don't commit it.
- **`get_project_info` always reports `autoloads: {}`.** It's a bug in the tool. Check the bridges with `execute_game_script` while the game runs.
- **godot-mcp drops its connection now and then.** Reload its tools; if the editor is closed, ask for it to be reopened.
- **Don't let the editor save over scene files changed on disk while it was open** (`main.tscn`, `player.tscn`). Reload the scene in the editor instead.
- **New `class_name` scripts need an import pass before headless runs:**
  `cd tavernaball && ../Godot_v4.7.2-stable_win64_console.exe --headless --path . --import`
- **A headless test script that errors before `quit()` hangs.** Run tests under `timeout`, and guard missing resources with an early `quit()`.
- **Headless key events:** use `root.push_input(event)`. `Input.parse_input_event` doesn't reach `_unhandled_input` there.
- **`dribble_bench.gd` runs its scenarios one after another in one scene,** so results can depend on order. That's how a slipping stride counter was found. Use `-- only=<name>` to isolate a scenario.
- **To trace a bench problem,** copy the bench to a scratch folder and insert prints at the first frame a metric crosses a limit, for example the ball's distance from the player. `pass_bench.gd` has this built in: `-- only=<name> trace`.
- **`main.tscn` has two stand-in teammates under `Teammates`.** Every test that loads it frees that node first, except `pass_bench.gd` and `record_pass.gd`. A new test should too, or the stand-ins will take the ball and block the player.
- **Setting `global_position` in a test's `_initialize` errors** (`!is_inside_tree()`): the tree isn't running yet. Set `position` there, or wait a frame.
- **The kick clips in `soccer_animations/`:** "kick soccerball (2)" is the light right-footed kick used for passes (toe at 4.8 m/s at contact); "kick soccerball" is a harder left-footed one (6.2 m/s); "strike foward jog" is a running shot. All come from a rig whose feet stand about 4 cm lower than the idle's.

## Caveats about the docs

- **The §5 table in touch-dribbling.md was measured early on the branch.** It predates gating, grip/agility, quicker strides, notched sprinting and the even sprint rhythm. Re-run `dribble_bench.gd` for current numbers. The later per-feature figures in its §3.0 and in initial-movement.md §3.4 are current.
- **`docs/superpowers/specs/` and `docs/superpowers/plans/` are historical:** the original design and plan for touch dribbling. Several rules and defaults changed during tuning, and the two docs describe the final behaviour.

## Tried and dropped on `ball-interaction`

These aren't covered in the docs.

- **Steering the player at the ball while a change waits.** At speed it overshot and orbited the ball, and it once ran the player away from a ball left behind. Replaced by keeping the last direction and bringing the next touch forward.
- **Stopping the ball dead while a change waits.** It also overrode the turnback plan.
- **No steering in the last 0.12 s before a touch,** to cut prediction noise. It caused more off-rhythm touches and pushed the ball out to 3.2 m.
- **Touching on every step at full jog speed, with a 0.75 m hip reach.** The ball held a fixed spot and answered the keys instantly: "pinned", "attached". Every-step touches are kept only at low speed (grip).
- **A 2.5× agile turn boost.** The body outran the ball, which swung out to 1.1–1.4 m.
- **A fixed "honest slowing" vector per touch (bug, fixed).** Once steering had reversed the ball, it pushed the ball on, away. The slowing is now always applied against the current motion.
- **Full-speed contact pushes at low speed.** A pivoting foot flung the ball out. Contact pushes now scale with grip.

## Open items

- **Skating on quick pivots.** Planted-foot slip is still about 1.0–1.3 m/s under rapid presses, against about 0.2 m/s at a steady jog. Pivots are built from jog legs. The real fix is cut or turn clips (Mixamo), or foot-locking IK (check `ClassDB` for TwoBoneIK3D-style modifiers in 4.7.2).
- **`IntentLean` (body hint while a change waits) has never been checked visually.** The bone-axis signs are unverified; if the shoulders turn away from the new direction, flip the twist sign.
- **Foot–ball overlap is about 4–5% of frames in random play,** mostly in turnbacks and pivots. That's the price of keeping the ball tight.
- **Passing feel is untested by the owner.** The first things to tune are in passing.md §7: how long a pass takes to go, and whether a pass off a sprint feels too slow.
- **Next features:** shooting (the kick path in `passing.gd` and `Ball.release` with hop are the base), other players, tackles and steals, then networking.
