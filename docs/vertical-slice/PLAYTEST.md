# Playtest protocol (M10)

The goal is **3 first-time players** through the whole slice. Their logs and your notes are
checked against the acceptance criteria in `PLAN.md` §6.2:

- A first-time player finishes in **8–12 minutes** (median of 3), with **fewer than 5 deaths**.
- The frame rate holds the D5 target (60 FPS on a discrete GPU, 30 on the Intel UHD laptop),
  with **no hitch over 50 ms**.
- Death, respawn and encounter reset work in every beat, with **no soft-lock after 3 deliberate
  deaths per beat** (you test this one yourself, not the playtesters).

## 1. Get a build (5 min)

- **From CI:** open GitHub ▸ Actions ▸ *Export desktop builds*, pick the latest green run on
  `vertical-slice-prototype`, and download `VerticalSlice-windows-x86_64` (or the Linux one).
- **Locally:** `godot --headless --path . --export-release "Windows Desktop" build/windows/VerticalSlice.exe`
  (the export templates must be installed).
- The executable isn't code-signed, so Windows SmartScreen warns on first launch: **More info ▸
  Run anyway**. On Linux, `chmod +x VerticalSlice.x86_64` after unzipping.

## 2. Before each session (2 min)

1. Start from a clean log. Rename or delete the old file:
   - Windows: `%APPDATA%\Godot\app_userdata\Scenic Open World\playtest.csv`
   - Linux: `~/.local/share/godot/app_userdata/Scenic Open World/playtest.csv`
2. Note the machine (CPU, GPU, screen resolution) and the input (keyboard and mouse, gamepad or
   touch). Leave the quality on its automatic preset unless you're testing a specific one.
3. Start a screen recording: OBS, or **Win+Alt+R** (Xbox Game Bar) on Windows.

## 3. During the session (10–15 min)

- Don't coach. Only answer "how do I…" questions after the player has been stuck for 30
  seconds, and write down that they asked.
- For each beat, jot down: where they hesitated, what they didn't understand (guard, parry,
  lock-on, heavy branch, gold vs red glint), and what killed them.
- The game logs time, deaths, parries, attempts and frame hitches per beat. Your notes cover
  the *why*.

| Beat | Watch for |
|---|---|
| Approach | Do they find guard and parry without being told? Do they rest at the shrine? |
| Courtyard | Do they lock on? Do they read gold (parry) vs red (dodge) glints? Is the third wave a wall? |
| Breather | Do they notice the gate opened, and rest at the second shrine? |
| Sanctum | Do they execute the Gatekeeper on its posture break? How long is phase 2? |

## 4. After the session (5 min)

1. Copy their `playtest.csv` and rename it after the player (for example `alice.csv`).
2. Ask five questions and write the answers down:
   1. What was the most satisfying moment?
   2. When did you feel it was unfair?
   3. Did you understand what the gold and red flashes meant?
   4. Was anything too long, or too short?
   5. Would you play another 10 minutes of this?
3. Put the CSVs, notes and recordings in one folder (don't commit the recordings).

## 5. Summarise (5 min)

```
python3 tools/playtest/summarize.py alice.csv bob.csv carol.csv --min-fps 30
```

It prints every run, the median seconds per beat against the §6.1 beat sheet, and PASS/FAIL
for each §6.2 criterion. Only runs that reached the victory screen count, unless you add `--all`.

Then hand the CSVs and your notes to a cloud session with the M10 prompt (`PROMPTS.md`): it
proposes `AttackData` and director tuning diffs for the beats that miss their targets.

## Where to look when a beat misses its target

| Symptom | Knobs (see the README's tuning cheatsheet) |
|---|---|
| Approach runs long | Wolf count and `wolf.tscn` DetectionArea radius; `--spawn-offset` shows how long the walk alone takes |
| Courtyard runs long, few deaths | Fewer enemies per wave (`resources/encounters/*.tres`), `wave_delay`, enemy `max_health` |
| Courtyard deaths pile up | Director `max_attack_tokens` and `token_cooldown`; enemy `attack_cooldown` and `telegraph_lead` |
| Players never parry | ParrySystem `parry_window`; the glint lead (`telegraph_lead`); a context prompt at the first shrine |
| Gatekeeper phase 2 is a wall | `scenes/mobs/enemy_gatekeeper.tscn`: `phase_two_ratio`, `phase_two_combos` (fewer red strikes), its PostureComponent recovery |
| Hitches | The worst beat in the log; set the DevHUD quality lower and re-test, then look at what spawns there |
