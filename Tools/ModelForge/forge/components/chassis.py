"""Chassis / frame variants: the body that carries everything else."""
from __future__ import annotations

import math

from ..geom import (Mesh, annulus_sector, circle2, combine, cylinder, extrude_x, lathe, rect2,
                    round_polygon, rounded_box, sphere, torus)
from ..layout import BASKET, chassis_mechanics
from ..scene import Part
from ..variant import Variant, rgb


def side_profile(front_z, back_z, apron_h, tower_h, deck_y=0.064, slope_to=0.07, rounding=0.012):
    pts = [(front_z, 0.0), (front_z, apron_h), (slope_to, deck_y - 0.002), (-0.022, deck_y),
           (-0.042, tower_h), (back_z, tower_h), (back_z, 0.0)]
    return round_polygon(pts, rounding, 4)


def shell(width, *, front_z=0.196, back_z=-0.165, apron_h=0.032, tower_h=0.104, wall=0.012,
          rounding=0.012, deck_y=0.064, body_role="paint", back_role="paint", holes=None,
          back_radius=0.008, profile=None):
    """Common open-frame body: two side cheeks, back housing, apron, floor."""
    body = Part("Body")
    prof = profile or side_profile(front_z, back_z, apron_h, tower_h, deck_y, rounding=rounding)
    for side in (-1, 1):
        m = extrude_x(prof, wall)
        if holes:
            from ..geom import extrude as ex
            m = ex([(z, y) for (z, y) in prof], wall, holes=holes)
            m.map(lambda p: (p[2], p[1], p[0]))
            m.flip()
        m.translate(side * (width / 2 - wall / 2), 0, 0)
        body.mesh("Cheek" + ("R" if side > 0 else "L"), m, body_role)
    depth = (-0.040) - back_z
    body.mesh("BackHousing", rounded_box(width - 2 * wall + 0.002, tower_h - 0.004, depth, back_radius,
                                         center=(0, (tower_h - 0.004) / 2, back_z + depth / 2)), back_role)
    body.mesh("Apron", rounded_box(width - 2 * wall + 0.002, apron_h, 0.010, 0.003,
                                   center=(0, apron_h / 2, front_z - 0.005)), body_role)
    body.mesh("Floor", rounded_box(width - 0.004, 0.006, front_z - back_z - 0.004, 0.002,
                                   center=(0, 0.003, (front_z + back_z) / 2)), "blackSteel")
    body.mesh("Well", rounded_box(width - 2 * wall, 0.002, 0.20, 0.0,
                                  center=(0, 0.0072, 0.07)), "felt")
    return body


def segment_part(role="blackSteel", thickness=0.010):
    c = BASKET["center"]
    r = BASKET["radius"]
    seg = Part("Segment", translate=(c[0], c[1] - 0.006, c[2]))
    seg.mesh("Arc", annulus_sector(r - 0.007, r + 0.007, thickness, -82, 82, 40), role)
    # slotted comb on top of the arc, one tooth per typebar
    teeth = Mesh()
    for i in range(46):
        a = math.radians(-78 + 156 * i / 45)
        t = rounded_box(0.0012, 0.004, 0.012, 0.0, center=(r * math.sin(a), thickness / 2 + 0.002, r * math.cos(a)))
        t.rotate_y(0)
        teeth.merge(t)
    seg.mesh("Comb", teeth, role)
    return seg


def rails(width, role="steel", y=0.112, z=-0.090):
    p = Part("Rails")
    for dz in (-0.018, 0.018):
        p.mesh(f"Rail{'F' if dz > 0 else 'B'}", cylinder(0.0035, width + 0.06, 24, center=(0, y, z + dz), axis="x"), role)
    return p


def feet(width, front_z=0.18, back_z=-0.15, role="rubber", r=0.012, h=0.008, shape="round"):
    f = Part("Feet")
    for x in (-width / 2 + 0.03, width / 2 - 0.03):
        for z in (front_z, back_z):
            if shape == "round":
                m = cylinder(r, h, 24, bevel=0.002, center=(x, -h / 2 + 0.001, z))
            else:
                m = rounded_box(r * 2.2, h, r * 1.6, 0.002, center=(x, -h / 2 + 0.001, z))
            f.mesh("Foot", m, role)
    return f


def bolts(points, role="steel", r=0.0035, axis="z"):
    m = Mesh()
    for (x, y, z) in points:
        b = lathe([(0.0, 0.0), (r, 0.0), (r, 0.0012), (r * 0.7, 0.0024), (0.0, 0.0028)], 16)
        if axis == "z":
            b.rotate_x(90)
        elif axis == "x":
            b.rotate_z(-90)
        b.translate(x, y, z)
        m.merge(b)
    return m


# ---------------------------------------------------------------------------

def atlas_upright():
    W = 0.37
    holes = [round_polygon(rect2(0.11, 0.035, -0.095, 0.05), 0.012, 4),
             round_polygon(rect2(0.05, 0.03, 0.05, 0.028), 0.01, 4)]
    body = shell(W, front_z=0.198, apron_h=0.036, tower_h=0.108, holes=holes, rounding=0.016)
    # gold pinstripes around the apron and back housing
    stripes = Mesh()
    stripes.merge(rounded_box(W - 0.03, 0.0012, 0.0012, 0.0, center=(0, 0.027, 0.2035)))
    stripes.merge(rounded_box(W - 0.03, 0.0012, 0.0012, 0.0, center=(0, 0.007, 0.2035)))
    stripes.merge(rounded_box(W - 0.03, 0.0012, 0.0012, 0.0, center=(0, 0.098, -0.0395)))
    body.mesh("Pinstripe", stripes, "paintAccent")
    plate = rounded_box(0.09, 0.022, 0.003, 0.004, center=(0, 0.07, -0.039))
    body.mesh("Nameplate", plate, "paintAccent")
    parts = [body, segment_part(), rails(W), feet(W, r=0.013, h=0.012)]
    return parts


def courier_portable():
    W = 0.35
    prof = round_polygon([(0.196, 0.0), (0.196, 0.026), (0.08, 0.058), (-0.022, 0.062), (-0.05, 0.102),
                          (-0.165, 0.098), (-0.172, 0.0)], 0.03, 6)
    body = shell(W, profile=prof, back_role="paintSecond", back_radius=0.022, wall=0.014)
    band = rounded_box(W + 0.002, 0.006, 0.004, 0.002, center=(0, 0.018, 0.199))
    body.mesh("ChromeBand", band, "chrome")
    for side in (-1, 1):
        body.mesh("SideBand" + ("R" if side > 0 else "L"),
                  rounded_box(0.003, 0.006, 0.30, 0.0015, center=(side * (W / 2 + 0.0005), 0.018, 0.02)), "chrome")
    return [body, segment_part(), rails(W, "chrome"), feet(W, r=0.010, h=0.006)]


def bureau_standard():
    W = 0.43
    body = shell(W, front_z=0.2, apron_h=0.04, tower_h=0.106, wall=0.02, rounding=0.008, back_radius=0.006)
    lid = rounded_box(W - 0.04, 0.012, 0.075, 0.006, center=(0, 0.108, -0.085))
    lid.rotate_x(0)
    body.mesh("Lid", lid, "paintSecond")
    for side in (-1, 1):
        body.mesh("Grille" + ("R" if side > 0 else "L"),
                  combine(rounded_box(0.0015, 0.004, 0.08, 0.001, center=(side * (W / 2 + 0.0004), 0.02 + i * 0.008, -0.08))
                          for i in range(8)), "darkPlastic")
    return [body, segment_part(), rails(W), feet(W, r=0.016, h=0.010, shape="block")]


def deco_imperial():
    W = 0.38
    body = shell(W, tower_h=0.100, rounding=0.01, back_radius=0.004)
    tiers = Mesh()
    for i, (w, h, d) in enumerate([(W - 0.03, 0.010, 0.115), (W - 0.08, 0.006, 0.10), (W - 0.14, 0.004, 0.085)]):
        tiers.merge(rounded_box(w, h, d, 0.002, center=(0, 0.100 + sum([0.010, 0.006, 0.004][:i]) + h / 2, -0.10)))
    body.mesh("Tiers", tiers, "paint")
    fins = Mesh()
    for side in (-1, 1):
        for i in range(3):
            fins.merge(rounded_box(0.004, 0.040 - i * 0.008, 0.012, 0.0018,
                                   center=(side * (W / 2 + 0.002), 0.03, 0.06 - i * 0.03)))
    body.mesh("Fins", fins, "chrome")
    medal = lathe([(0.0, 0.0), (0.016, 0.0), (0.016, 0.002), (0.012, 0.004), (0.0, 0.0045)], 40)
    medal.rotate_x(90).translate(0, 0.022, 0.2015)
    body.mesh("Medallion", medal, "chrome")
    body.mesh("Bands", combine(rounded_box(W + 0.001, 0.0025, 0.0025, 0.001, center=(0, y, 0.2005)) for y in (0.008, 0.032)), "chrome")
    return [body, segment_part(), rails(W, "chrome"), feet(W, r=0.014, h=0.008)]


def orbit_70():
    W = 0.40
    prof = round_polygon([(0.205, 0.0), (0.205, 0.022), (0.06, 0.060), (-0.022, 0.066), (-0.050, 0.104),
                          (-0.175, 0.090), (-0.175, 0.0)], 0.018, 5)
    body = shell(W, profile=prof, back_role="darkPlastic", back_radius=0.015, wall=0.016)
    visor = rounded_box(W - 0.05, 0.004, 0.06, 0.002, center=(0, 0.103, -0.075))
    visor.rotate_x(-6)
    body.mesh("Visor", visor, "smoked")
    stripe = combine(rounded_box(0.004, 0.022, 0.30, 0.002, center=(s * (W / 2 + 0.0005), 0.02, 0.02)) for s in (-1, 1))
    body.mesh("RacingStripe", stripe, "paintSecond")
    return [body, segment_part("darkPlastic"), rails(W), feet(W, r=0.011, h=0.004)]


def foundry_industrial():
    W = 0.39
    body = shell(W, tower_h=0.108, rounding=0.004, wall=0.014, back_radius=0.002)
    pts = []
    for z in (0.17, 0.10, 0.02, -0.06, -0.14):
        for side in (-1, 1):
            pts.append((side * (W / 2 + 0.0001), 0.012 if z > 0.0 else 0.02, z))
    body.mesh("Bolts", bolts(pts, "steel", axis="x"), "steel")
    front_bolts = [(x, 0.016, 0.2015) for x in (-0.16, -0.08, 0.0, 0.08, 0.16)]
    body.mesh("FrontBolts", bolts(front_bolts, axis="z"), "steel")
    body.mesh("Plate", rounded_box(0.1, 0.026, 0.002, 0.002, center=(0, 0.072, -0.0392)), "brass")
    body.mesh("Plate2", rounded_box(W - 0.02, 0.003, 0.004, 0.0, center=(0, 0.034, 0.199)), "blackSteel")
    return [body, segment_part(), rails(W), feet(W, r=0.015, h=0.006, shape="block")]


def slate_ultraflat():
    W = 0.36
    prof = round_polygon([(0.19, 0.0), (0.19, 0.018), (0.07, 0.044), (-0.022, 0.050), (-0.045, 0.090),
                          (-0.16, 0.090), (-0.16, 0.0)], 0.008, 4)
    body = shell(W, profile=prof, wall=0.010, back_radius=0.003)
    body.mesh("Seam", rounded_box(W + 0.0005, 0.0008, 0.36, 0.0, center=(0, 0.009, 0.015)), "chrome")
    return [body, segment_part(), rails(W, y=0.098), feet(W, r=0.008, h=0.003)]


def bauhaus_cylinder():
    W = 0.38
    body = shell(W, tower_h=0.07, rounding=0.002, back_radius=0.002)
    hood = lathe([(0.0, -0.5), (0.058, -0.5), (0.058, 0.5), (0.0, 0.5)], 48, start_deg=0, sweep_deg=180)
    hood.scale(1.0, (W - 0.024), 1.0)
    hood.rotate_z(90).rotate_x(0)
    hood.map(lambda p: (p[0], p[1], p[2]))
    hood.translate(0, 0.07, -0.10)
    body.mesh("Hood", hood, "paint")
    disc = cylinder(0.022, 0.003, 48, center=(W / 2 + 0.0015, 0.04, 0.08), axis="x")
    body.mesh("Dot", disc, "paintAccent")
    body.mesh("Bar", rounded_box(W, 0.008, 0.008, 0.0, center=(0, 0.004, 0.2)), "paintSecond")
    return [body, segment_part(), rails(W, y=0.108), feet(W, r=0.011, h=0.006, shape="block")]


VARIANTS = [
    Variant("atlas_upright", "Atlas Upright", "1923",
            "Tall open-frame office upright with window cheeks and gold pinstriping. Carriage shift, ringing steel frame.",
            atlas_upright,
            mechanics=chassis_mechanics(shiftType="carriage", shiftTravel=0.0065, frameResonance=0.9,
                                        keyboard=dict(rowRiseY=0.0125, frontY=0.052)),
            sound=dict(pitch=0.85, body=0.8, brightness=0.55, decay=1.3, ring=0.7),
            animation=dict(speed=0.9, travel=1.1, overshoot=0.12),
            palette=dict(paint=rgb("#0c0b0b"), paintAccent=rgb("#c49a4a")), tags=["open frame", "steel"]),
    Variant("courier_portable", "Courier Portable", "1956",
            "Streamlined two-tone portable with chrome belt line. Light, slightly hollow sounding case.",
            courier_portable,
            mechanics=chassis_mechanics(frameResonance=0.4, keyboard=dict(rowRiseY=0.0075)),
            sound=dict(pitch=1.1, body=0.45, brightness=0.7, decay=0.9, ring=0.25),
            animation=dict(speed=1.05, travel=0.95, overshoot=0.08),
            palette=dict(paint=rgb("#7da39a"), paintSecond=rgb("#e9e2cf")), tags=["portable", "two-tone"]),
    Variant("bureau_standard", "Bureau Standard", "1964",
            "Wide office desktop machine. Heavy walls, ventilation grilles, damped thick case.",
            bureau_standard,
            mechanics=chassis_mechanics(frameResonance=0.3, keyboard=dict(keyPitchX=0.0210)),
            sound=dict(pitch=0.8, body=0.9, brightness=0.4, decay=0.8, ring=0.15),
            animation=dict(speed=0.95, travel=1.0, overshoot=0.05),
            palette=dict(paint=rgb("#8c8a83"), paintSecond=rgb("#5b5a55")), tags=["office", "heavy"]),
    Variant("deco_imperial", "Deco Imperial", "1934",
            "Stepped art-deco tiers, chrome fins and a sunburst medallion. Bright metallic voice.",
            deco_imperial,
            mechanics=chassis_mechanics(frameResonance=0.65, keyboard=dict(rowRiseY=0.0105)),
            sound=dict(pitch=1.0, body=0.6, brightness=0.8, decay=1.1, ring=0.55),
            animation=dict(speed=1.0, travel=1.0, overshoot=0.1),
            palette=dict(paint=rgb("#2a1416")), tags=["art deco", "chrome"]),
    Variant("orbit_70", "Orbit 70", "1971",
            "Space-age wedge with a smoked visor and racing stripes. Plastic shell absorbs the clatter.",
            orbit_70,
            mechanics=chassis_mechanics(frameResonance=0.15, keyboard=dict(rowRiseY=0.0070, frontY=0.046)),
            sound=dict(pitch=1.25, body=0.3, brightness=0.6, decay=0.6, ring=0.05),
            animation=dict(speed=1.15, travel=0.85, overshoot=0.04),
            palette=dict(paint=rgb("#d0581c"), paintSecond=rgb("#f2e6c9")), tags=["plastic", "space age"]),
    Variant("foundry_industrial", "Foundry Industrial", "1948",
            "Bolted steel plates, hammertone paint and a brass maker plate. Loud, metallic, unapologetic.",
            foundry_industrial,
            mechanics=chassis_mechanics(frameResonance=0.8, shiftTravel=0.0062),
            sound=dict(pitch=0.75, body=0.85, brightness=0.65, decay=1.2, ring=0.6),
            animation=dict(speed=0.85, travel=1.15, overshoot=0.14),
            palette=dict(paint=rgb("#4b5052")), tags=["steel", "bolted"]),
    Variant("slate_ultraflat", "Slate Ultraflat", "1979",
            "Ultra-slim travel machine with a low platen line and shallow keyboard.",
            slate_ultraflat,
            mechanics=chassis_mechanics(frameResonance=0.25, anchors=dict(carriage=[0.0, 0.126, -0.068]),
                                        basket=dict(center=[0.0, 0.064, -0.030]),
                                        keyboard=dict(frontY=0.040, rowRiseY=0.0055)),
            sound=dict(pitch=1.35, body=0.25, brightness=0.75, decay=0.55, ring=0.12),
            animation=dict(speed=1.2, travel=0.75, overshoot=0.03),
            palette=dict(paint=rgb("#2c2f33")), tags=["slim", "travel"]),
    Variant("bauhaus_cylinder", "Bauhaus Cylinder", "1929",
            "Pure geometry: a box base under a half-cylinder hood with a single red disc.",
            bauhaus_cylinder,
            mechanics=chassis_mechanics(frameResonance=0.55, shiftType="carriage", shiftTravel=0.0058),
            sound=dict(pitch=0.95, body=0.65, brightness=0.6, decay=1.0, ring=0.4),
            animation=dict(speed=1.0, travel=1.0, overshoot=0.09),
            palette=dict(paint=rgb("#141414"), paintAccent=rgb("#c8281e"), paintSecond=rgb("#e8c547")),
            tags=["bauhaus", "geometric"]),
]
