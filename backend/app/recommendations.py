"""Gender-conditional styling recommendations — TRD §7.

Lookup-based, not ML, exactly as TRD §7 specifies. Inputs are the outfit's dominant palette and its
occasion; outputs are rows for `style_recommendations`.

**The gate is enforced here, server-side, from the profile.** PRD §4.5 says the male accessory path
runs only when `profiles.wears_accessories` is true. Gating in the UI instead would still compute
and ship the suggestion, which leaks the profile flag to anyone reading the response — and would
fail the validation matrix, which asserts the gate at the API boundary.

Note on PRD §7: that section listed this module as out of scope while §4.1, §4.5, TRD §7 and TRD §8
all specified it. Resolved in favour of building it (issue #1, skills/README.md); the stale PRD line
has been corrected.

The tables below are curated *content*. They should be reviewed the way copy is reviewed, and
revised freely — no engine logic depends on their wording.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from .colour import Lab
from .vocabulary import Gender, Occasion, RecommendationType


@dataclass(frozen=True)
class Recommendation:
    type: RecommendationType
    suggestion_text: str
    lookup_key: str


def palette_temperature(dominant: Lab, neutral_chroma: float = 15.0) -> str:
    """Classify the outfit's dominant colour as warm, cool, or neutral.

    Neutral is checked first: a near-grey has an essentially random hue angle, so classifying a
    charcoal trouser as "warm" would be noise driving a user-visible recommendation.
    """
    if math.hypot(dominant.a, dominant.b) < neutral_chroma:
        return "neutral"
    hue = math.degrees(math.atan2(dominant.b, dominant.a)) % 360.0
    # Warm half of the wheel: reds through yellows. Cool: greens through violets.
    return "warm" if (hue < 90.0 or hue >= 300.0) else "cool"


# --- Female --------------------------------------------------------------------

_MAKEUP: dict[tuple[str, str], str] = {
    ("casual", "warm"): "A natural daytime look — tinted moisturiser, warm peach or terracotta on the cheek, clear or nude gloss.",
    ("casual", "cool"): "A natural daytime look — sheer base, soft rose blush, a balm rather than a bold lip.",
    ("casual", "neutral"): "Keep it bare — light base, groomed brows, a touch of mascara. Neutral outfits look best with skin left alone.",
    ("formal", "warm"): "Polished and matte — soft bronze lid, defined brow, a muted brick or rosewood lip.",
    ("formal", "cool"): "Polished and matte — taupe or soft grey lid, clean liner, a mauve or berry lip.",
    ("formal", "neutral"): "Sharp and minimal — flawless base, a single wash of neutral shadow, a defined lip in a nude that suits your depth.",
    ("party", "warm"): "Go bold — warm gold or copper shimmer, a sharp wing, and either a strong lip or a strong eye, not both.",
    ("party", "cool"): "Go bold — smoky plum or silver shimmer, a sharp wing, and a deep berry or nude lip.",
    ("party", "neutral"): "A neutral outfit is a licence to go dramatic on the face — a full smoky eye or a true red lip will carry the whole look.",
    ("cultural", "warm"): "Traditional and warm — kajal-defined eyes, gold shimmer on the lid, a deep red or maroon lip.",
    ("cultural", "cool"): "Traditional with a cool base — kajal-defined eyes, soft silver or pearl on the lid, a rose or plum lip.",
    ("cultural", "neutral"): "Let the eyes lead — heavy kajal and lashes, a soft neutral lip, and the jewellery does the rest.",
}

_JEWELRY: dict[tuple[str, str], str] = {
    ("casual", "warm"): "Minimal and gold — small hoops or studs, one thin chain. Nothing that needs thinking about.",
    ("casual", "cool"): "Minimal and silver — studs, a fine chain, maybe a single ring.",
    ("casual", "neutral"): "Minimal, in whichever metal you wear most. One piece, not three.",
    ("formal", "warm"): "Restrained gold — a single good piece. A watch or a fine chain, not both.",
    ("formal", "cool"): "Restrained silver or white gold — studs and one bracelet. Formal outfits are ruined by clutter.",
    ("formal", "neutral"): "One deliberate piece in any metal. With a neutral outfit the jewellery is the only accent, so make it a good one.",
    ("party", "warm"): "Statement gold — chandelier earrings or a bold cuff. Pick one focal point.",
    ("party", "cool"): "Statement silver or stones — a strong necklace or dramatic earrings, never both at once.",
    ("party", "neutral"): "Go statement. A neutral party outfit is built to be the backdrop for one big piece.",
    ("cultural", "warm"): "Traditional gold — jhumkas, bangles, and a maang tikka if the occasion carries it.",
    ("cultural", "cool"): "Silver or oxidised — jhumkas and stacked bangles read beautifully against cool tones.",
    ("cultural", "neutral"): "Heavy traditional jewellery. A neutral cultural outfit is the classic setting for it.",
}

# --- Male ----------------------------------------------------------------------

_ACCESSORY: dict[tuple[str, str], str] = {
    ("casual", "warm"): "Brown leather — a casual strap watch and a matching belt. Keep the metal warm too.",
    ("casual", "cool"): "Black or navy leather, or a canvas strap. Steel watch, matching belt.",
    ("casual", "neutral"): "Anything goes — a steel or leather watch and a belt in the same family as your shoes.",
    ("formal", "warm"): "Brown leather belt matched to brown shoes, a slim dress watch on a leather strap. No bracelet.",
    ("formal", "cool"): "Black leather belt matched to black shoes, a slim steel or silver-cased watch. Nothing else on the wrist.",
    ("formal", "neutral"): "Match belt to shoes exactly, and keep the watch thin. Neutral formal outfits show every extra piece.",
    ("party", "warm"): "One strong piece — a gold-toned watch or a leather bracelet stack. Not both.",
    ("party", "cool"): "One strong piece — a dark-dial watch or a single silver bracelet. Sunglasses if it's daytime.",
    ("party", "neutral"): "A neutral outfit takes a bolder accessory than you'd normally wear. This is the time for the interesting watch.",
    ("cultural", "warm"): "Keep it sparse — a simple watch, and a shawl if the occasion carries one. Traditional outfits are not the place for a stack.",
    ("cultural", "cool"): "A plain steel or leather watch, nothing more. Let the outfit do the work.",
    ("cultural", "neutral"): "Almost nothing — a plain watch. Traditional neutrals are meant to read clean.",
}


def build_recommendations(
    gender: Gender | None,
    wears_accessories: bool | None,
    occasion: Occasion,
    dominant: Lab,
) -> list[Recommendation]:
    """Return the styling suggestions this user is entitled to. May legitimately be empty."""
    temperature = palette_temperature(dominant)
    key = (occasion.value, temperature)
    lookup_key = f"{occasion.value}/{temperature}"

    if gender is Gender.FEMALE:
        return [
            Recommendation(RecommendationType.MAKEUP, _MAKEUP[key], lookup_key),
            Recommendation(RecommendationType.JEWELRY, _JEWELRY[key], lookup_key),
        ]

    if gender is Gender.MALE:
        # PRD §4.1/§4.5: the module does not run at all when the user said they don't wear
        # accessories. `None` (never asked) is treated the same as False — never guess a yes.
        if wears_accessories is not True:
            return []
        return [
            Recommendation(RecommendationType.ACCESSORY, _ACCESSORY[key], lookup_key)
        ]

    # gender is None: the profile has not completed onboarding. No recommendations, no error —
    # the app routes such users to onboarding before they can reach outfit evaluation anyway.
    return []
