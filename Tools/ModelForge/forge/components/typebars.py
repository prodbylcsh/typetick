"""Typebar variants. `Typebar` has its origin on the hinge, the bar runs along
+Z with a nominal length of 0.11 m (the app stretches Z to the real distance
between the segment slot and the printing point) and the slug sits at the tip."""
from __future__ import annotations

from ..geom import Mesh, bezier, combine, cylinder, rect2, round_polygon, rounded_box, sphere, sweep
from ..scene import Part
from ..variant import Variant, rgb

L0 = 0.11


def strip(w, h, z0=0.004, z1=L0 - 0.004, y=0.0, x=0.0, r=0.0003):
    return rounded_box(w, h, z1 - z0, r, band=1, center=(x, y, (z0 + z1) / 2))


def hub(r=0.0026, w=0.0016, role_mesh=None):
    return cylinder(r, w, 20, bevel=0.0003, axis="x")


def slug(w=0.0042, h=0.0062, d=0.0032, r=0.0005):
    return rounded_box(w, h, d, r, band=2, center=(0, 0, L0 - d / 2))


def rect_section(w, h):
    return [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]


def part(meshes):
    p = Part("Typebar")
    for name, m, role in meshes:
        p.mesh(name, m, role)
    return [p]


def slim_steel():
    return part([("Bar", strip(0.0010, 0.0028), "steel"), ("Hub", hub(), "steel"), ("Slug", slug(), "steel")])


def heavy_forged():
    bar = strip(0.0018, 0.0044, r=0.0005)
    return part([("Bar", bar, "blackSteel"), ("Hub", hub(0.0036, 0.0024), "blackSteel"),
                 ("Slug", slug(0.0048, 0.0070, 0.0040), "steel")])


def skeleton():
    m = Mesh()
    m.merge(strip(0.0010, 0.0008, y=0.0014))
    m.merge(strip(0.0010, 0.0008, y=-0.0014))
    import math
    n = 9
    for i in range(n):
        z = 0.008 + (L0 - 0.016) * i / (n - 1)
        web = rounded_box(0.0010, 0.0030, 0.0008, 0.0, center=(0, 0, z))
        m.merge(web)
    return part([("Bar", m, "steel"), ("Hub", hub(0.0028), "steel"), ("Slug", slug(), "steel")])


def brass_bar():
    path = [(0.0, 0.0, 0.003 + (L0 - 0.007) * i / 12) for i in range(13)]
    bar = sweep(path, lambda t: 1.0 - 0.35 * t, cap=True, section=rect_section(0.0014, 0.0036))
    return part([("Bar", bar, "brass"), ("Hub", hub(0.003, 0.002), "brass"), ("Slug", slug(), "brass")])


def swan_neck():
    path = bezier([(0, 0, 0.003), (0, -0.010, 0.045), (0, 0.012, 0.080), (0, 0.0, L0 - 0.003)], 24)
    bar = sweep(path, 1.0, cap=True, section=rect_section(0.0011, 0.0030))
    return part([("Bar", bar, "steel"), ("Hub", hub(0.0028), "steel"), ("Slug", slug(0.0044, 0.0060, 0.0036), "chrome")])


def twin_rail():
    m = Mesh()
    m.merge(strip(0.0007, 0.0030, x=-0.0011))
    m.merge(strip(0.0007, 0.0030, x=0.0011))
    for z in (0.03, 0.06, 0.09):
        m.merge(rounded_box(0.0029, 0.0012, 0.0012, 0.0, center=(0, 0, z)))
    return part([("Bar", m, "steel"), ("Hub", hub(0.0029, 0.0034), "blackSteel"), ("Slug", slug(0.0046), "steel")])


def short_black():
    bar = strip(0.0014, 0.0034, r=0.0004)
    knuckle = rounded_box(0.0026, 0.007, 0.012, 0.001, center=(0, 0.0015, 0.008))
    return part([("Bar", bar, "blackSteel"), ("Knuckle", knuckle, "blackSteel"),
                 ("Hub", hub(0.0032, 0.0028), "brass"), ("Slug", slug(0.0040, 0.0058, 0.0030), "blackSteel")])


def chrome_long():
    path = [(0.0, 0.0, 0.003 + (L0 - 0.008) * i / 10) for i in range(11)]
    bar = sweep(path, 0.0011, 12)
    ball = sphere(0.0030, 20, 10)
    return part([("Bar", bar, "chrome"), ("Hub", ball, "chrome"), ("Slug", slug(0.0040, 0.0060, 0.0034, 0.0012), "chrome")])


VARIANTS = [
    Variant("slim_steel", "Slim Steel", "Classic",
            "Thin stamped steel bars. Quick swing and a clean, sharp strike.",
            slim_steel, mechanics=dict(swingTime=0.034, returnTime=0.07, impactForce=0.75),
            sound=dict(pitch=1.0, body=0.5, brightness=0.7, decay=1.0, ring=0.25),
            animation=dict(speed=1.0, overshoot=0.06)),
    Variant("heavy_forged", "Heavy Forged", "Industrial",
            "Fat forged bars with a deep slug. Slower, but they hit like a hammer and emboss soft paper.",
            heavy_forged, mechanics=dict(swingTime=0.046, returnTime=0.09, impactForce=1.0),
            sound=dict(pitch=0.75, body=0.95, brightness=0.55, decay=1.1, ring=0.2),
            animation=dict(speed=0.85, overshoot=0.03)),
    Variant("skeleton", "Skeleton", "Racing",
            "Lightened, perforated bars for speed typists. Fastest swing, papery snap.",
            skeleton, mechanics=dict(swingTime=0.026, returnTime=0.055, impactForce=0.6),
            sound=dict(pitch=1.25, body=0.3, brightness=0.85, decay=0.8, ring=0.3),
            animation=dict(speed=1.2, overshoot=0.1)),
    Variant("brass_bar", "Brass Taper", "Victorian",
            "Tapered solid brass bars. Rich ringing strike with a long tail.",
            brass_bar, mechanics=dict(swingTime=0.040, returnTime=0.08, impactForce=0.85),
            sound=dict(pitch=0.9, body=0.6, brightness=0.8, decay=1.4, ring=0.8),
            animation=dict(speed=0.95, overshoot=0.08)),
    Variant("swan_neck", "Swan Neck", "1930s",
            "S-curved bars that clear a deeper basket. Smooth arc and a soft-edged strike.",
            swan_neck, mechanics=dict(swingTime=0.038, returnTime=0.075, impactForce=0.7),
            sound=dict(pitch=0.95, body=0.55, brightness=0.6, decay=1.0, ring=0.35),
            animation=dict(speed=1.0, overshoot=0.12)),
    Variant("twin_rail", "Twin Rail", "Precision",
            "Double rails with cross ties: no twisting, perfectly aligned type.",
            twin_rail, mechanics=dict(swingTime=0.036, returnTime=0.07, impactForce=0.8, alignmentJitter=0.25),
            sound=dict(pitch=1.05, body=0.6, brightness=0.65, decay=0.9, ring=0.15),
            animation=dict(speed=1.0, overshoot=0.04)),
    Variant("short_black", "Blackened Knuckle", "Wartime",
            "Blackened bars with a heavy knuckle at the hinge. Gritty, loose, noticeable misalignment.",
            short_black, mechanics=dict(swingTime=0.042, returnTime=0.085, impactForce=0.9, alignmentJitter=1.8),
            sound=dict(pitch=0.85, body=0.8, brightness=0.5, decay=0.9, ring=0.1),
            animation=dict(speed=0.9, overshoot=0.15)),
    Variant("chrome_long", "Chrome Rod", "Streamline",
            "Polished round rods on ball hinges. Reflective, light and bright sounding.",
            chrome_long, mechanics=dict(swingTime=0.032, returnTime=0.065, impactForce=0.7),
            sound=dict(pitch=1.15, body=0.4, brightness=0.9, decay=1.1, ring=0.55),
            animation=dict(speed=1.1, overshoot=0.09)),
]
