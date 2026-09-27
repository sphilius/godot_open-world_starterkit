"""Builds the four slice characters (M2) from the Quaternius CC0 drops in assets/incoming/.

Run with headless Blender 4.5 (the cloud setup script installs it):

    "$BLENDER" -b --factory-startup --python tools/art/build_characters.py -- [--only duelist] [--preview DIR]

Each character is a Modular Character Outfits - Fantasy outfit on the shared 65-bone humanoid
rig, plus the head (face, eyes, eyebrows) cut from a Universal Base Characters body, a hairstyle
rigged to the head bone, a skin tint and optional glowing eyes. The pack's readme asks for
exactly that: only the base body's head under an outfit (a full body clips through it).

Output: assets/characters/<name>/<name>.glb (glTF +Y up, skinned, no animations; textures
downscaled to TEXTURE_SIZE). The models stay at their native ~1.82 m; the Godot scenes scale
the Brute and the Gatekeeper up, so one animation set fits every character. --preview renders a
front and a 3/4 view of each character into DIR.
"""

import math
import os
import sys

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
Q = os.path.join(ROOT, "assets", "incoming", "characters", "quaternius")
BASE = os.path.join(Q, "Universal Base Characters[Standard]", "Base Characters", "Godot - UE")
HAIR = os.path.join(Q, "Universal Base Characters[Standard]", "Hairstyles", "Rigged to Head Bone", "glTF (Godot -Unreal)")
OUTFITS = os.path.join(Q, "Modular Character Outfits - Fantasy[Standard]")
PARTS = os.path.join(OUTFITS, "Exports", "glTF (Godot-Unreal)", "Modular Parts")
TEXTURES = os.path.join(OUTFITS, "Textures")
OUT = os.path.join(ROOT, "assets", "characters")

TEXTURE_SIZE = 2048
HEAD_CUT_Z = 1.47            # base-body vertices below this (rest pose, metres) are hidden by the outfit
TRIANGLE_BUDGET = 25000      # per character (PLAN §4: 25k player and grunt, 35k brute and boss)

# Skin: (multiplier on the base bodies' tan skin, desaturation 0..1 applied first)
SKIN_DARK_BROWN = ((0.50, 0.36, 0.28), 0.0)
SKIN_ASHEN = ((0.72, 0.78, 0.86), 0.8)   # grey-blue and bloodless: the cult's thralls
HAIR_BLACK = (0.10, 0.085, 0.075)      # the pack's hair textures are near white

# name: base body head, outfit parts, hair pieces, skin and hair tints, outfit texture swaps,
# eye glow (colour, strength)
CHARACTERS = {
    "duelist": {
        "head": "Superhero_Male_FullBody.gltf",
        "parts": ["Male_Ranger_Body", "Male_Ranger_Arms", "Male_Ranger_Legs", "Male_Ranger_Feet_Boots", "Male_Ranger_Acc_Pauldron"],
        "hair": ["Hair_Buzzed", "Hair_Beard", "Eyebrows_Regular"],
        "skin": SKIN_DARK_BROWN,
        "hair_tint": HAIR_BLACK,
        "swap": {},
        "eyes": None,
    },
    "grunt": {
        "head": "Superhero_Male_FullBody.gltf",
        "parts": ["Male_Peasant_Body", "Male_Peasant_Arms", "Male_Peasant_Legs", "Male_Peasant_Feet", "Male_Ranger_Head_Hood"],
        "hair": ["Eyebrows_Regular"],
        "skin": SKIN_ASHEN,
        "hair_tint": HAIR_BLACK,
        "swap": {"T_Peasant_BaseColor": os.path.join(TEXTURES, "Peasant", "T_Peasant_2_BaseColor.png"),
                 "T_Ranger_BaseColor": os.path.join(TEXTURES, "Ranger", "T_Ranger_3_BaseColor.png")},   # a brown hood
        "eyes": ((1.0, 0.15, 0.05), 6.0),
    },
    "brute": {
        "head": "Superhero_Male_FullBody.gltf",
        "parts": ["Male_Peasant_Body", "Male_Peasant_Arms", "Male_Peasant_Legs", "Male_Ranger_Feet_Boots", "Male_Ranger_Acc_Pauldron"],
        "hair": ["Hair_Buzzed", "Hair_Beard", "Eyebrows_Regular"],
        "skin": SKIN_ASHEN,
        "hair_tint": HAIR_BLACK,
        "swap": {},
        "eyes": ((1.0, 0.2, 0.05), 4.0),
    },
    "gatekeeper": {
        "head": "Superhero_Male_FullBody.gltf",
        "parts": ["Male_Ranger_Body", "Male_Ranger_Arms", "Male_Ranger_Legs", "Male_Ranger_Feet_Boots", "Male_Ranger_Acc_Pauldron", "Male_Ranger_Head_Hood"],
        "hair": ["Eyebrows_Regular"],
        "skin": SKIN_ASHEN,
        "hair_tint": HAIR_BLACK,
        "swap": {"T_Ranger_BaseColor": os.path.join(TEXTURES, "Ranger", "T_Ranger_3_BaseColor.png")},
        "eyes": ((1.0, 0.75, 0.2), 8.0),
    },
}


def import_gltf(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def armature_of(objects):
    return next(o for o in objects if o.type == 'ARMATURE')


def bind_to(mesh, armature):
    """Skins `mesh` to `armature` (vertex groups are bone names, shared by every Quaternius rig)."""
    world = mesh.matrix_world.copy()
    mesh.parent = armature
    mesh.matrix_world = world
    for mod in mesh.modifiers:
        if mod.type == 'ARMATURE':
            mod.object = armature
    if not any(m.type == 'ARMATURE' for m in mesh.modifiers):
        mesh.modifiers.new("Armature", 'ARMATURE').object = armature


def keep_head(mesh):
    """Deletes the base body below the neck (the outfit covers it)."""
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='DESELECT')
    bpy.ops.object.mode_set(mode='OBJECT')
    for v in mesh.data.vertices:
        v.select = (mesh.matrix_world @ v.co).z < HEAD_CUT_Z
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.delete(type='VERT')
    bpy.ops.object.mode_set(mode='OBJECT')


def image_nodes():
    for mat in bpy.data.materials:
        if mat.node_tree:
            for node in mat.node_tree.nodes:
                if node.type == 'TEX_IMAGE' and node.image:
                    yield mat, node


def tint(image, factor, desaturate=0.0):
    import numpy as np
    px = np.empty(len(image.pixels), dtype=np.float32)
    image.pixels.foreach_get(px)
    px = px.reshape(-1, 4)
    if desaturate:
        grey = px[:, :3] @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
        px[:, :3] += (grey[:, None] - px[:, :3]) * desaturate
    px[:, :3] *= np.array(factor, dtype=np.float32)
    image.pixels.foreach_set(px.ravel())
    image.update()


def is_skin(image):
    name = image.name
    return "BaseColor" in name and ("Superhero" in name or "Regular" in name) or name.startswith("T_Superhero_Male_Dark")


def eye_glow(meshes, colour, strength):
    for mesh in meshes:
        for slot in mesh.material_slots:
            mat = slot.material
            if mat and "eye" in mat.name.lower() and mat.node_tree:
                bsdf = next((n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
                if bsdf:
                    bsdf.inputs["Emission Color"].default_value = (*colour, 1.0)
                    bsdf.inputs["Emission Strength"].default_value = strength


def triangles(meshes):
    return sum(sum(len(p.vertices) - 2 for p in m.data.polygons) for m in meshes)


def build(name, spec, preview_dir=None):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    parts = [import_gltf(os.path.join(PARTS, p + ".gltf")) for p in spec["parts"]]
    rig = armature_of(parts[0])
    rig.name = rig.data.name = "Armature"          # Godot imports it as Armature/Skeleton3D
    body = import_gltf(os.path.join(BASE, spec["head"]))
    extras = [o for o in body if o.type == 'MESH' and o.name not in ("Eyes", "Eyebrows") and "Icosphere" not in o.name]
    heads = [o for o in extras if o.data.vertices]
    for head in heads:
        keep_head(head)
    hair = [import_gltf(os.path.join(HAIR, h + ".gltf")) for h in spec["hair"]]

    meshes = []
    for group in parts + [body] + hair:
        for obj in group:
            if obj.type == 'MESH' and "Icosphere" not in obj.name and not (obj.name == "Eyebrows" and any("Eyebrows_" in h for h in spec["hair"])):
                bind_to(obj, rig)
                meshes.append(obj)
    for obj in list(bpy.data.objects):     # the other armatures, helpers and unused meshes
        if obj is not rig and obj not in meshes:
            bpy.data.objects.remove(obj, do_unlink=True)

    for boots in [m for m in meshes if "Feet_Boots" in m.name]:
        dec = boots.modifiers.new("Decimate", 'DECIMATE')
        dec.ratio = 0.35
        bpy.context.view_layer.objects.active = boots
        bpy.ops.object.modifier_move_to_index(modifier="Decimate", index=0)
        bpy.ops.object.modifier_apply(modifier="Decimate")

    for mat, node in list(image_nodes()):
        key = os.path.splitext(node.image.name)[0]
        if key in spec["swap"]:
            node.image = bpy.data.images.load(spec["swap"][key])
    done = set()
    for mat, node in list(image_nodes()):
        img = node.image
        if img.name in done:
            continue
        done.add(img.name)
        if img.size[0] > TEXTURE_SIZE:
            img.scale(TEXTURE_SIZE, TEXTURE_SIZE)
        if is_skin(img):
            tint(img, *spec["skin"])
        elif img.name.startswith("T_Hair") and "BaseColor" in img.name:
            tint(img, spec["hair_tint"])
        img.pack()
    if spec["eyes"]:
        eye_glow(meshes, *spec["eyes"])

    tris = triangles(meshes)
    print(f"{name}: {len(meshes)} meshes, {tris} triangles" + ("  OVER BUDGET" if tris > TRIANGLE_BUDGET else ""))

    os.makedirs(os.path.join(OUT, name), exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [rig] + meshes:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT, name, name + ".glb"), export_format='GLB', use_selection=True,
        export_animations=False, export_skins=True, export_yup=True, export_image_format='WEBP',
        export_image_quality=90)
    if preview_dir:
        render_preview(name, preview_dir)
    return tris


def render_preview(name, out_dir):
    scene = bpy.context.scene
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items]
    scene.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in engines else 'BLENDER_EEVEE'
    scene.render.resolution_x, scene.render.resolution_y = 420, 640
    scene.world = bpy.data.worlds.new("w")
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.33, 0.34, 0.38, 1)
    bg.inputs[1].default_value = 0.9
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN'))
    scene.collection.objects.link(sun)
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = 2.15
    target = bpy.data.objects.new("target", None)
    scene.collection.objects.link(target)
    target.location = (0, 0, 0.93)
    track = cam.constraints.new('TRACK_TO')
    track.target, track.track_axis, track.up_axis = target, 'TRACK_NEGATIVE_Z', 'UP_Y'
    os.makedirs(out_dir, exist_ok=True)
    for i, angle in enumerate((0, -35)):
        cam.location = (5 * math.sin(math.radians(angle)), -5 * math.cos(math.radians(angle)), 1.2)
        scene.render.filepath = os.path.join(out_dir, f"{name}_{i}.png")
        bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = argv[argv.index("--only") + 1] if "--only" in argv else None
    preview = argv[argv.index("--preview") + 1] if "--preview" in argv else None
    over = []
    for name, spec in CHARACTERS.items():
        if only and name != only:
            continue
        if build(name, spec, preview) > TRIANGLE_BUDGET:
            over.append(name)
    if over:
        print("Over the triangle budget:", ", ".join(over))


main()
