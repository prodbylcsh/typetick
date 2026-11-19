"""Paper bail + paper release lever variants (carriage relative).

`pivot_Bail` hinges behind the platen; rotating it negatively about X lifts
the rollers off the paper. Nominal width 0.24 m, the app scales X to the
platen length. `pivot_ReleaseLever` opens the feed rollers for inserting and
straightening paper."""
from __future__ import annotations

import math

from ..geom import Mesh, bezier, cylinder, lathe, rounded_box, sweep
from ..scene import Part
from ..variant import Variant, rgb

W = 0.24
HINGE = (0.0, -0.004, -0.026)


def rod_pos(r_platen=0.0165, angle=21.0, gap=0.0055):
    a = math.radians(angle)
    rr = r_platen + gap
    return (rr * math.sin(a) - HINGE[1], rr * math.cos(a) - HINGE[2])  # relative to hinge (y, z)


def arms(y, z, role="chrome", r=0.0016):
    m = Mesh()
    for s in (-1, 1):
        x = s * (W / 2 + 0.002)
        path = bezier([(x, 0.0, 0.0), (x, 0.03, 0.006), (x, y + 0.012, z - 0.004), (x, y, z)], 20)
        m.merge(sweep(path, r, 10))
        m.merge(cylinder(0.003, 0.004, 16, center=(x, 0, 0), axis="x"))
    return m


def release_lever(role="chrome", tip="bakelite", shape="ball"):
    p = Part("pivot_ReleaseLever")
    p.mesh("Stalk", sweep([(0, 0, 0), (0, 0.012, -0.004), (0, 0.026, -0.006)], 0.0018, 10), role)
    if shape == "ball":
        from ..geom import sphere
        p.mesh("Tip", sphere(0.0042, 20, 10).translate(0, 0.028, -0.006), tip)
    else:
        p.mesh("Tip", rounded_box(0.006, 0.012, 0.004, 0.0015, center=(0, 0.028, -0.006)), tip)
    return p


def bail(meshes, lever):
    p = Part("pivot_Bail", translate=HINGE)
    for n, m, role in meshes:
        p.mesh(n, m, role)
    return [p, lever]


def rollers(y, z, count, radius=0.0035, width=0.012, role="rubber"):
    m = Mesh()
    for i in range(count):
        x = -W * 0.36 + (W * 0.72) * (i / max(count - 1, 1)) if count > 1 else 0.0
        m.merge(cylinder(radius, width, 28, bevel=0.0008, center=(x, y, z), axis="x"))
    return m


def roller_bail():
    y, z = rod_pos()
    return bail([("Rod", cylinder(0.0018, W, 20, center=(0, y, z), axis="x"), "chrome"),
                 ("Rollers", rollers(y, z, 3), "rubber"), ("Arms", arms(y, z), "chrome")], release_lever())


def wire_bail():
    y, z = rod_pos(gap=0.0022)
    return bail([("Rod", cylinder(0.0011, W, 12, center=(0, y, z), axis="x"), "steel"),
                 ("Arms", arms(y, z, "steel", 0.0011), "steel")], release_lever("steel", "steel", "flat"))


def scale_plate():
    y, z = rod_pos(gap=0.004)
    plate = rounded_box(W * 0.9, 0.012, 0.0012, 0.0005, center=(0, y + 0.004, z + 0.001))
    plate.rotate_x(0)
    ticks = Mesh()
    for i in range(0, 86, 5):
        x = -W * 0.45 + W * 0.9 * i / 85
        ticks.merge(rounded_box(0.0003, 0.004 if i % 10 == 0 else 0.0025, 0.0003, 0.0, center=(x, y + 0.008, z + 0.0018)))
    return bail([("Plate", plate, "glass"), ("Ticks", ticks, "paintAccent"),
                 ("Rollers", rollers(y - 0.002, z, 2, 0.003), "rubber"), ("Arms", arms(y, z), "chrome")],
                release_lever())


def double_rod():
    y, z = rod_pos()
    rods = Mesh()
    rods.merge(cylinder(0.0016, W, 16, center=(0, y, z), axis="x"))
    rods.merge(cylinder(0.0016, W, 16, center=(0, y + 0.007, z - 0.004), axis="x"))
    return bail([("Rods", rods, "chrome"), ("Rollers", rollers(y, z, 4, 0.003, 0.008), "rubber"),
                 ("Arms", arms(y, z), "chrome")], release_lever("chrome", "chrome"))


def wide_rollers():
    y, z = rod_pos(gap=0.0065)
    return bail([("Rod", cylinder(0.0022, W, 20, center=(0, y, z), axis="x"), "chrome"),
                 ("Rollers", rollers(y, z, 2, 0.0045, 0.03), "rubber"), ("Arms", arms(y, z, r=0.002), "chrome")],
                release_lever("chrome", "paint", "flat"))


def finger_hooks():
    y, z = rod_pos(gap=0.003)
    fingers = Mesh()
    for s in (-1, 1):
        x = s * W * 0.38
        fingers.merge(sweep(bezier([(x, 0.0, 0.0), (x, 0.032, 0.008), (x, y + 0.004, z + 0.002), (x, y - 0.004, z)], 16), 0.0014, 8))
        fingers.merge(cylinder(0.0028, 0.008, 18, center=(x, y - 0.002, z), axis="x"))
    return bail([("Fingers", fingers, "steel")], release_lever("steel", "darkPlastic", "flat"))


def brass_bail():
    y, z = rod_pos()
    return bail([("Rod", cylinder(0.0019, W, 20, center=(0, y, z), axis="x"), "brass"),
                 ("Rollers", rollers(y, z, 4, 0.0034, 0.009), "brass"), ("Arms", arms(y, z, "brass"), "brass")],
                release_lever("brass", "wood"))


def shield():
    y, z = rod_pos(gap=0.0045)
    bar = rounded_box(W, 0.008, 0.003, 0.0014, center=(0, y + 0.003, z + 0.002))
    return bail([("Shield", bar, "darkPlastic"), ("Rollers", rollers(y - 0.001, z, 3, 0.0032), "rubber"),
                 ("Arms", arms(y, z, "darkPlastic", 0.0019), "darkPlastic")], release_lever("darkPlastic", "darkPlastic", "flat"))


def m(lift=35.0, rollers_=3, pressure=0.6, release=40.0):
    return dict(bailLiftDegrees=lift, rollerCount=rollers_, pressure=pressure, releaseLeverDegrees=release,
                hinge=list(HINGE), nominalWidth=W)


VARIANTS = [
    Variant("roller_bail", "Roller Bail", "Classic", "Chrome rod with three rubber rollers.", roller_bail, mechanics=m(),
            sound=dict(pitch=1.0, body=0.5, brightness=0.7, decay=1.0, ring=0.3)),
    Variant("wire_bail", "Wire Bail", "1910s", "A single sprung wire. Snaps back with a twang.", wire_bail,
            mechanics=m(40, 0, 0.4), sound=dict(pitch=1.4, body=0.2, brightness=1.0, decay=1.4, ring=0.9)),
    Variant("scale_plate", "Scale Plate", "1960s", "Clear celluloid plate with a column scale.", scale_plate,
            mechanics=m(32, 2, 0.5), sound=dict(pitch=1.1, body=0.4, brightness=0.5, decay=0.7, ring=0.1)),
    Variant("double_rod", "Double Rod", "Office", "Two rods and four small rollers hold heavy card stock flat.", double_rod,
            mechanics=m(30, 4, 0.85), sound=dict(pitch=0.9, body=0.6, brightness=0.7, decay=1.0, ring=0.35)),
    Variant("wide_rollers", "Wide Rollers", "1950s", "Two wide rubber drums. Quiet and grippy.", wide_rollers,
            mechanics=m(33, 2, 0.7), sound=dict(pitch=0.85, body=0.6, brightness=0.4, decay=0.7, ring=0.1)),
    Variant("finger_hooks", "Paper Fingers", "Minimal", "Two sprung fingers instead of a bail bar.", finger_hooks,
            mechanics=m(45, 2, 0.35), sound=dict(pitch=1.2, body=0.3, brightness=0.8, decay=1.0, ring=0.5)),
    Variant("brass_bail", "Brass Bail", "Victorian", "Brass rod and brass wheels.", brass_bail,
            mechanics=m(35, 4, 0.65), sound=dict(pitch=0.95, body=0.55, brightness=0.85, decay=1.3, ring=0.7)),
    Variant("shield", "Paper Shield", "1980s", "Plastic shield bar with rollers underneath.", shield,
            mechanics=m(28, 3, 0.6), sound=dict(pitch=1.15, body=0.4, brightness=0.45, decay=0.5, ring=0.0)),
]
for _v in VARIANTS:
    _v.animation = dict(speed=1.0, overshoot=0.08)
