"""Carriage variants. Origin = platen axis center. The carriage moves along X;
`pivot_Platen` rotates around X for line spacing and knob turns."""
from __future__ import annotations

import math

from ..geom import (Mesh, circle2, combine, cylinder, extrude_x, lathe, rect2, round_polygon, rounded_box,
                    sweep, torus)
from ..scene import Part
from ..variant import Variant, rgb

PICA = 0.00254
ELITE = 0.0021167
LINE = 0.0042333


def platen(length, radius, role="rubber"):
    p = Part("pivot_Platen")
    p.mesh("Roller", cylinder(radius, length, 72, bevel=0.0012, axis="x"), role)
    p.mesh("Axle", cylinder(0.0032, length + 0.05, 20, axis="x"), "steel")
    # fine knurl rings at the ends show the platen rotating
    rings = combine(torus(radius * 0.55, 0.0006, 40, 6).rotate_z(90).translate(s * (length / 2 + 0.0006), 0, 0)
                    for s in (-1, 1))
    p.mesh("EndRings", rings, "steel")
    return p


def end_plate_profile(r):
    return round_polygon([(0.020, -0.034), (0.022, -0.012), (0.010, 0.024), (-0.012, 0.030),
                          (-0.034, 0.020), (-0.040, -0.034)], 0.006, 4)


def end_plates(length, role="paint", thickness=0.006, profile=None, r=0.0165):
    prof = profile or end_plate_profile(r)
    m = Mesh()
    for s in (-1, 1):
        m.merge(extrude_x(prof, thickness).translate(s * (length / 2 + 0.005 + thickness / 2), 0, 0))
    return m


def paper_table(length, r, role="paint", height=0.11, thickness=0.0016, tilt_deg=55.0, inset=0.003):
    # the sheet hangs off the back of the platen at phi = -125 deg, leaning back 55 deg
    phi = math.radians(-125)
    base = (0.0, (r + inset) * math.sin(phi), (r + inset) * math.cos(phi))
    t = math.radians(tilt_deg)
    plate = rounded_box(length * 0.92, height, thickness, 0.0007, center=(0, height / 2, 0))
    plate.rotate_x(-tilt_deg)
    plate.translate(0, base[1] + 0.004, base[2] - 0.006)
    return plate


def rail_shoes(length, role="blackSteel"):
    m = Mesh()
    for s in (-1, 1):
        m.merge(rounded_box(0.03, 0.010, 0.05, 0.002, center=(s * (length / 2 - 0.01), -0.028, -0.02)))
    m.merge(rounded_box(length, 0.008, 0.012, 0.002, center=(0, -0.026, -0.042)))
    return m


def front_scale(length, role="scale", y=-0.0215, z=0.0205):
    plate = rounded_box(length * 0.8, 0.0045, 0.0012, 0.0004, center=(0, y, z))
    plate.rotate_x(0)
    return plate


def mech(platen_len, radius, pitch=PICA, **kw):
    half = platen_len / 2
    d = dict(
        platenLength=platen_len, platenRadius=radius, pitch=pitch, lineHeight=LINE,
        printAngleDegrees=8.0, paperExitDegrees=30.0, paperEntryDegrees=-125.0, bailAngleDegrees=21.0,
        returnSpeed=0.9, powerReturn=False, escapementSnap=0.012,
        anchors=dict(
            knobLeft=[-(half + 0.014), 0.0, 0.0], knobRight=[half + 0.014, 0.0, 0.0],
            returnLever=[-(half + 0.009), 0.018, 0.006],
            bail=[0.0, 0.0, 0.0], releaseLever=[half - 0.006, 0.026, -0.026],
            marginRack=[0.0, -0.033, 0.026],
        ),
    )
    d.update(kw)
    return d


# ---------------------------------------------------------------------------

def classic_black():
    L, r = 0.245, 0.0165
    frame = Part("Frame")
    frame.mesh("EndPlates", end_plates(L, r=r), "paint")
    frame.mesh("Table", paper_table(L, r), "paint")
    frame.mesh("Shoes", rail_shoes(L), "blackSteel")
    frame.mesh("Scale", front_scale(L), "scale")
    return [platen(L, r), frame]


def wide_ledger():
    L, r = 0.36, 0.018
    frame = Part("Frame")
    frame.mesh("EndPlates", end_plates(L, thickness=0.008, r=r), "paint")
    frame.mesh("Table", paper_table(L, r, height=0.13), "paint")
    frame.mesh("Shoes", rail_shoes(L), "blackSteel")
    frame.mesh("Scale", front_scale(L), "scale")
    frame.mesh("Brace", cylinder(0.003, L, 16, center=(0, 0.012, -0.040), axis="x"), "steel")
    return [platen(L, r), frame]


def chrome_shroud():
    L, r = 0.25, 0.0165
    frame = Part("Frame")
    frame.mesh("EndPlates", end_plates(L, r=r), "paint")
    shroud = Mesh()
    for s in (-1, 1):
        cap = lathe([(0.0, 0.0), (0.028, 0.0), (0.030, 0.003), (0.030, 0.008), (0.024, 0.014), (0.0, 0.016)], 48)
        cap.rotate_z(-90 * s).translate(s * (L / 2 + 0.011), 0, -0.004)
        shroud.merge(cap)
    frame.mesh("Shrouds", shroud, "chrome")
    frame.mesh("Table", paper_table(L, r), "chrome")
    frame.mesh("Shoes", rail_shoes(L), "blackSteel")
    frame.mesh("Scale", front_scale(L), "scale")
    return [platen(L, r), frame]


def open_rail():
    L, r = 0.245, 0.016
    frame = Part("Frame")
    loops = Mesh()
    for s in (-1, 1):
        ring = torus(0.026, 0.0028, 40, 10).rotate_z(90).translate(s * (L / 2 + 0.008), -0.004, -0.008)
        loops.merge(ring)
    frame.mesh("Loops", loops, "blackSteel")
    wires = Mesh()
    for x in (-0.08, -0.03, 0.03, 0.08):
        path = [(x, -0.012, -0.02), (x, 0.01, -0.04), (x, 0.045, -0.085), (x, 0.065, -0.115)]
        wires.merge(sweep(path, 0.0012, 8))
    wires.merge(cylinder(0.0014, L * 0.8, 10, center=(0, 0.065, -0.115), axis="x"))
    frame.mesh("PaperWires", wires, "chrome")
    frame.mesh("Shoes", rail_shoes(L), "blackSteel")
    frame.mesh("Scale", front_scale(L), "steel")
    return [platen(L, r), frame]


def streamline():
    L, r = 0.25, 0.017
    frame = Part("Frame")
    covers = Mesh()
    for s in (-1, 1):
        c = rounded_box(0.02, 0.07, 0.075, 0.009, band=4, center=(s * (L / 2 + 0.012), -0.002, -0.012))
        covers.merge(c)
    frame.mesh("Covers", covers, "paint")
    frame.mesh("Table", paper_table(L, r, thickness=0.003, height=0.1), "paintSecond")
    frame.mesh("Shoes", rail_shoes(L), "blackSteel")
    frame.mesh("Scale", front_scale(L), "scale")
    return [platen(L, r), frame]


def brass_ends():
    L, r = 0.245, 0.0165
    frame = Part("Frame")
    frame.mesh("EndPlates", end_plates(L, thickness=0.005, r=r), "brass")
    rosettes = Mesh()
    for s in (-1, 1):
        ros = lathe([(0.0, 0.0), (0.011, 0.0), (0.011, 0.0015), (0.008, 0.0028), (0.004, 0.0032), (0.0, 0.0034)], 32)
        ros.rotate_z(-90 * s).translate(s * (L / 2 + 0.0105), -0.012, -0.016)
        rosettes.merge(ros)
    frame.mesh("Rosettes", rosettes, "copper")
    frame.mesh("Table", paper_table(L, r, thickness=0.002), "wood")
    frame.mesh("Shoes", rail_shoes(L), "brass")
    frame.mesh("Scale", front_scale(L), "brass")
    return [platen(L, r), frame]


def red_platen():
    L, r = 0.24, 0.016
    frame = Part("Frame")
    frame.mesh("EndPlates", end_plates(L, r=r), "paintSecond")
    frame.mesh("Table", paper_table(L, r), "paintSecond")
    frame.mesh("Shoes", rail_shoes(L), "blackSteel")
    frame.mesh("Scale", front_scale(L), "scale")
    return [platen(L, r, "redRubber"), frame]


def minimal_power():
    L, r = 0.24, 0.0155
    frame = Part("Frame")
    prof = round_polygon([(0.016, -0.03), (0.016, 0.012), (-0.02, 0.022), (-0.034, -0.03)], 0.004, 3)
    frame.mesh("EndPlates", end_plates(L, thickness=0.004, profile=prof, r=r), "steel")
    fingers = Mesh()
    for x in (-0.06, 0.06):
        fingers.merge(sweep([(x, -0.012, -0.02), (x, 0.02, -0.05), (x, 0.05, -0.095)], 0.0016, 8))
    frame.mesh("Fingers", fingers, "steel")
    frame.mesh("Motor", cylinder(0.009, 0.03, 32, bevel=0.002, center=(-L / 2 - 0.004, -0.024, -0.03), axis="x"), "darkPlastic")
    frame.mesh("Shoes", rail_shoes(L), "darkPlastic")
    frame.mesh("Scale", front_scale(L), "scale")
    return [platen(L, r), frame]


VARIANTS = [
    Variant("classic_black", "Classic Black", "1930s",
            "Black enamel carriage with a pica escapement and a firm hard-rubber platen.",
            classic_black, mechanics=mech(0.245, 0.0165),
            sound=dict(pitch=1.0, body=0.6, brightness=0.6, decay=1.0, ring=0.3),
            animation=dict(speed=1.0, overshoot=0.06), tags=["pica"]),
    Variant("wide_ledger", "Wide Ledger", "Office",
            "Extra wide 14 inch carriage for ledgers. Heavy and slow on the return, with a deep thud at the stop.",
            wide_ledger, mechanics=mech(0.36, 0.018, returnSpeed=0.65),
            sound=dict(pitch=0.75, body=0.95, brightness=0.45, decay=1.3, ring=0.25),
            animation=dict(speed=0.8, overshoot=0.04), tags=["wide", "pica"]),
    Variant("chrome_shroud", "Chrome Shroud", "1950s",
            "Chrome end shrouds and a mirror paper table. Elite type, quick escapement.",
            chrome_shroud, mechanics=mech(0.25, 0.0165, pitch=ELITE, returnSpeed=1.0),
            sound=dict(pitch=1.15, body=0.5, brightness=0.8, decay=1.0, ring=0.45),
            animation=dict(speed=1.05, overshoot=0.07), tags=["elite"]),
    Variant("open_rail", "Open Rail", "1910s",
            "Ringed end loops and wire paper supports. Loud, bouncy carriage.",
            open_rail, mechanics=mech(0.245, 0.016, returnSpeed=1.1, escapementSnap=0.02),
            sound=dict(pitch=1.1, body=0.4, brightness=0.85, decay=1.2, ring=0.6),
            animation=dict(speed=1.1, overshoot=0.14), tags=["pica", "wire"]),
    Variant("streamline", "Streamline", "1950s",
            "Rounded end covers and a cream paper table. Smooth, damped glide.",
            streamline, mechanics=mech(0.25, 0.017, returnSpeed=0.95, escapementSnap=0.008),
            sound=dict(pitch=0.95, body=0.7, brightness=0.45, decay=0.8, ring=0.15),
            animation=dict(speed=1.0, overshoot=0.03), tags=["pica"]),
    Variant("brass_ends", "Brass Ends", "Victorian",
            "Brass end plates with copper rosettes and a walnut paper table.",
            brass_ends, mechanics=mech(0.245, 0.0165, returnSpeed=0.85),
            sound=dict(pitch=0.9, body=0.6, brightness=0.75, decay=1.3, ring=0.7),
            animation=dict(speed=0.95, overshoot=0.08), tags=["brass", "pica"]),
    Variant("red_platen", "Red Platen", "1960s",
            "Cream carriage around a soft red rubber platen. Elite pitch, quieter strikes.",
            red_platen, mechanics=mech(0.24, 0.016, pitch=ELITE, platenHardness=0.45),
            sound=dict(pitch=1.05, body=0.5, brightness=0.4, decay=0.7, ring=0.1),
            animation=dict(speed=1.05, overshoot=0.05), tags=["elite", "soft platen"]),
    Variant("minimal_power", "Minimal Power", "1980s",
            "Thin aluminium carriage with an electric return motor. The return lever only taps a switch.",
            minimal_power, mechanics=mech(0.24, 0.0155, pitch=ELITE, powerReturn=True, returnSpeed=1.6),
            sound=dict(pitch=1.2, body=0.35, brightness=0.6, decay=0.6, ring=0.05),
            animation=dict(speed=1.2, overshoot=0.02), tags=["electric", "elite"]),
]
