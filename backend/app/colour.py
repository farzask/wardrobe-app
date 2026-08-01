"""Colour extraction and perceptual distance.

Two deliberate choices, both recorded as decision #4 in skills/README.md:

1. **Colour is measured, not inferred.** The palette comes from k-means over the garment's actual
   pixels, never from asking the vision model to name a hex code. Measuring is free, deterministic,
   and exactly correct; the model is worse on all three counts.

2. **Distance is CIEDE2000 over CIELAB, not HSV distance** as TRD §6 proposed. Two colours
   equidistant in HSV can look identical or clash badly — HSV is a convenience transform of RGB,
   not a perceptual space. CIEDE2000 is the standard perceptual metric.

The CIEDE2000 implementation below is verified against the Sharma-Wu-Dalal reference test vectors
in `tests/test_colour.py`. That formula has several published-errata traps (the hue-mean quadrant
rule and the Rt sign in particular), so it is checked against reference data rather than trusted.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

# D65 reference white, matching the sRGB standard illuminant.
_WHITE_X, _WHITE_Y, _WHITE_Z = 0.95047, 1.00000, 1.08883

_M_RGB_TO_XYZ = np.array(
    [
        [0.4124564, 0.3575761, 0.1804375],
        [0.2126729, 0.7151522, 0.0721750],
        [0.0193339, 0.1191920, 0.9503041],
    ]
)


@dataclass(frozen=True)
class Lab:
    l: float
    a: float
    b: float


@dataclass(frozen=True)
class PaletteEntry:
    hex: str
    weight: float
    lab: Lab


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    v = value.lstrip("#")
    if len(v) != 6:
        raise ValueError(f"expected a 6-digit hex colour, got {value!r}")
    return int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16)


def rgb_to_hex(rgb: tuple[int, int, int]) -> str:
    r, g, b = (max(0, min(255, int(round(c)))) for c in rgb)
    return f"#{r:02x}{g:02x}{b:02x}"


def _srgb_to_linear(channel: np.ndarray) -> np.ndarray:
    """Undo the sRGB transfer function. Skipping this is the single most common colour bug —
    it makes every dark colour read as far lighter than it is."""
    return np.where(channel <= 0.04045, channel / 12.92, ((channel + 0.055) / 1.055) ** 2.4)


def rgb_to_lab(rgb: tuple[int, int, int]) -> Lab:
    arr = np.array(rgb, dtype=float) / 255.0
    linear = _srgb_to_linear(arr)
    x, y, z = _M_RGB_TO_XYZ @ linear
    x, y, z = x / _WHITE_X, y / _WHITE_Y, z / _WHITE_Z

    delta = 6.0 / 29.0

    def f(t: float) -> float:
        return t ** (1.0 / 3.0) if t > delta**3 else t / (3 * delta**2) + 4.0 / 29.0

    fx, fy, fz = f(x), f(y), f(z)
    return Lab(l=116 * fy - 16, a=500 * (fx - fy), b=200 * (fy - fz))


def hex_to_lab(value: str) -> Lab:
    return rgb_to_lab(hex_to_rgb(value))


def ciede2000(c1: Lab, c2: Lab, kl: float = 1.0, kc: float = 1.0, kh: float = 1.0) -> float:
    """Perceptual distance between two colours. ~1.0 is a just-noticeable difference; >30 reads as
    a clearly different colour."""
    l1, a1, b1 = c1.l, c1.a, c1.b
    l2, a2, b2 = c2.l, c2.a, c2.b

    c1_ab = math.hypot(a1, b1)
    c2_ab = math.hypot(a2, b2)
    c_bar = (c1_ab + c2_ab) / 2.0

    # G expands the a* axis for low-chroma colours, where hue is perceptually unstable.
    g = 0.5 * (1 - math.sqrt(c_bar**7 / (c_bar**7 + 25.0**7))) if c_bar > 0 else 0.0

    a1p, a2p = (1 + g) * a1, (1 + g) * a2
    c1p, c2p = math.hypot(a1p, b1), math.hypot(a2p, b2)

    def _hue(bb: float, aa: float) -> float:
        if aa == 0 and bb == 0:
            return 0.0
        return math.degrees(math.atan2(bb, aa)) % 360.0

    h1p, h2p = _hue(b1, a1p), _hue(b2, a2p)

    dlp = l2 - l1
    dcp = c2p - c1p

    # Hue difference must take the short way around the circle.
    if c1p * c2p == 0:
        dhp = 0.0
    elif abs(h2p - h1p) <= 180:
        dhp = h2p - h1p
    elif h2p - h1p > 180:
        dhp = h2p - h1p - 360
    else:
        dhp = h2p - h1p + 360

    dhp_big = 2 * math.sqrt(c1p * c2p) * math.sin(math.radians(dhp) / 2.0)

    lp_bar = (l1 + l2) / 2.0
    cp_bar = (c1p + c2p) / 2.0

    # Quadrant-aware mean hue. Naively averaging 350° and 10° gives 180° — the opposite colour.
    if c1p * c2p == 0:
        hp_bar = h1p + h2p
    elif abs(h1p - h2p) <= 180:
        hp_bar = (h1p + h2p) / 2.0
    elif h1p + h2p < 360:
        hp_bar = (h1p + h2p + 360) / 2.0
    else:
        hp_bar = (h1p + h2p - 360) / 2.0

    t = (
        1
        - 0.17 * math.cos(math.radians(hp_bar - 30))
        + 0.24 * math.cos(math.radians(2 * hp_bar))
        + 0.32 * math.cos(math.radians(3 * hp_bar + 6))
        - 0.20 * math.cos(math.radians(4 * hp_bar - 63))
    )

    d_theta = 30 * math.exp(-(((hp_bar - 275) / 25.0) ** 2))
    rc = 2 * math.sqrt(cp_bar**7 / (cp_bar**7 + 25.0**7)) if cp_bar > 0 else 0.0

    sl = 1 + (0.015 * (lp_bar - 50) ** 2) / math.sqrt(20 + (lp_bar - 50) ** 2)
    sc = 1 + 0.045 * cp_bar
    sh = 1 + 0.015 * cp_bar * t
    rt = -math.sin(math.radians(2 * d_theta)) * rc

    term_l = dlp / (kl * sl)
    term_c = dcp / (kc * sc)
    term_h = dhp_big / (kh * sh)

    return math.sqrt(term_l**2 + term_c**2 + term_h**2 + rt * term_c * term_h)


def _kmeans(points: np.ndarray, k: int, iterations: int = 25) -> tuple[np.ndarray, np.ndarray]:
    """Minimal Lloyd's algorithm in Lab space.

    Deterministic by construction: centroids are seeded at fixed quantiles of the lightness-sorted
    points rather than at random. The backend contract requires the same image to produce the same
    attributes every time (skills/backend/SKILL.md §6), and random init would break that.
    """
    n = len(points)
    k = max(1, min(k, n))

    order = np.argsort(points[:, 0])
    seed_idx = np.linspace(0, n - 1, k).astype(int)
    centroids = points[order][seed_idx].copy()

    labels = np.zeros(n, dtype=int)
    for _ in range(iterations):
        d = np.linalg.norm(points[:, None, :] - centroids[None, :, :], axis=2)
        new_labels = np.argmin(d, axis=1)
        if np.array_equal(new_labels, labels):
            break
        labels = new_labels
        for i in range(k):
            member = points[labels == i]
            if len(member):
                centroids[i] = member.mean(axis=0)

    return centroids, labels


def extract_palette(
    rgb_pixels: np.ndarray,
    max_colours: int = 3,
    min_weight: float = 0.10,
) -> list[PaletteEntry]:
    """Cluster a garment's pixels into up to `max_colours` weighted colours, most dominant first.

    `rgb_pixels` is an (N, 3) uint8 array of garment pixels ONLY. Background must already be
    excluded by the caller — background pixels are the dominant cluster in most photos, and a
    palette of "wall beige" scores every outfit against the user's wall.

    Clustering happens in Lab, not RGB: equal distances in RGB are not equal perceptual differences,
    so RGB clustering splits greens finely and lumps all dark colours together.
    """
    if rgb_pixels.size == 0:
        raise ValueError("no pixels supplied; cannot extract a palette")

    pixels = rgb_pixels.reshape(-1, 3).astype(np.uint8)

    # Cap the work: a 320px thumbnail is ~100k pixels and the palette is stable well below that.
    # Strided rather than random sampling, again for determinism.
    if len(pixels) > 20_000:
        pixels = pixels[:: len(pixels) // 20_000]

    lab_points = np.array([[c.l, c.a, c.b] for c in (rgb_to_lab(tuple(p)) for p in pixels)])
    centroids, labels = _kmeans(lab_points, max_colours)

    entries: list[PaletteEntry] = []
    total = len(labels)
    for i, centroid in enumerate(centroids):
        weight = float(np.sum(labels == i)) / total
        if weight <= 0:
            continue
        member_rgb = pixels[labels == i]
        mean_rgb = tuple(member_rgb.mean(axis=0))
        entries.append(
            PaletteEntry(
                hex=rgb_to_hex(mean_rgb),
                weight=weight,
                lab=Lab(float(centroid[0]), float(centroid[1]), float(centroid[2])),
            )
        )

    entries.sort(key=lambda e: e.weight, reverse=True)

    # Drop slivers, but never drop the dominant colour however uniform the garment is.
    kept = [entries[0]] + [e for e in entries[1:] if e.weight >= min_weight]

    # Renormalise so weights sum to 1.0 — the DB check constraint and the harmony rule both assume
    # it, and dropping slivers above breaks it.
    total_weight = sum(e.weight for e in kept)
    return [
        PaletteEntry(hex=e.hex, weight=e.weight / total_weight, lab=e.lab) for e in kept
    ]
