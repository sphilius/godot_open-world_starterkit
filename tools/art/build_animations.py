"""Builds the Duelist and enemy animation sets (M2) from the Quaternius Universal Animation
Libraries (CC0) in assets/incoming/animations/, following assets/incoming/animations/clip_map.csv.

    "$BLENDER" -b --factory-startup --python tools/art/build_animations.py -- [--preview DIR]

Every character shares the libraries' 65-bone rig, so the clips need no retargeting. What this
does to them:
  * Strikes are fitted to their AttackData (resources/combat/**.tres, read here so the two stay
    in step): the swing's impact (the frame the right hand moves fastest) lands in the middle of
    the active window, and the clip lasts exactly `duration` (tests/test_data.gd checks both).
  * Joins (a swing plus its recovery), cuts (one swing of a combo, a roll without its get-up)
    and fits to gameplay timings (dodge, hit reactions, knockdown, roar).
  * Side-steps (strafe_l, strafe_r and the Duelist's backpedal strafe_b) are keyed here: the
    feet follow a step-together cycle through leg IK under the sword-ready stance, then the
    result is baked to plain keys.
Output: assets/characters/humanoid/{duelist,enemy}_animations.glb (rig and clips, no mesh) and a
matching *_clips.json (clip lengths, loop flags and, for side-steps, the speed in m/s the feet
match at normal playback) that tools/build_character_scenes.gd reads.
"""

import json
import math
import os
import re
import sys

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ANIMS = os.path.join(ROOT, "assets", "incoming", "animations", "quaternius")
UAL = {
    "UAL1": os.path.join(ANIMS, "Universal Animation Library[Standard]", "Unreal-Godot", "UAL1_Standard.glb"),
    "UAL2": os.path.join(ANIMS, "Universal Animation Library 2[Standard]", "Unreal-Godot", "UAL2_Standard.glb"),
}
COMBAT = os.path.join(ROOT, "resources", "combat")
OUT = os.path.join(ROOT, "assets", "characters", "humanoid")
FPS = 30

# Gameplay timings the reaction clips are fitted to (seconds; see the scripts and scenes named).
DODGE = 0.45            # CombatStateMachine.dodge_duration
FLINCH = 0.3            # DamageReactionComponent.flinch_time
HEAVY = 0.7             # DamageReactionComponent.heavy_time
KNOCKDOWN = 1.8         # DamageReactionComponent.knockdown_time (player)
ROAR = 1.2              # Gatekeeper.roar_time


def seg(lib, action, start=0.0, end=None):
    return (lib, action, start, end)


# name: segments (played back to back), fit, loop.
#   fit None keeps the source timing; ("attack", "attack_1.tres") fits to that AttackData;
#   ("length", s) scales to s seconds.
DUELIST = {
    "idle": ([seg("UAL1", "Sword_Idle")], None, True),
    "run": ([seg("UAL1", "Jog_Fwd_Loop")], None, True),
    "walk": ([seg("UAL1", "Walk_Loop")], None, True),
    "sprint": ([seg("UAL1", "Sprint_Loop")], None, True),
    "jump_start": ([seg("UAL1", "Jump_Start")], None, False),
    "jump_loop": ([seg("UAL1", "Jump_Loop")], None, True),
    "jump_land": ([seg("UAL1", "Jump_Land")], None, False),
    "attack_1": ([seg("UAL2", "Sword_Regular_A"), seg("UAL2", "Sword_Regular_A_Rec")], ("attack", "attack_1.tres"), False),
    "attack_2": ([seg("UAL2", "Sword_Regular_B"), seg("UAL2", "Sword_Regular_B_Rec")], ("attack", "attack_2.tres"), False),
    "attack_3": ([seg("UAL2", "Sword_Regular_C")], ("attack", "attack_3.tres"), False),
    # Sword_Heavy_Combo swings at ~0.45 s, 1.17 s, 1.84 s and 2.57 s (hand_r speed peaks at 30 fps);
    # one swing per clip, the finisher with the combo's recovery.
    "heavy_1": ([seg("UAL2", "Sword_Heavy_Combo", 0.0, 0.85)], ("attack", "heavy_1.tres"), False),
    "heavy_2": ([seg("UAL2", "Sword_Heavy_Combo", 0.85, 1.5)], ("attack", "heavy_2.tres"), False),
    "heavy_finisher": ([seg("UAL2", "Sword_Heavy_Combo", 2.2, 3.6)], ("attack", "heavy_finisher.tres"), False),
    "draw_attack": ([seg("UAL2", "Sword_Dash")], ("attack", "draw_attack.tres"), False),
    "execution": ([seg("UAL1", "Sword_Attack")], ("attack", "execution.tres"), False),
    "guard_idle": ([seg("UAL2", "Idle_Shield_Loop")], None, True),
    "guard_hit": ([seg("UAL2", "Sword_Block")], ("length", 0.5), False),
    "guard_break": ([seg("UAL2", "Idle_Shield_Break")], ("length", HEAVY), False),
    "parry_1": ([seg("UAL2", "Sword_Block", 0.0, 0.6)], ("length", 0.35), False),
    "parry_2": ([seg("UAL2", "Shield_OneShot")], ("length", 0.45), False),
    "dodge_f": ([seg("UAL1", "Roll", 0.0, 1.1)], ("length", DODGE), False),
    "dodge_b": ([seg("UAL1", "Roll", 0.0, 1.1)], ("length", DODGE), False),
    "dodge_l": ([seg("UAL1", "Roll", 0.0, 1.1)], ("length", DODGE), False),
    "dodge_r": ([seg("UAL1", "Roll", 0.0, 1.1)], ("length", DODGE), False),
    "hurt_f": ([seg("UAL1", "Hit_Chest")], ("length", FLINCH), False),
    "hurt_b": ([seg("UAL1", "Hit_Head")], ("length", FLINCH), False),
    "hurt_l": ([seg("UAL1", "Hit_Head")], ("length", FLINCH), False),
    "hurt_r": ([seg("UAL1", "Hit_Chest")], ("length", FLINCH), False),
    "hurt_heavy": ([seg("UAL2", "Idle_Shield_Break")], ("length", HEAVY), False),
    "knockdown": ([seg("UAL2", "Hit_Knockback"), seg("UAL2", "LayToIdle")], ("length", KNOCKDOWN), False),
    "death": ([seg("UAL1", "Death01")], None, False),
}
ENEMY = {
    "idle": ([seg("UAL1", "Sword_Idle")], None, True),
    "walk": ([seg("UAL1", "Walk_Loop")], None, True),
    "run": ([seg("UAL1", "Jog_Fwd_Loop")], None, True),
    "attack_1": ([seg("UAL2", "Sword_Regular_A"), seg("UAL2", "Sword_Regular_A_Rec")], ("attack", "enemies/grunt_slash.tres"), False),
    "attack_2": ([seg("UAL2", "Sword_Regular_B"), seg("UAL2", "Sword_Regular_B_Rec")], ("attack", "enemies/grunt_cut.tres"), False),
    "slam": ([seg("UAL1", "Sword_Attack")], ("attack", "enemies/brute_slam.tres"), False),
    "sweep": ([seg("UAL2", "Sword_Regular_C")], ("attack", "enemies/brute_sweep.tres"), False),
    "thrust_unblockable": ([seg("UAL2", "Sword_Dash")], ("attack", "enemies/brute_thrust.tres"), False),
    "hurt_f": ([seg("UAL1", "Hit_Chest")], None, False),
    "hurt_b": ([seg("UAL1", "Hit_Head")], None, False),
    "parried": ([seg("UAL2", "Idle_Shield_Break")], ("length", 1.2), False),
    "stagger": ([seg("UAL1", "Hit_Head")], ("length", HEAVY), False),
    "posture_break": ([seg("UAL1", "Fixing_Kneeling", 0.0, 1.6)], None, False),
    "executed": ([seg("UAL1", "Death01")], None, False),
    "roar": ([seg("UAL2", "Idle_Rail_Call", 0.2, 2.0)], ("length", ROAR), False),
    "death": ([seg("UAL1", "Death01")], None, False),
}
# Keyed side-steps: name -> (direction in the rig's space, lead foot). The rig faces -Y, so its
# right is -X and backwards is +Y.
STEPS_DUELIST = {"strafe_r": (Vector((-1, 0, 0)), "r"), "strafe_l": (Vector((1, 0, 0)), "l"), "strafe_b": (Vector((0, 1, 0)), None)}
STEPS_ENEMY = {"strafe_r": (Vector((-1, 0, 0)), "r"), "strafe_l": (Vector((1, 0, 0)), "l")}
STEP_CYCLE = 0.5        # seconds per step-together cycle (two steps)
STEP_STRIDE = 0.6       # metres covered per cycle: 1.2 m/s at normal speed. The clips are in place;
STEP_LIFT = 0.08        # the controllers move the body and scale playback to their actual speed
STEP_WIDEN = 0.07       # extra stance width per foot for side-steps


def attack_timing(rel):
    text = open(os.path.join(COMBAT, rel)).read()
    get = lambda key: float(re.search(rf"^{key} = ([0-9.]+)", text, re.M).group(1))
    return get("duration"), get("active_start"), get("active_end")


# --- Sampling ------------------------------------------------------------------------------

class Source:
    """One imported library: its rig and actions by name."""
    def __init__(self, path):
        before_obj, before_act = set(bpy.data.objects), set(bpy.data.actions)
        bpy.ops.import_scene.gltf(filepath=path)
        self.rig = next(o for o in bpy.data.objects if o not in before_obj and o.type == 'ARMATURE')
        self.actions = {a.name.split("|")[-1]: a for a in bpy.data.actions if a not in before_act}
        for obj in [o for o in bpy.data.objects if o not in before_obj and o.type == 'MESH']:
            bpy.data.objects.remove(obj, do_unlink=True)

    def use(self, name):
        action = self.actions[name]
        ad = self.rig.animation_data or self.rig.animation_data_create()
        ad.action = action
        if hasattr(ad, "action_slot") and action.slots:
            ad.action_slot = action.slots[0]
        return action

    def length(self, name):
        f0, f1 = self.actions[name].frame_range
        return (f1 - f0) / FPS

    def pose_at(self, name, t):
        """Local pose of every bone at `t` seconds into `name`: {bone: (loc, quat, scale)}."""
        action = self.use(name)
        f = action.frame_range[0] + t * FPS
        bpy.context.scene.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
        return {b.name: (b.location.copy(), b.rotation_quaternion.copy(), b.scale.copy()) for b in self.rig.pose.bones}

    def hand_speed_peak(self, name, start, end):
        """Seconds (from `start`) at which hand_r moves fastest between start and end."""
        action = self.use(name)
        best, best_t, prev = -1.0, 0.0, None
        steps = max(2, int((end - start) * FPS))
        for i in range(steps + 1):
            t = start + (end - start) * i / steps
            f = action.frame_range[0] + t * FPS
            bpy.context.scene.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
            p = self.rig.matrix_world @ self.rig.pose.bones["hand_r"].head
            if prev is not None and (p - prev).length > best:
                best, best_t = (p - prev).length, t - start
            prev = p.copy()
        return best_t


def build_clip(sources, rig, name, segments, fit):
    """Samples the segments onto `rig` as a new action `name`, retimed per `fit`. Returns its length."""
    spans = []
    for lib, action, start, end in segments:
        end = sources[lib].length(action) if end is None else min(end, sources[lib].length(action))
        spans.append((lib, action, start, end))
    total = sum(e - s for _, _, s, e in spans)

    # Output time -> source timeline (seconds from the start of the first span).
    if fit is None:
        out_len, remap = total, (lambda t: t)
    elif fit[0] == "length":
        out_len = fit[1]
        remap = lambda t, k=total / fit[1]: t * k
    else:
        duration, a0, a1 = attack_timing(fit[1])
        lib, action, s, e = spans[0]
        impact_src = sources[lib].hand_speed_peak(action, s, e)
        impact_dst = (a0 + a1) / 2.0
        out_len = duration
        def remap(t, isrc=impact_src, idst=impact_dst, tot=total, dur=duration):
            if t <= idst:
                return t / idst * isrc
            return isrc + (t - idst) / (dur - idst) * (tot - isrc)
        print(f"  {name}: impact {impact_src:.2f}s of {total:.2f}s -> {impact_dst:.2f}s of {duration:.2f}s")

    frames = int(round(out_len * FPS))
    poses = []
    for i in range(frames + 1):
        t = remap(min(i / FPS, out_len))
        for lib, action, s, e in spans:
            if t <= (e - s) + 1e-6 or (lib, action, s, e) == spans[-1]:
                poses.append(sources[lib].pose_at(action, s + min(t, e - s)))
                break
            t -= e - s
    write_action(rig, name, poses)
    return frames / FPS


def write_action(rig, name, poses):
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    ad = rig.animation_data or rig.animation_data_create()
    ad.action = action
    for frame, pose in enumerate(poses):
        for bone, (loc, quat, scale) in pose.items():
            pb = rig.pose.bones[bone]
            pb.rotation_mode = 'QUATERNION'
            pb.location, pb.rotation_quaternion, pb.scale = loc, quat, scale
            for path in ("location", "rotation_quaternion", "scale"):
                pb.keyframe_insert(path, frame=frame + 1, group=bone)
    return action


# --- Keyed side-steps ------------------------------------------------------------------------

def key_side_step(sources, rig, name, direction, lead):
    """A step-together (or backpedal) cycle in place under the sword-ready stance, via leg IK."""
    stance = sources["UAL1"].pose_at("Sword_Idle", 0.0)
    scene = bpy.context.scene
    ad = rig.animation_data or rig.animation_data_create()
    ad.action = None
    for bone, (loc, quat, scale) in stance.items():
        pb = rig.pose.bones[bone]
        pb.rotation_mode = 'QUATERNION'
        pb.location, pb.rotation_quaternion, pb.scale = loc, quat, scale
    bpy.context.view_layer.update()
    ankles = {s: rig.matrix_world @ rig.pose.bones[f"foot_{s}"].head for s in "lr"}
    knees = {s: rig.matrix_world @ rig.pose.bones[f"calf_{s}"].head for s in "lr"}

    helpers, constraints = [], []
    for s in "lr":
        target = bpy.data.objects.new(f"ik_{s}", None)
        pole = bpy.data.objects.new(f"pole_{s}", None)
        for obj in (target, pole):
            scene.collection.objects.link(obj)
            helpers.append(obj)
        pole.location = knees[s] + Vector((0, -0.6, 0))
        ik = rig.pose.bones[f"calf_{s}"].constraints.new('IK')
        ik.target, ik.pole_target, ik.chain_count, ik.pole_angle = target, pole, 2, math.radians(-90)
        constraints.append((f"calf_{s}", ik))

    frames = int(round(STEP_CYCLE * FPS))
    sideways = abs(direction.x) > 0.5
    for i in range(frames + 1):
        u = i / frames
        for s in "lr":
            if sideways:
                # Lead foot swings in the first half, the trailing foot in the second; each slides
                # against the direction of travel while planted (the clip is in place).
                phase = u if s == lead else (u + 0.5) % 1.0
            else:
                phase = u if s == "r" else (u + 0.5) % 1.0
            if phase < 0.5:
                k = phase / 0.5
                along, lift = (k - 0.5), math.sin(k * math.pi) * STEP_LIFT
            else:
                k = (phase - 0.5) / 0.5
                along, lift = (0.5 - k), 0.0
            offset = direction * (along * STEP_STRIDE / 2.0)
            if sideways:        # a wider base, so the feet stay ~20 cm apart where they meet
                offset += Vector((STEP_WIDEN if s == "l" else -STEP_WIDEN, 0, 0))
            target = scene.objects[f"ik_{s}"]
            target.location = ankles[s] + offset + Vector((0, 0, lift))
            target.keyframe_insert("location", frame=i + 1)
        pelvis = rig.pose.bones["pelvis"]
        pelvis.location = stance["pelvis"][0] + Vector((0, 0, -0.015 * (1 - math.cos(u * 4 * math.pi)) / 2))
        pelvis.keyframe_insert("location", frame=i + 1)

    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='POSE')
    bpy.ops.pose.select_all(action='SELECT')
    scene.frame_start, scene.frame_end = 1, frames + 1
    bpy.ops.nla.bake(frame_start=1, frame_end=frames + 1, only_selected=True, visual_keying=True,
                     clear_constraints=True, use_current_action=False, bake_types={'POSE'})
    bpy.ops.object.mode_set(mode='OBJECT')
    baked = rig.animation_data.action
    baked.name = name
    baked.use_fake_user = True
    rig.animation_data.action = None
    for obj in helpers:
        bpy.data.objects.remove(obj, do_unlink=True)
    return frames / FPS


# --- Export ----------------------------------------------------------------------------------

def build_set(label, clips, steps, preview_dir):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    sources = {key: Source(path) for key, path in UAL.items()}
    before = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=UAL["UAL1"])            # the export rig: a clean copy
    rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE' and o not in (s.rig for s in sources.values()))
    rig.name = rig.data.name = "Armature"
    for obj in [o for o in bpy.context.scene.objects if o.type == 'MESH']:
        bpy.data.objects.remove(obj, do_unlink=True)
    for act in [a for a in bpy.data.actions if a not in before]:
        bpy.data.actions.remove(act)
    if rig.animation_data:
        rig.animation_data.action = None

    info = {}
    print(f"{label}:")
    for name, (segments, fit, loop) in clips.items():
        info[name] = {"length": round(build_clip(sources, rig, name, segments, fit), 4), "loop": loop}
    for name, (direction, lead) in steps.items():
        info[name] = {"length": round(key_side_step(sources, rig, name, direction, lead), 4), "loop": True,
                      "speed": round(STEP_STRIDE / STEP_CYCLE, 3)}

    ours = {a.name for a in bpy.data.actions if a.name in info}
    for act in [a for a in bpy.data.actions if a.name not in ours]:
        bpy.data.actions.remove(act)
    for src in sources.values():
        bpy.data.objects.remove(src.rig, do_unlink=True)
    rig.animation_data.action = None
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT, f"{label}_animations.glb"), export_format='GLB', use_selection=True,
        export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=True,
        export_frame_step=1, export_yup=True)
    with open(os.path.join(OUT, f"{label}_clips.json"), "w") as handle:
        json.dump(info, handle, indent=1, sort_keys=True)
    print(f"{label}: {len(info)} clips")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    preview = argv[argv.index("--preview") + 1] if "--preview" in argv else None
    only = argv[argv.index("--only") + 1] if "--only" in argv else None
    for label, clips, steps in (("duelist", DUELIST, STEPS_DUELIST), ("enemy", ENEMY, STEPS_ENEMY)):
        if not only or only == label:
            build_set(label, clips, steps, preview)


main()
