#!/usr/bin/env python3
"""Path traced look-development render of an assembled machine (Blender Cycles).

    python3 Tools/ModelForge/preview.py export /tmp/machine.npz [kind=variant ...]
    <python with bpy> Tools/ModelForge/lookdev.py /tmp/machine.npz out.png [samples] [width] [height]

This is the visual target for the realtime renderer: same geometry and layout
as the app, physically based materials with micro detail (orange peel paint,
brushed and smudged metal, dust on top faces, rubber grain), a warm desk lamp,
a cool window and a typed sheet.
"""
import math
import sys

import bpy
import numpy as np
from mathutils import Vector

NPZ, OUT = sys.argv[-5] if len(sys.argv) >= 6 else sys.argv[1], None
args = [a for a in sys.argv[1:] if not a.startswith("-")]
NPZ, OUT = args[0], args[1]
SAMPLES = int(args[2]) if len(args) > 2 else 128
W = int(args[3]) if len(args) > 3 else 1600
H = int(args[4]) if len(args) > 4 else 1000

data = np.load(NPZ)


def to_blender(a):
    """Y-up (app) -> Z-up (Blender)."""
    out = np.empty_like(a)
    out[..., 0] = a[..., 0]
    out[..., 1] = -a[..., 2]
    out[..., 2] = a[..., 1]
    return out


def kelvin(k):
    t = k / 100
    if t <= 66:
        r = 255
        g = 99.47 * math.log(t) - 161.12
        b = 0 if t <= 19 else 138.52 * math.log(t - 10) - 305.04
    else:
        r = 329.7 * (t - 60) ** -0.1332
        g = 288.12 * (t - 60) ** -0.0755
        b = 255
    c = [max(0, min(255, v)) / 255 for v in (r, g, b)]
    return [v ** 2.2 for v in c]


# --------------------------------------------------------------------------- scene reset
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = SAMPLES
scene.cycles.use_adaptive_sampling = True
scene.cycles.use_denoising = True
scene.cycles.max_bounces = 8
scene.cycles.glossy_bounces = 4
scene.cycles.transmission_bounces = 4
scene.render.resolution_x = W
scene.render.resolution_y = H
scene.render.film_transparent = False
try:
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
except Exception:
    pass
scene.view_settings.exposure = -0.6

world = bpy.data.worlds.new("Room")
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs["Color"].default_value = (0.012, 0.012, 0.016, 1)
bg.inputs["Strength"].default_value = 1.0


# --------------------------------------------------------------------------- materials
def node(nt, kind, loc=(0, 0), **inputs):
    n = nt.nodes.new(kind)
    n.location = loc
    for k, v in inputs.items():
        n.inputs[k].default_value = v
    return n


def detail_material(name, color, metallic=0.0, roughness=0.5, coat=0.0, bump=0.002, bump_scale=900,
                    rough_var=0.12, dust=0.35, smudge=0.0, aniso=0.0, sheen=0.0, transmission=0.0, alpha=1.0):
    """Principled BSDF with procedural micro detail driven in object space."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = node(nt, "ShaderNodeOutputMaterial", (900, 0))
    bsdf = node(nt, "ShaderNodeBsdfPrincipled", (500, 0))
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    tc = node(nt, "ShaderNodeTexCoord", (-900, 0))
    geo = node(nt, "ShaderNodeNewGeometry", (-900, -300))
    # micro surface: fine noise for bump and roughness breakup
    fine = node(nt, "ShaderNodeTexNoise", (-600, 200), Scale=bump_scale, Detail=6.0, Roughness=0.6)
    nt.links.new(tc.outputs["Object"], fine.inputs["Vector"])
    big = node(nt, "ShaderNodeTexNoise", (-600, -50), Scale=40.0, Detail=4.0, Roughness=0.5)
    nt.links.new(tc.outputs["Object"], big.inputs["Vector"])
    # smudges / fingerprints: voronoi distance blobs
    vor = node(nt, "ShaderNodeTexVoronoi", (-600, -250))
    vor.inputs["Scale"].default_value = 60.0
    nt.links.new(tc.outputs["Object"], vor.inputs["Vector"])
    # roughness = base + variation + smudges
    rmix = node(nt, "ShaderNodeMath", (-300, 100))
    rmix.operation = "MULTIPLY_ADD"
    rmix.inputs[1].default_value = rough_var
    rmix.inputs[2].default_value = roughness - rough_var * 0.5
    nt.links.new(big.outputs["Fac"], rmix.inputs[0])
    smud = node(nt, "ShaderNodeMath", (-300, -150))
    smud.operation = "MULTIPLY"
    smud.inputs[1].default_value = smudge
    sm_ramp = node(nt, "ShaderNodeMapRange", (-450, -250))
    sm_ramp.inputs["From Min"].default_value = 0.0
    sm_ramp.inputs["From Max"].default_value = 0.35
    sm_ramp.inputs["To Min"].default_value = 1.0
    sm_ramp.inputs["To Max"].default_value = 0.0
    nt.links.new(vor.outputs["Distance"], sm_ramp.inputs["Value"])
    nt.links.new(sm_ramp.outputs["Result"], smud.inputs[0])
    rough = node(nt, "ShaderNodeMath", (-150, 50))
    rough.operation = "ADD"
    nt.links.new(rmix.outputs["Value"], rough.inputs[0])
    nt.links.new(smud.outputs["Value"], rough.inputs[1])
    # dust settles on faces looking up (Blender Z)
    sep = node(nt, "ShaderNodeSeparateXYZ", (-600, -450))
    nt.links.new(geo.outputs["Normal"], sep.inputs["Vector"])
    up = node(nt, "ShaderNodeMapRange", (-400, -450))
    up.inputs["From Min"].default_value = 0.55
    up.inputs["From Max"].default_value = 1.0
    nt.links.new(sep.outputs["Z"], up.inputs["Value"])
    dn = node(nt, "ShaderNodeTexNoise", (-600, -650), Scale=180.0, Detail=3.0)
    nt.links.new(tc.outputs["Object"], dn.inputs["Vector"])
    dmask = node(nt, "ShaderNodeMath", (-200, -500))
    dmask.operation = "MULTIPLY"
    nt.links.new(up.outputs["Result"], dmask.inputs[0])
    nt.links.new(dn.outputs["Fac"], dmask.inputs[1])
    dk = node(nt, "ShaderNodeMath", (-50, -500))
    dk.operation = "MULTIPLY"
    dk.inputs[1].default_value = dust
    nt.links.new(dmask.outputs["Value"], dk.inputs[0])
    col = node(nt, "ShaderNodeMix", (200, 300))
    col.data_type = "RGBA"
    col.inputs[6].default_value = (*color, 1)
    col.inputs[7].default_value = (0.52, 0.49, 0.45, 1)   # dust grey
    nt.links.new(dk.outputs["Value"], col.inputs[0])
    nt.links.new(col.outputs[2], bsdf.inputs["Base Color"])
    rfin = node(nt, "ShaderNodeMix", (250, 50))
    rfin.data_type = "FLOAT"
    rfin.inputs[3].default_value = 0.9
    nt.links.new(dk.outputs["Value"], rfin.inputs[0])
    nt.links.new(rough.outputs["Value"], rfin.inputs[2])
    nt.links.new(rfin.outputs[0], bsdf.inputs["Roughness"])
    bsdf.inputs["Metallic"].default_value = metallic
    bmp = node(nt, "ShaderNodeBump", (250, -200), Strength=1.0, Distance=bump)
    nt.links.new(fine.outputs["Fac"], bmp.inputs["Height"])
    nt.links.new(bmp.outputs["Normal"], bsdf.inputs["Normal"])
    if coat > 0:
        bsdf.inputs["Coat Weight"].default_value = coat
        bsdf.inputs["Coat Roughness"].default_value = 0.04
        cb = node(nt, "ShaderNodeBump", (250, -400), Strength=0.4, Distance=0.0006)
        op = node(nt, "ShaderNodeTexNoise", (0, -400), Scale=300.0, Detail=2.0)
        nt.links.new(tc.outputs["Object"], op.inputs["Vector"])
        nt.links.new(op.outputs["Fac"], cb.inputs["Height"])
        nt.links.new(cb.outputs["Normal"], bsdf.inputs["Coat Normal"])
    if aniso > 0:
        bsdf.inputs["Anisotropic"].default_value = aniso
    if sheen > 0:
        bsdf.inputs["Sheen Weight"].default_value = sheen
        bsdf.inputs["Sheen Roughness"].default_value = 0.6
    if transmission > 0:
        bsdf.inputs["Transmission Weight"].default_value = transmission
        bsdf.inputs["IOR"].default_value = 1.5
    if alpha < 1:
        bsdf.inputs["Alpha"].default_value = alpha
    return m


def srgb(c):
    return tuple(v ** 2.2 for v in c)


ROLE = {
    "paint": lambda c: detail_material("paint", srgb(c), 0.0, 0.32, coat=1.0, bump=0.0004, rough_var=0.1, dust=0.45, smudge=0.15),
    "paintAccent": lambda c: detail_material("paintAccent", srgb(c), 0.7, 0.3, coat=0.4, rough_var=0.1, dust=0.2),
    "paintSecond": lambda c: detail_material("paintSecond", srgb(c), 0.0, 0.36, coat=0.8, bump=0.0004, dust=0.4, smudge=0.1),
    "chrome": lambda c: detail_material("chrome", (0.9, 0.9, 0.92), 1.0, 0.07, bump=0.0002, rough_var=0.06, dust=0.25, smudge=0.25),
    "steel": lambda c: detail_material("steel", (0.62, 0.62, 0.64), 1.0, 0.3, bump=0.0004, rough_var=0.18, aniso=0.6, dust=0.3, smudge=0.1),
    "blackSteel": lambda c: detail_material("blackSteel", (0.07, 0.07, 0.075), 0.9, 0.38, bump=0.0004, rough_var=0.15, dust=0.35),
    "brass": lambda c: detail_material("brass", (0.83, 0.62, 0.32), 1.0, 0.24, bump=0.0003, rough_var=0.2, dust=0.25, smudge=0.25),
    "copper": lambda c: detail_material("copper", (0.85, 0.48, 0.34), 1.0, 0.28, rough_var=0.2, dust=0.25),
    "rubber": lambda c: detail_material("rubber", (0.03, 0.03, 0.032), 0.0, 0.72, bump=0.001, bump_scale=1600, rough_var=0.15, dust=0.55),
    "redRubber": lambda c: detail_material("redRubber", srgb(c), 0.0, 0.7, bump=0.001, dust=0.5),
    "bakelite": lambda c: detail_material("bakelite", srgb(c), 0.0, 0.2, coat=0.9, rough_var=0.1, dust=0.3, smudge=0.3),
    "keyTop": lambda c: detail_material("keyTop", srgb(c), 0.0, 0.22, coat=0.7, rough_var=0.08, dust=0.15, smudge=0.4),
    "keyBody": lambda c: detail_material("keyBody", srgb(c), 0.0, 0.3, coat=0.4, dust=0.3, smudge=0.2),
    "glass": lambda c: detail_material("glass", (0.95, 0.97, 0.97), 0.0, 0.02, transmission=1.0, dust=0.1),
    "smoked": lambda c: detail_material("smoked", (0.25, 0.18, 0.12), 0.0, 0.05, transmission=0.8),
    "felt": lambda c: detail_material("felt", srgb(c), 0.0, 0.95, bump=0.001, bump_scale=2500, sheen=1.0, dust=0.2),
    "plastic": lambda c: detail_material("plastic", srgb(c), 0.0, 0.4, dust=0.35, smudge=0.1),
    "darkPlastic": lambda c: detail_material("darkPlastic", srgb(c), 0.0, 0.45, dust=0.4, smudge=0.1),
    "wood": lambda c: detail_material("wood", srgb(c), 0.0, 0.45, coat=0.5, rough_var=0.15, dust=0.2),
    "enamel": lambda c: detail_material("enamel", srgb(c), 0.0, 0.12, coat=1.0, dust=0.2),
    "tape": lambda c: detail_material("tape", srgb(c), 0.0, 0.8, bump=0.0004, dust=0.0),
    "medium": lambda c: detail_material("medium", srgb(c), 0.0, 0.75, bump=0.0004, dust=0.0),
    "ribbon": lambda c: detail_material("ribbon", (0.015, 0.015, 0.018), 0.0, 0.85, bump=0.0003, bump_scale=3000, dust=0.0),
    "correction": lambda c: detail_material("correction", (0.93, 0.92, 0.89), 0.0, 0.9, dust=0.0),
    "scale": lambda c: detail_material("scale", srgb(c), 0.0, 0.45, coat=0.3, dust=0.2),
}


def build_mesh(name, pos, nrm, material, uv=None):
    pos = to_blender(pos.reshape(-1, 3, 3)).reshape(-1, 3)
    nrm = to_blender(nrm.reshape(-1, 3, 3)).reshape(-1, 3)
    n_tris = len(pos) // 3
    me = bpy.data.meshes.new(name)
    me.vertices.add(len(pos))
    me.vertices.foreach_set("co", pos.astype(np.float32).ravel())
    me.loops.add(len(pos))
    me.loops.foreach_set("vertex_index", np.arange(len(pos), dtype=np.int32))
    me.polygons.add(n_tris)
    me.polygons.foreach_set("loop_start", np.arange(0, len(pos), 3, dtype=np.int32))
    me.polygons.foreach_set("loop_total", np.full(n_tris, 3, dtype=np.int32))
    me.update()
    if uv is not None:
        layer = me.uv_layers.new(name="UVMap")
        layer.data.foreach_set("uv", uv.reshape(-1, 2).astype(np.float32).ravel())
    me.polygons.foreach_set("use_smooth", np.ones(n_tris, dtype=bool))
    me.normals_split_custom_set([tuple(v) for v in nrm])
    me.validate()
    ob = bpy.data.objects.new(name, me)
    ob.data.materials.append(material)
    scene.collection.objects.link(ob)
    return ob


# --------------------------------------------------------------------------- typed sheet texture
def paper_texture(vprint, path):
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
    dpi = 220
    pw, ph = int(8.5 * dpi), int(11 * dpi)
    rng = np.random.default_rng(7)
    base = np.array([241, 235, 220], dtype=np.float32)
    noise = rng.normal(0, 1, (ph // 4 + 1, pw // 4 + 1)).astype(np.float32)
    cloud = np.repeat(np.repeat(noise, 4, 0), 4, 1)[:ph, :pw]
    img = Image.fromarray(np.uint8(np.clip(base[None, None, :] + cloud[..., None] * 2.5 +
                                           rng.normal(0, 2.0, (ph, pw, 1)), 0, 255)))
    ink = Image.new("L", (pw, ph), 0)
    d = ImageDraw.Draw(ink)
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf", int(dpi / 6.0))
    lines = [
        "November 19, 1956",
        "",
        "Dear Margaret,",
        "",
        "The new machine arrived this morning. It is heavier than",
        "it looks, and the bell rings a little early, which I am",
        "told can be adjusted. The ribbon is fresh, so forgive the",
        "darkness of the letters; it will mellow by Christmas.",
        "",
        "I have been typing since breakfast. There is something",
        "about the sound of it - the clack, the little pause of",
        "the carriage, the bell - that makes the words come",
        "easier than they ever did with a pen.",
        "",
        "Yours, as ever,",
    ]
    pitch = dpi / 10
    line_h = dpi / 6
    # the last line sits on the printing line
    baseline0 = vprint * 11 * dpi - (len(lines) - 1) * line_h
    for i, line in enumerate(lines):
        y = baseline0 + i * line_h
        for j, ch in enumerate(line):
            if ch == " ":
                continue
            x = dpi + j * pitch + rng.normal(0, 0.6)
            dy = rng.normal(0, 0.7)
            tone = int(np.clip(rng.normal(225, 18), 150, 255))
            d.text((x, y + dy), ch, font=font, fill=tone, anchor="ls")
    ink = ink.filter(ImageFilter.GaussianBlur(0.7))
    weave = Image.fromarray(np.uint8(np.clip(255 - rng.random((ph, pw)) * 70, 0, 255)))
    ink = Image.fromarray(np.uint8(np.array(ink, np.float32) * np.array(weave, np.float32) / 255))
    inkc = Image.new("RGB", (pw, ph), (22, 20, 24))
    img = Image.composite(inkc, img, ink)
    img.save(path)
    return path


# --------------------------------------------------------------------------- build
palette_roles = {}
for key in data.files:
    role, kind = key.split("__")
    if kind != "pos":
        continue
    pos = data[f"{role}__pos"]
    nrm = data[f"{role}__nrm"]
    col = data[f"{role}__col"]
    c = tuple(float(v) for v in col.mean(axis=0)) if len(col) else (0.5, 0.5, 0.5)
    if role == "paper":
        vprint = float(data["paper__vprint"][0])
        tex_path = OUT.replace(".png", "_paper.png")
        paper_texture(vprint, tex_path)
        m = bpy.data.materials.new("paper")
        m.use_nodes = True
        nt = m.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(tex_path)
        tex.interpolation = "Cubic"
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.85
        bsdf.inputs["Subsurface Weight"].default_value = 0.08
        bmp = nt.nodes.new("ShaderNodeBump")
        bmp.inputs["Distance"].default_value = 0.0002
        nz = nt.nodes.new("ShaderNodeTexNoise")
        nz.inputs["Scale"].default_value = 4000.0
        nt.links.new(nz.outputs["Fac"], bmp.inputs["Height"])
        nt.links.new(bmp.outputs["Normal"], bsdf.inputs["Normal"])
        uv = data["paper__uv"].copy()
        uv[..., 1] = 1.0 - uv[..., 1]          # Blender images have their origin at the bottom
        ob = build_mesh("paper", pos, nrm, m, uv)
        # visible from both sides
        continue
    maker = ROLE.get(role, ROLE["paint"])
    # each role keeps one material; paint colors differ per variant, so key by color
    mat_key = (role, tuple(round(v, 3) for v in c))
    if mat_key not in palette_roles:
        palette_roles[mat_key] = maker(c)
    build_mesh(role, pos, nrm, palette_roles[mat_key])

# desk: walnut with waves + pores + clear coat
bpy.ops.mesh.primitive_plane_add(size=1, location=(0.05, 0.0, 0.0))
desk = bpy.context.active_object
desk.scale = (2.4, 1.6, 1)
dm = bpy.data.materials.new("desk")
dm.use_nodes = True
nt = dm.node_tree
bsdf = nt.nodes["Principled BSDF"]
tc = nt.nodes.new("ShaderNodeTexCoord")
mapn = nt.nodes.new("ShaderNodeMapping")
mapn.inputs["Scale"].default_value = (1.5, 30.0, 1.0)     # grain runs along X
nt.links.new(tc.outputs["Object"], mapn.inputs["Vector"])
grain = nt.nodes.new("ShaderNodeTexNoise")
grain.inputs["Scale"].default_value = 3.0
grain.inputs["Detail"].default_value = 10.0
grain.inputs["Roughness"].default_value = 0.62
grain.inputs["Distortion"].default_value = 0.4
nt.links.new(mapn.outputs["Vector"], grain.inputs["Vector"])
ramp = nt.nodes.new("ShaderNodeValToRGB")
ramp.color_ramp.elements[0].position = 0.35
ramp.color_ramp.elements[0].color = (0.035, 0.016, 0.007, 1)
ramp.color_ramp.elements[1].position = 0.7
ramp.color_ramp.elements[1].color = (0.13, 0.062, 0.028, 1)
nt.links.new(grain.outputs["Fac"], ramp.inputs["Fac"])
nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
bsdf.inputs["Roughness"].default_value = 0.42
bsdf.inputs["Coat Weight"].default_value = 0.6
bsdf.inputs["Coat Roughness"].default_value = 0.12
pores = nt.nodes.new("ShaderNodeTexNoise")
pores.inputs["Scale"].default_value = 900.0
nt.links.new(tc.outputs["Object"], pores.inputs["Vector"])
bmp = nt.nodes.new("ShaderNodeBump")
bmp.inputs["Distance"].default_value = 0.0006
nt.links.new(pores.outputs["Fac"], bmp.inputs["Height"])
nt.links.new(bmp.outputs["Normal"], bsdf.inputs["Normal"])
desk.data.materials.append(dm)

# back wall far behind, catches lamp spill
bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0.9, 0.6), rotation=(math.radians(90), 0, 0))
wall = bpy.context.active_object
wall.scale = (4, 2, 1)
wm = bpy.data.materials.new("wall")
wm.use_nodes = True
wm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.09, 0.075, 0.06, 1)
wm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
wall.data.materials.append(wm)

# --------------------------------------------------------------------------- lights
def area(name, loc, target, size, power, color, shape="DISK", size_y=None):
    ld = bpy.data.lights.new(name, "AREA")
    ld.shape = shape
    ld.size = size
    if size_y:
        ld.size_y = size_y
    ld.energy = power
    ld.color = color
    ob = bpy.data.objects.new(name, ld)
    ob.location = loc
    d = Vector(target) - Vector(loc)
    ob.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(ob)
    return ob

# banker's lamp: warm, small, close, upper left behind
area("Lamp", (-0.42, 0.22, 0.42), (0.0, 0.02, 0.08), 0.09, 32, kelvin(2700))
# lamp shade glow bounce
# (no visible bounce card: it reflected in the desk)
# cool window from the left
area("Window", (-1.3, -0.1, 0.75), (0.0, 0.0, 0.05), 1.2, 90, (0.62, 0.72, 1.0), "RECTANGLE", 0.9)
# faint fill from the typist side
area("Fill", (0.2, -1.2, 0.8), (0.0, 0.0, 0.1), 1.0, 12, kelvin(4500), "RECTANGLE", 0.6)

# --------------------------------------------------------------------------- camera (the app's "Seated" seat)
cam_data = bpy.data.cameras.new("Seat")
cam_data.sensor_fit = "VERTICAL"
cam_data.angle = math.radians(34)
cam_data.dof.use_dof = True
cam_data.dof.aperture_fstop = 5.6
cam = bpy.data.objects.new("Seat", cam_data)
eye = Vector((0.0, -0.44, 0.50))
target = Vector((0.0, 0.03, 0.13))
cam.location = eye
cam.rotation_euler = (target - eye).to_track_quat("-Z", "Y").to_euler()
cam_data.dof.focus_distance = (Vector((0.0, 0.054, 0.142)) - eye).length
scene.collection.objects.link(cam)
scene.camera = cam

scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("rendered", OUT)
