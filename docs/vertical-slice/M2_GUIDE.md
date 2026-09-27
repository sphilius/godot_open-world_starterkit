# M2 art: step-by-step on your Windows PC

M2 replaces the placeholder rigs and greybox with real art: the four characters and their
animations, the sword, scabbard and maul, the courtyard kit, the shrine and the sanctum gate.
You do the parts that need a GUI or a browser login on your PC. A cloud session then does the
Godot side: retargeting, clip renaming, sockets and swapping the scenes.

| Part | Where | You | AI time | Human-only equivalent |
|---|---|---|---|---|
| 1. One-time setup | PC | ✋ | — | 45–60 min |
| 2. Pick the route | PC | ✋ | — | 10 min |
| 3. Characters | PC + Blender MCP | ✋ + Claude | 1–2 h | 1–2 wk |
| 4. Animations | PC (download) → cloud (retarget) | ✋ + Claude | 1–2 h | 1–2 wk |
| 5. Weapons, courtyard kit, shrine, gate | PC + Blender MCP | Claude, you review | 2–3 h | 2–3 wk |
| 6. Check, license, push | PC | ✋ | — | 20 min |
| 7. Wire into Godot (PROMPTS §2B) | Cloud | Claude | 2–4 h | 1 wk |

"AI time" means Claude driving Blender while you review; the human column is a solo artist
doing the same without AI help.

---

## 1. One-time setup (45–60 min)

1. **Install** (winget from PowerShell for the first three):
   ```powershell
   winget install Git.Git
   winget install astral-sh.uv
   winget install Gyan.FFmpeg
   ```
   - **Blender 4.5 LTS:** from blender.org ▸ Download ▸ LTS. Match the cloud's 4.5, not the
     newest release.
   - **Godot 4.7.1:** the *standard* build (not .NET) from godotengine.org. Keep the
     `_console.exe` next to it; the tests use it.
   - **Claude Code:** the Claude desktop app's Code tab, or the CLI installer from
     claude.com/claude-code.
2. **Put uv on PATH:** open a new PowerShell and check `where uvx`. If nothing prints, run:
   ```powershell
   $localBin = "$env:USERPROFILE\.local\bin"
   [Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "User") + ";$localBin", "User")
   ```
3. **Clone and branch:**
   ```powershell
   git clone https://github.com/sphilius/godot_open-world_starterkit
   cd godot_open-world_starterkit
   git checkout vertical-slice-prototype
   git pull
   git checkout -b vs/m2-art
   ```
4. **Blender MCP** (the project is now called *MCP for Blender*):
   ```powershell
   uvx mcp-for-blender install-addon
   claude mcp add blender uvx mcp-for-blender
   ```
   - In Blender, go to Edit ▸ Preferences ▸ Add-ons and enable **Interface: MCP for Blender**.
   - In the 3D view press **N**, open the **MCP for Blender** tab and click **Connect to
     Claude**.
   - If Claude Code or the desktop app can't find `uvx`, register the server as
     `cmd /c uvx mcp-for-blender` instead.
5. **Smoke test:** in the repo folder, run `claude` and ask *"Using Blender MCP, list the
   objects in the open scene."* It should name the default Cube, Camera and Light.
6. **Optional:** tick **Poly Haven** in the MCP for Blender panel. It gives free CC0 textures,
   HDRIs and models with no account, and step 5 uses it for stone and wood.

## 2. Pick the character and animation route (10 min)

Your approved D3 route is "AI 3D generation plus free Mixamo, Quaternius and Kenney assets".
Within that, the **free** options rank like this:

| Route | What | Licence | Verdict |
|---|---|---|---|
| **A: Quaternius first** ⭐ | [Universal Base Characters](https://quaternius.com/packs/universalbasecharacters.html) (6 bodies, about 13k tris) + [Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html) + [Universal Animation Library 2](https://quaternius.com/packs/universalanimationlibrary2.html) (sword and melee combos split into single hits with recoveries). All on one humanoid rig | **CC0**; the free tier is about 60–70% of each pack | **Recommended.** Same rig for everything, so no rig-to-rig retarget, and CC0 files can live in this public repo |
| B: AI mesh + Mixamo | Meshy (free tier) or Hyper3D or Hunyuan3D for the mesh, then Mixamo auto-rig and Mixamo sword clips | Meshy free outputs are **CC BY 4.0** (credit Meshy); Mixamo is free for games but **can't be redistributed as standalone files** | Use it for a look Quaternius can't give. The raw Mixamo FBX files shouldn't go in the public repo (see below) |
| C: Hybrid | Route A bodies with armour, hood, pauldrons and belts modelled or kit-bashed through Blender MCP, plus Route B only for clips Route A lacks | Mixed | Best look for the money; more Blender time |

**Mixamo in a public repo:** Adobe's terms let you ship Mixamo animation *inside* a game but not
hand out the raw files. This repo is public, so keep raw Mixamo downloads in a folder git ignores
(`assets/incoming/private/`). Commit only what the game imports, and check that you're
comfortable with that before you push. The fully clean alternatives are to use only Route A's
CC0 clips, or to make the repo private (the free GitHub Pages web build needs a public repo).

**Recommendation:** Route A for all four characters and the whole animation set. Hand-key or
fill from Mixamo only the clips Route A lacks (usually `draw_attack`, `sheathe`, `execution`,
`parry_1/2`).

## 3. Characters (Claude drives Blender; you review)

Targets:

| Character | Height | Tri budget | Look |
|---|---|---|---|
| `player_duelist` | 1.8 m | < 25k | A generic warrior (D15): light armour, cloak, a straight sword at the left hip (D6) |
| `enemy_grunt` | 1.8 m | < 25k | Hooded cultist-soldier; emissive veins (Emission Strength about 2) |
| `enemy_brute` | 2.2 m | < 35k | Heavy, broad, armoured; carries the maul |
| `enemy_gatekeeper` | 2.5 m | < 35k | Boss: tall, ornate armour, a clear silhouette |

1. **Download** the Quaternius packs (free tier, glTF) and unzip them to
   `assets/incoming/characters/quaternius/`. For Route B, download the mesh as GLB or FBX to
   `assets/incoming/characters/<name>/`.
2. **Concept art (optional, 30 min):** run the `nano-banana-prompt-composer` skill for the four
   turnarounds. Save them to `docs/vertical-slice/concept/` as reference only; don't ship them.
3. **Prompt Claude Code** (Blender connected), once per character:
   ```text
   Read AGENTS.md, docs/vertical-slice/PROMPTS.md §2A and docs/vertical-slice/M2_GUIDE.md §3.
   Using Blender MCP, build <player_duelist> from
   assets/incoming/characters/quaternius/<base model>.glb:
   - Keep the Quaternius rig and skin weights. Don't re-rig or rename bones.
   - Scale to <1.8> m tall, feet at z=0, facing -Y, transforms applied.
   - Add <light armour, a hooded cloak, belts and a hip-left scabbard strap> as separate meshes
     parented to the right bones. Use Poly Haven textures (leather, worn metal, cloth), baked
     to 2k if procedural.
   - Principled BSDF only; materials named M_<Char>_<Part>. Stay under <25k> tris.
   - Export glTF 2.0 (+Y up, skinning, no animations) to assets/characters/<player_duelist>.glb.
   - Add its line to assets/LICENSES.md (base model: Quaternius, CC0; everything you modelled:
     this repo, CC0).
   Render a front and a 3/4 view with the viewport camera, and show me before exporting.
   ```
4. **Review each render.** Ask for changes in plain words ("a darker cloak", "the pauldrons are
   too big") before it exports.

## 4. Animations

1. **Download** both Universal Animation Libraries (free tier, glTF) to
   `assets/incoming/animations/quaternius/`. For Route B/C gap-fillers, download from Mixamo:
   FBX, 30 fps, *Without Skin*, and *In Place* for locomotion. Put them in
   `assets/incoming/private/mixamo/`.
2. **Map the clips** (Claude can list them for you):
   ```text
   Using Blender MCP (or by reading the glTF files), list every animation in
   assets/incoming/animations/quaternius/*.glb. Map them to the clip names in
   docs/vertical-slice/HANDOFF_MANIFEST.md ("Animation clip names") for the Duelist, the Grunt,
   and the Brute and Gatekeeper. Write assets/incoming/animations/clip_map.csv
   (character,target_clip,source_file,source_clip,notes) and list the clips with no good
   match.
   ```
   - The sword combo's single hits map to `attack_1`–`attack_3` and `heavy_*`.
   - Rolls map to `dodge_*`. A block hold maps to `guard_idle`, and a block reaction to
     `guard_hit`.
3. **Fill the gaps.** Anything missing (typically `draw_attack`, `draw`, `sheathe`, `parry_1/2`,
   `execution`, `executed`, `roar`) can come from three places:
   - Mixamo, into `assets/incoming/private/mixamo/`, noted in the CSV.
   - A sped-up or trimmed version of a close clip (parry is often a fast `guard_hit`), noted in
     the CSV. The cloud session does the retime.
   - Hand-keyed in Blender with Claude: "Key a 0.45 s hip draw-cut on the Duelist rig, starting
     with the hand on the hip-left grip…"

## 5. Weapons, courtyard kit, shrine and sanctum gate (Claude drives Blender)

Paste PROMPTS.md §2C (the sword is now the straight arming sword from D15) into Claude Code with
Blender connected. Do it one asset at a time, and ask for a render before each export:

1. **Weapons:** `duelist_blade`, `duelist_scabbard` and `brute_maul` go to `assets/weapons/`.
   Each needs the `Blade_Tip` and `Blade_Base` empties on the blade.
2. **Courtyard kit** (4 m grid, each piece with its `_col` collision mesh) goes to
   `assets/environment/modular_courtyard_kit.glb`. Use Poly Haven stone, plaster and wood
   textures instead of procedural nodes: image textures export to glTF as they are, so nothing
   needs baking.
3. **Checkpoint shrine** (with the `Marker3D_FlamePoint` empty) and the **sanctum gate** go to
   `assets/props/`.
4. **Match the valley:** the existing torii and lanterns in `scenes/landmarks/` set the palette.
   Warm stone, dark lacquer and brass.

## 6. Check, license, commit and push (20 min)

1. **Quick look in Godot:** open the project and drag each `.glb` into an empty 3D scene next to
   the 1.8 m player capsule to compare scale. Or ask Claude to run your `godot-asset-pipeline`
   skill for a lookdev render. Don't edit `main.tscn` or the mob scenes; the cloud session wires
   everything in.
2. **Licences:** every new file has a line in `assets/LICENSES.md`: Quaternius (CC0), Poly Haven
   (CC0), Meshy free tier (CC BY 4.0, "Meshy AI"), or this repo (CC0) for what Claude modelled.
3. **Keep private files private:** `.gitignore` already skips `assets/incoming/private/`. Check
   `git status` before committing.
4. **Sizes:** GitHub rejects files over 100 MB and warns over 50 MB. 2k textures keep a
   character GLB around 5–20 MB.
5. **Commit and push:**
   ```powershell
   git add assets docs .gitignore
   git commit -m "art(m2): characters, animations, weapons, courtyard kit and shrine"
   git push -u origin vs/m2-art
   ```
6. **Tests (optional locally):**
   `"C:\path\to\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --script res://tests/run_tests.gd`.
   They should still pass, because nothing is wired in yet.

## 7. Hand-off to the cloud (Godot side)

Start a cloud session (claude.ai/code) on `vs/m2-art` and paste:
```text
Read AGENTS.md, docs/vertical-slice/PROMPTS.md §2B and docs/vertical-slice/M2_GUIDE.md.
The M2 art is on this branch: assets/characters/*.glb, assets/incoming/animations/ (with
clip_map.csv), assets/weapons/, assets/environment/, assets/props/.
1. Import presets and a BoneMap (SkeletonProfileHumanoid) for every character; build each
   character's AnimationLibrary from clip_map.csv with the manifest's clip names (retime the
   derived clips as noted); run a clip-length check against every AttackData.
2. Add the sockets (hand, hip-left sheath, glint) and replace the placeholder models in
   player.tscn and the three enemy scenes (D15: rename Katana to Sword where the manifest
   allows, and update the manifest in the same PR).
3. Swap the courtyard greybox and the shrine and gate placeholders for the kit, keeping the
   collision, navmesh and gate behaviour.
4. Keep every test green; capture before/after screenshots with xvfb-run; open a PR into
   vertical-slice-prototype.
```
That session runs headless Blender for any fix-ups, so you don't need to be at the PC for it.
