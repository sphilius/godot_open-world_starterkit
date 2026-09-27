# Free audio sourcing list (M10)

Every pick below is **free** and licensed **CC0** (no credit needed) or **CC-BY** (credit
needed). The first picks were checked on their source pages in September 2026; the alternates
come from OpenGameArt and Kenney listings. Licences can change, so confirm the licence on the
page when you download, and write it into `CREDITS.csv`.

Why only CC0 and CC-BY: this repository is public, so the raw files get redistributed with it.
- **Sonniss GDC bundles and Pixabay:** their licences allow the sounds in a game but not
  redistribution of the files themselves, so keep them out of this repo.
- **NC (non-commercial) and ND (no derivatives) licences:** don't fit a game either.
- **GPL:** don't fit a game. Also watch out for remixes (see "Determined Pursuit" below).

The ingest script (`tools/audio/ingest_audio.py`) rejects anything that isn't CC0, CC-BY or
OGA-BY.

## Sound bank events (`resources/audio/sound_bank.tres`)

Take 3–5 variants of anything that repeats (steps, swings, hits); the bank randomises the take
and the pitch. The table gives a first pick and an alternate: audition both.

| Event | When it plays | First pick | Alternate |
|---|---|---|---|
| `whoosh_light` | Light swings | [Swishes Sound Pack](https://opengameart.org/content/swishes-sound-pack), artisticdude, **CC0**: the 4 lighter swishes | [RPG Sound Pack](https://opengameart.org/content/rpg-sound-pack), artisticdude, CC0: 3 weapon swooshes |
| `whoosh_heavy` | Heavy swings | Swishes Sound Pack: 3–4 of the 9 heavier swishes | [3 Melee sounds](https://opengameart.org/content/3-melee-sounds), CC0 |
| `hit` | A blade landing | [20 Sword Sound Effects](https://opengameart.org/content/20-sword-sound-effects-attacks-and-clashes), StarNinjas, **CC0**: 3–4 of the sword *attacks* | [Impact Sounds](https://kenney.nl/assets/impact-sounds), Kenney, CC0: `impactPunch_medium_00*` (body thud) |
| `hit_heavy` | Kills, heavy strikes, posture breaks | Kenney Impact Sounds: `impactPunch_heavy_00*` | 20 Sword Sound Effects: a sword attack pitched down in Audacity, layered on a punch |
| `block` | Guarded hits | 20 Sword Sound Effects: 3 of the 10 sword *clashes* (the duller ones) | Kenney Impact Sounds: `impactMetal_medium_00*` |
| `parry` | A successful parry | Kenney Impact Sounds: `impactMetal_heavy_00*` (it should ring) | 20 Sword Sound Effects: the brightest clashes |
| `posture_break` | Guard or posture broken | Kenney Impact Sounds: `impactPlate_heavy_00*` | Kenney `impactGlass_heavy_00*` for a shatter |
| `step_grass` | Footsteps off the path | Kenney Impact Sounds: `footstep_grass_000`–`004` | [Fantozzi's Footsteps](https://opengameart.org/content/fantozzis-footsteps-grasssand-stone), CC0 |
| `step_gravel` | Footsteps on the path | [Different steps on wood, stone, leaves, gravel and mud](https://opengameart.org/content/different-steps-on-wood-stone-leaves-gravel-and-mud), TinyWorlds, **CC0**: the gravel takes | [100 CC0 SFX #2](https://opengameart.org/content/100-cc0-sfx-2), rubberduck, CC0: footsteps |
| `step_stone` | Courtyard and sanctum floors | Kenney Impact Sounds: `footstep_concrete_000`–`004` | TinyWorlds pack: stone |
| `step_wood` | Wooden surfaces | Kenney Impact Sounds: `footstep_wood_000`–`004` | TinyWorlds pack: wood |
| `glint_gold` | The parryable-attack warning | Kenney Impact Sounds: one `impactBell_heavy_00*` (a clear ting) | Kenney `impactGlass_light_00*` |
| `glint_red` | The unblockable-attack warning | RPG Sound Pack: a *sword unsheathe* (a harsh scrape) | 20 Sword Sound Effects: a clash, pitched down in Audacity |
| `shrine_ignite` | Lighting a shrine | [Fire Crackling](https://opengameart.org/content/fire-crackling), AntumDeluge, **CC0**: the first 1–2 s | Swishes Sound Pack: a heavy swish, layered under the crackle |
| `gate` | Portcullis gates moving | [100 CC0 metal and wood SFX](https://opengameart.org/content/100-cc0-metal-and-wood-sfx), rubberduck, **CC0**: metal door opening | 100 CC0 SFX #2: doors or stones |
| `roar` | The Gatekeeper's phase-2 roar | [CC0 Deep Monster Roar](https://opengameart.org/content/cc0-deep-monster-roar), trazzz123, **CC0** | [80 CC0 creature SFX](https://opengameart.org/content/80-cc0-creature-sfx), rubberduck, CC0: 3 roars |
| `ui_confirm` | Menu buttons, pause | [Interface Sounds](https://kenney.nl/assets/interface-sounds), Kenney, **CC0**: a soft confirm | [UI Audio](https://kenney.nl/assets/ui-audio), Kenney, CC0 |
| `ui_back` | Closing the pause menu | Kenney Interface Sounds: a matching back or close sound | Kenney UI Audio |

## Music and ambience (MusicDirector cues in `scenes/main.tscn`)

| Cue | When it plays | First pick | Alternate |
|---|---|---|---|
| `ambience` | Always (valley wind) | [Wind Ambience (Looping)](https://freesound.org/people/jackyyang09/sounds/476849/), jackyyang09, **CC-BY 4.0** (credit: "Wind Ambience (Looping)" by jackyyang09), 52 s loop | [Wind Loop](https://freesound.org/people/Jakegwizdak/sounds/565491/), Jakegwizdak, CC0 (only 4.75 s, so the loop is easier to hear) |
| `combat` | Courtyard ambush | [Determined Pursuit (epic orchestra loop)](https://opengameart.org/content/determined-pursuit-epic-orchestra-loop), Emma_MA, **CC0**, loopable | [Orchestral Battle Music](https://opengameart.org/content/orchestral-battle-music-0), Lisboa, CC-BY 3.0 (credit the composer) |
| `boss` | Sanctum Gatekeeper | [Boss Battle Music](https://opengameart.org/content/boss-battle-music), SubspaceAudio, **CC0**, seamless loop | [Fantasy Music and Drum Loops Pack](https://opengameart.org/content/fantasy-music-and-drum-loops-pack), North Fantasy Music, CC-BY 4.0 (dark drum loops) |
| `victory` | Victory screen (plays once) | [Victory Fanfare Short](https://opengameart.org/content/victory-fanfare-short), cynicmusic, **CC0** | [Victory Theme for RPG](https://opengameart.org/content/victory-theme-for-rpg), cynicmusic, CC0 |

**Licence trap:** don't download the "[Determined Pursuit (Emma Ma & Zezf)](https://opengameart.org/content/determined-pursuit-emma-ma-zezf)"
remix. It mixes in a GPL track, so the result is GPL 3.0. Use Emma_MA's original loop
(`determined_pursuit_loop.wav`), which is CC0.

**Optional, and it needs a small code change:** [Forgoten tomb ambience](https://opengameart.org/content/forgoten-tomb-ambience),
kindland, CC0, as a night ambience in the sanctum. MusicDirector has one ambience slot today;
a cloud session can add a per-beat ambience in about 15 minutes. The valley has no exploration
music by design, only wind.

## Getting the files in (about 45 minutes)

1. **Download** (about 25 minutes). OpenGameArt and Kenney downloads need no account;
   Freesound needs a free account. Where a page offers OGG or FLAC as well as WAV, take the
   smaller file (the combat loop is 19 MB as WAV).
2. **Sort** into one folder per event or cue, named exactly as in the tables:
   ```
   assets/incoming/audio/
     CREDITS.csv
     whoosh_light/  whoosh_heavy/  hit/  hit_heavy/  block/  parry/  posture_break/
     step_grass/  step_gravel/  step_stone/  step_wood/  glint_gold/  glint_red/
     shrine_ignite/  gate/  roar/  ui_confirm/  ui_back/
     music/ambience.ogg  music/combat.wav  music/boss.wav  music/victory.wav
   ```
   Leave out any event you don't have yet: it keeps its placeholder.
3. **Credit** every file in `CREDITS.csv`, one row each:
   ```
   file,title,author,source_url,license
   hit/sword_attack_3.wav,20 Sword Sound Effects,StarNinjas,https://opengameart.org/content/20-sword-sound-effects-attacks-and-clashes,CC0
   music/ambience.wav,Wind Ambience (Looping),jackyyang09,https://freesound.org/people/jackyyang09/sounds/476849/,CC-BY 4.0
   ```
4. **Ingest** (about 5 minutes). Either:
   - Push the folder on a branch and ask a cloud session to "run the audio ingest and open a PR".
   - Or run it yourself: `python3 tools/audio/ingest_audio.py`, then `bash tools/ci/validate.sh`.
     On Windows, install ffmpeg first with `winget install Gyan.FFmpeg`.

   The script trims and normalises every take, rebuilds the sound bank, rewires the music cues,
   and adds each file to `assets/LICENSES.md`.
5. **Listen** in game (about 10 minutes): swing, block, parry, walk on the path and the grass, and
   light a shrine. Adjust the volume per event with `volume_db` on the SfxPool call sites, or
   swap takes and re-run the ingest.
6. **CC-BY credit** is covered by the credit column the ingest writes into `assets/LICENSES.md`.
   The README's Credits section points to that file, and the desktop builds ship both files
   next to the executable.
