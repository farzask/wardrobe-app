"""Gender-conditional recommendation gate — PRD §4.1, §4.5, TRD §7.

The gate is the requirement most likely to be implemented in the UI instead of the API, where it
would look correct while still computing and shipping the suggestion — leaking the user's
`wears_accessories` flag to anyone who reads the response body. These tests assert it at the
function boundary for that reason.
"""

from __future__ import annotations

import pytest

from app.colour import hex_to_lab
from app.recommendations import build_recommendations, palette_temperature
from app.vocabulary import Gender, Occasion, RecommendationType

WARM = hex_to_lab("#e67e22")   # orange
COOL = hex_to_lab("#2e5f8a")   # blue
NEUTRAL = hex_to_lab("#8a8a8a")  # grey


class TestMaleGate:
    def test_opted_in_male_gets_an_accessory_suggestion(self):
        recs = build_recommendations(Gender.MALE, True, Occasion.FORMAL, COOL)
        assert [r.type for r in recs] == [RecommendationType.ACCESSORY]

    def test_opted_out_male_gets_nothing(self):
        """PRD §4.5: 'Not shown at all if the user indicated at signup that they don't wear
        accessories.' Not hidden — not produced."""
        assert build_recommendations(Gender.MALE, False, Occasion.FORMAL, COOL) == []

    def test_male_who_was_never_asked_gets_nothing(self):
        """None means the question was never answered. Treated as no — never guess a yes."""
        assert build_recommendations(Gender.MALE, None, Occasion.FORMAL, COOL) == []

    @pytest.mark.parametrize("occasion", list(Occasion))
    def test_gate_holds_for_every_occasion(self, occasion):
        assert build_recommendations(Gender.MALE, False, occasion, WARM) == []


class TestFemale:
    def test_gets_makeup_and_jewelry(self):
        """PRD §4.5 specifies both, unconditionally — there is no opt-in for female users."""
        recs = build_recommendations(Gender.FEMALE, None, Occasion.PARTY, WARM)
        assert {r.type for r in recs} == {
            RecommendationType.MAKEUP,
            RecommendationType.JEWELRY,
        }

    def test_wears_accessories_is_irrelevant_for_female_users(self):
        a = build_recommendations(Gender.FEMALE, True, Occasion.CASUAL, COOL)
        b = build_recommendations(Gender.FEMALE, False, Occasion.CASUAL, COOL)
        assert [r.suggestion_text for r in a] == [r.suggestion_text for r in b]

    @pytest.mark.parametrize("occasion", list(Occasion))
    @pytest.mark.parametrize("dominant", [WARM, COOL, NEUTRAL])
    def test_every_combination_has_curated_copy(self, occasion, dominant):
        """The lookup tables must be total. A missing key would be a KeyError in production, on a
        screen the user reached by doing nothing unusual."""
        recs = build_recommendations(Gender.FEMALE, None, occasion, dominant)
        assert len(recs) == 2
        assert all(r.suggestion_text.strip() for r in recs)


class TestOnboardingIncomplete:
    def test_no_gender_yields_no_recommendations(self):
        assert build_recommendations(None, None, Occasion.CASUAL, WARM) == []


class TestPaletteTemperature:
    def test_grey_is_neutral_not_warm_or_cool(self):
        """A near-grey has an essentially random hue angle. Classifying charcoal as 'warm' would be
        noise driving user-visible copy."""
        assert palette_temperature(NEUTRAL) == "neutral"

    def test_orange_is_warm(self):
        assert palette_temperature(WARM) == "warm"

    def test_blue_is_cool(self):
        assert palette_temperature(COOL) == "cool"

    def test_black_and_white_are_neutral(self):
        assert palette_temperature(hex_to_lab("#000000")) == "neutral"
        assert palette_temperature(hex_to_lab("#ffffff")) == "neutral"
