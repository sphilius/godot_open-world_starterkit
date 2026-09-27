#!/usr/bin/env python3
"""Swaps sourced audio in for the placeholders (M10). Needs ffmpeg and ffprobe on PATH.

Drop the raw files in assets/incoming/audio/, one folder per sound bank event or music cue:

    assets/incoming/audio/
      CREDITS.csv                 file,title,author,source_url,license   (one row per raw file)
      hit/  parry/  step_gravel/  …    any number of takes: wav, ogg, mp3, flac, aif(f)
      music/combat.ogg  music/boss.wav  music/victory.wav  music/ambience.ogg

Then run:

    python3 tools/audio/ingest_audio.py          # --dry-run lists what it would do

For each event folder it trims the leading silence, peak-normalises every take to -3 dBFS and
writes 16-bit 44.1 kHz WAVs to assets/audio/sfx/<event>_<n>.wav (mono for positional sounds,
stereo kept for the ui_* events). Music and ambience are loudness-normalised (-18 LUFS, -1.5
dBTP) to Ogg Vorbis in assets/audio/music/<cue>.ogg. It then rebuilds
resources/audio/sound_bank.tres (events without sourced takes keep their placeholders, and every
event keeps its pitch variation), points MusicDirector's cues in scenes/main.tscn at the new
music, and appends a line to assets/LICENSES.md for every processed file and every raw source
(the raw drops stay in assets/incoming/, which the export presets leave out of builds).

Every raw file needs a CREDITS.csv row with a licence that allows use in a public repository
and a commercial game: CC0, CC-BY or OGA-BY. Anything else (NC, ND, SA, GPL, "royalty-free"
store licences that forbid redistribution) stops the run before anything is written.
Afterwards: bash tools/ci/validate.sh (it re-imports), listen in game, commit.
"""

from __future__ import annotations

import argparse
import csv
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INCOMING = ROOT / "assets" / "incoming" / "audio"
SFX_OUT = ROOT / "assets" / "audio" / "sfx"
MUSIC_OUT = ROOT / "assets" / "audio" / "music"
BANK = ROOT / "resources" / "audio" / "sound_bank.tres"
MAIN = ROOT / "scenes" / "main.tscn"
LICENSES = ROOT / "assets" / "LICENSES.md"

EVENTS = [
    "block", "gate", "glint_gold", "glint_red", "hit", "hit_heavy", "parry", "posture_break",
    "roar", "shrine_ignite", "step_grass", "step_gravel", "step_stone", "step_wood", "ui_back",
    "ui_confirm", "whoosh_heavy", "whoosh_light",
]
# Music cue → MusicDirector's ext_resource id in main.tscn.
CUES = {"ambience": "44_wind", "combat": "45_combat", "boss": "46_boss", "victory": "47_victory"}
AUDIO = {".wav", ".ogg", ".mp3", ".flac", ".aif", ".aiff"}
ALLOWED = re.compile(r"^(CC0|CC[- ]BY( \d\.\d)?|OGA[- ]BY( \d\.\d)?)$", re.IGNORECASE)


def run(args: list[str]) -> str:
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"ffmpeg failed on {args[-1]}:\n{result.stderr[-800:]}")
    return result.stderr


def peak_db(path: Path) -> float:
    out = run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af", "volumedetect", "-f", "null", "-"])
    match = re.search(r"max_volume: (-?[\d.]+) dB", out)
    return float(match.group(1)) if match else 0.0


def convert_sfx(source: Path, target: Path, stereo: bool) -> None:
    trimmed = target.with_suffix(".tmp.wav")
    run(["ffmpeg", "-hide_banner", "-y", "-i", str(source), "-af",
         "silenceremove=start_periods=1:start_threshold=-50dB",
         "-ac", "2" if stereo else "1", "-ar", "44100", "-sample_fmt", "s16", str(trimmed)])
    gain = -3.0 - peak_db(trimmed)
    run(["ffmpeg", "-hide_banner", "-y", "-i", str(trimmed), "-af", f"volume={gain:.2f}dB",
         "-sample_fmt", "s16", str(target)])
    trimmed.unlink()


def convert_music(source: Path, target: Path) -> None:
    run(["ffmpeg", "-hide_banner", "-y", "-i", str(source), "-af", "loudnorm=I=-18:TP=-1.5:LRA=11",
         "-ar", "44100", "-c:a", "libvorbis", "-q:a", "5", str(target)])


def read_credits() -> dict[str, dict]:
    path = INCOMING / "CREDITS.csv"
    if not path.exists():
        sys.exit(f"Missing {path.relative_to(ROOT)} (columns: file,title,author,source_url,license).")
    with path.open(newline="", encoding="utf-8") as handle:
        return {row["file"].strip().replace("\\", "/"): row for row in csv.DictReader(handle)}


def existing_bank() -> tuple[dict[str, list[str]], dict[str, str]]:
    """Placeholder paths and random_pitch per event, read from the current bank."""
    text = BANK.read_text(encoding="utf-8")
    paths = dict(re.findall(r'path="(res://[^"]+)" id="([^"]+)"', text))
    ids_to_path = {v: k for k, v in paths.items()}
    files: dict[str, list[str]] = {}
    pitch: dict[str, str] = {}
    for event, body in re.findall(r'id="AudioStreamRandomizer_(\w+)"\]\n(.*?)(?=\n\[|\Z)', text, re.S):
        pitch[event] = (re.search(r"random_pitch = ([\d.]+)", body) or ["", "1.0"])[1]
        files[event] = [ids_to_path[i] for i in re.findall(r'stream_\d+/stream = ExtResource\("([^"]+)"\)', body)]
    return files, pitch


def write_bank(files: dict[str, list[str]], pitch: dict[str, str]) -> None:
    lines = ['[gd_resource type="Resource" script_class="SoundBank" format=3]', "",
             '[ext_resource type="Script" path="res://scripts/audio/sound_bank.gd" id="0_bank"]']
    ids: dict[str, str] = {}
    for event in EVENTS:
        for path in files[event]:
            ids[path] = f"{len(ids) + 1}_{Path(path).stem}"
            lines.append(f'[ext_resource type="AudioStream" path="{path}" id="{ids[path]}"]')
    for event in EVENTS:
        takes = files[event]
        lines += ["", f'[sub_resource type="AudioStreamRandomizer" id="AudioStreamRandomizer_{event}"]',
                  f"random_pitch = {pitch.get(event, '1.0')}"]
        if len(takes) == 1:
            lines.append("playback_mode = 1")
        lines.append(f"streams_count = {len(takes)}")
        for i, path in enumerate(takes):
            lines += [f'stream_{i}/stream = ExtResource("{ids[path]}")', f"stream_{i}/weight = 1.0"]
    lines += ["", "[resource]", 'script = ExtResource("0_bank")', "sounds = Dictionary[StringName, AudioStream]({"]
    lines.append(",\n".join(f'&"{event}": SubResource("AudioStreamRandomizer_{event}")' for event in EVENTS))
    lines += ["})", ""]
    BANK.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if not shutil.which("ffmpeg"):
        sys.exit("ffmpeg isn't on PATH (bash tools/setup/gamedev_env.sh installs it).")
    credits = read_credits()

    jobs: list[tuple[Path, Path, str]] = []            # (source, target, kind)
    for folder in sorted(p for p in INCOMING.iterdir() if p.is_dir()):
        sources = sorted(p for p in folder.iterdir() if p.suffix.lower() in AUDIO)
        if folder.name == "music":
            for source in sources:
                if source.stem not in CUES:
                    sys.exit(f"music/{source.name}: name it after a cue ({', '.join(CUES)}).")
                jobs.append((source, MUSIC_OUT / f"{source.stem}.ogg", "music"))
        elif folder.name in EVENTS:
            for n, source in enumerate(sources, 1):
                jobs.append((source, SFX_OUT / f"{folder.name}_{n}.wav", folder.name))
        else:
            sys.exit(f"{folder.name}/ isn't a sound bank event or music/ (events: {', '.join(EVENTS)}).")
    if not jobs:
        print("Nothing to ingest.")
        return 0

    problems = []
    for source, _, _ in jobs:
        key = source.relative_to(INCOMING).as_posix()
        row = credits.get(key)
        if row is None:
            problems.append(f"{key}: no CREDITS.csv row")
        elif not ALLOWED.match(row["license"].strip()):
            problems.append(f"{key}: licence '{row['license']}' isn't CC0, CC-BY or OGA-BY")
    if problems:
        sys.exit("Fix these first (nothing was written):\n  " + "\n  ".join(problems))

    for source, target, kind in jobs:
        print(f"{source.relative_to(INCOMING)} → {target.relative_to(ROOT)}")
    if args.dry_run:
        return 0

    SFX_OUT.mkdir(parents=True, exist_ok=True)
    MUSIC_OUT.mkdir(parents=True, exist_ok=True)
    files, pitch = existing_bank()
    sourced: dict[str, list[str]] = {}
    main_scene = MAIN.read_text(encoding="utf-8")
    for source, target, kind in jobs:
        if kind == "music":
            convert_music(source, target)
            main_scene = re.sub(rf'path="[^"]+" id="{CUES[source.stem]}"',
                                f'path="res://{target.relative_to(ROOT).as_posix()}" id="{CUES[source.stem]}"', main_scene)
        else:
            convert_sfx(source, target, stereo=kind.startswith("ui_"))
            sourced.setdefault(kind, []).append(f"res://{target.relative_to(ROOT).as_posix()}")
    files.update(sourced)
    write_bank(files, pitch)
    MAIN.write_text(main_scene, encoding="utf-8")

    # Both the processed file and its raw source (which stays in assets/incoming/) get a line.
    listed = LICENSES.read_text(encoding="utf-8")
    with LICENSES.open("a", encoding="utf-8") as handle:
        for source, target, _ in jobs:
            row = credits[source.relative_to(INCOMING).as_posix()]
            credit = "—" if row["license"].strip().upper() == "CC0" else f"{row['title']} by {row['author']}"
            for path, what in ((target, row["title"]), (source, f"{row['title']} (raw source of `{target.relative_to(ROOT).as_posix()}`)")):
                key = f"`{path.relative_to(ROOT).as_posix()}`"
                if key in listed:
                    continue                             # a re-run replaces the file, not its line
                handle.write(f"| {key} | {what} | [{row['author']}]({row['source_url']}) | "
                             f"{row['license'].strip()} | {credit} |\n")
    print(f"\n{len(jobs)} files ingested; {BANK.relative_to(ROOT)}, {MAIN.relative_to(ROOT)} and "
          f"{LICENSES.relative_to(ROOT)} updated. Next: bash tools/ci/validate.sh")
    return 0


if __name__ == "__main__":
    sys.exit(main())
