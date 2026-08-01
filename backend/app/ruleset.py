"""Versioned compatibility ruleset.

TRD §12 states plainly that the initial rule weights are a first draft needing real-world tuning.
Two consequences, both enforced here rather than left to discipline:

1. **No weight is a literal in the scorer.** Every tunable number lives in this file, so retuning
   is a data change with a version bump, not a code hunt.
2. **The version is persisted on every `outfits` row.** Without it, a retune silently changes the
   meaning of every score already shown to a user, and historical rows become uninterpretable.

Bumping `VERSION` is mandatory when any number below changes.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .vocabulary import Occasion, Season

VERSION = "rules-2026.08.01"


@dataclass(frozen=True)
class Ruleset:
    version: str = VERSION

    # Relative contribution of each rule family to an edge weight. Must sum to 1.0.
    # Combined as a weighted GEOMETRIC mean — see engine.build_edge for why.
    #
    # Season was originally 0.10 and had to be raised: at that weight the engine could not flag
    # TRD §6's own worked example (winter jacket + summer shorts), which scored 93/100. A rule
    # family too lightly weighted to fire on the case the spec cites is not implemented.
    weight_colour: float = 0.35
    weight_occasion: float = 0.30
    weight_season: float = 0.20
    weight_pattern: float = 0.15

    # --- Colour ------------------------------------------------------------
    # Below this CIEDE2000 distance two colours read as the same colour: a tonal/monochrome pairing.
    monochrome_delta_e: float = 12.0
    # Below this LCh chroma a colour is a neutral (black, white, grey, beige, navy). Neutrals pair
    # with everything — the most important rule in the whole engine, and the one whose absence makes
    # a rule engine feel obviously wrong to a real user.
    neutral_chroma: float = 15.0
    # Hue-angle bands, in degrees.
    analogous_max_hue: float = 30.0
    complementary_min_hue: float = 150.0
    score_monochrome: float = 0.95
    score_neutral: float = 1.00
    score_analogous: float = 0.90
    score_complementary: float = 0.85
    score_near_miss: float = 0.55   # 30–60°: close enough to look accidental rather than chosen
    score_clash: float = 0.30       # 60–150°: the genuine clash band

    # --- Pattern -----------------------------------------------------------
    # Two bold patterns in one outfit (TRD §6). Penalty scales with the slots' bold weights, so a
    # printed shirt + printed trouser is punished far harder than a printed shirt + printed shoe.
    score_pattern_ok: float = 1.00
    score_pattern_clash: float = 0.25

    # --- Season ------------------------------------------------------------
    score_season_ok: float = 1.00
    score_season_mismatch: float = 0.30   # winter jacket + summer shorts (TRD §6)

    # --- Occasion ----------------------------------------------------------
    # Symmetric distance between occasions. 1.0 = fully coherent, 0.0 = fully incoherent.
    # First draft, per TRD §12: formal↔casual is the classic failure; party sits nearer formal than
    # casual; cultural is deliberately generous because a kurta reads correctly almost anywhere.
    occasion_matrix: dict[tuple[str, str], float] = field(
        default_factory=lambda: {
            ("casual", "casual"): 1.00,
            ("formal", "formal"): 1.00,
            ("party", "party"): 1.00,
            ("cultural", "cultural"): 1.00,
            ("casual", "formal"): 0.25,
            ("casual", "party"): 0.55,
            ("casual", "cultural"): 0.70,
            ("formal", "party"): 0.75,
            ("formal", "cultural"): 0.70,
            ("party", "cultural"): 0.70,
        }
    )

    def occasion_score(self, a: Occasion, b: Occasion) -> float:
        key = (a.value, b.value)
        if key in self.occasion_matrix:
            return self.occasion_matrix[key]
        return self.occasion_matrix[(b.value, a.value)]

    def season_score(self, a: Season, b: Season) -> float:
        if a == Season.ALL_SEASON or b == Season.ALL_SEASON or a == b:
            return self.score_season_ok
        return self.score_season_mismatch

    def __post_init__(self) -> None:
        total = (
            self.weight_colour
            + self.weight_occasion
            + self.weight_pattern
            + self.weight_season
        )
        if abs(total - 1.0) > 1e-9:
            raise ValueError(f"rule weights must sum to 1.0, got {total}")


DEFAULT_RULESET = Ruleset()
