#!/usr/bin/env python3
"""Software preview renderer for the component library (no GPU needed).

    python3 Tools/ModelForge/preview.py sheet  out.png   # contact sheet of all variants
    python3 Tools/ModelForge/preview.py machine out.png [kind=variant ...]

The machine mode assembles a full typewriter with the same layout rules the
app uses (see Sources/TypetickScene/MachineLayout.swift) so the geometry and
anchors can be checked without building the app.
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from pxr import Gf, Usd, UsdGeom, UsdShade

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
LIB = os.path.join(ROOT, "Sources", "TypetickScene", "Resources", "Components")
sys.path.insert(0, HERE)
from forge.scene import ROLE_DEFAULTS  # noqa: E402


def manifest(kind):
    with open(os.path.join(LIB, kind, "manifest.json")) as fh:
        return json.load(fh)


def variant(kind, vid):
    for v in manifest(kind)["variants"]:
        if v["id"] == vid:
            return v
    raise KeyError(vid)


# ---------------------------------------------------------------------------

class Model:
    """Triangles grouped by part (top-level prim under the root)."""

    def __init__(self, path, palette):
        stage = Usd.Stage.Open(path)
        root = stage.GetDefaultPrim()
        self.parts = {}
        self.extra = {}
        cache = UsdGeom.XformCache()
        for top in root.GetChildren():
            if top.GetName() == "Looks":
                continue
            tris, cols, nrms, roles = [], [], [], []
            top_inv = cache.GetLocalToWorldTransform(top).GetInverse()
            top_local = cache.GetLocalToWorldTransform(top)
            for prim in Usd.PrimRange(top):
                if not prim.IsA(UsdGeom.Mesh):
                    continue
                mesh = UsdGeom.Mesh(prim)
                pts = np.array(mesh.GetPointsAttr().Get(), dtype=np.float64)
                counts = mesh.GetFaceVertexCountsAttr().Get()
                idx = mesh.GetFaceVertexIndicesAttr().Get()
                xf = cache.GetLocalToWorldTransform(prim)
                # transform relative to the part's own origin, then the part's local placement
                m = np.array(xf * top_inv * Gf.Matrix4d(top_local.ExtractRotationMatrix(), top_local.ExtractTranslation()))
                ph = np.c_[pts, np.ones(len(pts))] @ m
                pts = ph[:, :3]
                role = prim.GetName().split("__")[-1]
                nv = UsdGeom.PrimvarsAPI(mesh).GetPrimvar("normals").Get()
                nmat = np.array(xf * top_inv * Gf.Matrix4d(top_local.ExtractRotationMatrix(), top_local.ExtractTranslation()))[:3, :3]
                cn = (np.array(nv, dtype=np.float64) @ nmat) if nv is not None else None
                spec = dict(ROLE_DEFAULTS.get(role, ROLE_DEFAULTS["paint"]))
                color = palette.get(role, spec["color"])
                k = 0
                for c in counts:
                    face = idx[k:k + c]
                    for j in range(1, c - 1):
                        tris.append([pts[face[0]], pts[face[j]], pts[face[j + 1]]])
                        cols.append((color, spec["metallic"], spec["roughness"]))
                        roles.append(role)
                        if cn is not None:
                            nrms.append([cn[k], cn[k + j], cn[k + j + 1]])
                        else:
                            nrms.append([[0, 1, 0]] * 3)
                    k += c
            self.parts[top.GetName()] = (np.array(tris).reshape(-1, 3, 3), cols, top_local)
            self.extra[top.GetName()] = (np.array(nrms).reshape(-1, 3, 3), roles)


def mat_t(x, y, z):
    m = np.eye(4)
    m[3, :3] = (x, y, z)
    return m


def mat_s(x, y, z):
    m = np.eye(4)
    m[0, 0], m[1, 1], m[2, 2] = x, y, z
    return m


def mat_rx(deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    m = np.eye(4)
    m[1, 1], m[1, 2], m[2, 1], m[2, 2] = c, s, -s, c
    return m


def mat_ry(deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    m = np.eye(4)
    m[0, 0], m[0, 2], m[2, 0], m[2, 2] = c, -s, s, c
    return m


def mat_from_quat_align(a, b):
    """Rotation (row-vector convention) taking unit vector a to b."""
    a, b = np.array(a, float), np.array(b, float)
    a /= np.linalg.norm(a)
    b /= np.linalg.norm(b)
    v = np.cross(a, b)
    c = float(np.dot(a, b))
    if np.linalg.norm(v) < 1e-9:
        R = np.eye(3) if c > 0 else -np.eye(3)
    else:
        vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
        R = np.eye(3) + vx + vx @ vx * (1 / (1 + c))
    m = np.eye(4)
    m[:3, :3] = R.T
    return m


class Scene:
    def __init__(self):
        self.tris = []
        self.cols = []
        self.normals = []
        self.roles = []

    def add(self, model, part, m=np.eye(4), skip_local=False):
        tris, cols, local = model.parts[part]
        if len(tris) == 0:
            return
        flat = tris.reshape(-1, 3)
        if skip_local:
            # remove the authored placement of the part (anchors replace it)
            L = np.array(Gf.Matrix4d(local.ExtractRotationMatrix(), local.ExtractTranslation()))
            flat = (np.c_[flat, np.ones(len(flat))] @ np.linalg.inv(L))[:, :3]
        out = (np.c_[flat, np.ones(len(flat))] @ m)[:, :3]
        self.tris.append(out.reshape(-1, 3, 3))
        self.cols.extend(cols)
        nrm, roles = model.extra[part]
        nm = np.linalg.inv(m[:3, :3]).T if not skip_local else np.linalg.inv((np.linalg.inv(np.array(Gf.Matrix4d(local.ExtractRotationMatrix(), local.ExtractTranslation()))) @ m)[:3, :3]).T
        n2 = nrm.reshape(-1, 3) @ nm
        n2 /= np.maximum(np.linalg.norm(n2, axis=1, keepdims=True), 1e-9)
        self.normals.append(n2.reshape(-1, 3, 3))
        self.roles.extend(roles)

    def add_tris(self, tris, color, role="paper", uvs=None):
        t = np.array(tris).reshape(-1, 3, 3)
        self.tris.append(t)
        self.cols.extend([(color, 0.0, 0.8)] * len(t))
        e1, e2 = t[:, 1] - t[:, 0], t[:, 2] - t[:, 0]
        n = np.cross(e1, e2)
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        self.normals.append(np.repeat(n[:, None, :], 3, axis=1))
        self.roles.extend([role] * len(t))
        if uvs is not None:
            self.paper_uv = np.array(uvs).reshape(-1, 3, 2)

    def export(self, path, palettes):
        """Dump triangles grouped by role for the Blender look-dev render."""
        tris = np.concatenate(self.tris)
        nrm = np.concatenate(self.normals)
        roles = np.array(self.roles)
        cols = np.array([c[0] for c in self.cols], dtype=np.float64)
        out = {}
        for role in sorted(set(self.roles)):
            sel = roles == role
            out[f"{role}__pos"] = tris[sel].astype(np.float32)
            out[f"{role}__nrm"] = nrm[sel].astype(np.float32)
            out[f"{role}__col"] = cols[sel].astype(np.float32)
        if hasattr(self, "paper_uv"):
            out["paper__uv"] = self.paper_uv.astype(np.float32)
            out["paper__vprint"] = np.array([self.paper_vprint], dtype=np.float32)
        np.savez_compressed(path, **out)

    def render(self, path, eye, target, fov=32.0, size=(1200, 860), bg=(0.16, 0.13, 0.11)):
        W, H = size
        tris = np.concatenate(self.tris)
        eye, target = np.array(eye, float), np.array(target, float)
        f = target - eye
        f /= np.linalg.norm(f)
        r = np.cross(f, [0, 1, 0])
        r /= np.linalg.norm(r)
        u = np.cross(r, f)
        rel = tris - eye
        cx = rel @ r
        cy = rel @ u
        cz = rel @ f
        scale = (H / 2) / math.tan(math.radians(fov / 2))
        with np.errstate(divide="ignore", invalid="ignore"):
            sx = W / 2 + cx / cz * scale
            sy = H / 2 - cy / cz * scale
        e1 = tris[:, 1] - tris[:, 0]
        e2 = tris[:, 2] - tris[:, 0]
        n = np.cross(e1, e2)
        nl = np.linalg.norm(n, axis=1, keepdims=True)
        n = n / np.maximum(nl, 1e-12)
        light = np.array([-0.35, 0.85, 0.45])
        light /= np.linalg.norm(light)
        center = tris.mean(axis=1)
        view = eye - center
        view /= np.linalg.norm(view, axis=1, keepdims=True)
        facing = np.sum(n * view, axis=1)
        nn = np.where(facing[:, None] < 0, -n, n)  # two-sided shading, flag back faces
        img = np.zeros((H, W, 3))
        img[:] = bg
        zbuf = np.full((H, W), np.inf)
        back = np.zeros((H, W), bool)
        for i in range(len(tris)):
            if np.any(cz[i] <= 0.01):
                continue
            x0, x1 = int(max(min(sx[i]), 0)), int(min(max(sx[i]), W - 1)) + 1
            y0, y1 = int(max(min(sy[i]), 0)), int(min(max(sy[i]), H - 1)) + 1
            if x1 <= x0 or y1 <= y0:
                continue
            xs, ys = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
            (p0x, p1x, p2x), (p0y, p1y, p2y) = sx[i], sy[i]
            d = (p1y - p2y) * (p0x - p2x) + (p2x - p1x) * (p0y - p2y)
            if abs(d) < 1e-12:
                continue
            w0 = ((p1y - p2y) * (xs - p2x) + (p2x - p1x) * (ys - p2y)) / d
            w1 = ((p2y - p0y) * (xs - p2x) + (p0x - p2x) * (ys - p2y)) / d
            w2 = 1 - w0 - w1
            inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
            if not inside.any():
                continue
            z = 1.0 / (w0 / cz[i, 0] + w1 / cz[i, 1] + w2 / cz[i, 2])
            zb = zbuf[y0:y1, x0:x1]
            mask = inside & (z < zb)
            if not mask.any():
                continue
            zb[mask] = z[mask]
            col, metal, rough = self.cols[i]
            col = np.array(col)
            ndl = max(float(np.dot(nn[i], light)), 0.0)
            h = light + view[i]
            h /= np.linalg.norm(h)
            spec = max(float(np.dot(nn[i], h)), 0.0) ** (8 + 120 * (1 - rough)) * (0.25 + 0.9 * metal)
            amb = 0.22 + 0.12 * nn[i][1]
            if metal > 0.5:
                env = 0.35 + 0.35 * nn[i][1]
                shade = col * (amb + 0.55 * ndl + env * 0.5) + spec
            else:
                shade = col * (amb + 0.85 * ndl) + spec * 0.6
            img[y0:y1, x0:x1][mask] = np.clip(shade, 0, 1)
            back[y0:y1, x0:x1][mask] = facing[i] < 0
        out = (np.clip(img, 0, 1) ** (1 / 1.6) * 255).astype(np.uint8)
        Image.fromarray(out).save(path)
        return back.mean()


# ---------------------------------------------------------------------------
# machine assembly (mirrors MachineLayout.swift)

KEY_ROWS = [list("zxcvbnm,./"), list("asdfghjkl;'"), list("qwertyuiop[]"), list("1234567890-=")]


def keyboard_positions(kb):
    keys = []
    for row, chars in enumerate(KEY_ROWS):
        n = len(chars)
        z = kb["frontZ"] - row * kb["rowPitchZ"]
        y = kb["frontY"] + row * kb["rowRiseY"]
        for i, ch in enumerate(chars):
            x = (i - (n - 1) / 2) * kb["keyPitchX"] + kb["rowStaggerX"][row] + 0.5 * kb["keyPitchX"] * (row == 1) * 0
            keys.append((ch, (x, y, z), row))
    return keys


def assemble(sel, no_desk=False):
    sc = Scene()
    sc.no_desk = no_desk
    load = {}

    def model(kind):
        v = variant(kind, sel[kind])
        if kind not in load:
            load[kind] = (Model(os.path.join(LIB, kind, v["file"]), {k: tuple(c) for k, c in v["palette"].items()}), v)
        return load[kind]

    ch, chv = model("chassis")
    mech = chv["mechanics"]
    for p in ch.parts:
        sc.add(ch, p)
    A = mech["anchors"]
    car, carv = model("carriage")
    cm = carv["mechanics"]
    r = cm["platenRadius"]
    ca = np.array(A["carriage"])
    pa = math.radians(cm["printAngleDegrees"])
    P = ca + np.array([0, r * math.sin(pa), r * math.cos(pa)])
    column = 30
    page_w = 0.2159
    carriage_x = page_w / 2 - column * cm["pitch"]
    Mc = mat_t(ca[0] + carriage_x, ca[1], ca[2])
    for p in car.parts:
        sc.add(car, p, Mc)
    # paper
    add_paper(sc, cm, Mc)
    # knobs
    kn, _ = model("knobs")
    sc.add(kn, "Knob", mat_t(*cm["anchors"]["knobRight"]) @ Mc)
    sc.add(kn, "Knob", mat_ry(180) @ mat_t(*cm["anchors"]["knobLeft"]) @ Mc)
    lv, _ = model("returnLever")
    for p in lv.parts:
        sc.add(lv, p, mat_t(*cm["anchors"]["returnLever"]) @ Mc)
    bl, blv = model("paperBail")
    sx = cm["platenLength"] / blv["mechanics"]["nominalWidth"]
    sc.add(bl, "pivot_Bail", mat_s(sx, 1, 1) @ Mc)
    sc.add(bl, "pivot_ReleaseLever", mat_t(*cm["anchors"]["releaseLever"]) @ Mc)
    mr, mrv = model("marginRack")
    rs = cm["platenLength"] / mrv["mechanics"]["nominalWidth"]
    Mr = mat_t(*cm["anchors"]["marginRack"]) @ Mc
    sc.add(mr, "Rack", mat_s(rs, 1, 1) @ Mr)
    for col in (10, 75):
        sc.add(mr, "MarginStop", mat_t(-page_w / 2 + col * cm["pitch"], 0.004, 0) @ Mr)
    for col in mrv["mechanics"]["defaultTabs"]:
        sc.add(mr, "TabStop", mat_t(-page_w / 2 + col * cm["pitch"], 0.004, 0) @ Mr)
    # keys
    ky, kyv = model("keys")
    kb = mech["keyboard"]
    keys = keyboard_positions(kb)
    for ch_, pos, row in keys:
        sc.add(ky, "Key", mat_rx(-kyv["mechanics"]["tilt"]) @ mat_t(*pos))
    sc.add(ky, "SpaceBar", mat_t(0, kb["spaceY"], kb["spaceZ"]))
    # typebars
    tb, _ = model("typebars")
    b = mech["basket"]
    C = np.array(b["center"])
    n = len(keys)
    order = sorted(range(n), key=lambda i: keys[i][1][0] + 0.0001 * keys[i][2])
    for slot, ki in enumerate(order):
        a = math.radians(-b["arcDegrees"] / 2 + b["arcDegrees"] * slot / (n - 1))
        pivot = C + b["radius"] * np.array([math.sin(a), 0, math.cos(a)])
        to_p = P - pivot
        L = np.linalg.norm(to_p)
        horiz = np.array([pivot[0] - P[0], 0, pivot[2] - P[2]])
        horiz /= np.linalg.norm(horiz)
        tilt = math.radians(b["restTiltDegrees"])
        rest = horiz * math.cos(tilt) - np.array([0, 1, 0]) * math.sin(tilt)
        struck = slot == 20
        d = to_p / L if struck else rest
        M = mat_s(1, 1, L / 0.11) @ mat_from_quat_align([0, 0, 1], d) @ mat_t(*pivot)
        sc.add(tb, "Typebar", M)
    # ribbon + correction
    rb, rbv = model("ribbon")
    for part in rb.parts:
        if "Left" in part:
            sc.add(rb, part, mat_t(*A["spoolLeft"]), skip_local=True)
        elif "Right" in part:
            sc.add(rb, part, mat_t(*A["spoolRight"]), skip_local=True)
        else:
            sc.add(rb, part, mat_t(P[0], P[1] - rbv["mechanics"]["vibratorLift"], P[2] + 0.003))
    cr, _ = model("correction")
    sc.add(cr, "pivot_CorrSpoolLeft", mat_t(*A["correctionLeft"]), skip_local=True)
    sc.add(cr, "pivot_CorrSpoolRight", mat_t(*A["correctionRight"]), skip_local=True)
    sc.add(cr, "pivot_Lifter", mat_t(P[0], P[1] - 0.013, P[2] + 0.005))
    bel, _ = model("bell")
    for p in bel.parts:
        sc.add(bel, p, mat_t(*A["bell"]))
    rec, _ = model("recorder")
    for p in rec.parts:
        sc.add(rec, p, mat_t(*A["recorder"]))
    # desk
    if not getattr(sc, "no_desk", False):
        sc.add_tris([[(-0.6, 0, -0.5), (0.6, 0, -0.5), (0.6, 0, 0.5)], [(-0.6, 0, -0.5), (0.6, 0, 0.5), (-0.6, 0, 0.5)]], (0.35, 0.22, 0.13), "desk")
    return sc, P


def add_paper(sc, cm, Mc):
    r = cm["platenRadius"] + 0.0002
    exit_a = math.radians(cm["paperExitDegrees"])
    entry_a = math.radians(cm["paperEntryDegrees"])
    pts = []
    for i in range(30):
        a = entry_a + (exit_a - entry_a) * i / 29
        pts.append((r * math.sin(a), r * math.cos(a)))
    E = np.array(pts[-1])
    t = np.array([math.cos(exit_a), -math.sin(exit_a)])
    for i in range(1, 12):
        s = 0.012 * i
        pts.append(tuple(E + t * s))
    S = np.array(pts[0])
    tb = np.array([-math.cos(entry_a), math.sin(entry_a)])
    pts = [tuple(S + tb * 0.012 * i) for i in range(8, 0, -1)] + pts
    # arc length of each path point, measured back from the top end
    seg = [0.0]
    for i in range(1, len(pts)):
        seg.append(seg[-1] + math.dist(pts[i], pts[i - 1]))
    total = seg[-1]
    top_s = total            # the page's top edge sits at the top end of the path
    page_h = 0.2794
    tris, uvs = [], []
    w = 0.2159 / 2
    for i in range(len(pts) - 1):
        (y0, z0), (y1, z1) = pts[i], pts[i + 1]
        v0 = (top_s - seg[i]) / page_h
        v1 = (top_s - seg[i + 1]) / page_h
        a, b, c, d = (-w, y0, z0), (w, y0, z0), (w, y1, z1), (-w, y1, z1)
        tris += [[a, b, c], [a, c, d]]
        uvs += [[(0, v0), (1, v0), (1, v1)], [(0, v0), (1, v1), (0, v1)]]
    tris = np.array(tris)
    flat = tris.reshape(-1, 3)
    flat = (np.c_[flat, np.ones(len(flat))] @ Mc)[:, :3]
    sc.add_tris(flat.reshape(-1, 3, 3), (0.93, 0.92, 0.88), "paper", uvs)
    # where the printing line falls on the page (v from the top edge)
    pa = math.radians(cm["printAngleDegrees"])
    k = 8 + (pa - entry_a) / (exit_a - entry_a) * 29
    s_print = seg[int(k)] + (seg[int(k) + 1] - seg[int(k)]) * (k - int(k))
    sc.paper_vprint = (top_s - s_print) / page_h


DEFAULT = dict(chassis="atlas_upright", keys="glass_ring", typebars="slim_steel", carriage="classic_black",
               knobs="fluted_bakelite", returnLever="chrome_arm", paperBail="roller_bail", ribbon="open_metal",
               correction="chalk_cover", bell="classic_dome", marginRack="sliding_tabs", recorder="telegraph_perforator")


def sheet(path):
    kinds = [k["kind"] for k in json.load(open(os.path.join(LIB, "catalog.json")))["kinds"]]
    tiles = []
    for kind in kinds:
        for v in manifest(kind)["variants"]:
            m = Model(os.path.join(LIB, kind, v["file"]), {k: tuple(c) for k, c in v["palette"].items()})
            sc = Scene()
            for p in m.parts:
                sc.add(m, p)
            allt = np.concatenate(sc.tris).reshape(-1, 3)
            lo, hi = allt.min(0), allt.max(0)
            c = (lo + hi) / 2
            rad = np.linalg.norm(hi - lo) / 2
            eye = c + np.array([0.55, 0.75, 1.0]) / np.linalg.norm([0.55, 0.75, 1.0]) * rad * 3.1
            tile = f"/tmp/tile_{kind}_{v['id']}.png" if not os.environ.get("SCRATCH") else os.path.join(os.environ["SCRATCH"], f"tile_{kind}_{v['id']}.png")
            backfrac = sc.render(tile, eye, c, 36, (240, 200), (0.2, 0.2, 0.22))
            tiles.append((kind, v["name"], tile, backfrac))
            print(f"{kind:12s} {v['id']:22s} backfaces={backfrac:.3f}")
    cols = 8
    rows = math.ceil(len(tiles) / cols)
    out = Image.new("RGB", (cols * 240, rows * 220), (30, 30, 32))
    d = ImageDraw.Draw(out)
    for i, (kind, name, tile, bf) in enumerate(tiles):
        x, y = (i % cols) * 240, (i // cols) * 220
        out.paste(Image.open(tile), (x, y))
        d.text((x + 4, y + 202), f"{kind}: {name}", fill=(230, 230, 230))
    out.save(path)


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "export":
        sel = dict(DEFAULT)
        for a in sys.argv[3:]:
            k, v = a.split("=")
            sel[k] = v
        sc, P = assemble(sel, no_desk=True)
        sc.export(sys.argv[2], {})
        print("exported", sum(len(t) for t in sc.tris), "triangles; print point", P)
    elif mode == "sheet":
        sheet(sys.argv[2])
    else:
        sel = dict(DEFAULT)
        for a in sys.argv[3:]:
            k, v = a.split("=")
            sel[k] = v
        sc, P = assemble(sel)
        sc.render(sys.argv[2], eye=(0.0, 0.52, 0.50), target=(0.0, 0.11, -0.02), fov=40)
