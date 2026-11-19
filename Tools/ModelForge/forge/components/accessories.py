"""Bell, margin rack and recorder (mechanical clipboard) variants."""
from __future__ import annotations

import math

from ..geom import (Mesh, bezier, circle2, combine, cylinder, disc_top, extrude, lathe, rect2, regular2,
                    round_polygon, rounded_box, sphere, strip_uv_plane, sweep, torus, uv_cylinder)
from ..scene import Part
from ..variant import Variant, rgb

# =========================================================================== bell


def hammer(arm_len=0.026, role="steel", head_role="steel", head="ball"):
    p = Part("pivot_Hammer", translate=(0.0, 0.004, 0.024))
    p.mesh("Arm", sweep([(0, 0, 0), (0, 0.004, -arm_len * 0.5), (0, 0.012, -arm_len)], 0.0011, 8), role)
    if head == "ball":
        p.mesh("Head", sphere(0.0032, 16, 8).translate(0, 0.012, -arm_len), head_role)
    else:
        p.mesh("Head", rounded_box(0.006, 0.004, 0.004, 0.0012, center=(0, 0.012, -arm_len)), head_role)
    p.mesh("Spring", sweep([(0.002 * math.cos(t * 0.6), -0.002 - 0.0004 * t, 0.002 * math.sin(t * 0.6)) for t in range(30)], 0.0004, 6), "steel")
    return p


def bell_part(meshes):
    p = Part("Bell")
    for n, m, role in meshes:
        p.mesh(n, m, role)
    return p


def b_classic_dome():
    dome = lathe([(0.0, 0.020), (0.008, 0.0195), (0.016, 0.016), (0.021, 0.008), (0.022, 0.0), (0.0205, 0.0),
                  (0.0195, 0.007), (0.0145, 0.0145), (0.007, 0.018), (0.0, 0.0185)], 64)
    post = cylinder(0.002, 0.02, 12, center=(0, 0.01, 0))
    return [bell_part([("Dome", dome, "chrome"), ("Post", post, "steel")]), hammer()]


def b_double_gong():
    d1 = lathe([(0.0, 0.016), (0.014, 0.013), (0.019, 0.004), (0.019, 0.0), (0.0175, 0.0), (0.0175, 0.004),
                (0.013, 0.012), (0.0, 0.0145)], 56).translate(-0.012, 0, 0)
    d2 = lathe([(0.0, 0.012), (0.010, 0.010), (0.014, 0.003), (0.014, 0.0), (0.0125, 0.0), (0.0125, 0.003),
                (0.009, 0.009), (0.0, 0.0105)], 56).translate(0.014, 0.004, 0)
    base = rounded_box(0.05, 0.004, 0.012, 0.0015, center=(0, -0.002, 0))
    return [bell_part([("Large", d1, "brass"), ("Small", d2, "chrome"), ("Base", base, "blackSteel")]), hammer(head="block")]


def b_bicycle():
    dome = lathe([(0.0, 0.016), (0.012, 0.0145), (0.0185, 0.008), (0.0195, 0.0), (0.018, 0.0), (0.0172, 0.007),
                  (0.011, 0.013), (0.0, 0.0145)], 64)
    ridges = combine(torus(0.0155 - i * 0.003, 0.0006, 56, 6).translate(0, 0.009 + i * 0.002, 0) for i in range(3))
    return [bell_part([("Dome", dome, "chrome"), ("Ridges", ridges, "chrome")]), hammer(head_role="brass")]


def b_cowbell():
    body = lathe([(0.0, 0.026), (0.010, 0.026), (0.016, 0.0), (0.0145, 0.0), (0.009, 0.024), (0.0, 0.024)], 4, start_deg=45)
    body.crease_deg = 30
    body.scale(1.0, 1.0, 0.7)
    return [bell_part([("Body", body, "brass")]), hammer(head="block", head_role="blackSteel")]


def b_chime_bar():
    bar = rounded_box(0.05, 0.003, 0.010, 0.0012, center=(0, 0.012, 0))
    supports = combine(cylinder(0.0015, 0.012, 10, center=(x, 0.006, 0)) for x in (-0.012, 0.012))
    felt = combine(rounded_box(0.004, 0.002, 0.008, 0.0008, center=(x, 0.0105, 0)) for x in (-0.012, 0.012))
    return [bell_part([("Bar", bar, "steel"), ("Supports", supports, "blackSteel"), ("Felt", felt, "felt")]),
            hammer(head="ball", head_role="rubber")]


def b_tiny_ting():
    dome = lathe([(0.0, 0.010), (0.007, 0.009), (0.0105, 0.004), (0.011, 0.0), (0.0098, 0.0), (0.0094, 0.0035),
                  (0.006, 0.008), (0.0, 0.009)], 48)
    post = cylinder(0.0015, 0.012, 10, center=(0, 0.004, 0))
    return [bell_part([("Dome", dome, "steel"), ("Post", post, "steel")]), hammer(0.018)]


def b_brass_bowl():
    bowl = lathe([(0.0, 0.0), (0.012, 0.0), (0.024, 0.006), (0.028, 0.014), (0.0265, 0.014), (0.0225, 0.007),
                  (0.011, 0.0015), (0.0, 0.0015)], 72)
    cushion = cylinder(0.014, 0.004, 32, bevel=0.0015, center=(0, -0.002, 0))
    return [bell_part([("Bowl", bowl, "brass"), ("Cushion", cushion, "felt")]), hammer(head="ball", head_role="wood")]


def b_spring_coil():
    pts = []
    for i in range(240):
        a = i * 0.16
        r = 0.006 + 0.012 * i / 240
        pts.append((r * math.cos(a), 0.008 + 0.0001 * math.sin(i), r * math.sin(a)))
    coil = sweep(pts, 0.0009, 6)
    post = cylinder(0.002, 0.012, 12, center=(0, 0.004, 0))
    return [bell_part([("Coil", coil, "brass"), ("Post", post, "steel")]), hammer(head="block")]


def bmech(offset, partials, hammer_deg=28.0):
    return dict(bellOffsetColumns=offset, partials=partials, hammerDegrees=hammer_deg)


BELL_VARIANTS = [
    Variant("classic_dome", "Classic Dome", "Classic", "The bright single ding everyone remembers.", b_classic_dome,
            mechanics=bmech(7, [[2380, 1.4, 1.0], [5710, 0.7, 0.45], [9260, 0.35, 0.2], [3190, 1.0, 0.2]]),
            sound=dict(pitch=1.0, ring=1.0)),
    Variant("double_gong", "Double Gong", "Office", "Two domes struck together: a two-tone 'ding-dong' interval.", b_double_gong,
            mechanics=bmech(8, [[1760, 1.6, 0.8], [2640, 1.2, 0.7], [4400, 0.6, 0.3], [6600, 0.35, 0.2]]),
            sound=dict(pitch=1.0, ring=1.0)),
    Variant("bicycle", "Bicycle Bell", "Street", "Ridged chrome dome with a nervous double-strike.", b_bicycle,
            mechanics=bmech(6, [[3150, 0.9, 1.0], [7400, 0.4, 0.5], [4820, 0.6, 0.3]], 34.0) | dict(strikes=2),
            sound=dict(pitch=1.0, ring=0.8)),
    Variant("cowbell", "Cowbell", "Alpine", "A hollow brass clank instead of a ring.", b_cowbell,
            mechanics=bmech(7, [[560, 0.35, 1.0], [845, 0.3, 0.8], [1340, 0.2, 0.4], [1910, 0.15, 0.2]]),
            sound=dict(pitch=1.0, ring=0.4)),
    Variant("chime_bar", "Chime Bar", "Studio", "A tuned steel bar: one pure, long sine.", b_chime_bar,
            mechanics=bmech(8, [[1568, 2.8, 1.0], [4320, 0.8, 0.15]]), sound=dict(pitch=1.0, ring=1.0)),
    Variant("tiny_ting", "Tiny Ting", "Portable", "A thimble-sized bell. High and short.", b_tiny_ting,
            mechanics=bmech(5, [[4250, 0.55, 1.0], [9900, 0.2, 0.3]]), sound=dict(pitch=1.0, ring=0.7)),
    Variant("brass_bowl", "Singing Bowl", "Zen", "A small brass singing bowl on felt. Warm, beating hum.", b_brass_bowl,
            mechanics=bmech(9, [[523, 4.0, 1.0], [527, 4.0, 0.8], [1410, 2.2, 0.45], [2690, 1.0, 0.25]], 18.0),
            sound=dict(pitch=1.0, ring=1.0)),
    Variant("spring_coil", "Coil Gong", "Clockwork", "A flat coiled spring like in a mantel clock: dispersive 'shimmer'.", b_spring_coil,
            mechanics=bmech(7, [[880, 2.5, 0.8], [1250, 2.0, 0.6], [1990, 1.4, 0.5], [3120, 0.9, 0.4]]) | dict(dispersion=0.8),
            sound=dict(pitch=1.0, ring=1.0)),
]
for _v in BELL_VARIANTS:
    _v.animation = dict(speed=1.0, overshoot=0.2)

# =========================================================================== margin rack

RACK_W = 0.24


def rack_parts(rack_mesh, rack_role, stop_mesh, stop_role, tab_mesh, tab_role, extra=None):
    rack = Part("Rack")
    rack.mesh("Bar", rack_mesh, rack_role)
    teeth = Mesh()
    for i in range(86):
        x = -RACK_W * 0.45 + RACK_W * 0.9 * i / 85
        teeth.merge(rounded_box(0.0008, 0.0016, 0.0012, 0.0, center=(x, -0.0028, 0.0)))
    rack.mesh("Teeth", teeth, "steel")
    if extra:
        for n, m, r in extra:
            rack.mesh(n, m, r)
    stop = Part("MarginStop")
    stop.mesh("Body", stop_mesh, stop_role)
    tab = Part("TabStop")
    tab.mesh("Body", tab_mesh, tab_role)
    return [rack, stop, tab]


def m_sliding_tabs():
    return rack_parts(rounded_box(RACK_W, 0.004, 0.006, 0.001), "blackSteel",
                      rounded_box(0.006, 0.010, 0.008, 0.0015, center=(0, 0.004, 0)), "chrome",
                      rounded_box(0.002, 0.005, 0.004, 0.0006, center=(0, 0.002, -0.004)), "steel")


def m_pointer_arrows():
    arrow = extrude([(-0.004, 0.0), (0.004, 0.0), (0.0, -0.007)], 0.002).rotate_x(-90).translate(0, 0.0035, 0)
    return rack_parts(rounded_box(RACK_W, 0.003, 0.009, 0.0012), "scale",
                      combine([rounded_box(0.008, 0.006, 0.006, 0.002, center=(0, 0.006, 0)), arrow]), "paintAccent",
                      rounded_box(0.0015, 0.004, 0.003, 0.0004, center=(0, 0.0025, -0.004)), "blackSteel")


def m_ball_stops():
    return rack_parts(cylinder(0.0025, RACK_W, 16, axis="x"), "chrome",
                      combine([sphere(0.0045, 16, 8).translate(0, 0.006, 0), cylinder(0.0014, 0.006, 8, center=(0, 0.002, 0))]), "bakelite",
                      sphere(0.0018, 10, 5).translate(0, 0.003, -0.003), "brass")


def m_hook_clips():
    clip = sweep(bezier([(0, -0.002, 0.003), (0, 0.008, 0.004), (0, 0.009, -0.004), (0, 0.0, -0.004)], 16), 0.0012, 8)
    return rack_parts(rounded_box(RACK_W, 0.005, 0.005, 0.0005), "steel", clip, "steel",
                      rounded_box(0.0012, 0.006, 0.002, 0.0003, center=(0, 0.003, -0.003)), "steel")


def m_brass_riders():
    rider = combine([rounded_box(0.009, 0.006, 0.009, 0.0012, center=(0, 0.003, 0)),
                     cylinder(0.0022, 0.004, 12, center=(0, 0.008, 0))])
    return rack_parts(rounded_box(RACK_W, 0.004, 0.008, 0.0015), "wood", rider, "brass",
                      cylinder(0.0014, 0.004, 10, center=(0, 0.002, -0.004)), "brass")


def m_flag_stops():
    flag = combine([cylinder(0.0008, 0.012, 8, center=(0, 0.006, 0)),
                    rounded_box(0.0005, 0.005, 0.008, 0.0002, center=(0, 0.0095, 0.004))])
    return rack_parts(rounded_box(RACK_W, 0.003, 0.004, 0.0008), "blackSteel", flag, "paintAccent",
                      rounded_box(0.0015, 0.003, 0.003, 0.0004, center=(0, 0.0015, -0.003)), "paintAccent")


def m_push_buttons():
    btn = combine([rounded_box(0.007, 0.005, 0.007, 0.0025, center=(0, 0.003, 0))])
    return rack_parts(rounded_box(RACK_W, 0.006, 0.01, 0.0025), "darkPlastic", btn, "paintAccent",
                      rounded_box(0.002, 0.003, 0.002, 0.0008, center=(0, 0.002, -0.004)), "plastic")


def m_magnetic():
    mag = combine([cylinder(0.004, 0.003, 24, bevel=0.0006, center=(0, 0.002, 0)),
                   cylinder(0.0045, 0.0008, 24, center=(0, 0.0038, 0))])
    return rack_parts(rounded_box(RACK_W, 0.0025, 0.008, 0.001), "steel", mag, "copper",
                      cylinder(0.0016, 0.002, 12, center=(0, 0.001, -0.003)), "copper")


def mmech(set_style, **kw):
    d = dict(setStyle=set_style, nominalWidth=RACK_W, defaultLeftMargin=10, defaultRightMargin=75,
             defaultTabs=[15, 25, 35, 45, 55, 65])
    d.update(kw)
    return d


MARGIN_VARIANTS = [
    Variant("sliding_tabs", "Sliding Tabs", "Classic", "Chrome slides you pinch and move.", m_sliding_tabs, mechanics=mmech("pinch")),
    Variant("pointer_arrows", "Pointer Arrows", "1950s", "Red pointers over a printed scale.", m_pointer_arrows, mechanics=mmech("pinch")),
    Variant("ball_stops", "Ball Stops", "1930s", "Bakelite balls on a chrome rod.", m_ball_stops, mechanics=mmech("slide")),
    Variant("hook_clips", "Hook Clips", "Workshop", "Spring hooks clipped onto a toothed bar.", m_hook_clips, mechanics=mmech("clip")),
    Variant("brass_riders", "Brass Riders", "Victorian", "Brass riders on a walnut rail.", m_brass_riders, mechanics=mmech("slide")),
    Variant("flag_stops", "Flag Stops", "Railway", "Little red flags. Tabs are tiny red pins.", m_flag_stops, mechanics=mmech("clip")),
    Variant("push_buttons", "Push Buttons", "1970s", "Margin set buttons: move the carriage, press, done.", m_push_buttons,
            mechanics=mmech("button", tabSetClicks=2)),
    Variant("magnetic", "Magnetic Pucks", "Modern", "Copper magnetic pucks snap onto a steel rail.", m_magnetic, mechanics=mmech("snap")),
]
for _v in MARGIN_VARIANTS:
    _v.sound = dict(pitch=1.0, body=0.4, brightness=0.7, decay=0.7, ring=0.2)
    _v.animation = dict(speed=1.0)

# =========================================================================== recorder

def medium_tape(length=0.16, width=0.022, y=0.0, z=0.0, x=0.0, along="z"):
    m = strip_uv_plane(length, width, 32, 1)   # XY, facing +Z, u along X
    m.rotate_x(-90)                             # lie flat facing +Y
    if along == "z":
        m.rotate_y(90)                          # u now runs toward -Z
    return m.translate(x, y, z)


def reel(name, r=0.03, h=0.012, role="brass", wound_role="tape", holes=5, at=(0, 0, 0)):
    p = Part(name, translate=at)
    fl = extrude(circle2(r, 56), 0.0012, holes=[circle2(r * 0.22, 16, r * 0.55 * math.cos(2 * math.pi * i / holes),
                                                         r * 0.55 * math.sin(2 * math.pi * i / holes)) for i in range(holes)])
    fl.map(lambda q: (q[0], q[2], q[1]))
    fl.flip()
    p.mesh("Flange", fl.translate(0, 0.0006, 0), role)
    p.mesh("Hub", cylinder(0.006, h, 24, center=(0, h / 2, 0)), "steel")
    p.mesh("Wound", cylinder(1.0, h * 0.7, 48, center=(0, h * 0.4, 0)).scale(r * 0.6, 1.0, r * 0.6), wound_role)
    return p


def pivot(name, meshes, at=(0, 0, 0)):
    p = Part(name, translate=at)
    for n, m, r in meshes:
        p.mesh(n, m, r)
    return p


def gear(radius, teeth, thickness=0.003):
    pts = []
    for i in range(teeth * 2):
        a = math.pi * i / teeth
        rr = radius if i % 2 == 0 else radius * 0.86
        pts.append((rr * math.cos(a), rr * math.sin(a)))
    m = extrude(pts, thickness)
    m.map(lambda q: (q[0], q[2], q[1]))
    m.flip()
    m.crease_deg = 30
    return m


def linkage(role="steel"):
    p = Part("Linkage")
    p.mesh("Rod", sweep(bezier([(-0.05, 0.03, -0.05), (-0.09, 0.025, -0.05), (-0.13, 0.04, -0.06)], 16), 0.0018, 8), role)
    p.mesh("Clevis", rounded_box(0.008, 0.008, 0.008, 0.002, center=(-0.05, 0.03, -0.05)), role)
    return p


def common_mechanism(punch_at, reader_at, spring_at, gauge_at, role="brass"):
    parts = []
    parts.append(pivot("pivot_Punch", [("Head", rounded_box(0.026, 0.010, 0.012, 0.0015, center=(0, 0.005, 0)), "blackSteel"),
                                       ("Pins", combine(cylinder(0.0007, 0.006, 6, center=(-0.009 + 0.0025 * i, -0.002, 0)) for i in range(8)), "steel")],
                       punch_at))
    parts.append(pivot("pivot_Reader", [("Needles", combine(cylinder(0.0005, 0.007, 6, center=(-0.009 + 0.0025 * i, 0.0035, 0)) for i in range(8)), "chrome"),
                                        ("Block", rounded_box(0.024, 0.004, 0.008, 0.001, center=(0, -0.002, 0)), "steel")], reader_at))
    barrel = combine([cylinder(0.014, 0.012, 40, bevel=0.0015, center=(0, 0.006, 0))])
    parts.append(pivot("pivot_SpringBarrel", [("Barrel", barrel, role),
                                              ("Ratchet", gear(0.012, 18, 0.002).translate(0, 0.0132, 0), "steel"),
                                              ("Key", rounded_box(0.012, 0.004, 0.003, 0.001, center=(0, 0.017, 0)), "steel")], spring_at))
    dial = Part("Gauge", translate=gauge_at)
    dial.mesh("Face", disc_top(0.011, 0.0, 40, dome=0.0), "enamel")
    dial.mesh("Bezel", torus(0.0115, 0.001, 40, 8), "chrome")
    parts.append(dial)
    parts.append(pivot("pivot_GaugeNeedle", [("Needle", rounded_box(0.0006, 0.0004, 0.009, 0.0, center=(0, 0.0006, -0.004)), "paintAccent")],
                       (gauge_at[0], gauge_at[1] + 0.0004, gauge_at[2])))
    return parts


def r_telegraph():
    base = rounded_box(0.12, 0.012, 0.22, 0.003, center=(0, 0.006, 0))
    deck = rounded_box(0.10, 0.004, 0.2, 0.001, center=(0, 0.014, 0))
    housing = Part("Housing")
    housing.mesh("Base", base, "wood")
    housing.mesh("Deck", deck, "brass")
    housing.mesh("Guides", combine(rounded_box(0.003, 0.004, 0.13, 0.0008, center=(x, 0.018, 0.0)) for x in (-0.0125, 0.0125)), "brass")
    parts = [housing,
             reel("pivot_ReelSupply", at=(0.0, 0.016, -0.085)),
             reel("pivot_ReelTakeup", at=(0.0, 0.016, 0.085)),
             pivot("Medium", [("Tape", medium_tape(0.11, 0.022, 0.0172, 0.0), "medium")])]
    parts += common_mechanism((0, 0.022, -0.02), (0, 0.012, 0.03), (0.038, 0.016, 0.05), (0.038, 0.017, -0.04))
    parts.append(pivot("pivot_Gear1", [("Gear", gear(0.012, 20), "brass")], (-0.035, 0.017, 0.05)))
    parts.append(pivot("pivot_Gear2", [("Gear", gear(0.008, 14), "brass")], (-0.035, 0.017, 0.0305)))
    parts.append(linkage("brass"))
    return parts


def r_gear_drum():
    housing = Part("Housing")
    housing.mesh("Base", rounded_box(0.12, 0.01, 0.2, 0.002, center=(0, 0.005, 0)), "blackSteel")
    housing.mesh("Cheeks", combine(rounded_box(0.006, 0.06, 0.08, 0.002, center=(x, 0.035, -0.02)) for x in (-0.052, 0.052)), "blackSteel")
    drum = uv_cylinder(0.026, 0.096, 64)
    parts = [housing,
             pivot("pivot_Drum", [("Medium", drum, "medium"), ("Axle", cylinder(0.003, 0.11, 12, axis="x"), "steel"),
                                  ("Rims", combine(torus(0.026, 0.0015, 48, 6).rotate_z(90).translate(x, 0, 0) for x in (-0.048, 0.048)), "brass")],
                   (0, 0.042, -0.02))]
    parts += common_mechanism((0, 0.074, -0.02), (0, 0.022, 0.012), (0.035, 0.01, 0.06), (-0.035, 0.011, 0.06))
    parts.append(pivot("pivot_Gear1", [("Gear", gear(0.022, 32).rotate_z(90), "brass")], (0.06, 0.042, -0.02)))
    parts.append(pivot("pivot_Gear2", [("Gear", gear(0.010, 16).rotate_z(90), "steel")], (0.06, 0.042, 0.012)))
    parts.append(linkage())
    return parts


def r_brass_chronograph():
    housing = Part("Housing")
    housing.mesh("Case", lathe([(0.0, 0.0), (0.058, 0.0), (0.06, 0.004), (0.06, 0.026), (0.057, 0.03), (0.054, 0.03),
                                 (0.054, 0.012), (0.0, 0.012)], 72), "brass")
    housing.mesh("Glass", disc_top(0.054, 0.03, 64, dome=0.004), "glass")
    ring = Mesh()
    steps = 64
    for i in range(steps):
        a0 = 2 * math.pi * i / steps
        a1 = 2 * math.pi * (i + 1) / steps
        r0, r1 = 0.032, 0.046
        ids = [ring.add_point((r0 * math.sin(a0), 0.0, r0 * math.cos(a0))), ring.add_point((r1 * math.sin(a0), 0.0, r1 * math.cos(a0))),
               ring.add_point((r1 * math.sin(a1), 0.0, r1 * math.cos(a1))), ring.add_point((r0 * math.sin(a1), 0.0, r0 * math.cos(a1)))]
        ring.add_face(list(reversed(ids)), list(reversed([(i / steps, 0.0), (i / steps, 1.0), ((i + 1) / steps, 1.0), ((i + 1) / steps, 0.0)])))
    parts = [housing, pivot("pivot_Loop", [("Medium", ring.translate(0, 0.0135, 0), "medium")], (0, 0, 0))]
    parts += common_mechanism((0.0, 0.018, 0.039), (0.0, 0.0125, -0.039), (-0.018, 0.012, 0.0), (0.018, 0.0125, 0.0))
    parts.append(pivot("pivot_Gear1", [("Gear", gear(0.009, 16), "steel")], (0.0, 0.013, 0.0)))
    parts.append(pivot("pivot_Gear2", [("Gear", gear(0.006, 12), "steel")], (0.0, 0.016, 0.0)))
    parts.append(linkage("brass"))
    return parts


def r_teletype():
    housing = Part("Housing")
    housing.mesh("Box", rounded_box(0.11, 0.05, 0.2, 0.006, center=(0, 0.025, 0)), "paint")
    housing.mesh("Window", rounded_box(0.06, 0.002, 0.12, 0.002, center=(0, 0.0505, 0)), "smoked")
    parts = [housing,
             reel("pivot_ReelSupply", 0.022, 0.01, "darkPlastic", at=(0, 0.051, -0.075)),
             reel("pivot_ReelTakeup", 0.022, 0.01, "darkPlastic", at=(0, 0.051, 0.075)),
             pivot("Medium", [("Tape", medium_tape(0.1, 0.022, 0.0515, 0.0), "medium")])]
    parts += common_mechanism((0, 0.055, -0.02), (0, 0.048, 0.025), (0.042, 0.051, 0.07), (0.042, 0.0512, -0.07))
    parts.append(pivot("pivot_Gear1", [("StarWheel", gear(0.007, 8, 0.002), "steel")], (-0.03, 0.052, 0.025)))
    parts.append(pivot("pivot_Gear2", [("Gear", gear(0.006, 10), "steel")], (-0.03, 0.052, 0.04)))
    parts.append(linkage())
    return parts


def r_cam_bank():
    housing = Part("Housing")
    housing.mesh("Base", rounded_box(0.12, 0.012, 0.2, 0.004, center=(0, 0.006, 0)), "paint")
    housing.mesh("Pedestals", combine(rounded_box(0.008, 0.04, 0.02, 0.002, center=(x, 0.03, -0.03)) for x in (-0.055, 0.055)), "paint")
    cams = Mesh()
    for i in range(9):
        cams.merge(gear(0.018 - (i % 3) * 0.002, 6 + i, 0.004).rotate_z(90).translate(-0.04 + 0.01 * i, 0, 0))
    parts = [housing,
             pivot("pivot_Drum", [("Cams", cams, "steel"), ("Medium", uv_cylinder(0.0125, 0.096, 48), "medium"),
                                  ("Shaft", cylinder(0.0025, 0.12, 12, axis="x"), "steel")], (0, 0.05, -0.03))]
    parts += common_mechanism((0, 0.075, -0.03), (0, 0.032, -0.005), (0.035, 0.012, 0.06), (-0.035, 0.0125, 0.06))
    parts.append(pivot("pivot_Gear1", [("Gear", gear(0.016, 24).rotate_z(90), "brass")], (0.064, 0.05, -0.03)))
    parts.append(pivot("pivot_Gear2", [("Gear", gear(0.008, 12).rotate_z(90), "brass")], (0.064, 0.05, 0.0)))
    parts.append(linkage())
    return parts


def r_jacquard():
    housing = Part("Housing")
    housing.mesh("Frame", combine([rounded_box(0.006, 0.09, 0.006, 0.001, center=(x, 0.045, z)) for x in (-0.05, 0.05) for z in (-0.06, 0.06)]), "wood")
    housing.mesh("Base", rounded_box(0.12, 0.01, 0.2, 0.002, center=(0, 0.005, 0)), "wood")
    housing.mesh("Beam", rounded_box(0.11, 0.008, 0.13, 0.002, center=(0, 0.092, 0)), "wood")
    prism = Mesh()
    sq = regular2(0.02, 4, 45)
    # square prism with per-face 0..1 UVs (frames along v around the prism)
    for i in range(4):
        a, b = sq[i], sq[(i + 1) % 4]
        ids = [prism.add_point((-0.045, a[0], a[1])), prism.add_point((0.045, a[0], a[1])),
               prism.add_point((0.045, b[0], b[1])), prism.add_point((-0.045, b[0], b[1]))]
        prism.add_face(ids, [(0.0, i / 4), (1.0, i / 4), (1.0, (i + 1) / 4), (0.0, (i + 1) / 4)])
    for i, f in enumerate(prism.faces):
        n = prism.face_normal(f)
        c = prism.points[f[0]]
        if n[1] * c[1] + n[2] * c[2] < 0:
            prism.faces[i] = list(reversed(f))
            prism.uvs[i] = list(reversed(prism.uvs[i]))
    prism.crease_deg = 30
    parts = [housing, pivot("pivot_Drum", [("Medium", prism, "medium"), ("Axle", cylinder(0.002, 0.11, 10, axis="x"), "steel")], (0, 0.06, -0.02))]
    parts += common_mechanism((0, 0.084, -0.02), (0, 0.035, -0.02), (0.035, 0.012, 0.07), (-0.035, 0.0105, 0.07))
    parts.append(pivot("pivot_Gear1", [("Gear", gear(0.014, 20).rotate_z(90), "brass")], (0.056, 0.06, -0.02)))
    parts.append(pivot("pivot_Gear2", [("Gear", gear(0.007, 10).rotate_z(90), "brass")], (0.056, 0.06, 0.003)))
    parts.append(linkage("wood"))
    return parts


def r_music_box():
    housing = Part("Housing")
    housing.mesh("Box", rounded_box(0.12, 0.03, 0.2, 0.004, center=(0, 0.015, 0)), "wood")
    housing.mesh("Plate", rounded_box(0.11, 0.003, 0.19, 0.001, center=(0, 0.0315, 0)), "brass")
    comb = Mesh()
    for i in range(18):
        comb.merge(rounded_box(0.0035, 0.0012, 0.02 + 0.0006 * i, 0.0002, center=(-0.04 + 0.0047 * i, 0.044, 0.004 + 0.0003 * i)))
    housing.mesh("Comb", comb, "steel")
    parts = [housing, pivot("pivot_Drum", [("Medium", uv_cylinder(0.014, 0.09, 64), "medium"),
                                           ("Axle", cylinder(0.002, 0.104, 10, axis="x"), "brass")], (0, 0.048, -0.022))]
    parts += common_mechanism((0, 0.068, -0.022), (0, 0.036, 0.03), (0.036, 0.034, 0.06), (-0.036, 0.0335, 0.06))
    parts.append(pivot("pivot_Gear1", [("Gear", gear(0.012, 20).rotate_z(90), "brass")], (0.05, 0.048, -0.022)))
    parts.append(pivot("pivot_Gear2", [("Fan", combine(rounded_box(0.012, 0.0005, 0.003, 0.0, center=(0, 0, 0)).rotate_y(a) for a in (0, 90)), "brass")],
                       (0.035, 0.036, 0.03)))
    parts.append(linkage("brass"))
    return parts


def r_glass_tube():
    housing = Part("Housing")
    housing.mesh("Base", rounded_box(0.11, 0.01, 0.22, 0.003, center=(0, 0.005, 0)), "darkPlastic")
    tube = lathe([(0.0125, -0.09), (0.0125, 0.09)], 48, cap_start=False, cap_end=False)
    tube.rotate_x(90).translate(0, 0.03, 0)
    housing.mesh("Tube", tube, "glass")
    housing.mesh("Caps", combine(cylinder(0.014, 0.01, 32, bevel=0.002, center=(0, 0.03, z), axis="z") for z in (-0.095, 0.095)), "chrome")
    parts = [housing,
             reel("pivot_ReelSupply", 0.02, 0.008, "chrome", at=(0.035, 0.01, -0.07)),
             reel("pivot_ReelTakeup", 0.02, 0.008, "chrome", at=(0.035, 0.01, 0.07)),
             pivot("Medium", [("Tape", medium_tape(0.17, 0.02, 0.0, 0.0), "medium")], (0, 0.03, 0))]
    parts += common_mechanism((0, 0.046, -0.05), (0, 0.016, 0.05), (-0.035, 0.01, 0.07), (-0.035, 0.0105, -0.07))
    parts.append(pivot("pivot_Gear1", [("Gear", gear(0.009, 14), "chrome")], (0.035, 0.012, 0.0)))
    parts.append(pivot("pivot_Gear2", [("Gear", gear(0.006, 10), "chrome")], (0.035, 0.012, 0.015)))
    parts.append(linkage("chrome"))
    return parts


def rmech(medium, along, frames, cps, capacity, **kw):
    d = dict(medium=medium, framesAlong=along, framesVisible=frames, charactersPerSecond=cps, springCapacity=capacity)
    d.update(kw)
    return d


RECORDER_VARIANTS = [
    Variant("telegraph_perforator", "Telegraph Perforator", "1890s",
            "Brass reels of paper tape and an eight-pin punch on a walnut base. Every keystroke is punched; Copy rewinds to the selection, Paste reads it back through sensing needles.",
            r_telegraph, mechanics=rmech("tape", "u", 40, 11.0, 220),
            sound=dict(pitch=1.0, body=0.5, brightness=0.8, decay=0.8, ring=0.4)),
    Variant("gear_drum", "Pinned Drum Memory", "1910s",
            "A drum of movable pins set by cam followers. Pins rise for each key; the drum turns back to read them.",
            r_gear_drum, mechanics=rmech("drum", "v", 64, 9.0, 260),
            sound=dict(pitch=0.85, body=0.7, brightness=0.6, decay=1.0, ring=0.5)),
    Variant("brass_chronograph", "Chronograph Loop", "1920s",
            "An endless tape loop under a domed crystal, like the inside of a giant pocket watch.",
            r_brass_chronograph, mechanics=rmech("loop", "u", 96, 12.0, 180),
            sound=dict(pitch=1.3, body=0.3, brightness=0.9, decay=1.1, ring=0.8)),
    Variant("teletype_reader", "Teletype Reader", "1950s",
            "Grey cabinet with a star-wheel reader and chadless tape under a smoked window. Fast and businesslike.",
            r_teletype, mechanics=rmech("tape", "u", 36, 16.0, 400),
            sound=dict(pitch=1.1, body=0.6, brightness=0.6, decay=0.6, ring=0.1)),
    Variant("cam_bank", "Cam Bank", "1930s",
            "A row of notched cams on a shaft stores the code; followers drop into notches to read.",
            r_cam_bank, mechanics=rmech("drum", "v", 48, 10.0, 240),
            sound=dict(pitch=0.9, body=0.7, brightness=0.55, decay=0.8, ring=0.3)),
    Variant("jacquard_cards", "Jacquard Cards", "1800s",
            "A chain of punched wooden cards over a square cylinder, borrowed from a loom.",
            r_jacquard, mechanics=rmech("cards", "v", 24, 6.0, 160),
            sound=dict(pitch=0.75, body=0.85, brightness=0.45, decay=0.9, ring=0.1)),
    Variant("music_box", "Music Box", "Clockwork",
            "A pinned cylinder plucks a steel comb while it replays. Paste sounds like a melody of your text.",
            r_music_box, mechanics=rmech("drum", "v", 64, 8.0, 200, plucksComb=True),
            sound=dict(pitch=1.2, body=0.4, brightness=0.9, decay=1.6, ring=1.0)),
    Variant("glass_tube", "Pneumatic Tube", "Retro-future",
            "Tape running through a glass tube between chrome reels; a puff of air advances each frame.",
            r_glass_tube, mechanics=rmech("tape", "u", 60, 14.0, 300, pneumatic=True),
            sound=dict(pitch=1.05, body=0.35, brightness=0.5, decay=0.7, ring=0.2)),
]
for _v in RECORDER_VARIANTS:
    _v.animation = dict(speed=1.0, overshoot=0.05)
