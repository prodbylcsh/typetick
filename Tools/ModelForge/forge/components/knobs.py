"""Platen knob variants. `Knob` sits on the platen axle and points along +X
(the app mirrors it for the left side). It spins with the platen."""
from __future__ import annotations

import math

from ..geom import Mesh, combine, cylinder, lathe, rounded_box, sphere, sweep, torus
from ..scene import Part
from ..variant import Variant, rgb


def along_x(m: Mesh) -> Mesh:
    return m.rotate_z(-90)


def knob(meshes):
    p = Part("Knob")
    for n, m, role in meshes:
        p.mesh(n, along_x(m), role)
    return [p]


def ribs_around(radius, y0, y1, count, w=0.0018, depth=0.0016):
    m = Mesh()
    for i in range(count):
        a = 360.0 * i / count
        rib = rounded_box(w, y1 - y0, depth, 0.0006, center=(0, (y0 + y1) / 2, radius))
        rib.rotate_y(a)
        m.merge(rib)
    return m


def fluted_bakelite():
    body = lathe([(0.0, 0.0), (0.006, 0.0), (0.006, 0.004), (0.016, 0.006), (0.0175, 0.012), (0.0175, 0.024),
                  (0.016, 0.027), (0.0, 0.028)], 48)
    return knob([("Body", body, "bakelite"), ("Flutes", ribs_around(0.0172, 0.010, 0.025, 20), "bakelite")])


def knurled_chrome():
    body = lathe([(0.0, 0.0), (0.005, 0.0), (0.005, 0.005), (0.015, 0.006), (0.015, 0.024), (0.013, 0.026),
                  (0.0, 0.026)], 64)
    knurl = ribs_around(0.0152, 0.008, 0.022, 48, w=0.0008, depth=0.0008)
    return knob([("Body", body, "chrome"), ("Knurl", knurl, "chrome")])


def mushroom():
    neck = cylinder(0.0045, 0.012, 24, center=(0, 0.006, 0))
    cap = lathe([(0.0, 0.010), (0.020, 0.012), (0.021, 0.016), (0.017, 0.022), (0.009, 0.0255), (0.0, 0.026)], 64)
    return knob([("Neck", neck, "steel"), ("Cap", cap, "bakelite")])


def wing():
    hubm = lathe([(0.0, 0.0), (0.008, 0.0), (0.008, 0.02), (0.006, 0.022), (0.0, 0.022)], 40)
    w = Mesh()
    for s in (-1, 1):
        ear = rounded_box(0.034, 0.016, 0.004, 0.0035, band=3, center=(s * 0.018, 0.012, 0))
        w.merge(ear)
    return knob([("Hub", hubm, "steel"), ("Wings", w, "steel")])


def faceted():
    m = lathe([(0.0, 0.0), (0.006, 0.0), (0.006, 0.004), (0.017, 0.007), (0.017, 0.022), (0.012, 0.027),
               (0.0, 0.027)], 8)
    m.crease_deg = 30.0
    return knob([("Body", m, "brass")])


def ribbed_rubber():
    core = lathe([(0.0, 0.0), (0.006, 0.0), (0.006, 0.004), (0.0155, 0.006), (0.0155, 0.026), (0.0, 0.027)], 48)
    rings = combine(torus(0.0155, 0.0018, 48, 10).translate(0, 0.009 + i * 0.0045, 0) for i in range(4))
    return knob([("Core", core, "steel"), ("Rings", rings, "rubber")])


def disc():
    d = lathe([(0.0, 0.0), (0.005, 0.0), (0.005, 0.006), (0.024, 0.007), (0.025, 0.009), (0.025, 0.012),
               (0.023, 0.013), (0.0, 0.0135)], 72)
    dimples = Mesh()
    for i in range(10):
        a = 2 * math.pi * i / 10
        dimples.merge(sphere(0.0022, 12, 6, 0.5).translate(0.019 * math.sin(a), 0.0135, 0.019 * math.cos(a)))
    return knob([("Disc", d, "bakelite"), ("Dimples", dimples, "chrome")])


def crank():
    base = lathe([(0.0, 0.0), (0.006, 0.0), (0.006, 0.004), (0.014, 0.006), (0.014, 0.012), (0.0, 0.013)], 40)
    arm = sweep([(0.0, 0.010, 0.0), (0.0, 0.014, 0.012), (0.0, 0.016, 0.026)], 0.0022, 10)
    handle = lathe([(0.0, 0.0), (0.004, 0.002), (0.0045, 0.012), (0.003, 0.016), (0.0, 0.017)], 24).translate(0, 0.016, 0.026)
    return knob([("Base", base, "chrome"), ("Arm", arm, "chrome"), ("Handle", handle, "wood")])


VARIANTS = [
    Variant("fluted_bakelite", "Fluted Bakelite", "1930s", "Deep fluted black bakelite. Three soft detents per line.",
            fluted_bakelite, mechanics=dict(detentsPerLine=3, diameter=0.035, friction=0.5),
            sound=dict(pitch=0.95, body=0.6, brightness=0.45, decay=0.8, ring=0.05), animation=dict(speed=1.0)),
    Variant("knurled_chrome", "Knurled Chrome", "1950s", "Fine diamond knurling in polished chrome. Six crisp clicks per line.",
            knurled_chrome, mechanics=dict(detentsPerLine=6, diameter=0.031, friction=0.35),
            sound=dict(pitch=1.3, body=0.3, brightness=0.9, decay=0.9, ring=0.5), animation=dict(speed=1.1)),
    Variant("mushroom", "Mushroom", "1920s", "Wide domed cap on a slim neck. Two heavy detents per line.",
            mushroom, mechanics=dict(detentsPerLine=2, diameter=0.042, friction=0.6),
            sound=dict(pitch=0.8, body=0.75, brightness=0.4, decay=1.0, ring=0.1), animation=dict(speed=0.9)),
    Variant("wing", "Wing Nut", "Industrial", "Two steel ears instead of a knob. Coarse ratchet, one click per line.",
            wing, mechanics=dict(detentsPerLine=1, diameter=0.07, friction=0.7),
            sound=dict(pitch=0.85, body=0.5, brightness=0.8, decay=1.1, ring=0.6), animation=dict(speed=0.85)),
    Variant("faceted", "Faceted Brass", "Victorian", "Octagonal brass knob. Four bright detents per line.",
            faceted, mechanics=dict(detentsPerLine=4, diameter=0.034, friction=0.45),
            sound=dict(pitch=1.1, body=0.45, brightness=0.85, decay=1.2, ring=0.7), animation=dict(speed=1.0)),
    Variant("ribbed_rubber", "Ribbed Rubber", "1970s", "Rubber grip rings. Almost silent, smooth free roll.",
            ribbed_rubber, mechanics=dict(detentsPerLine=8, diameter=0.034, friction=0.25),
            sound=dict(pitch=1.0, body=0.4, brightness=0.2, decay=0.5, ring=0.0), animation=dict(speed=1.15)),
    Variant("disc", "Dimpled Disc", "1940s", "Wide flat disc with chrome finger dimples. Long smooth turns.",
            disc, mechanics=dict(detentsPerLine=4, diameter=0.05, friction=0.4),
            sound=dict(pitch=0.9, body=0.6, brightness=0.5, decay=0.9, ring=0.2), animation=dict(speed=0.95)),
    Variant("crank", "Crank Handle", "Workshop", "A little crank with a walnut handle. Each line is a deliberate half turn.",
            crank, mechanics=dict(detentsPerLine=2, diameter=0.06, friction=0.55, turnsPerLine=0.5),
            sound=dict(pitch=0.9, body=0.55, brightness=0.6, decay=1.0, ring=0.3), animation=dict(speed=0.9)),
]
