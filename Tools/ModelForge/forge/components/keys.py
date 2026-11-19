"""Keycap variants. Each file holds a `Key` (instanced for every key, its
`Top` mesh carries 0..1 UVs for the legend) and a `SpaceBar`."""
from __future__ import annotations

from ..geom import (circle2, combine, cylinder, disc_top, extrude, lathe, rect2, regular2, round_polygon,
                    rounded_box, sweep, torus)
from ..scene import Part
from ..variant import Variant, rgb

STEM_DEPTH = 0.034


def stem(r=0.0011, top=-0.004, role="steel"):
    return cylinder(r, STEM_DEPTH, 12, center=(0, top - STEM_DEPTH / 2, 0))


def flat_extrude_y(outline, height, y_top):
    """Prism with an XZ outline from y_top-height to y_top."""
    m = extrude(outline, height)
    m.map(lambda p: (p[0], p[2], p[1]))
    m.flip()
    return m.translate(0, y_top - height / 2, 0)


def spacebar_simple(length=0.17, role="keyBody", h=0.007, d=0.011, r=0.003, arm_role="steel"):
    sb = Part("SpaceBar")
    sb.mesh("Bar", rounded_box(length, h, d, r, center=(0, -h / 2, 0)), role)
    for x in (-length / 2 + 0.02, length / 2 - 0.02):
        arm = sweep([(x, -h, 0.0), (x, -h - 0.006, -0.008), (x, -h - 0.012, -0.03)], 0.0012, 10)
        sb.mesh("Arm", arm, arm_role)
    return sb


# ---------------------------------------------------------------------------

def glass_ring():
    k = Part("Key")
    k.mesh("Ring", torus(0.0071, 0.0011, 40, 12).translate(0, -0.0006, 0), "chrome")
    skirt = lathe([(0.0, -0.0042), (0.0068, -0.0042), (0.0072, -0.0016), (0.0, -0.0016)], 40)
    k.mesh("Skirt", skirt, "chrome")
    k.mesh("Top", disc_top(0.0066, -0.0004, 40, dome=0.0007), "keyTop")
    k.mesh("Stem", stem(), "steel")
    sb = spacebar_simple(0.175, "chrome", h=0.005, d=0.009, r=0.0024)
    return [k, sb]


def bakelite_round():
    k = Part("Key")
    body = lathe([(0.0, -0.0075), (0.0070, -0.0075), (0.0074, -0.0068), (0.0074, -0.0010),
                  (0.0071, -0.0002), (0.0066, 0.0)], 40, cap_end=False)
    k.mesh("Cap", body, "keyBody")
    k.mesh("Top", disc_top(0.0066, 0.0, 40, dome=-0.0006), "keyTop")
    k.mesh("Stem", stem(top=-0.0075), "steel")
    return [k, spacebar_simple(0.17, "keyBody", h=0.008, d=0.012, r=0.0035)]


def chiclet_square():
    k = Part("Key")
    k.mesh("Cap", rounded_box(0.0148, 0.0055, 0.0148, 0.0018, center=(0, -0.0029, 0)), "keyBody")
    shape = [(x / 0.0074, z / 0.0074) for (x, z) in round_polygon(rect2(0.0136, 0.0136), 0.0016, 4)]
    k.mesh("Top", disc_top(0.0074 * 0.92, 0.00005, dome=0.0, shape=shape, rings=4), "keyTop")
    k.mesh("Stem", stem(top=-0.0055), "steel")
    return [k, spacebar_simple(0.19, "keyBody", h=0.0055, d=0.0148, r=0.0018)]


def tombstone_scoop():
    k = Part("Key")
    outline = [(-0.0068, -0.0072), (0.0068, -0.0072), (0.0068, 0.0025)]
    import math
    for i in range(1, 12):
        a = math.radians(180 * i / 12)
        outline.append((0.0068 * math.cos(a), 0.0025 + 0.0048 * math.sin(a)))
    outline.append((-0.0068, 0.0025))
    outline = [(x, -z) for (x, z) in outline]  # tombstone rounded toward the back (-Z)
    k.mesh("Cap", flat_extrude_y(round_polygon(outline, 0.0012, 3), 0.0085, -0.0003), "keyBody")
    shape = [(x / 0.0076, z / 0.0076) for (x, z) in round_polygon(outline, 0.0012, 3)]
    k.mesh("Top", disc_top(0.0076 * 0.88, 0.0, dome=-0.0005, shape=shape, rings=5), "keyTop")
    k.mesh("Stem", stem(top=-0.0088), "steel")
    sb = Part("SpaceBar")
    bar = rounded_box(0.18, 0.009, 0.012, 0.004, center=(0, -0.0045, 0))
    sb.mesh("Bar", bar, "keyBody")
    sb.mesh("Scoop", rounded_box(0.17, 0.001, 0.008, 0.0005, center=(0, 0.0002, 0)), "keyTop")
    return [k, sb]


def hex_brass():
    k = Part("Key")
    hexo = regular2(0.0076, 6, 0)
    k.mesh("Rim", flat_extrude_y(hexo, 0.0055, 0.0004), "brass")
    inner = [(x / 0.0076, z / 0.0076) for (x, z) in regular2(0.0076, 6, 0)]
    k.mesh("Top", disc_top(0.0064, 0.0006, dome=0.0, shape=inner, rings=4), "keyTop")
    k.mesh("Stem", stem(top=-0.0052, role="brass"), "brass")
    sb = Part("SpaceBar")
    sb.mesh("Bar", rounded_box(0.172, 0.006, 0.010, 0.0015, center=(0, -0.003, 0)), "brass")
    sb.mesh("Inlay", rounded_box(0.165, 0.001, 0.006, 0.0004, center=(0, 0.0003, 0)), "keyTop")
    return [k, sb]


def disc_flat():
    k = Part("Key")
    k.mesh("Disc", lathe([(0.0, -0.0016), (0.0072, -0.0016), (0.0075, -0.0010), (0.0075, -0.0004),
                          (0.0071, 0.0)], 40, cap_end=False), "steel")
    k.mesh("Top", disc_top(0.0071, 0.0, 40, dome=0.0), "keyTop")
    k.mesh("Stem", cylinder(0.0016, STEM_DEPTH + 0.004, 16, center=(0, -0.0016 - (STEM_DEPTH + 0.004) / 2, 0)), "chrome")
    k.mesh("Collar", cylinder(0.0024, 0.0014, 16, center=(0, -0.0045, 0)), "chrome")
    sb = Part("SpaceBar")
    sb.mesh("Bar", cylinder(0.0035, 0.18, 24, center=(0, -0.0035, 0), axis="x"), "chrome")
    for x in (-0.07, 0.07):
        sb.mesh("Post", cylinder(0.0013, 0.03, 10, center=(x, -0.02, 0)), "chrome")
    return [k, sb]


def sculpted_dish():
    k = Part("Key")
    body = lathe([(0.0, -0.0095), (0.0080, -0.0095), (0.0078, -0.0060), (0.0068, -0.0006),
                  (0.0064, 0.0)], 40, cap_end=False)
    k.mesh("Cap", body, "keyBody")
    k.mesh("Top", disc_top(0.0064, 0.0, 40, dome=-0.0012, rings=8), "keyTop")
    k.mesh("Stem", stem(top=-0.0095), "steel")
    sb = Part("SpaceBar")
    prof = round_polygon([(-0.092, -0.010), (0.092, -0.010), (0.088, 0.0), (-0.088, 0.0)], 0.002, 3)
    bar = extrude(prof, 0.014)
    sb.mesh("Bar", bar, "keyBody")
    return [k, sb]


def pill_soft():
    k = Part("Key")
    import math
    outline = []
    for i in range(24):
        a = 2 * math.pi * i / 24
        outline.append((0.0080 * math.cos(a), 0.0062 * math.sin(a)))
    k.mesh("Cap", flat_extrude_y(round_polygon(outline, 0.0, 1), 0.0062, -0.0004), "keyBody")
    shape = [(x / 0.0080, z / 0.0080) for (x, z) in outline]
    k.mesh("Top", disc_top(0.0080 * 0.9, -0.0003, dome=0.0004, shape=shape, rings=5), "keyTop")
    k.mesh("Stem", stem(top=-0.0065), "darkPlastic")
    return [k, spacebar_simple(0.2, "keyBody", h=0.0062, d=0.0124, r=0.0031, arm_role="darkPlastic")]


VARIANTS = [
    Variant("glass_ring", "Glass Ring", "1920s",
            "Chrome rimmed keys with domed glass legends on long levers. Deep travel, bright ting on release.",
            glass_ring, mechanics=dict(travel=0.0105, tilt=7.0, legend="engraved"),
            sound=dict(pitch=1.2, body=0.3, brightness=0.85, decay=0.9, ring=0.6),
            animation=dict(speed=0.9, travel=1.0, overshoot=0.18),
            palette=dict(keyTop=rgb("#0b0b0c")), tags=["glass", "ring"]),
    Variant("bakelite_round", "Bakelite Round", "1940s",
            "Thick dished bakelite buttons. Warm, woody click.",
            bakelite_round, mechanics=dict(travel=0.0090, tilt=5.0, legend="printed"),
            sound=dict(pitch=0.9, body=0.7, brightness=0.45, decay=0.8, ring=0.05),
            animation=dict(speed=1.0, travel=1.0, overshoot=0.08),
            palette=dict(keyBody=rgb("#1d1612"), keyTop=rgb("#1d1612")), tags=["bakelite"]),
    Variant("chiclet_square", "Chiclet Square", "1970s",
            "Low square plastic caps with a short, crisp travel.",
            chiclet_square, mechanics=dict(travel=0.0060, tilt=2.0, legend="printed"),
            sound=dict(pitch=1.4, body=0.35, brightness=0.6, decay=0.6, ring=0.0),
            animation=dict(speed=1.25, travel=1.0, overshoot=0.04),
            palette=dict(keyBody=rgb("#e7e1d3"), keyTop=rgb("#efe9dc")), tags=["plastic", "square"]),
    Variant("tombstone_scoop", "Tombstone Scoop", "1960s",
            "Tall tombstone keys with a cylindrical scoop. Long, damped stroke.",
            tombstone_scoop, mechanics=dict(travel=0.0085, tilt=4.0, legend="printed"),
            sound=dict(pitch=0.85, body=0.8, brightness=0.4, decay=0.7, ring=0.0),
            animation=dict(speed=0.95, travel=1.0, overshoot=0.05),
            palette=dict(keyBody=rgb("#3b3a37"), keyTop=rgb("#3b3a37")), tags=["sculpted"]),
    Variant("hex_brass", "Hex Brass", "Steampunk",
            "Hexagonal brass bezels around enamel legends. Metallic chink on every press.",
            hex_brass, mechanics=dict(travel=0.0095, tilt=6.0, legend="enamel"),
            sound=dict(pitch=1.1, body=0.4, brightness=0.9, decay=1.1, ring=0.75),
            animation=dict(speed=0.9, travel=1.0, overshoot=0.15),
            palette=dict(keyTop=rgb("#efe7d2")), tags=["brass", "hex"]),
    Variant("disc_flat", "Steel Disc", "1910s",
            "Thin steel discs on exposed chrome stems with collars. Clattery, very long throw.",
            disc_flat, mechanics=dict(travel=0.0120, tilt=9.0, legend="stamped"),
            sound=dict(pitch=1.3, body=0.2, brightness=1.0, decay=1.2, ring=0.8),
            animation=dict(speed=0.85, travel=1.0, overshoot=0.22),
            palette=dict(keyTop=rgb("#101010")), tags=["steel", "exposed"]),
    Variant("sculpted_dish", "Sculpted Dish", "1980s",
            "Tapered caps with a spherical dish. Soft landing, muted thock.",
            sculpted_dish, mechanics=dict(travel=0.0070, tilt=3.0, legend="doubleshot"),
            sound=dict(pitch=0.75, body=0.85, brightness=0.3, decay=0.6, ring=0.0),
            animation=dict(speed=1.1, travel=1.0, overshoot=0.03),
            palette=dict(keyBody=rgb("#26272a"), keyTop=rgb("#26272a")), tags=["dish"]),
    Variant("pill_soft", "Pill Soft", "1990s",
            "Wide elliptical pills in soft-touch plastic. Quiet and springy.",
            pill_soft, mechanics=dict(travel=0.0065, tilt=2.5, legend="printed"),
            sound=dict(pitch=1.0, body=0.5, brightness=0.35, decay=0.5, ring=0.0),
            animation=dict(speed=1.2, travel=1.0, overshoot=0.1),
            palette=dict(keyBody=rgb("#d9cfc0"), keyTop=rgb("#e6ddcf")), tags=["soft touch"]),
]
