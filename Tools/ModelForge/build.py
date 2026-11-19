#!/usr/bin/env python3
"""Generate the typewriter component library.

    python3 Tools/ModelForge/build.py            # everything
    python3 Tools/ModelForge/build.py bell keys  # only some kinds

For every component kind this writes, into
``Sources/TypetickScene/Resources/Components/<kind>/``:

* ``<variant>.usdz``  packaged, flattened binary the app loads at runtime
* ``manifest.json``   names, descriptions, mechanics, sound and animation data

plus a ``catalog.json`` index next to the kind folders. Human-readable
``.usda`` sources of every variant go to ``Tools/ModelForge/out/<kind>/``. Requires ``usd-core``
(``pip install usd-core``).
"""
from __future__ import annotations

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from forge.components import accessories, bail, carriage, chassis, keys, knobs, levers, ribbon, typebars  # noqa: E402
from forge.scene import ROLE_DEFAULTS, package_usdz, write_usd  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "Sources", "TypetickScene", "Resources", "Components")
# Readable .usda sources are reproducible from this generator, so they live in
# an ignored folder instead of the repository.
SRC_OUT = os.path.join(HERE, "out")

KINDS = [
    ("chassis", "Chassis", "The body and frame. Sets the keyboard rake, segment and shift mechanism.", chassis.VARIANTS),
    ("keys", "Keys", "Keycaps, key levers and space bar.", keys.VARIANTS),
    ("typebars", "Typebars", "The type arms that swing up and strike the paper.", typebars.VARIANTS),
    ("carriage", "Carriage", "Platen, frame and paper table. Sets pitch, width and return mechanics.", carriage.VARIANTS),
    ("knobs", "Platen Knobs", "The knobs that turn the platen; detents set the ratchet feel.", knobs.VARIANTS),
    ("returnLever", "Return Lever", "Line space and carriage return lever.", levers.VARIANTS),
    ("paperBail", "Paper Bail", "Holds the sheet against the platen; includes the paper release lever.", bail.VARIANTS),
    ("ribbon", "Ribbon", "Ink ribbon spools and the vibrator that lifts the ribbon for every strike.", ribbon.RIBBON_VARIANTS),
    ("correction", "Correction", "Correction tape spools and lifter used by Delete and Cut.", ribbon.CORRECTION_VARIANTS),
    ("bell", "Bell", "Margin bell and hammer.", accessories.BELL_VARIANTS),
    ("marginRack", "Margin Rack", "Margin stops and tab stops.", accessories.MARGIN_VARIANTS),
    ("recorder", "Recorder", "The mechanical clipboard bolted to the side of the machine.", accessories.RECORDER_VARIANTS),
]


def main(selected):
    os.makedirs(OUT, exist_ok=True)
    catalog = {"version": 1, "units": "meters", "upAxis": "Y", "kinds": [], "materialRoles": ROLE_DEFAULTS}
    for kind, title, blurb, variants in KINDS:
        entry = {"kind": kind, "title": title, "summary": blurb, "variants": [v.id for v in variants]}
        catalog["kinds"].append(entry)
        if selected and kind not in selected:
            continue
        folder = os.path.join(OUT, kind)
        os.makedirs(folder, exist_ok=True)
        manifest = {"kind": kind, "title": title, "summary": blurb, "variants": []}
        for v in variants:
            parts = v.build()
            os.makedirs(os.path.join(SRC_OUT, kind), exist_ok=True)
            usda = os.path.join(SRC_OUT, kind, f"{v.id}.usda")
            usdz = os.path.join(folder, f"{v.id}.usdz")
            write_usd(usda, kind, parts, v.palette, doc=f"Typetick {title}: {v.name}. {v.summary}")
            package_usdz(usda, usdz)
            manifest["variants"].append({
                "id": v.id, "name": v.name, "era": v.era, "summary": v.summary, "tags": v.tags,
                "file": f"{v.id}.usdz", "source": f"{v.id}.usda",
                "parts": [p.name for p in parts],
                "mechanics": v.mechanics, "sound": v.sound, "animation": v.animation,
                "palette": {k: list(c) for k, c in v.palette.items()},
            })
            print(f"  {kind:12s} {v.id:22s} parts={len(parts)}")
        with open(os.path.join(folder, "manifest.json"), "w") as fh:
            json.dump(manifest, fh, indent=2)
    with open(os.path.join(OUT, "catalog.json"), "w") as fh:
        json.dump(catalog, fh, indent=2)
    print("done ->", OUT)


if __name__ == "__main__":
    main(set(sys.argv[1:]))
