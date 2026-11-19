"""Ink ribbon spools/vibrator and correction tape unit variants.

Spools are placed on the chassis spool anchors, spin around Y and contain a
`Wound__ribbon` (or `Wound__correction`) cylinder that the app scales as tape
moves from one spool to the other. The vibrator/lifter is placed at the
printing point and raised for every strike. Visible ribbon/tape strips between
the parts are generated at runtime so they always follow the real path."""
from __future__ import annotations

import math

from ..geom import (Mesh, circle2, combine, cylinder, extrude, lathe, rect2, round_polygon, rounded_box, sweep,
                    torus)
from ..scene import Part
from ..variant import Variant, rgb


def flange(radius, thickness, holes=None, n=48):
    outer = circle2(radius, n)
    m = extrude(outer, thickness, holes=holes or [])
    m.map(lambda p: (p[0], p[2], p[1]))
    m.flip()
    return m


def hole_ring(count, r_at, r_hole, n=16):
    return [circle2(r_hole, n, r_at * math.cos(2 * math.pi * i / count), r_at * math.sin(2 * math.pi * i / count))
            for i in range(count)]


def slot_ring(count, r0, r1, width):
    out = []
    for i in range(count):
        a = 2 * math.pi * i / count
        c, s = math.cos(a), math.sin(a)
        poly = [(r0, -width / 2), (r1, -width / 2), (r1, width / 2), (r0, width / 2)]
        out.append([(x * c - y * s, x * s + y * c) for (x, y) in poly])
    return out


def spool(name, flange_m, hub_role="steel", flange_role="steel", wound_role="ribbon", height=0.014,
          wound_r=0.016, extra=None):
    p = Part(name)
    p.mesh("Hub", cylinder(0.0045, height + 0.004, 24, center=(0, height / 2, 0)), hub_role)
    p.mesh("FlangeLow", flange_m.copy().translate(0, 0.0006, 0), flange_role)
    p.mesh("FlangeHigh", flange_m.copy().translate(0, height - 0.0006, 0), flange_role)
    p.mesh("Wound", cylinder(1.0, height - 0.002, 48, center=(0, height / 2, 0)).scale(wound_r, 1.0, wound_r), wound_role)
    if extra:
        for n, m, role in extra:
            p.mesh(n, m, role)
    return p


def vibrator(name="pivot_Vibrator", role="steel", style="fork"):
    p = Part(name)
    if style == "fork":
        m = Mesh()
        for s in (-1, 1):
            m.merge(rounded_box(0.0016, 0.012, 0.0012, 0.0004, center=(s * 0.0075, 0.0, 0.0)))
        m.merge(rounded_box(0.017, 0.0016, 0.0012, 0.0004, center=(0, -0.0065, 0)))
        m.merge(sweep([(0, -0.0065, 0.0), (0, -0.012, 0.004), (0, -0.022, 0.006)], 0.0009, 8))
        p.mesh("Fork", m, role)
    elif style == "window":
        outline = round_polygon(rect2(0.022, 0.014), 0.002, 3)
        hole = round_polygon(rect2(0.010, 0.009), 0.001, 2)
        plate = extrude(outline, 0.0008, holes=[hole])
        p.mesh("Guide", plate, role)
        p.mesh("Stem", sweep([(0, -0.007, 0), (0, -0.016, 0.003), (0, -0.024, 0.004)], 0.0009, 8), role)
    else:  # hooks
        m = Mesh()
        for s in (-1, 1):
            m.merge(sweep([(s * 0.0085, -0.007, 0), (s * 0.0085, 0.004, 0), (s * 0.006, 0.0065, 0.0)], 0.0007, 8))
        m.merge(cylinder(0.0008, 0.018, 8, center=(0, -0.007, 0), axis="x"))
        p.mesh("Hooks", m, role)
    return p


# --------------------------------------------------------------------------- ribbon

def ribbon_open_metal():
    f = flange(0.024, 0.0010, hole_ring(6, 0.014, 0.0045))
    return [spool("pivot_SpoolLeft", f), spool("pivot_SpoolRight", f), vibrator()]


def ribbon_covered_cups():
    f = flange(0.024, 0.0008)
    cup = lathe([(0.0, 0.0215), (0.026, 0.017), (0.027, 0.014), (0.027, 0.0)], 56, cap_start=False)
    cup.translate(0, 0.0, 0)
    knob = cylinder(0.006, 0.006, 24, bevel=0.0015, center=(0, 0.024, 0))
    extra = [("Cup", cup, "chrome"), ("CupKnob", knob, "bakelite")]
    return [spool("pivot_SpoolLeft", f, extra=extra), spool("pivot_SpoolRight", f, extra=extra), vibrator(style="window")]


def ribbon_cassette():
    f = flange(0.021, 0.0008)
    shell = rounded_box(0.054, 0.018, 0.054, 0.005, center=(0, 0.009, 0))
    window = rounded_box(0.03, 0.001, 0.03, 0.002, center=(0, 0.0182, 0))
    # shell parts are fixed (not spinning): use plain parts at the same anchor names
    outL = Part("SpoolLeft_Housing")
    outL.mesh("Shell", shell.copy(), "darkPlastic")
    outL.mesh("Window", window.copy(), "smoked")
    outR = Part("SpoolRight_Housing")
    outR.mesh("Shell", shell.copy(), "darkPlastic")
    outR.mesh("Window", window.copy(), "smoked")
    return [spool("pivot_SpoolLeft", f, "darkPlastic", "darkPlastic", wound_r=0.015),
            spool("pivot_SpoolRight", f, "darkPlastic", "darkPlastic", wound_r=0.015), outL, outR,
            vibrator(role="darkPlastic", style="window")]


def ribbon_brass_reels():
    f = flange(0.025, 0.0012, hole_ring(5, 0.015, 0.005))
    return [spool("pivot_SpoolLeft", f, "brass", "brass"), spool("pivot_SpoolRight", f, "brass", "brass"),
            vibrator(role="brass")]


def ribbon_vented():
    f = flange(0.024, 0.0010, slot_ring(8, 0.008, 0.021, 0.0035))
    return [spool("pivot_SpoolLeft", f, "blackSteel", "blackSteel"), spool("pivot_SpoolRight", f, "blackSteel", "blackSteel"),
            vibrator(role="blackSteel", style="hooks")]


def ribbon_wooden():
    f = flange(0.024, 0.0014)
    hubw = cylinder(0.009, 0.016, 32, bevel=0.0015, center=(0, 0.008, 0))
    extra = [("WoodHub", hubw, "wood")]
    return [spool("pivot_SpoolLeft", f, "wood", "brass", extra=extra), spool("pivot_SpoolRight", f, "wood", "brass", extra=extra),
            vibrator(role="brass")]


def ribbon_translucent():
    f = flange(0.025, 0.0016)
    return [spool("pivot_SpoolLeft", f, "chrome", "glass"), spool("pivot_SpoolRight", f, "chrome", "glass"),
            vibrator(role="chrome", style="window")]


def ribbon_double_stack():
    f = flange(0.024, 0.0010, hole_ring(4, 0.013, 0.004))
    return [spool("pivot_SpoolLeft", f, height=0.022), spool("pivot_SpoolRight", f, height=0.022), vibrator()]


def rmech(width=0.013, lift=0.0065, auto_reverse="eyelet", **kw):
    d = dict(ribbonWidth=width, vibratorLift=lift, autoReverse=auto_reverse, advancePerStrike=0.0006,
             ribbonLength=10.0, spoolHeight=0.014)
    d.update(kw)
    return d


RIBBON_VARIANTS = [
    Variant("open_metal", "Open Metal Spools", "Classic", "Pressed steel spools with lightening holes and a sprung fork vibrator.",
            ribbon_open_metal, mechanics=rmech(), sound=dict(pitch=1.0, body=0.4, brightness=0.7, decay=0.8, ring=0.3)),
    Variant("covered_cups", "Covered Cups", "1950s", "Chrome cups hide the spools; only the ribbon shows.",
            ribbon_covered_cups, mechanics=rmech(), sound=dict(pitch=0.95, body=0.5, brightness=0.6, decay=0.7, ring=0.2)),
    Variant("cassette", "Cartridge", "1970s", "Snap-in cartridges with smoked windows. Clean fingers, quiet ratchet.",
            ribbon_cassette, mechanics=rmech(lift=0.0055, auto_reverse="none", ribbonLength=6.0),
            sound=dict(pitch=1.2, body=0.3, brightness=0.4, decay=0.5, ring=0.0)),
    Variant("brass_reels", "Brass Reels", "Victorian", "Five-hole brass reels and a brass fork.",
            ribbon_brass_reels, mechanics=rmech(), sound=dict(pitch=0.9, body=0.5, brightness=0.85, decay=1.2, ring=0.7)),
    Variant("vented", "Vented Spools", "Industrial", "Slotted black spools with hook vibrator.",
            ribbon_vented, mechanics=rmech(lift=0.0075), sound=dict(pitch=0.85, body=0.6, brightness=0.6, decay=0.9, ring=0.3)),
    Variant("wooden", "Wooden Hubs", "Craft", "Turned wooden hubs between brass flanges.",
            ribbon_wooden, mechanics=rmech(), sound=dict(pitch=0.8, body=0.7, brightness=0.4, decay=0.7, ring=0.1)),
    Variant("translucent", "Clear Spools", "1960s", "Clear flanges so you can watch the ribbon wind.",
            ribbon_translucent, mechanics=rmech(lift=0.006), sound=dict(pitch=1.1, body=0.35, brightness=0.55, decay=0.6, ring=0.05)),
    Variant("double_stack", "Two-Color Stack", "Office", "Tall spools for a wide two-color ribbon. Shift the color with the selector.",
            ribbon_double_stack, mechanics=rmech(width=0.016, lift=0.0075, twoColor=True, spoolHeight=0.022),
            sound=dict(pitch=0.95, body=0.5, brightness=0.65, decay=0.9, ring=0.3)),
]
for _v in RIBBON_VARIANTS:
    _v.animation = dict(speed=1.0, overshoot=0.05)


# --------------------------------------------------------------------------- correction

def corr(spool_role, flange_role, lifter_role, lifter_style, r=0.013, holes=None, extra=None):
    f = flange(r, 0.0008, holes)
    return [spool("pivot_CorrSpoolLeft", f, spool_role, flange_role, "correction", 0.010, 0.010, extra),
            spool("pivot_CorrSpoolRight", f, spool_role, flange_role, "correction", 0.010, 0.010, extra),
            vibrator("pivot_Lifter", lifter_role, lifter_style)]


def cmech(mode="coverUp", tint=(0.0, 0.0, 0.0), coverage=1.0, **kw):
    d = dict(mode=mode, tintOffset=list(tint), coverage=coverage, tapeWidth=0.008, lifterLift=0.011,
             tapeLength=4.0)
    d.update(kw)
    return d


CORRECTION_VARIANTS = [
    Variant("chalk_cover", "Chalk Cover-Up", "1970s", "Classic white chalk tape. Covers the glyph with a slightly cooler white.",
            lambda: corr("darkPlastic", "darkPlastic", "steel", "fork"),
            mechanics=cmech("coverUp", (-0.01, 0.0, 0.015), 1.0),
            sound=dict(pitch=1.1, body=0.3, brightness=0.5, decay=0.6, ring=0.0)),
    Variant("lift_off", "Lift-Off Tape", "1980s", "Adhesive tape that pulls carbon ink off the page, leaving a faint ghost.",
            lambda: corr("plastic", "plastic", "chrome", "window", holes=hole_ring(4, 0.007, 0.002)),
            mechanics=cmech("liftOff", (0.0, 0.0, 0.0), 0.88),
            sound=dict(pitch=1.0, body=0.35, brightness=0.45, decay=0.5, ring=0.0)),
    Variant("ivory_cover", "Ivory Cover-Up", "Archive", "Warm ivory chalk for cream papers.",
            lambda: corr("brass", "brass", "brass", "fork"),
            mechanics=cmech("coverUp", (0.02, 0.0, -0.035), 1.0),
            sound=dict(pitch=0.9, body=0.4, brightness=0.6, decay=0.8, ring=0.3)),
    Variant("film_cover", "Film Cover-Up", "1960s", "Thin coated film. Crisp edges, slightly glossy patch.",
            lambda: corr("chrome", "glass", "chrome", "window"),
            mechanics=cmech("coverUp", (0.0, 0.005, 0.0), 0.96, gloss=0.4),
            sound=dict(pitch=1.2, body=0.3, brightness=0.6, decay=0.6, ring=0.1)),
    Variant("paper_patch", "Paper Patch", "Wartime", "A sprung lever presses a strip of thin correction paper. Rough, visible patch.",
            lambda: corr("wood", "steel", "blackSteel", "hooks", r=0.014),
            mechanics=cmech("coverUp", (0.01, 0.0, -0.02), 1.0, patch=True, roughness=0.9),
            sound=dict(pitch=0.8, body=0.5, brightness=0.5, decay=0.8, ring=0.05)),
    Variant("ink_eraser", "Ink Eraser Wheel", "Experimental", "A fine abrasive band that scuffs ink away and roughens the paper.",
            lambda: corr("steel", "blackSteel", "steel", "hooks", extra=[("Grit", torus(0.006, 0.0011, 24, 8).translate(0, 0.005, 0), "darkPlastic")]),
            mechanics=cmech("liftOff", (0.0, 0.0, 0.0), 0.8, abrasion=0.6),
            sound=dict(pitch=0.7, body=0.4, brightness=0.9, decay=0.6, ring=0.0)),
    Variant("tinted_cover", "Color-Matched Tape", "Studio", "Matches the paper tint closely; only a sheen gives it away.",
            lambda: corr("plastic", "plastic", "chrome", "window"),
            mechanics=cmech("coverUp", (0.0, 0.0, 0.0), 1.0, matchPaper=0.85),
            sound=dict(pitch=1.05, body=0.35, brightness=0.45, decay=0.5, ring=0.0)),
    Variant("brass_bellows", "Brass Bellows", "Steampunk", "A puff of white powder blown through a stencil. Soft, slightly grainy cover.",
            lambda: corr("brass", "brass", "brass", "window", extra=[("Bellows", cylinder(0.007, 0.008, 12, center=(0, 0.014, 0)), "wood")]),
            mechanics=cmech("coverUp", (0.0, 0.0, 0.0), 0.92, grain=0.7),
            sound=dict(pitch=0.85, body=0.45, brightness=0.35, decay=0.9, ring=0.2)),
]
for _v in CORRECTION_VARIANTS:
    _v.animation = dict(speed=1.0, overshoot=0.04)
