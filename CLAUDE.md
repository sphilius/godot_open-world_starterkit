@AGENTS.md

## Claude Code specifics

- Cloud sessions: `.claude/hooks/session-start.sh` installs Godot and builds the import cache.
  For Blender and the rest, put `bash tools/setup/gamedev_env.sh` in the environment's setup
  script (see `docs/DEV_ENVIRONMENT.md`).
- Local sessions on Windows with Blender MCP handle the interactive M2 art work
  (`docs/vertical-slice/PROMPTS.md` §2A–2C); cloud sessions handle headless Blender scripting,
  import, retargeting and everything in Godot.
