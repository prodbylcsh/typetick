"""Small procedural mesh toolkit used to author the typewriter component library.

All units are meters, +Y is up, +Z points toward the typist, +X to the right.
Meshes are polygon soups with shared vertices so that crease-aware normals can
be computed when they are written to USD.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Callable, Iterable, List, Optional, Sequence, Tuple

Vec2 = Tuple[float, float]
Vec3 = Tuple[float, float, float]


# ---------------------------------------------------------------------------
# vector helpers
# ---------------------------------------------------------------------------

def add(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def mul(a: Vec3, s: float) -> Vec3:
    return (a[0] * s, a[1] * s, a[2] * s)


def dot(a: Vec3, b: Vec3) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a: Vec3, b: Vec3) -> Vec3:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def length(a: Vec3) -> float:
    return math.sqrt(dot(a, a))


def norm(a: Vec3) -> Vec3:
    l = length(a)
    if l < 1e-12:
        return (0.0, 1.0, 0.0)
    return (a[0] / l, a[1] / l, a[2] / l)


def lerp3(a: Vec3, b: Vec3, t: float) -> Vec3:
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def rot_x(p: Vec3, deg: float) -> Vec3:
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return (p[0], p[1] * c - p[2] * s, p[1] * s + p[2] * c)


def rot_y(p: Vec3, deg: float) -> Vec3:
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return (p[0] * c + p[2] * s, p[1], -p[0] * s + p[2] * c)


def rot_z(p: Vec3, deg: float) -> Vec3:
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return (p[0] * c - p[1] * s, p[0] * s + p[1] * c, p[2])


# ---------------------------------------------------------------------------
# mesh container
# ---------------------------------------------------------------------------

@dataclass
class Mesh:
    points: List[Vec3] = field(default_factory=list)
    faces: List[List[int]] = field(default_factory=list)
    # Optional explicit per-face-corner UVs (same layout as faces).
    uvs: Optional[List[List[Vec2]]] = None
    crease_deg: float = 38.0

    # -- construction -------------------------------------------------------
    def add_point(self, p: Vec3) -> int:
        self.points.append((float(p[0]), float(p[1]), float(p[2])))
        return len(self.points) - 1

    def add_face(self, idx: Sequence[int], uv: Optional[Sequence[Vec2]] = None) -> None:
        self.faces.append(list(idx))
        if uv is not None:
            if self.uvs is None:
                self.uvs = [[(0.0, 0.0)] * len(f) for f in self.faces[:-1]]
            self.uvs.append(list(uv))
        elif self.uvs is not None:
            self.uvs.append([(0.0, 0.0)] * len(idx))

    def merge(self, other: "Mesh") -> "Mesh":
        base = len(self.points)
        if other.uvs is not None and self.uvs is None:
            self.uvs = [[(0.0, 0.0)] * len(f) for f in self.faces]
        self.points.extend(other.points)
        for i, f in enumerate(other.faces):
            self.faces.append([v + base for v in f])
            if self.uvs is not None:
                self.uvs.append(list(other.uvs[i]) if other.uvs is not None else [(0.0, 0.0)] * len(f))
        return self

    def copy(self) -> "Mesh":
        m = Mesh([p for p in self.points], [list(f) for f in self.faces], None, self.crease_deg)
        if self.uvs is not None:
            m.uvs = [list(u) for u in self.uvs]
        return m

    # -- transforms ---------------------------------------------------------
    def map(self, fn: Callable[[Vec3], Vec3]) -> "Mesh":
        self.points = [fn(p) for p in self.points]
        return self

    def translate(self, x: float = 0.0, y: float = 0.0, z: float = 0.0) -> "Mesh":
        return self.map(lambda p: (p[0] + x, p[1] + y, p[2] + z))

    def scale(self, sx: float, sy: Optional[float] = None, sz: Optional[float] = None) -> "Mesh":
        sy = sx if sy is None else sy
        sz = sx if sz is None else sz
        m = self.map(lambda p: (p[0] * sx, p[1] * sy, p[2] * sz))
        if sx * sy * sz < 0:
            m.flip()
        return m

    def rotate_x(self, deg: float) -> "Mesh":
        return self.map(lambda p: rot_x(p, deg))

    def rotate_y(self, deg: float) -> "Mesh":
        return self.map(lambda p: rot_y(p, deg))

    def rotate_z(self, deg: float) -> "Mesh":
        return self.map(lambda p: rot_z(p, deg))

    def flip(self) -> "Mesh":
        self.faces = [list(reversed(f)) for f in self.faces]
        if self.uvs is not None:
            self.uvs = [list(reversed(u)) for u in self.uvs]
        return self

    def bounds(self) -> Tuple[Vec3, Vec3]:
        xs = [p[0] for p in self.points]
        ys = [p[1] for p in self.points]
        zs = [p[2] for p in self.points]
        return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))

    # -- shading data ---------------------------------------------------------
    def face_normal(self, f: Sequence[int]) -> Vec3:
        # Newell's method: robust for n-gons.
        nx = ny = nz = 0.0
        for i in range(len(f)):
            a = self.points[f[i]]
            b = self.points[f[(i + 1) % len(f)]]
            nx += (a[1] - b[1]) * (a[2] + b[2])
            ny += (a[2] - b[2]) * (a[0] + b[0])
            nz += (a[0] - b[0]) * (a[1] + b[1])
        return norm((nx, ny, nz))

    def corner_normals(self) -> List[List[Vec3]]:
        fn = [self.face_normal(f) for f in self.faces]
        incident: List[List[int]] = [[] for _ in self.points]
        for fi, f in enumerate(self.faces):
            for v in f:
                incident[v].append(fi)
        cos_limit = math.cos(math.radians(self.crease_deg))
        out: List[List[Vec3]] = []
        for fi, f in enumerate(self.faces):
            n0 = fn[fi]
            corner = []
            for v in f:
                acc = (0.0, 0.0, 0.0)
                for fj in incident[v]:
                    if dot(fn[fj], n0) >= cos_limit:
                        acc = add(acc, fn[fj])
                corner.append(norm(acc) if length(acc) > 1e-9 else n0)
            out.append(corner)
        return out

    def corner_uvs(self, texel: float = 0.06) -> List[List[Vec2]]:
        if self.uvs is not None:
            return self.uvs
        out: List[List[Vec2]] = []
        for f in self.faces:
            n = self.face_normal(f)
            ax = max(range(3), key=lambda i: abs(n[i]))
            uv = []
            for v in f:
                p = self.points[v]
                if ax == 0:
                    uv.append((p[2] / texel, p[1] / texel))
                elif ax == 1:
                    uv.append((p[0] / texel, p[2] / texel))
                else:
                    uv.append((p[0] / texel, p[1] / texel))
            out.append(uv)
        return out


def combine(meshes: Iterable[Mesh]) -> Mesh:
    out = Mesh()
    for m in meshes:
        out.merge(m)
    return out


# ---------------------------------------------------------------------------
# primitives
# ---------------------------------------------------------------------------

def _axis_samples(h: float, r: float, inner_steps: int, band_steps: int) -> List[float]:
    """Sample positions along one axis of a rounded box (see rounded_box)."""
    vals = set()
    core = max(h - r, 0.0)
    for i in range(inner_steps + 1):
        vals.add(round(-core + 2 * core * i / max(inner_steps, 1), 9))
    if r > 0:
        for k in range(1, band_steps + 1):
            theta = math.radians(45.0 * k / band_steps)
            d = r * math.tan(theta)
            vals.add(round(core + d, 9))
            vals.add(round(-core - d, 9))
    else:
        vals.add(round(h, 9))
        vals.add(round(-h, 9))
    return sorted(vals)


def rounded_box(sx: float, sy: float, sz: float, r: float = 0.0, band: int = 3,
                center: Vec3 = (0.0, 0.0, 0.0)) -> Mesh:
    """Box of full size (sx, sy, sz) with every edge rounded by radius r."""
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    r = max(0.0, min(r, hx * 0.999, hy * 0.999, hz * 0.999))
    xs = _axis_samples(hx, r, 1, band)
    ys = _axis_samples(hy, r, 1, band)
    zs = _axis_samples(hz, r, 1, band)
    m = Mesh()
    index = {}

    def vid(p: Vec3) -> int:
        key = (round(p[0], 7), round(p[1], 7), round(p[2], 7))
        if key in index:
            return index[key]
        cx = max(-(hx - r), min(hx - r, p[0]))
        cy = max(-(hy - r), min(hy - r, p[1]))
        cz = max(-(hz - r), min(hz - r, p[2]))
        if r > 0:
            d = sub(p, (cx, cy, cz))
            q = add((cx, cy, cz), mul(norm(d), r))
        else:
            q = p
        i = m.add_point(add(q, center))
        index[key] = i
        return i

    def face_grid(us, vs, make):
        for i in range(len(us) - 1):
            for j in range(len(vs) - 1):
                a = vid(make(us[i], vs[j]))
                b = vid(make(us[i + 1], vs[j]))
                c = vid(make(us[i + 1], vs[j + 1]))
                d = vid(make(us[i], vs[j + 1]))
                m.add_face([a, b, c, d])

    face_grid(zs, ys, lambda z, y: (hx, y, -z))   # +X
    face_grid(zs, ys, lambda z, y: (-hx, y, z))   # -X
    face_grid(xs, zs, lambda x, z: (x, hy, -z))   # +Y
    face_grid(xs, zs, lambda x, z: (x, -hy, z))   # -Y
    face_grid(xs, ys, lambda x, y: (x, y, hz))    # +Z
    face_grid(xs, ys, lambda x, y: (-x, y, -hz))  # -Z
    _fix_winding_outward(m, center)
    return m


def box(sx: float, sy: float, sz: float, center: Vec3 = (0.0, 0.0, 0.0)) -> Mesh:
    return rounded_box(sx, sy, sz, 0.0, center=center)


def _fix_winding_outward(m: Mesh, center: Vec3) -> None:
    """Make every face of a convex-ish mesh point away from `center`."""
    for i, f in enumerate(m.faces):
        n = m.face_normal(f)
        c = mul(add_all([m.points[v] for v in f]), 1.0 / len(f))
        if dot(n, sub(c, center)) < 0:
            m.faces[i] = list(reversed(f))
            if m.uvs is not None:
                m.uvs[i] = list(reversed(m.uvs[i]))


def add_all(ps: Sequence[Vec3]) -> Vec3:
    acc = (0.0, 0.0, 0.0)
    for p in ps:
        acc = add(acc, p)
    return acc


def lathe(profile: Sequence[Vec2], segments: int = 48, start_deg: float = 0.0,
          sweep_deg: float = 360.0, cap_start: bool = True, cap_end: bool = True) -> Mesh:
    """Revolve a (radius, y) profile around the Y axis.

    The profile is listed from bottom to top; a radius of 0 closes the shape
    at the axis. With sweep < 360 the open sides are capped flat.
    """
    m = Mesh()
    full = abs(sweep_deg - 360.0) < 1e-6
    steps = segments if full else max(2, int(segments * sweep_deg / 360.0))
    rings: List[List[int]] = []
    for (r, y) in profile:
        ring = []
        count = steps if full else steps + 1
        if r <= 1e-9:
            idx = m.add_point((0.0, y, 0.0))
            ring = [idx] * count
        else:
            for s in range(count):
                a = math.radians(start_deg + sweep_deg * s / steps)
                ring.append(m.add_point((r * math.sin(a), y, r * math.cos(a))))
        rings.append(ring)
    count = len(rings[0])
    for i in range(len(rings) - 1):
        r0, r1 = rings[i], rings[i + 1]
        for s in range(steps):
            s1 = (s + 1) % count if full else s + 1
            quad = [r0[s], r0[s1], r1[s1], r1[s]]
            uniq = []
            for q in quad:
                if q not in uniq:
                    uniq.append(q)
            if len(uniq) >= 3:
                m.add_face(uniq)
    if full:
        if cap_start and profile[0][0] > 1e-9:
            c = m.add_point((0.0, profile[0][1], 0.0))
            for s in range(steps):
                m.add_face([c, rings[0][(s + 1) % count], rings[0][s]])
        if cap_end and profile[-1][0] > 1e-9:
            c = m.add_point((0.0, profile[-1][1], 0.0))
            for s in range(steps):
                m.add_face([c, rings[-1][s], rings[-1][(s + 1) % count]])
    else:
        # flat side caps of a partial revolve
        for side, s in ((0, 0), (1, steps)):
            loop = [rings[i][s] for i in range(len(rings))]
            axis_pts = [m.add_point((0.0, profile[i][1], 0.0)) for i in range(len(rings))]
            for i in range(len(rings) - 1):
                f = [axis_pts[i], loop[i], loop[i + 1], axis_pts[i + 1]]
                if side == 1:
                    f = list(reversed(f))
                m.add_face(f)
    # Profiles traced counter-clockwise in the (r, y) plane produce outward
    # normals by construction; clockwise ones (e.g. a dome traced from the top
    # down) are flipped so thin shells face the right way on both sides.
    if polygon_area([(r, y) for (r, y) in profile]) < 0:
        m.flip()
    return m


def cylinder(radius: float, height: float, segments: int = 40, bevel: float = 0.0,
             center: Vec3 = (0.0, 0.0, 0.0), axis: str = "y") -> Mesh:
    h = height / 2
    if bevel > 0:
        b = min(bevel, radius * 0.5, h * 0.9)
        prof = [(0.0, -h), (radius - b, -h), (radius - b * 0.3, -h + b * 0.3), (radius, -h + b),
                (radius, h - b), (radius - b * 0.3, h - b * 0.3), (radius - b, h), (0.0, h)]
    else:
        prof = [(0.0, -h), (radius, -h), (radius, h), (0.0, h)]
    m = lathe(prof, segments)
    return orient_axis(m, axis).translate(*center)


def orient_axis(m: Mesh, axis: str) -> Mesh:
    if axis == "x":
        m.rotate_z(-90)
    elif axis == "z":
        m.rotate_x(90)
    return m


def torus(R: float, r: float, seg: int = 40, sides: int = 14) -> Mesh:
    prof = []
    for i in range(sides + 1):
        a = math.radians(-90 + 360.0 * i / sides)
        prof.append((R + r * math.cos(a), r * math.sin(a)))
    m = Mesh()
    rings = []
    for (rr, y) in prof[:-1]:
        ring = []
        for s in range(seg):
            a = math.radians(360.0 * s / seg)
            ring.append(m.add_point((rr * math.sin(a), y, rr * math.cos(a))))
        rings.append(ring)
    n = len(rings)
    for i in range(n):
        r0, r1 = rings[i], rings[(i + 1) % n]
        for s in range(seg):
            m.add_face([r0[s], r0[(s + 1) % seg], r1[(s + 1) % seg], r1[s]])
    # orient outward from the tube center circle
    for i, f in enumerate(m.faces):
        nrm = m.face_normal(f)
        c = mul(add_all([m.points[v] for v in f]), 1.0 / len(f))
        radial = norm((c[0], 0.0, c[2]))
        tube_c = mul(radial, R)
        if dot(nrm, sub(c, tube_c)) < 0:
            m.faces[i] = list(reversed(f))
    return m


def sphere(r: float, seg: int = 32, rings: int = 16, squash: float = 1.0) -> Mesh:
    prof = []
    for i in range(rings + 1):
        a = math.radians(-90 + 180.0 * i / rings)
        prof.append((r * math.cos(a), r * math.sin(a) * squash))
    prof[0] = (0.0, prof[0][1])
    prof[-1] = (0.0, prof[-1][1])
    return lathe(prof, seg)


# ---------------------------------------------------------------------------
# 2D profiles + extrusion
# ---------------------------------------------------------------------------

def polygon_area(poly: Sequence[Vec2]) -> float:
    a = 0.0
    for i in range(len(poly)):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % len(poly)]
        a += x0 * y1 - x1 * y0
    return a / 2


def round_polygon(poly: Sequence[Vec2], radius: float, steps: int = 5) -> List[Vec2]:
    """Fillet every corner of a simple polygon."""
    if radius <= 0:
        return list(poly)
    out: List[Vec2] = []
    n = len(poly)
    for i in range(n):
        p0 = poly[(i - 1) % n]
        p1 = poly[i]
        p2 = poly[(i + 1) % n]
        d0 = (p0[0] - p1[0], p0[1] - p1[1])
        d2 = (p2[0] - p1[0], p2[1] - p1[1])
        l0 = math.hypot(*d0)
        l2 = math.hypot(*d2)
        if l0 < 1e-9 or l2 < 1e-9:
            continue
        r = min(radius, l0 * 0.45, l2 * 0.45)
        a = (p1[0] + d0[0] / l0 * r, p1[1] + d0[1] / l0 * r)
        b = (p1[0] + d2[0] / l2 * r, p1[1] + d2[1] / l2 * r)
        for k in range(steps + 1):
            t = k / steps
            # quadratic bezier a -> p1 -> b
            x = (1 - t) ** 2 * a[0] + 2 * (1 - t) * t * p1[0] + t * t * b[0]
            y = (1 - t) ** 2 * a[1] + 2 * (1 - t) * t * p1[1] + t * t * b[1]
            out.append((x, y))
    return out


def circle2(r: float, n: int = 32, cx: float = 0.0, cy: float = 0.0, start: float = 0.0) -> List[Vec2]:
    return [(cx + r * math.cos(math.radians(start + 360.0 * i / n)),
             cy + r * math.sin(math.radians(start + 360.0 * i / n))) for i in range(n)]


def regular2(r: float, n: int, start: float = 90.0) -> List[Vec2]:
    return circle2(r, n, start=start)


def rect2(w: float, h: float, cx: float = 0.0, cy: float = 0.0) -> List[Vec2]:
    return [(cx - w / 2, cy - h / 2), (cx + w / 2, cy - h / 2), (cx + w / 2, cy + h / 2), (cx - w / 2, cy + h / 2)]


def triangulate(poly: Sequence[Vec2]) -> List[Tuple[int, int, int]]:
    """Ear clipping for simple polygons (CCW or CW)."""
    n = len(poly)
    if n < 3:
        return []
    idx = list(range(n))
    ccw = polygon_area(poly) > 0
    tris: List[Tuple[int, int, int]] = []

    def is_convex(a, b, c):
        cr = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
        return cr > 1e-14 if ccw else cr < -1e-14

    def inside(p, a, b, c):
        def s(p1, p2, p3):
            return (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1])
        d1, d2, d3 = s(p, a, b), s(p, b, c), s(p, c, a)
        neg = d1 < 0 or d2 < 0 or d3 < 0
        pos = d1 > 0 or d2 > 0 or d3 > 0
        return not (neg and pos)

    guard = 0
    while len(idx) > 3 and guard < 10000:
        guard += 1
        found = False
        for k in range(len(idx)):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            a, b, c = poly[i0], poly[i1], poly[i2]
            if not is_convex(a, b, c):
                continue
            if any(inside(poly[j], a, b, c) for j in idx if j not in (i0, i1, i2)):
                continue
            tris.append((i0, i1, i2))
            idx.pop(k)
            found = True
            break
        if not found:
            break
    if len(idx) == 3:
        tris.append((idx[0], idx[1], idx[2]))
    if not ccw:
        tris = [(a, c, b) for (a, b, c) in tris]
    return tris


def extrude(poly: Sequence[Vec2], depth: float, center: bool = True, cap: bool = True,
            holes: Sequence[Sequence[Vec2]] = ()) -> Mesh:
    """Extrude a 2D polygon (XY plane) along +Z.

    Holes are supported by bridging them into the outer contour.
    """
    outline = list(poly)
    if polygon_area(outline) < 0:
        outline.reverse()
    for hole in holes:
        outline = _bridge_hole(outline, list(hole))
    z0 = -depth / 2 if center else 0.0
    z1 = z0 + depth
    m = Mesh()
    front = [m.add_point((x, y, z1)) for (x, y) in outline]
    back = [m.add_point((x, y, z0)) for (x, y) in outline]
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        a, b = outline[i], outline[j]
        if math.hypot(b[0] - a[0], b[1] - a[1]) < 1e-9:
            continue
        m.add_face([back[i], back[j], front[j], front[i]])
    if cap:
        for (a, b, c) in triangulate(outline):
            m.add_face([front[a], front[b], front[c]])
            m.add_face([back[c], back[b], back[a]])
    return m


def _bridge_hole(outer: List[Vec2], hole: List[Vec2]) -> List[Vec2]:
    if polygon_area(hole) > 0:
        hole = list(reversed(hole))
    # rightmost hole vertex connects to the nearest visible outer vertex
    hi = max(range(len(hole)), key=lambda i: hole[i][0])
    hp = hole[hi]
    best, best_d = 0, 1e9
    for i, p in enumerate(outer):
        if p[0] >= hp[0]:
            d = math.hypot(p[0] - hp[0], p[1] - hp[1])
            if d < best_d:
                best, best_d = i, d
    ring = hole[hi:] + hole[:hi + 1]
    eps = 1e-7
    bridged = outer[:best + 1] + [(ring[0][0] + eps, ring[0][1])] + ring[1:] + [outer[best]]
    return bridged + outer[best + 1:]


def extrude_x(poly_zy: Sequence[Vec2], width: float, center: bool = True) -> Mesh:
    """Extrude a side profile given as (z, y) pairs across X (for body panels)."""
    m = extrude([(z, y) for (z, y) in poly_zy], width, center)
    # currently: x=z_profile, y=y, z=extrusion -> rotate so extrusion is X
    m.map(lambda p: (p[2], p[1], p[0]))
    m.flip()
    return m


def annulus_sector(r_in: float, r_out: float, height: float, start_deg: float, end_deg: float,
                   steps: int = 32) -> Mesh:
    """Flat ring sector lying in XZ, extruded along Y (used for type segments)."""
    pts_out = []
    pts_in = []
    for i in range(steps + 1):
        a = math.radians(start_deg + (end_deg - start_deg) * i / steps)
        pts_out.append((r_out * math.sin(a), r_out * math.cos(a)))
        pts_in.append((r_in * math.sin(a), r_in * math.cos(a)))
    poly = pts_out + list(reversed(pts_in))
    m = extrude([(x, z) for (x, z) in poly], height)
    # extrude made XY profile + Z depth; we want XZ profile + Y depth
    m.map(lambda p: (p[0], p[2], p[1]))
    m.flip()
    return m


# ---------------------------------------------------------------------------
# sweeps
# ---------------------------------------------------------------------------

def bezier(points: Sequence[Vec3], steps: int = 24) -> List[Vec3]:
    out = []
    n = len(points) - 1
    for k in range(steps + 1):
        t = k / steps
        p = (0.0, 0.0, 0.0)
        for i, c in enumerate(points):
            b = math.comb(n, i) * (t ** i) * ((1 - t) ** (n - i))
            p = add(p, mul(c, b))
        out.append(p)
    return out


def polyline_smooth(points: Sequence[Vec3], steps: int = 8) -> List[Vec3]:
    """Catmull-Rom through all points."""
    pts = [points[0]] + list(points) + [points[-1]]
    out: List[Vec3] = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for k in range(steps):
            t = k / steps
            t2, t3 = t * t, t * t * t
            p = tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2
                             + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in range(3))
            out.append(p)  # type: ignore[arg-type]
    out.append(points[-1])
    return out


def sweep(path: Sequence[Vec3], radius, sides: int = 12, cap: bool = True,
          section: Optional[Sequence[Vec2]] = None) -> Mesh:
    """Sweep a circle (or custom section) along a path with parallel transport.

    `radius` may be a float or a function t -> radius for tapering.
    """
    m = Mesh()
    n = len(path)
    if section is None:
        section = circle2(1.0, sides)
    sides = len(section)
    tangents = []
    for i in range(n):
        a = path[max(i - 1, 0)]
        b = path[min(i + 1, n - 1)]
        tangents.append(norm(sub(b, a)))
    t0 = tangents[0]
    ref = (0.0, 1.0, 0.0) if abs(t0[1]) < 0.9 else (1.0, 0.0, 0.0)
    u = norm(cross(t0, ref))
    rings = []
    for i in range(n):
        t = tangents[i]
        u = norm(sub(u, mul(t, dot(u, t))))
        v = cross(t, u)
        rr = radius(i / max(n - 1, 1)) if callable(radius) else radius
        ring = []
        for (sx, sy) in section:
            off = add(mul(u, sx * rr), mul(v, sy * rr))
            ring.append(m.add_point(add(path[i], off)))
        rings.append(ring)
    for i in range(n - 1):
        for s in range(sides):
            a, b = rings[i][s], rings[i][(s + 1) % sides]
            c, d = rings[i + 1][(s + 1) % sides], rings[i + 1][s]
            m.add_face([a, d, c, b])
    if cap:
        c0 = m.add_point(path[0])
        c1 = m.add_point(path[-1])
        for s in range(sides):
            m.add_face([c0, rings[0][s], rings[0][(s + 1) % sides]])
            m.add_face([c1, rings[-1][(s + 1) % sides], rings[-1][s]])
    # orientation: make side faces point away from the path
    for i, f in enumerate(m.faces):
        if len(f) != 4:
            continue
        nrm = m.face_normal(f)
        c = mul(add_all([m.points[v] for v in f]), 0.25)
        # nearest path point
        best = min(path, key=lambda p: length(sub(p, c)))
        if dot(nrm, sub(c, best)) < 0:
            m.faces[i] = list(reversed(f))
    # caps: point along -t0 / +tn
    for i, f in enumerate(m.faces):
        if len(f) != 3:
            continue
        nrm = m.face_normal(f)
        if f[0] == len(m.points) - 2 and dot(nrm, tangents[0]) > 0:
            m.faces[i] = list(reversed(f))
        if f[0] == len(m.points) - 1 and dot(nrm, tangents[-1]) < 0:
            m.faces[i] = list(reversed(f))
    return m


def disc_top(radius: float, y: float, segments: int = 40, dome: float = 0.0, rings: int = 6,
             shape: Optional[Sequence[Vec2]] = None) -> Mesh:
    """A flat or domed cap with planar 0..1 UVs, used for key legends.

    `shape` (unit-ish 2D outline in XZ) replaces the circle for non-round keys.
    """
    m = Mesh()
    outline = shape if shape is not None else circle2(1.0, segments)
    center = m.add_point((0.0, y + dome, 0.0))
    prev = None
    ring_ids: List[List[int]] = []
    for k in range(1, rings + 1):
        t = k / rings
        ids = []
        for (ox, oz) in outline:
            x, z = ox * radius * t, oz * radius * t
            yy = y + dome * (1 - t * t)
            ids.append(m.add_point((x, yy, z)))
        ring_ids.append(ids)

    def uv_of(i):
        p = m.points[i]
        return (0.5 + p[0] / (2 * radius), 0.5 - p[2] / (2 * radius))

    n = len(outline)
    first = ring_ids[0]
    for s in range(n):
        f = [center, first[(s + 1) % n], first[s]]
        m.add_face(f, [uv_of(i) for i in f])
    for k in range(len(ring_ids) - 1):
        a, b = ring_ids[k], ring_ids[k + 1]
        for s in range(n):
            f = [a[s], a[(s + 1) % n], b[(s + 1) % n], b[s]]
            m.add_face(f, [uv_of(i) for i in f])
    # ensure upward facing
    for i, f in enumerate(m.faces):
        if m.face_normal(f)[1] < 0:
            m.faces[i] = list(reversed(f))
            m.uvs[i] = list(reversed(m.uvs[i]))  # type: ignore[index]
    return m


def strip_uv_plane(w: float, h: float, cols: int = 1, rows: int = 1) -> Mesh:
    """XY plane facing +Z with 0..1 UVs (used for media like punch tape windows)."""
    m = Mesh()
    ids = []
    for j in range(rows + 1):
        row = []
        for i in range(cols + 1):
            row.append(m.add_point((-w / 2 + w * i / cols, -h / 2 + h * j / rows, 0.0)))
        ids.append(row)
    for j in range(rows):
        for i in range(cols):
            f = [ids[j][i], ids[j][i + 1], ids[j + 1][i + 1], ids[j + 1][i]]
            uv = [(i / cols, j / rows), ((i + 1) / cols, j / rows), ((i + 1) / cols, (j + 1) / rows),
                  (i / cols, (j + 1) / rows)]
            m.add_face(f, uv)
    return m


def uv_cylinder(radius: float, length_: float, segments: int = 48) -> Mesh:
    """Open cylinder along X with UVs wrapping around (u = along X, v = angle)."""
    m = Mesh()
    rows = []
    for j in range(segments + 1):
        a = 2 * math.pi * j / segments
        row = []
        for i in range(2):
            x = -length_ / 2 + length_ * i
            row.append(m.add_point((x, radius * math.sin(a), radius * math.cos(a))))
        rows.append(row)
    for j in range(segments):
        f = [rows[j][0], rows[j][1], rows[j + 1][1], rows[j + 1][0]]
        uv = [(0.0, j / segments), (1.0, j / segments), (1.0, (j + 1) / segments), (0.0, (j + 1) / segments)]
        m.add_face(f, uv)
    for i, f in enumerate(m.faces):
        nrm = m.face_normal(f)
        c = mul(add_all([m.points[v] for v in f]), 0.25)
        if dot(nrm, (0.0, c[1], c[2])) < 0:
            m.faces[i] = list(reversed(f))
            m.uvs[i] = list(reversed(m.uvs[i]))  # type: ignore[index]
    return m
