from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable, Dict, List, Sequence

from .scene import Part


@dataclass
class Variant:
    """One interchangeable design of a typewriter component.

    * ``build`` returns the top-level parts written to the USD file.
    * ``mechanics`` changes how the part behaves (geometry anchors, pitch,
      detents, timings). The app reads it from ``manifest.json``.
    * ``sound`` parameterizes the procedural synthesizer for this part.
    * ``animation`` scales/shapes the motion curves.
    * ``palette`` overrides material role colors (RGB 0..1).
    """
    id: str
    name: str
    era: str
    summary: str
    build: Callable[[], List[Part]]
    mechanics: Dict = field(default_factory=dict)
    sound: Dict = field(default_factory=dict)
    animation: Dict = field(default_factory=dict)
    palette: Dict[str, Sequence[float]] = field(default_factory=dict)
    tags: List[str] = field(default_factory=list)


def rgb(hex_str: str) -> List[float]:
    h = hex_str.lstrip("#")
    return [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
