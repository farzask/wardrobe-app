"""CIEDE2000 verified against the Sharma-Wu-Dalal (2005) reference test vectors.

These 34 pairs exist precisely because the CIEDE2000 formula has several traps that produce a
plausible-looking but wrong implementation: the quadrant rule for mean hue, the short-way-around
hue difference, and the sign of the Rt rotation term. Pairs 9-17 are the ones specifically designed
to catch a broken hue-quadrant rule.

An implementation that passes all of these is correct. One that "looks right" is not evidence.
"""

from __future__ import annotations

import numpy as np
import pytest

from app.colour import (
    Lab,
    ciede2000,
    extract_palette,
    hex_to_lab,
    rgb_to_hex,
    rgb_to_lab,
)

# (L1, a1, b1, L2, a2, b2, expected dE00)
SHARMA_VECTORS = [
    (50.0000, 2.6772, -79.7751, 50.0000, 0.0000, -82.7485, 2.0425),
    (50.0000, 3.1571, -77.2803, 50.0000, 0.0000, -82.7485, 2.8615),
    (50.0000, 2.8361, -74.0200, 50.0000, 0.0000, -82.7485, 3.4412),
    (50.0000, -1.3802, -84.2814, 50.0000, 0.0000, -82.7485, 1.0000),
    (50.0000, -1.1848, -84.8006, 50.0000, 0.0000, -82.7485, 1.0000),
    (50.0000, -0.9009, -85.5211, 50.0000, 0.0000, -82.7485, 1.0000),
    (50.0000, 0.0000, 0.0000, 50.0000, -1.0000, 2.0000, 2.3669),
    (50.0000, -1.0000, 2.0000, 50.0000, 0.0000, 0.0000, 2.3669),
    (50.0000, 2.4900, -0.0010, 50.0000, -2.4900, 0.0009, 7.1792),
    (50.0000, 2.4900, -0.0010, 50.0000, -2.4900, 0.0010, 7.1792),
    (50.0000, 2.4900, -0.0010, 50.0000, -2.4900, 0.0011, 7.2195),
    (50.0000, 2.4900, -0.0010, 50.0000, -2.4900, 0.0012, 7.2195),
    (50.0000, -0.0010, 2.4900, 50.0000, 0.0009, -2.4900, 4.8045),
    (50.0000, -0.0010, 2.4900, 50.0000, 0.0010, -2.4900, 4.8045),
    (50.0000, -0.0010, 2.4900, 50.0000, 0.0011, -2.4900, 4.7461),
    (50.0000, 2.5000, 0.0000, 50.0000, 0.0000, -2.5000, 4.3065),
    (50.0000, 2.5000, 0.0000, 73.0000, 25.0000, -18.0000, 27.1492),
    (50.0000, 2.5000, 0.0000, 61.0000, -5.0000, 29.0000, 22.8977),
    (50.0000, 2.5000, 0.0000, 56.0000, -27.0000, -3.0000, 31.9030),
    (50.0000, 2.5000, 0.0000, 58.0000, 24.0000, 15.0000, 19.4535),
    (50.0000, 2.5000, 0.0000, 50.0000, 3.1736, 0.5854, 1.0000),
    (50.0000, 2.5000, 0.0000, 50.0000, 3.2972, 0.0000, 1.0000),
    (50.0000, 2.5000, 0.0000, 50.0000, 1.8634, 0.5757, 1.0000),
    (50.0000, 2.5000, 0.0000, 50.0000, 3.2592, 0.3350, 1.0000),
    (60.2574, -34.0099, 36.2677, 60.4626, -34.1751, 39.4387, 1.2644),
    (63.0109, -31.0961, -5.8663, 62.8187, -29.7946, -4.0864, 1.2630),
    (61.2901, 3.7196, -5.3901, 61.4292, 2.2480, -4.9620, 1.8731),
    (35.0831, -44.1164, 3.7933, 35.0232, -40.0716, 1.5901, 1.8645),
    (22.7233, 20.0904, -46.6940, 23.0331, 14.9730, -42.5619, 2.0373),
    (36.4612, 47.8580, 18.3852, 36.2715, 50.5065, 21.2231, 1.4146),
    (90.8027, -2.0831, 1.4410, 91.1528, -1.6435, 0.0447, 1.4441),
    (90.9257, -0.5406, -0.9208, 88.6381, -0.8985, -0.7239, 1.5381),
    (6.7747, -0.2908, -2.4247, 5.8714, -0.0985, -2.2286, 0.6377),
    (2.0776, 0.0795, -1.1350, 0.9033, -0.0636, -0.5514, 0.9082),
]


@pytest.mark.parametrize("l1,a1,b1,l2,a2,b2,expected", SHARMA_VECTORS)
def test_ciede2000_matches_reference(l1, a1, b1, l2, a2, b2, expected):
    got = ciede2000(Lab(l1, a1, b1), Lab(l2, a2, b2))
    assert got == pytest.approx(expected, abs=1e-4)


def test_ciede2000_is_symmetric():
    a, b = Lab(50, 2.5, 0), Lab(73, 25, -18)
    assert ciede2000(a, b) == pytest.approx(ciede2000(b, a))


def test_ciede2000_identity_is_zero():
    a = Lab(42.0, 13.5, -7.25)
    assert ciede2000(a, a) == pytest.approx(0.0)


class TestLabConversion:
    def test_pure_white(self):
        lab = rgb_to_lab((255, 255, 255))
        assert lab.l == pytest.approx(100.0, abs=0.01)
        assert lab.a == pytest.approx(0.0, abs=0.01)
        assert lab.b == pytest.approx(0.0, abs=0.01)

    def test_pure_black(self):
        lab = rgb_to_lab((0, 0, 0))
        assert lab.l == pytest.approx(0.0, abs=0.01)

    def test_mid_grey_is_not_lightness_50(self):
        """The sRGB transfer function is why #808080 sits near L*=53.6, not 50. If this test reads
        50, the linearisation step has been skipped — the single most common colour bug."""
        lab = rgb_to_lab((128, 128, 128))
        assert lab.l == pytest.approx(53.585, abs=0.05)

    def test_red_is_warm_and_saturated(self):
        lab = rgb_to_lab((255, 0, 0))
        assert lab.a > 60
        assert lab.b > 40

    def test_hex_roundtrip(self):
        assert rgb_to_hex((18, 52, 86)) == "#123456"
        lab = hex_to_lab("#123456")
        assert lab.l < 40  # a dark navy


class TestPalette:
    def test_uniform_image_yields_one_colour(self):
        pixels = np.tile(np.array([[200, 30, 40]], dtype=np.uint8), (500, 1))
        palette = extract_palette(pixels)
        assert len(palette) == 1
        assert palette[0].weight == pytest.approx(1.0)

    def test_two_tone_image_yields_both(self):
        """The case TRD §3's single color_hex cannot represent: a red-and-white striped shirt must
        report red AND white, not the pink that averaging produces."""
        red = np.tile(np.array([[220, 20, 30]], dtype=np.uint8), (500, 1))
        white = np.tile(np.array([[245, 245, 245]], dtype=np.uint8), (500, 1))
        palette = extract_palette(np.vstack([red, white]))

        assert len(palette) >= 2
        lightness = sorted(e.lab.l for e in palette)
        assert lightness[0] < 60 and lightness[-1] > 85

        # And critically: no entry is the pink midpoint.
        for entry in palette:
            assert not (60 < entry.lab.l < 85), f"{entry.hex} is an averaged colour, not a real one"

    def test_weights_sum_to_one(self):
        """The DB check constraint and the harmony rule both assume this."""
        pixels = np.vstack(
            [
                np.tile(np.array([[10, 10, 200]], dtype=np.uint8), (600, 1)),
                np.tile(np.array([[240, 240, 10]], dtype=np.uint8), (300, 1)),
                np.tile(np.array([[10, 200, 10]], dtype=np.uint8), (100, 1)),
            ]
        )
        palette = extract_palette(pixels)
        assert sum(e.weight for e in palette) == pytest.approx(1.0)

    def test_is_deterministic(self):
        """skills/backend/SKILL.md §6 — the same image must produce the same attributes every time.
        Random k-means initialisation would silently break this."""
        rng = np.random.default_rng(7)
        pixels = rng.integers(0, 255, size=(2000, 3), dtype=np.uint8)
        first = extract_palette(pixels)
        second = extract_palette(pixels)
        assert [(e.hex, round(e.weight, 9)) for e in first] == [
            (e.hex, round(e.weight, 9)) for e in second
        ]

    def test_empty_input_is_an_error_not_a_default(self):
        with pytest.raises(ValueError):
            extract_palette(np.empty((0, 3), dtype=np.uint8))
