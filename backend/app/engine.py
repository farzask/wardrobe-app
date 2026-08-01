"""Outfit compatibility engine — TRD §6, formulated as a graph.

Graph engineering (skills/README.md): an outfit is a complete graph over its garments.

    nodes  = the items
    edges  = pairwise compatibility, scored by the four TRD §6 rule families
    score  = normalised mean edge weight, 0–100
    weak   = the node with the lowest mean incident edge weight
    swap   = the wardrobe item, in the weak node's slot, that most raises the total

The graph formulation is what makes "which item is the weak link" a well-defined query rather than
a heuristic. The obvious alternative — "the item that failed the most rules" — is wrong: an item
can fail exactly one rule catastrophically, and that is the one the user can see.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from itertools import combinations

from .colour import Lab, ciede2000
from .ruleset import DEFAULT_RULESET, Ruleset
from .vocabulary import (
    BOLD_PATTERNS,
    CATEGORY_SLOT,
    SLOT_BOLD_WEIGHT,
    Category,
    Fit,
    Occasion,
    Pattern,
    Season,
    Slot,
)


@dataclass(frozen=True)
class Item:
    id: str
    category: Category
    pattern: Pattern
    occasion: Occasion
    season: Season
    fit: Fit
    color_hex: str
    lab: Lab
    primary_color: str

    @property
    def slot(self) -> Slot:
        return CATEGORY_SLOT[self.category]


@dataclass(frozen=True)
class RuleScore:
    rule: str
    score: float
    explanation: str


@dataclass(frozen=True)
class Edge:
    a: str
    b: str
    weight: float
    rules: tuple[RuleScore, ...]

    @property
    def worst_rule(self) -> RuleScore:
        return min(self.rules, key=lambda r: r.score)


@dataclass(frozen=True)
class Evaluation:
    score: int
    weak_item_id: str | None
    feedback: str
    edges: tuple[Edge, ...]
    ruleset_version: str


# --- Rule families -----------------------------------------------------------


def _chroma(lab: Lab) -> float:
    return math.hypot(lab.a, lab.b)


def _hue_angle(lab: Lab) -> float:
    return math.degrees(math.atan2(lab.b, lab.a)) % 360.0


def _hue_difference(h1: float, h2: float) -> float:
    """Shortest way around the colour wheel, 0–180."""
    d = abs(h1 - h2) % 360.0
    return 360.0 - d if d > 180.0 else d


def colour_rule(a: Item, b: Item, rs: Ruleset) -> RuleScore:
    """Colour harmony, per TRD §6 but scored perceptually rather than by HSV distance.

    Order matters here. Neutrals are checked first because a neutral has an unstable hue angle —
    the hue of near-grey is essentially noise, so classifying grey-vs-red as a "clash" by hue band
    would be both wrong and the most visible possible failure of the engine.
    """
    ca, cb = _chroma(a.lab), _chroma(b.lab)

    if ca < rs.neutral_chroma or cb < rs.neutral_chroma:
        neutral = a if ca < cb else b
        return RuleScore(
            "colour",
            rs.score_neutral,
            f"{neutral.primary_color} is a neutral and pairs with anything",
        )

    delta_e = ciede2000(a.lab, b.lab)
    if delta_e < rs.monochrome_delta_e:
        return RuleScore(
            "colour",
            rs.score_monochrome,
            f"{a.primary_color} and {b.primary_color} are a tonal match",
        )

    hue_diff = _hue_difference(_hue_angle(a.lab), _hue_angle(b.lab))

    if hue_diff <= rs.analogous_max_hue:
        return RuleScore(
            "colour",
            rs.score_analogous,
            f"{a.primary_color} and {b.primary_color} are neighbouring colours",
        )
    if hue_diff >= rs.complementary_min_hue:
        return RuleScore(
            "colour",
            rs.score_complementary,
            f"{a.primary_color} and {b.primary_color} are complementary",
        )
    if hue_diff <= 60.0:
        return RuleScore(
            "colour",
            rs.score_near_miss,
            f"{a.primary_color} and {b.primary_color} are close but not close enough — "
            f"the mismatch reads as accidental",
        )
    return RuleScore(
        "colour",
        rs.score_clash,
        f"{a.primary_color} and {b.primary_color} clash",
    )


def occasion_rule(a: Item, b: Item, rs: Ruleset) -> RuleScore:
    score = rs.occasion_score(a.occasion, b.occasion)
    if score >= 0.9:
        expl = f"both read as {a.occasion.value}"
    else:
        expl = f"a {a.occasion.value} {a.category.value} with a {b.occasion.value} {b.category.value}"
    return RuleScore("occasion", score, expl)


def pattern_rule(a: Item, b: Item, rs: Ruleset) -> RuleScore:
    """At most one bold pattern per outfit (TRD §6).

    The penalty is scaled by both slots' bold weights, so printed-shirt + printed-trouser is
    punished hard while printed-shirt + printed-shoe barely registers. A flat rule would flag the
    second pairing as loudly as the first, which no one would agree with.
    """
    a_bold = a.pattern in BOLD_PATTERNS
    b_bold = b.pattern in BOLD_PATTERNS
    if not (a_bold and b_bold):
        return RuleScore("pattern", rs.score_pattern_ok, "patterns do not compete")

    severity = SLOT_BOLD_WEIGHT[a.slot] * SLOT_BOLD_WEIGHT[b.slot]
    score = rs.score_pattern_ok - severity * (rs.score_pattern_ok - rs.score_pattern_clash)
    return RuleScore(
        "pattern",
        score,
        f"{a.pattern.value} {a.category.value} and {b.pattern.value} {b.category.value} "
        f"compete for attention",
    )


def season_rule(a: Item, b: Item, rs: Ruleset) -> RuleScore:
    score = rs.season_score(a.season, b.season)
    if score >= rs.score_season_ok:
        return RuleScore("season", score, "seasons are compatible")
    return RuleScore(
        "season",
        score,
        f"a {a.season.value} {a.category.value} with a {b.season.value} {b.category.value}",
    )


# --- Graph -------------------------------------------------------------------


def build_edge(a: Item, b: Item, rs: Ruleset) -> Edge:
    """Combine the four rule scores into one edge weight, using a **weighted geometric mean**.

    An arithmetic mean is the obvious choice and it is wrong here. With weights summing to 1, a
    single catastrophic rule cannot pull the result far: a formal shirt with casual shorts fails
    the occasion rule outright (0.25) and still scores 78/100, because three passing rules dilute
    it. Every outfit then lands in a narrow band around 70-90 and the score stops discriminating —
    exactly the "technically meets the requirement, obviously fails it in spirit" case that
    skills/independent-validation/SKILL.md §6 exists to catch.

    A geometric mean is multiplicative: any rule scoring near zero drags the whole edge near zero,
    no matter how well the others do. That matches how outfits actually fail — one thing being
    badly wrong ruins the outfit, and three things being slightly off does not.
    """
    rules = (
        colour_rule(a, b, rs),
        occasion_rule(a, b, rs),
        pattern_rule(a, b, rs),
        season_rule(a, b, rs),
    )
    weights = (rs.weight_colour, rs.weight_occasion, rs.weight_pattern, rs.weight_season)

    # exp(Σ wᵢ·ln sᵢ). Scores are clamped away from zero so a single rule can drive the edge low
    # without driving it to a hard zero, which would make every outfit containing it score 0.
    log_sum = sum(w * math.log(max(r.score, 0.01)) for r, w in zip(rules, weights))
    return Edge(a=a.id, b=b.id, weight=math.exp(log_sum), rules=rules)


def build_graph(items: list[Item], rs: Ruleset = DEFAULT_RULESET) -> list[Edge]:
    return [build_edge(a, b, rs) for a, b in combinations(items, 2)]


# How readily a user can change a garment without rebuilding the outfit. Used only to break ties
# in weak-link selection; higher means "easier to swap, so name this one".
_SWAPPABILITY: dict[Slot, int] = {
    Slot.ACCESSORY: 6,
    Slot.FOOTWEAR: 5,
    Slot.OUTERWEAR: 4,
    Slot.DRAPE: 3,
    Slot.BOTTOM: 2,
    Slot.TOP: 1,
    Slot.FULL_BODY: 0,
}


def _mean_incident_weight(item_id: str, edges: list[Edge]) -> float:
    incident = [e.weight for e in edges if e.a == item_id or e.b == item_id]
    return sum(incident) / len(incident) if incident else 1.0


def evaluate(items: list[Item], rs: Ruleset = DEFAULT_RULESET) -> Evaluation:
    """Score an outfit and name its weak link."""
    if len(items) < 2:
        raise ValueError("an outfit needs at least two items to have any pairing to score")

    edges = build_graph(items, rs)
    score = int(round(100 * sum(e.weight for e in edges) / len(edges)))

    # The weak link is the node dragging the graph down, not the item that failed the most rules.
    #
    # Ties are real and common: a two-item outfit has exactly one edge, so both nodes carry
    # identical incident weight and "which is the weak link" is genuinely undetermined by the graph.
    # Broken by swappability — advise changing the more peripheral garment. Telling someone their
    # shoes don't work is useful; telling them their dress doesn't work is not.
    weak = min(
        items,
        key=lambda i: (_mean_incident_weight(i.id, edges), -_SWAPPABILITY[i.slot]),
    )
    weak_mean = _mean_incident_weight(weak.id, edges)

    # A genuinely good outfit has no weak link. Reporting one anyway trains users to ignore the
    # feature — PRD §8 hangs the whole value of this screen on the feedback being trustworthy.
    if weak_mean >= 0.85:
        return Evaluation(
            score=score,
            weak_item_id=None,
            feedback="This works. Nothing here is fighting anything else.",
            edges=tuple(edges),
            ruleset_version=rs.version,
        )

    weak_edges = [e for e in edges if e.a == weak.id or e.b == weak.id]
    worst_edge = min(weak_edges, key=lambda e: e.weight)
    worst_rule = worst_edge.worst_rule

    feedback = (
        f"The {weak.primary_color} {weak.category.value} is the weak link: {worst_rule.explanation}."
    )

    return Evaluation(
        score=score,
        weak_item_id=weak.id,
        feedback=feedback,
        edges=tuple(edges),
        ruleset_version=rs.version,
    )


@dataclass(frozen=True)
class Suggestion:
    replacement_item_id: str
    replaces_item_id: str
    new_score: int
    delta: int
    reason: str


def suggest_swaps(
    items: list[Item],
    weak_item_id: str,
    candidates: list[Item],
    rs: Ruleset = DEFAULT_RULESET,
    limit: int = 2,
) -> list[Suggestion]:
    """Graph search: hold the outfit fixed, replace one node, keep the best replacements.

    PRD §4.4 asks for 1–2 alternatives drawn from the user's own wardrobe. `candidates` must already
    be filtered to the user's active, non-deleted items in the weak item's slot — that filtering
    belongs to the query, not here.
    """
    weak = next((i for i in items if i.id == weak_item_id), None)
    if weak is None:
        return []

    base_score = evaluate(items, rs).score
    rest = [i for i in items if i.id != weak_item_id]

    scored: list[Suggestion] = []
    for candidate in candidates:
        if candidate.id == weak_item_id or candidate.slot != weak.slot:
            continue
        trial = evaluate(rest + [candidate], rs)
        if trial.score <= base_score:
            continue
        scored.append(
            Suggestion(
                replacement_item_id=candidate.id,
                replaces_item_id=weak_item_id,
                new_score=trial.score,
                delta=trial.score - base_score,
                reason=(
                    f"the {candidate.primary_color} {candidate.category.value} instead — "
                    f"scores {trial.score} against the rest of this outfit"
                ),
            )
        )

    scored.sort(key=lambda s: s.delta, reverse=True)
    return scored[:limit]


def completeness_warning(items: list[Item]) -> str | None:
    """An outfit needs either a full-body garment or both a top and a bottom.

    Kept out of the score deliberately: a missing bottom is not a *compatibility* problem, and
    folding it into the 0–100 would make the number mean two different things at once.
    """
    slots = {i.slot for i in items}
    if Slot.FULL_BODY in slots:
        return None
    missing = [s.value for s in (Slot.TOP, Slot.BOTTOM) if s not in slots]
    if missing:
        return f"This outfit has no {' and no '.join(missing)}."
    return None
