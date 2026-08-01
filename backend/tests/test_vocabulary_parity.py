"""The vocabulary exists in three places. This test proves they agree.

`supabase/migrations/001_enums.sql`, `backend/app/vocabulary.py` and
`lib/core/vocabulary/fc_vocabulary.dart` all declare the same closed sets. Drift between them is
the highest-probability silent failure in the system:

- a value in Python but not in Postgres → constraint violation on insert, at runtime
- a value in Postgres but not in Python → silently unreachable
- a value in Dart but not in Postgres → the user picks it on the review screen and the save fails

None of those surface in ordinary testing, and all three are caught here.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from app import vocabulary as v

REPO = Path(__file__).resolve().parents[2]
SQL = (REPO / "supabase" / "migrations" / "001_enums.sql").read_text(encoding="utf-8")
SLOTS_SQL = (REPO / "supabase" / "migrations" / "003_category_slots.sql").read_text(encoding="utf-8")
DART = (REPO / "lib" / "core" / "vocabulary" / "fc_vocabulary.dart").read_text(encoding="utf-8")


def sql_enum(name: str) -> set[str]:
    match = re.search(rf"create type {name} as enum\s*\((.*?)\);", SQL, re.S | re.I)
    if not match:
        raise AssertionError(f"{name} is not declared in 001_enums.sql")
    # Strip SQL comments before pulling quoted literals, or a commented-out value would count.
    body = re.sub(r"--[^\n]*", "", match.group(1))
    return set(re.findall(r"'([a-z_0-9]+)'", body))


def dart_enum(name: str) -> set[str]:
    match = re.search(rf"enum {name} \{{(.*?)\n\}}", DART, re.S)
    if not match:
        raise AssertionError(f"{name} is not declared in fc_vocabulary.dart")
    body = re.sub(r"//[^\n]*", "", match.group(1))
    return set(re.findall(r"""wire:\s*['"]([a-z_0-9]+)['"]""", body))


PAIRS = [
    ("fc_gender", v.Gender, "FcGender"),
    ("fc_category", v.Category, "FcCategory"),
    ("fc_occasion", v.Occasion, "FcOccasion"),
    ("fc_pattern", v.Pattern, "FcPattern"),
    ("fc_season", v.Season, "FcSeason"),
    ("fc_fit", v.Fit, "FcFit"),
    ("fc_sleeve_type", v.SleeveType, "FcSleeveType"),
    ("fc_neckline", v.Neckline, "FcNeckline"),
    ("fc_slot", v.Slot, "FcSlot"),
    ("fc_outfit_source", v.OutfitSource, "FcOutfitSource"),
    ("fc_item_status", v.ItemStatus, "FcItemStatus"),
    ("fc_recommendation_type", v.RecommendationType, "FcRecommendationType"),
]


@pytest.mark.parametrize("sql_name,py_enum,dart_name", PAIRS)
def test_python_matches_sql(sql_name, py_enum, dart_name):
    assert {m.value for m in py_enum} == sql_enum(sql_name)


@pytest.mark.parametrize("sql_name,py_enum,dart_name", PAIRS)
def test_dart_matches_sql(sql_name, py_enum, dart_name):
    assert dart_enum(dart_name) == sql_enum(sql_name)


def test_every_category_has_a_slot_in_python():
    """A category with no slot is invisible to the outfit builder and unreachable by the swap
    engine. 003_category_slots.sql asserts the same thing at migration time."""
    assert set(v.CATEGORY_SLOT) == set(v.Category)


def test_every_slot_has_a_bold_weight():
    assert set(v.SLOT_BOLD_WEIGHT) == set(v.Slot)


def test_python_slot_map_matches_the_sql_seed():
    """The two copies of the category → slot mapping must agree, or the backend and the database
    disagree about what can replace what."""
    rows = re.findall(r"\('([a-z_]+)',\s*'([a-z_]+)',\s*[\d.]+\)", SLOTS_SQL)
    assert rows, "no seed rows found in 003_category_slots.sql"
    from_sql = {category: slot for category, slot in rows}
    from_py = {c.value: s.value for c, s in v.CATEGORY_SLOT.items()}
    assert from_py == from_sql
