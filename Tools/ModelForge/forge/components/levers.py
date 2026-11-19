"""Carriage return / line space lever variants. `pivot_ReturnLever` hinges at
the left end of the carriage; the app swings it around its local Y axis."""
from __future__ import annotations

from ..geom import Mesh, bezier, cylinder, lathe, rounded_box, sphere, sweep, torus
from ..scene import Part
from ..variant import Variant, rgb


def lever(meshes, selector_role="steel"):
    p = Part("pivot_ReturnLever")
    p.mesh("Hinge", cylinder(0.0045, 0.006, 20, bevel=0.001), "steel")
    for n, m, role in meshes:
        p.mesh(n, m, role)
    sel = Part("LineSpaceSelector", translate=(0.0, 0.004, -0.008))
    sel.mesh("Tab", rounded_box(0.004, 0.003, 0.012, 0.001, center=(-0.004, 0, 0)), selector_role)
    return [p, sel]


def arm(points, r=0.0022, steps=24):
    return sweep(bezier(points, steps), r, 12)


def chrome_arm():
    a = arm([(0, 0.002, 0), (-0.01, 0.012, 0.03), (-0.03, 0.02, 0.05), (-0.045, 0.022, 0.07)])
    pad = rounded_box(0.026, 0.004, 0.014, 0.0018, center=(-0.052, 0.022, 0.078))
    pad.rotate_y(0)
    return lever([("Arm", a, "chrome"), ("Paddle", pad, "chrome")])


def paddle():
    a = arm([(0, 0.002, 0), (-0.008, 0.008, 0.02), (-0.02, 0.012, 0.035)], 0.0028)
    pad = rounded_box(0.04, 0.005, 0.022, 0.0024, center=(-0.036, 0.013, 0.045))
    return lever([("Arm", a, "blackSteel"), ("Paddle", pad, "bakelite")])


def ball_tip():
    a = arm([(0, 0.002, 0), (-0.02, 0.016, 0.03), (-0.04, 0.024, 0.06)], 0.0019, 12)
    ball = sphere(0.0065, 24, 12).translate(-0.042, 0.025, 0.064)
    return lever([("Arm", a, "chrome"), ("Ball", ball, "bakelite")])


def deco_fin():
    a = arm([(0, 0.002, 0), (-0.015, 0.012, 0.025), (-0.035, 0.018, 0.055)], 0.0024)
    fins = Mesh()
    for i in range(3):
        fins.merge(rounded_box(0.002, 0.010 - i * 0.002, 0.018, 0.0009, center=(-0.03 - i * 0.004, 0.022, 0.05 + i * 0.002)))
    tip = rounded_box(0.028, 0.004, 0.012, 0.002, center=(-0.044, 0.018, 0.062))
    return lever([("Arm", a, "chrome"), ("Fins", fins, "chrome"), ("Tip", tip, "paint")])


def hook():
    a = arm([(0, 0.002, 0), (-0.02, 0.01, 0.03), (-0.05, 0.016, 0.06), (-0.06, 0.03, 0.05), (-0.05, 0.034, 0.04)], 0.0024, 32)
    return lever([("Arm", a, "blackSteel")])


def long_swan():
    a = arm([(0, 0.002, 0), (-0.01, 0.03, 0.02), (-0.05, -0.005, 0.06), (-0.075, 0.02, 0.09)], 0.0021, 32)
    pad = sphere(0.0045, 16, 8, 0.7).scale(1.8, 1.0, 1.0).translate(-0.078, 0.02, 0.093)
    return lever([("Arm", a, "chrome"), ("Grip", pad, "rubber")])


def short_stub():
    a = rounded_box(0.008, 0.006, 0.026, 0.0026, center=(-0.004, 0.004, 0.014))
    cap = rounded_box(0.014, 0.008, 0.012, 0.003, center=(-0.007, 0.006, 0.03))
    return lever([("Stub", a, "darkPlastic"), ("Switch", cap, "paintAccent")], "darkPlastic")


def loop():
    a = arm([(0, 0.002, 0), (-0.015, 0.012, 0.03), (-0.03, 0.016, 0.05)], 0.0022)
    ring = torus(0.011, 0.0022, 40, 10).rotate_z(0).translate(-0.04, 0.017, 0.062)
    return lever([("Arm", a, "chrome"), ("Loop", ring, "chrome")])


def m(swing, spacing=(1.0, 1.5, 2.0), feed_first=True, **kw):
    d = dict(swingDegrees=swing, lineSpacingOptions=list(spacing), feedBeforeReturn=feed_first)
    d.update(kw)
    return d


VARIANTS = [
    Variant("chrome_arm", "Chrome Arm", "1930s", "Curved chrome arm with a flat thumb paddle.", chrome_arm,
            mechanics=m(32), sound=dict(pitch=1.0, body=0.5, brightness=0.7, decay=1.0, ring=0.4), animation=dict(speed=1.0)),
    Variant("paddle", "Bakelite Paddle", "1940s", "Short arm with a big bakelite paddle. Short throw.", paddle,
            mechanics=m(22), sound=dict(pitch=0.9, body=0.7, brightness=0.4, decay=0.8, ring=0.1), animation=dict(speed=1.1)),
    Variant("ball_tip", "Ball Tip", "1920s", "Thin rod with a bakelite ball. Long sweeping throw.", ball_tip,
            mechanics=m(40), sound=dict(pitch=1.05, body=0.45, brightness=0.7, decay=1.1, ring=0.5), animation=dict(speed=0.9)),
    Variant("deco_fin", "Deco Fin", "1930s", "Finned chrome arm with an enamel tip.", deco_fin,
            mechanics=m(30), sound=dict(pitch=1.1, body=0.5, brightness=0.8, decay=1.0, ring=0.45), animation=dict(speed=1.0)),
    Variant("hook", "Shepherd Hook", "Workshop", "Blackened hook you pull rather than push.", hook,
            mechanics=m(36, (1.0, 2.0, 3.0)), sound=dict(pitch=0.85, body=0.6, brightness=0.6, decay=1.0, ring=0.3),
            animation=dict(speed=0.95)),
    Variant("long_swan", "Long Swan", "Streamline", "Very long S-curve with a rubber grip. Lightest feel.", long_swan,
            mechanics=m(28), sound=dict(pitch=1.0, body=0.4, brightness=0.6, decay=0.9, ring=0.35), animation=dict(speed=1.05)),
    Variant("short_stub", "Power Switch", "1980s", "A stubby rocker for electric carriages. Clicks a switch, the motor does the rest.",
            short_stub, mechanics=m(8, feed_first=False, isSwitch=True),
            sound=dict(pitch=1.4, body=0.3, brightness=0.5, decay=0.4, ring=0.0), animation=dict(speed=1.4)),
    Variant("loop", "Ring Pull", "1950s", "Chrome ring handle with a 1, 1½ and 2 line selector.", loop,
            mechanics=m(30), sound=dict(pitch=1.05, body=0.5, brightness=0.75, decay=1.0, ring=0.5), animation=dict(speed=1.0)),
]
