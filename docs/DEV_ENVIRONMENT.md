# Game-Dev Environment: Claude Code, Codex, Jules and Local

How to get a working environment for this repo (and any Godot + Blender game repo) in every
place an agent might run. It's one script, `tools/setup/gamedev_env.sh`, used everywhere, plus
`AGENTS.md` for the rules every agent follows.

## 1. The stack

| Tool | Version | Used for | Where it runs |
|---|---|---|---|
| Godot | 4.7.1 (`GODOT_VERSION`) | Engine, headless tests (`tools/ci/validate.sh`), import, rig generation, exports | Cloud and local |
| Blender | 4.5 LTS (`BLENDER_VERSION`, 4.5.14) | M2: modelling, cleanup, retargeting, GLB export. Headless (`--background --python`) in the cloud; interactive plus Blender MCP locally | Cloud (scripts) and local (interactive) |
| Xvfb + Mesa | distro | Software OpenGL: game screenshots (`--capture`), Blender renders, lookdev without a GPU | Cloud |
| ffmpeg | distro | M9b audio: convert and trim to `.ogg` (loops, music) and `.wav` (SFX); video captures | Cloud and local |
| Python 3 | distro | Tooling, procedural placeholder audio, asset batch scripts | Cloud and local |
| Godot export templates | 4.7.1 (optional) | M10 web and desktop exports (`WITH_EXPORT_TEMPLATES=1`, ~1 GB) | Cloud or local |
| GitHub Actions | — | `validate.yml` (PRs into `vertical-slice-prototype`), `deploy-web.yml` (PRs into `main`, web deploy) | GitHub |

Still ahead, and where it needs to happen:

| Work | Needs | Best place |
|---|---|---|
| M2 characters (AI-generated or pack) and Mixamo rigging | Browser logins (Mixamo, the 3D generator), Blender GUI | **Local Windows PC** |
| M2 blade, scabbard, courtyard kit, shrine via Blender MCP (PROMPTS §2A–2C) | Blender GUI + Blender MCP | **Local Windows PC** |
| M2 import, `BoneMap` retarget, clip renames, retiming, sockets, swapping placeholders | Godot + Blender headless | Cloud or local |
| M9b audio (sourcing), music | Freesound / ElevenLabs / Lyria accounts or purchased packs | Local (download), then cloud (conversion, wiring) |
| M10 playtest and tuning | A real GPU, gamepad, tablet | Local |

## 2. Claude Code on the web (this cloud environment)

Every new cloud session starts from a fresh container. `.claude/hooks/session-start.sh` runs
on start:

- **Default:** installs Godot and builds the import cache (~15 s). Tests work immediately.
- **With `GAMEDEV_FULL=1`:** runs `tools/setup/gamedev_env.sh` (Godot, Blender, Xvfb, Mesa,
  ffmpeg; about a minute longer).

To set it up once:
1. Open the cloud environment menu in the session's title bar and choose **Edit**.
2. **Environment variables:** add `GAMEDEV_FULL=1` (only when a session needs Blender or
   screenshots; leave it off for code-only milestones to start faster).
3. **Network access:** the downloads need `github.com` and its release-asset hosts (Godot),
   `download.blender.org` (Blender) and the Ubuntu mirrors (apt). If the environment's network
   policy is limited, add these hosts or use full access.
4. Optional **setup script** (runs before Claude starts, for every repo in the environment):
   `bash tools/setup/gamedev_env.sh` when the working directory is the repo. The hook above does
   the same from inside the repo, so either works.

Check it with the "Verify" prompt in §6.

## 3. Local Windows PC (Blender MCP, M2 art, playtests)

The cloud can't reach your PC, so interactive Blender work runs in a local Claude Code session.
Start it with the Claude desktop app, or with `claude` (or `claude remote-control`, so it shows
up in the Claude app on your phone) in a terminal in the repo folder.

One-time setup:
1. Install **Git for Windows** (it provides Git Bash for the `.sh` tools), **Godot 4.7.1**
   (standard, not .NET) plus its export templates, **Blender 4.5 LTS**, **uv**
   (`winget install astral-sh.uv`) and **Claude Code**.
2. `git clone https://github.com/sphilius/godot_open-world_starterkit` and check out
   `vertical-slice-prototype` (or the milestone branch).
3. **Blender MCP**: install the Blender add-on from the blender-mcp project
   (`addon.py` → Blender ▸ Edit ▸ Preferences ▸ Add-ons ▸ Install), enable it, and click
   **Connect** in the 3D view's sidebar (N ▸ BlenderMCP). Register the server with Claude Code:
   `claude mcp add blender -- uvx blender-mcp`. Check the project's README for current steps;
   its Hyper3D Rodin and Poly Haven toggles live in the same sidebar panel.
4. Optional: a Godot MCP server, so Claude can run the editor and read its errors; and Context7
   for current Godot docs (`claude mcp add context7 ...` per its README).
5. Tests on Windows: `"C:\path\to\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --script res://tests/run_tests.gd`,
   or `bash tools/ci/validate.sh` from Git Bash with `GODOT` pointing at the console exe.

Hand-off between local and cloud is just git: commit the raw drops to `assets/incoming/` (with
`assets/LICENSES.md` lines) on a branch, push, and a cloud session picks them up.

## 4. Codex (cloud) and Jules

Both read `AGENTS.md` automatically and run a setup script in an Ubuntu container before the
agent starts.

**Codex:** in the Codex environment settings for this repo:
- Setup script: `bash tools/setup/gamedev_env.sh` (add `SKIP_BLENDER=1 ` in front for code-only
  tasks).
- Agent internet access can stay off: the setup script runs with network access and caches
  Godot and Blender before the agent starts.

**Jules:** in the repo's configuration:
- Initial setup: `bash tools/setup/gamedev_env.sh`
- Run it and save the snapshot, so later tasks start with Godot and Blender already installed.

Labels in both UIs change often; the pieces to look for are "setup script" and "environment
variables".

## 5. Reusing this for another game repo

Copy `tools/ci/install_godot.sh`, `tools/setup/`, `.claude/hooks/session-start.sh` (plus the
`SessionStart` entry in `.claude/settings.json`), `.devcontainer/`, `AGENTS.md` and `CLAUDE.md`,
then edit `AGENTS.md`'s project section. Set `GODOT_VERSION` / `BLENDER_VERSION` to pin other
versions. The same setup works in VS Code Dev Containers and GitHub Codespaces through
`.devcontainer/devcontainer.json`. Or use the bootstrap prompt below.

## 6. Prompts

### Verify the environment (any agent, first message of a session)
```text
Read AGENTS.md. Run `bash tools/setup/gamedev_env.sh` if $GODOT isn't set, then:
1. `bash tools/ci/validate.sh` and report the pass/fail count.
2. `"$BLENDER" --background --factory-startup --python-expr "import bpy; print(bpy.app.version_string)"`.
3. Capture one frame of the game with xvfb-run (the command in AGENTS.md) and show it to me.
Report anything missing and the exact command that failed.
```

### Bootstrap a new Godot + Blender repo
```text
Set this repository up for agent-driven game development, modelled on
sphilius/godot_open-world_starterkit:
- tools/ci/install_godot.sh (cached official Linux binary, GODOT_VERSION),
  tools/setup/install_blender.sh (cached Blender LTS, BLENDER_VERSION) and
  tools/setup/gamedev_env.sh (apt: Xvfb, Mesa, ffmpeg; Godot; Blender; import cache;
  writes ~/.gamedev_env; idempotent; SKIP_APT / SKIP_BLENDER / WITH_EXPORT_TEMPLATES).
- .claude/settings.json + .claude/hooks/session-start.sh (Godot by default, the full script with
  GAMEDEV_FULL=1), .devcontainer/devcontainer.json running the setup script.
- tests/run_tests.gd: a SceneTree test runner with a parse gate that loads every script and scene,
  and tools/ci/validate.sh; .github/workflows/validate.yml running it on PRs.
- AGENTS.md (project summary, validate command, conventions, git workflow) and a CLAUDE.md that
  imports it.
Run the setup script and the tests before you push, and open a PR.
```

### M2 art session (local Windows, Blender MCP)
```text
Read AGENTS.md, docs/vertical-slice/PLAN.md §4 (bill of materials) and PROMPTS.md §2A–2C.
Blender MCP is connected. Build <asset> to the spec there (scale 1 unit = 1 m, pivot at the
base or grip, facing -Y in Blender, named sockets as empties, transforms applied), export it as GLB to
assets/incoming/<category>/, add its line to assets/LICENSES.md, commit on branch vs/m2-art and
push. Don't touch scenes; the cloud session wires assets in.
```

### Asset wiring session (cloud, after an art drop)
```text
Read AGENTS.md and the new files under assets/incoming/. With GAMEDEV_FULL=1 active, use
headless Blender for any cleanup (apply transforms, rename bones to the BoneMap, decimate), import
into Godot with the retarget presets, rename clips to the manifest's clip names, add sockets,
replace the placeholder in <scene>, and keep every test green. Capture before/after screenshots
with xvfb-run and put them in the PR.
```

### Codex or Jules task (one component per task, D14)
```text
Read AGENTS.md and docs/vertical-slice/HANDOFF_MANIFEST.md. Implement <component> from
docs/vertical-slice/PROMPTS.md §<n> without changing any manifest signature. Add tests in
tests/test_<topic>.gd, run `bash tools/ci/validate.sh` until it reports 0 failed, and open a PR
into vertical-slice-prototype.
```
