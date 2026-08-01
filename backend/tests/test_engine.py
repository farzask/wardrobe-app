"""Compatibility engine tests against a hand-labelled outfit corpus.

Per skills/backend/SKILL.md §6, the contract has two tiers:

- **Scores may be retuned.** TRD §12 says the weights are a first draft, so tests assert score
  ORDERING and bands, never exact numbers. A test pinning "this outfit scores 74" would have to be
  rewritten on every tune and would therefore be deleted rather than heeded.
- **Weak-link identity on the clear cases must not regress.** This is the assertion that actually
  protects the product requirement: PRD §8 says the whole value of the feature is that the feedback
  names the right item. A correct score with the wrong item named is a failure.
"""

from __future__ import annotations

import pytest

from app.colour import hex_to_lab
from app.engine import (
    Item,
    build_graph,
    completeness_warning,
    evaluate,
    suggest_swaps,
)
from app.ruleset import DEFAULT_RULESET, Ruleset
from app.vocabulary import Category, Fit, Occasion, Pattern, Season


def item(
    id: str,
    category: Category,
    hex_colour: str,
    colour_name: str,
    *,
    pattern: Pattern = Pattern.SOLID,
    occasion: Occasion = Occasion.CASUAL,
    season: Season = Season.ALL_SEASON,
    fit: Fit = Fit.REGULAR,
) -> Item:
    return Item(
        id=id,
        category=category,
        pattern=pattern,
        occasion=occasion,
        season=season,
        fit=fit,
        color_hex=hex_colour,
        lab=hex_to_lab(hex_colour),
        primary_color=colour_name,
    )


# --- The corpus ---------------------------------------------------------------

WHITE_SHIRT = item("white-shirt", Category.SHIRT, "#f2f2f0", "white", occasion=Occasion.FORMAL)
NAVY_TROUSER = item("navy-trouser", Category.TROUSER, "#1b2a4a", "navy", occasion=Occasion.FORMAL)
BLACK_SHOES = item("black-shoes", Category.SHOES, "#141414", "black", occasion=Occasion.FORMAL)

RED_SHIRT = item("red-shirt", Category.SHIRT, "#c0392b", "red")
GREEN_TROUSER = item("green-trouser", Category.TROUSER, "#2e8b57", "green")
ORANGE_SHIRT = item("orange-shirt", Category.SHIRT, "#e67e22", "orange")

BLUE_JEANS = item("blue-jeans", Category.JEANS, "#3b5c8a", "blue")
GREY_TSHIRT = item("grey-tshirt", Category.TSHIRT, "#8a8a8a", "grey")

PRINTED_SHIRT = item("printed-shirt", Category.SHIRT, "#b03a2e", "red", pattern=Pattern.PRINTED)
PRINTED_TROUSER = item(
    "printed-trouser", Category.TROUSER, "#2e5f8a", "blue", pattern=Pattern.PRINTED
)
PRINTED_SHOES = item("printed-shoes", Category.SHOES, "#2e5f8a", "blue", pattern=Pattern.PRINTED)
# Identical to PRINTED_TROUSER in colour and occasion, differing ONLY in pattern. The pattern tests
# below compare against this rather than against NAVY_TROUSER, which is formal — comparing a casual
# printed shirt to a formal trouser measures the occasion rule, not the pattern rule.
SOLID_TROUSER = item("solid-trouser", Category.TROUSER, "#2e5f8a", "blue")

WINTER_COAT = item(
    "winter-coat", Category.COAT, "#3d3d3d", "charcoal", season=Season.WINTER
)
SUMMER_SHORTS = item(
    "summer-shorts", Category.SHORTS, "#d9c9a3", "beige", season=Season.SUMMER
)

FORMAL_SHIRT = item("formal-shirt", Category.SHIRT, "#e8e8ea", "white", occasion=Occasion.FORMAL)
CASUAL_SHORTS = item("casual-shorts", Category.SHORTS, "#5a6b7a", "slate", occasion=Occasion.CASUAL)

KURTA = item("kurta", Category.KURTA, "#f0e6d2", "cream", occasion=Occasion.CULTURAL)
SHALWAR = item("shalwar", Category.SHALWAR, "#efe5d1", "cream", occasion=Occasion.CULTURAL)


class TestClearlyGoodOutfits:
    def test_navy_and_white_formal_scores_high(self):
        result = evaluate([WHITE_SHIRT, NAVY_TROUSER, BLACK_SHOES])
        assert result.score >= 85

    def test_a_good_outfit_names_no_weak_link(self):
        """Reporting a weak link on a genuinely good outfit trains users to ignore the feature.
        PRD §8 makes trust in this feedback the success condition for the whole screen."""
        result = evaluate([WHITE_SHIRT, NAVY_TROUSER, BLACK_SHOES])
        assert result.weak_item_id is None
        assert "works" in result.feedback.lower()

    def test_neutrals_pair_with_anything(self):
        """Grey and blue-jeans is the most ordinary outfit on earth. An engine that flags it is
        obviously wrong to any real user, whatever its score arithmetic says."""
        assert evaluate([GREY_TSHIRT, BLUE_JEANS]).score >= 85

    def test_matched_cultural_set_scores_high(self):
        """TRD §12 names non-Western garments as the accuracy risk. A kurta-shalwar set is the
        single most common outfit in the target wardrobe and must not be penalised for existing."""
        assert evaluate([KURTA, SHALWAR]).score >= 85


class TestClearlyBadOutfits:
    def test_clashing_hues_score_lower_than_harmonious(self):
        clash = evaluate([RED_SHIRT, GREEN_TROUSER]).score
        harmony = evaluate([GREY_TSHIRT, BLUE_JEANS]).score
        assert clash < harmony

    def test_formal_top_with_casual_bottom_is_flagged(self):
        """TRD §6 names this case explicitly."""
        result = evaluate([FORMAL_SHIRT, CASUAL_SHORTS])
        assert result.score < 75
        assert result.weak_item_id is not None

    def test_winter_with_summer_is_flagged(self):
        """TRD §6's own example: winter jacket + summer shorts."""
        result = evaluate([WINTER_COAT, SUMMER_SHORTS])
        assert result.weak_item_id is not None
        assert any(
            r.rule == "season" and r.score < 0.5
            for edge in build_graph([WINTER_COAT, SUMMER_SHORTS])
            for r in edge.rules
        )


class TestWeakLinkIdentity:
    """These assertions are the ones that must never regress."""

    def test_the_odd_item_out_is_named(self):
        """Two coherent formal pieces plus one loud casual one — the loud one is the weak link, not
        either of the two that agree with each other."""
        result = evaluate([WHITE_SHIRT, NAVY_TROUSER, ORANGE_SHIRT])
        assert result.weak_item_id == "orange-shirt"

    def test_weak_link_is_lowest_incident_weight_not_most_rules_failed(self):
        """An item can fail exactly one rule catastrophically. That item is what the user can see,
        and it must beat an item that fails three rules mildly."""
        result = evaluate([WHITE_SHIRT, NAVY_TROUSER, BLACK_SHOES, SUMMER_SHORTS])
        assert result.weak_item_id == "summer-shorts"

    def test_feedback_names_the_item_in_words(self):
        """PRD §4.4 and §8: the feedback must name the specific item, not describe the problem
        abstractly. A generic 'colours clash' fails the product requirement even with a right score."""
        result = evaluate([WHITE_SHIRT, NAVY_TROUSER, ORANGE_SHIRT])
        assert "orange" in result.feedback.lower()
        assert "shirt" in result.feedback.lower()


class TestPatternRule:
    def test_two_bold_patterns_are_penalised(self):
        """Only the pattern differs between the two outfits — same colour, same occasion."""
        assert evaluate([PRINTED_SHIRT, PRINTED_TROUSER]).score < evaluate(
            [PRINTED_SHIRT, SOLID_TROUSER]
        ).score

    def test_penalty_is_scaled_by_slot(self):
        """A printed shirt with printed trousers is a real problem. A printed shirt with patterned
        shoes barely registers. A flat rule would shout equally at both."""
        big = evaluate([PRINTED_SHIRT, PRINTED_TROUSER]).score
        small = evaluate([PRINTED_SHIRT, PRINTED_SHOES]).score
        assert small > big


class TestSwapSuggestions:
    def test_a_swap_that_improves_the_outfit_is_offered(self):
        outfit = [WHITE_SHIRT, NAVY_TROUSER, ORANGE_SHIRT]
        result = evaluate(outfit)
        suggestions = suggest_swaps(outfit, result.weak_item_id, [GREY_TSHIRT, RED_SHIRT])
        assert suggestions
        assert all(s.delta > 0 for s in suggestions)
        assert suggestions[0].delta >= suggestions[-1].delta  # best first

    def test_swaps_stay_in_the_same_slot(self):
        """Suggesting a trouser to replace a shirt is nonsense the graph must not permit."""
        outfit = [WHITE_SHIRT, NAVY_TROUSER, ORANGE_SHIRT]
        result = evaluate(outfit)
        suggestions = suggest_swaps(outfit, result.weak_item_id, [BLUE_JEANS, GREEN_TROUSER])
        assert suggestions == []

    def test_at_most_two_are_returned(self):
        """PRD §4.4 asks for 1-2 alternatives."""
        outfit = [WHITE_SHIRT, NAVY_TROUSER, ORANGE_SHIRT]
        result = evaluate(outfit)
        candidates = [GREY_TSHIRT, RED_SHIRT, PRINTED_SHIRT, FORMAL_SHIRT]
        assert len(suggest_swaps(outfit, result.weak_item_id, candidates)) <= 2


class TestContract:
    def test_a_single_item_is_an_error(self):
        with pytest.raises(ValueError):
            evaluate([WHITE_SHIRT])

    def test_score_is_an_int_in_range(self):
        result = evaluate([RED_SHIRT, GREEN_TROUSER])
        assert isinstance(result.score, int)
        assert 0 <= result.score <= 100

    def test_evaluation_is_deterministic(self):
        outfit = [WHITE_SHIRT, NAVY_TROUSER, ORANGE_SHIRT]
        a, b = evaluate(outfit), evaluate(outfit)
        assert (a.score, a.weak_item_id, a.feedback) == (b.score, b.weak_item_id, b.feedback)

    def test_ruleset_version_is_reported(self):
        """Persisted on every outfits row so a later retune cannot silently change the meaning of
        historical scores."""
        assert evaluate([WHITE_SHIRT, NAVY_TROUSER]).ruleset_version == DEFAULT_RULESET.version

    def test_rule_weights_must_sum_to_one(self):
        with pytest.raises(ValueError):
            Ruleset(weight_colour=0.9, weight_occasion=0.9)


class TestCompleteness:
    def test_missing_bottom_is_reported(self):
        assert "bottom" in (completeness_warning([WHITE_SHIRT, BLACK_SHOES]) or "")

    def test_full_body_garment_needs_no_top_or_bottom(self):
        """A frock is a complete outfit. An engine that demands a separate top and bottom would
        report every dress as incomplete."""
        frock = item("frock", Category.FROCK, "#7a3b5c", "plum")
        assert completeness_warning([frock, BLACK_SHOES]) is None

    def test_complete_outfit_has_no_warning(self):
        assert completeness_warning([WHITE_SHIRT, NAVY_TROUSER, BLACK_SHOES]) is None
