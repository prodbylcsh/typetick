"""Part hierarchy + USD export for typewriter components."""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Sequence, Tuple

from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdUtils, Vt

from .geom import Mesh

# Default physically based looks for every material role. The app rebuilds
# materials from the same role names, so these mostly matter for previews in
# external tools (Reality Composer Pro, Blender, Preview.app).
ROLE_DEFAULTS: Dict[str, dict] = {
    "paint":        dict(color=(0.04, 0.04, 0.045), metallic=0.0, roughness=0.32, clearcoat=0.8),
    "paintAccent":  dict(color=(0.78, 0.62, 0.30), metallic=0.6, roughness=0.35, clearcoat=0.3),
    "paintSecond":  dict(color=(0.86, 0.83, 0.74), metallic=0.0, roughness=0.38, clearcoat=0.6),
    "chrome":       dict(color=(0.92, 0.92, 0.94), metallic=1.0, roughness=0.08, clearcoat=0.0),
    "steel":        dict(color=(0.62, 0.63, 0.65), metallic=1.0, roughness=0.32, clearcoat=0.0),
    "blackSteel":   dict(color=(0.10, 0.10, 0.11), metallic=0.9, roughness=0.42, clearcoat=0.0),
    "brass":        dict(color=(0.86, 0.68, 0.36), metallic=1.0, roughness=0.26, clearcoat=0.0),
    "copper":       dict(color=(0.85, 0.50, 0.36), metallic=1.0, roughness=0.3, clearcoat=0.0),
    "rubber":       dict(color=(0.035, 0.035, 0.037), metallic=0.0, roughness=0.78, clearcoat=0.0),
    "redRubber":    dict(color=(0.42, 0.07, 0.05), metallic=0.0, roughness=0.72, clearcoat=0.0),
    "bakelite":     dict(color=(0.05, 0.035, 0.03), metallic=0.0, roughness=0.22, clearcoat=0.9),
    "keyTop":       dict(color=(0.05, 0.05, 0.05), metallic=0.0, roughness=0.25, clearcoat=0.7),
    "keyBody":      dict(color=(0.07, 0.07, 0.07), metallic=0.0, roughness=0.3, clearcoat=0.5),
    "glass":        dict(color=(0.9, 0.95, 0.95), metallic=0.0, roughness=0.02, clearcoat=1.0, opacity=0.35),
    "smoked":       dict(color=(0.18, 0.14, 0.11), metallic=0.0, roughness=0.06, clearcoat=1.0, opacity=0.6),
    "felt":         dict(color=(0.13, 0.20, 0.13), metallic=0.0, roughness=0.95, clearcoat=0.0),
    "plastic":      dict(color=(0.80, 0.78, 0.72), metallic=0.0, roughness=0.4, clearcoat=0.2),
    "darkPlastic":  dict(color=(0.12, 0.12, 0.13), metallic=0.0, roughness=0.45, clearcoat=0.1),
    "wood":         dict(color=(0.36, 0.20, 0.10), metallic=0.0, roughness=0.5, clearcoat=0.6),
    "enamel":       dict(color=(0.93, 0.92, 0.88), metallic=0.0, roughness=0.15, clearcoat=1.0),
    "tape":         dict(color=(0.93, 0.88, 0.70), metallic=0.0, roughness=0.8, clearcoat=0.0),
    "medium":       dict(color=(0.93, 0.88, 0.70), metallic=0.0, roughness=0.75, clearcoat=0.0),
    "ribbon":       dict(color=(0.03, 0.03, 0.03), metallic=0.0, roughness=0.85, clearcoat=0.0),
    "correction":   dict(color=(0.97, 0.96, 0.93), metallic=0.0, roughness=0.9, clearcoat=0.0),
    "scale":        dict(color=(0.90, 0.88, 0.80), metallic=0.0, roughness=0.5, clearcoat=0.2),
    "lamp":         dict(color=(1.0, 0.8, 0.5), metallic=0.0, roughness=0.3, clearcoat=0.0),
}


@dataclass
class Part:
    """An Xform in the exported hierarchy.

    Names starting with ``pivot_`` are animated by the app: their origin is the
    hinge/axle of the mechanism. Mesh names carry their material role after a
    double underscore (``Body__paint``).
    """
    name: str
    translate: Tuple[float, float, float] = (0.0, 0.0, 0.0)
    rotate: Tuple[float, float, float] = (0.0, 0.0, 0.0)  # XYZ euler degrees
    meshes: List[Tuple[str, Mesh, str]] = field(default_factory=list)
    children: List["Part"] = field(default_factory=list)

    def mesh(self, name: str, mesh: Mesh, role: str) -> "Part":
        self.meshes.append((name, mesh, role))
        return self

    def child(self, part: "Part") -> "Part":
        self.children.append(part)
        return part


def _mat_color(role: str, palette: Dict[str, Sequence[float]]) -> dict:
    base = dict(ROLE_DEFAULTS.get(role, ROLE_DEFAULTS["paint"]))
    if role in palette:
        base["color"] = tuple(palette[role][:3])
    return base


def write_usd(path: str, root_name: str, parts: Sequence[Part], palette: Dict[str, Sequence[float]],
              doc: str = "") -> None:
    if os.path.exists(path):
        os.remove(path)
    stage = Usd.Stage.CreateNew(path)
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    UsdGeom.SetStageMetersPerUnit(stage, 1.0)
    root = UsdGeom.Xform.Define(stage, f"/{root_name}")
    stage.SetDefaultPrim(root.GetPrim())
    if doc:
        stage.SetMetadata("comment", doc)
    looks_path = f"/{root_name}/Looks"
    UsdGeom.Scope.Define(stage, looks_path)
    materials: Dict[str, UsdShade.Material] = {}

    def material_for(role: str) -> UsdShade.Material:
        if role in materials:
            return materials[role]
        spec = _mat_color(role, palette)
        mat = UsdShade.Material.Define(stage, f"{looks_path}/{role}")
        sh = UsdShade.Shader.Define(stage, f"{looks_path}/{role}/Surface")
        sh.CreateIdAttr("UsdPreviewSurface")
        sh.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*spec["color"]))
        sh.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(float(spec["metallic"]))
        sh.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(float(spec["roughness"]))
        sh.CreateInput("clearcoat", Sdf.ValueTypeNames.Float).Set(float(spec.get("clearcoat", 0.0)))
        sh.CreateInput("clearcoatRoughness", Sdf.ValueTypeNames.Float).Set(0.08)
        if "opacity" in spec:
            sh.CreateInput("opacity", Sdf.ValueTypeNames.Float).Set(float(spec["opacity"]))
        mat.CreateSurfaceOutput().ConnectToSource(sh.ConnectableAPI(), "surface")
        materials[role] = mat
        return mat

    def emit(parent_path: str, part: Part) -> None:
        xf = UsdGeom.Xform.Define(stage, f"{parent_path}/{part.name}")
        api = UsdGeom.XformCommonAPI(xf)
        if any(abs(v) > 0 for v in part.translate):
            api.SetTranslate(Gf.Vec3d(*part.translate))
        if any(abs(v) > 0 for v in part.rotate):
            api.SetRotate(Gf.Vec3f(*part.rotate), UsdGeom.XformCommonAPI.RotationOrderXYZ)
        for (name, mesh, role) in part.meshes:
            _emit_mesh(stage, f"{parent_path}/{part.name}/{name}__{role}", mesh, material_for(role))
        for c in part.children:
            emit(f"{parent_path}/{part.name}", c)

    for p in parts:
        emit(f"/{root_name}", p)
    stage.GetRootLayer().Save()


def _emit_mesh(stage: Usd.Stage, path: str, mesh: Mesh, material: UsdShade.Material) -> None:
    gm = UsdGeom.Mesh.Define(stage, path)
    gm.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
    pts = [Gf.Vec3f(*p) for p in mesh.points]
    gm.CreatePointsAttr(Vt.Vec3fArray(pts))
    gm.CreateFaceVertexCountsAttr(Vt.IntArray([len(f) for f in mesh.faces]))
    gm.CreateFaceVertexIndicesAttr(Vt.IntArray([i for f in mesh.faces for i in f]))
    gm.CreateOrientationAttr(UsdGeom.Tokens.rightHanded)
    normals = mesh.corner_normals()
    flat_n = [Gf.Vec3f(*n) for face in normals for n in face]
    pv_api = UsdGeom.PrimvarsAPI(gm)
    nprim = pv_api.CreatePrimvar("normals", Sdf.ValueTypeNames.Normal3fArray, UsdGeom.Tokens.faceVarying)
    nprim.Set(Vt.Vec3fArray(flat_n))
    uvs = mesh.corner_uvs()
    st = pv_api.CreatePrimvar("st", Sdf.ValueTypeNames.TexCoord2fArray, UsdGeom.Tokens.faceVarying)
    st.Set(Vt.Vec2fArray([Gf.Vec2f(*uv) for face in uvs for uv in face]))
    lo, hi = mesh.bounds()
    gm.CreateExtentAttr(Vt.Vec3fArray([Gf.Vec3f(*lo), Gf.Vec3f(*hi)]))
    UsdShade.MaterialBindingAPI.Apply(gm.GetPrim()).Bind(material)


def package_usdz(usda_path: str, usdz_path: str) -> None:
    if os.path.exists(usdz_path):
        os.remove(usdz_path)
    # Flatten first so the package is a single self contained layer.
    stage = Usd.Stage.Open(usda_path)
    flat = usdz_path.replace(".usdz", ".flat.usdc")
    stage.Export(flat)
    ok = UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(flat), usdz_path)
    os.remove(flat)
    if not ok:
        raise RuntimeError(f"usdz packaging failed for {usda_path}")
