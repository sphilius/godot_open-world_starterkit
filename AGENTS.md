# Agent instructions

Read this before changing anything. Claude Code (via `CLAUDE.md`), Codex and Jules all load it.

## Project

Godot 4.7 third-person open-world starter kit, being grown into a 10-minute combat vertical
slice. The plan and its milestones (M0–M10) are in `docs/vertical-slice/PLAN.md`; the public
API every component must keep is in `docs/vertical-slice/HANDOFF_MANIFEST.md`. Session prompts
per milestone are in `docs/vertical-slice/PROMPTS.md`.

## Environment

`bash tools/setup/gamedev_env.sh` installs everything (Godot 4.7.1, Blender 4.5 LTS, Xvfb and
Mesa for software rendering, ffmpeg) and writes `GODOT` / `BLENDER` to `~/.gamedev_env`. It's
idempotent. See `docs/DEV_ENVIRONMENT.md` for per-platform setup.

## Validate before every commit

```
bash tools/ci/validate.sh                  # import, parse gate and every headless test (~95 s)
bash tools/ci/validate.sh --filter=level   # one test file or test name substring
```

A run passes only with **0 failed**. Any engine or script error logged during a test fails it.
`godot --import` exits 0 even when scripts are broken, so the tests (`tests/test_project.gd`)
are the real parse gate.

For a quick look at the game without a GPU:
```
xvfb-run -a "$GODOT" --rendering-method gl_compatibility --rendering-driver opengl3 --path . -- --skip-menu --capture=/tmp/shot.png
```

## Conventions

- Statically typed GDScript, tabs, `##` doc comments at the top of every script explaining its
  behaviour. Designer-facing numbers are `@export`s or `Resource`s.
- Don't change a signature listed in `HANDOFF_MANIFEST.md` without updating it in the same PR.
- Physics layers: 1 world, 2 player, 3 mobs, 4 player_hitbox, 5 mob_hurtbox, 6 mob_hitbox,
  7 player_hurtbox.
- `TimeScale` is the only writer of `Engine.time_scale` (push/pop named requests).
- No autoloads. `GameManager` (M9a) is a node in `main.tscn` (`GameManager.find(tree)`).
- Placeholder rigs and clips come from `tools/build_placeholder_rigs.gd`; rebuild with
  `"$GODOT" --headless --path . --script res://tools/build_placeholder_rigs.gd`, then
  `git checkout assets/characters/wolf/` to drop the wolf's re-export noise.
- New behaviour gets a test in `tests/test_<topic>.gd` (`extends "res://tests/test_case.gd"`;
  `await load_world()` for the real world, `add_to_stage()` for a bare stage). Check that the
  test fails without the change.
- Art and audio: every sourced file under `assets/` gets a line in `assets/LICENSES.md` (create
  it with the first one). Raw drops go to `assets/incoming/`.

## Git

- Milestone branches `vs/<milestone>-<topic>`, PRs into `vertical-slice-prototype` (merge
  commits). `vertical-slice-prototype` → `main` is PR #1, merged at M10.
- Never rewrite history on a shared branch; bring the base in with a merge commit.
- Keep model names out of commits, PR text and code.
