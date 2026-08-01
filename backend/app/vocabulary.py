"""Closed vocabularies — the single source of truth for the Python side.

These MUST stay identical to `supabase/migrations/001_enums.sql` and
`lib/core/vocabulary/fc_vocabulary.dart`. A value that exists here but not in the database enum
produces a constraint violation on insert; a value that exists in the database but not here is
silently unreachable. `tests/test_vocabulary_parity.py` asserts the SQL file and this module agree,
so drift fails CI rather than production.

Adding a value is a migration (see skills/migrations/SKILL.md §2), not an edit to this file alone.
"""

from __future__ import annotations

from enum import Enum


class Gender(str, Enum):
    MALE = "male"
    FEMALE = "female"


class Category(str, Enum):
    SHIRT = "shirt"
    TSHIRT = "tshirt"
    KURTA = "kurta"
    KAMEEZ = "kameez"
    BLOUSE = "blouse"
    FROCK = "frock"
    DRESS = "dress"
    ABAYA = "abaya"
    WAISTCOAT = "waistcoat"
    JACKET = "jacket"
    COAT = "coat"
    SWEATER = "sweater"
    TROUSER = "trouser"
    JEANS = "jeans"
    SHALWAR = "shalwar"
    SKIRT = "skirt"
    SHORTS = "shorts"
    DUPATTA = "dupatta"
    SCARF = "scarf"
    SHOES = "shoes"
    SANDALS = "sandals"
    HEELS = "heels"
    ACCESSORY = "accessory"


class Occasion(str, Enum):
    CASUAL = "casual"
    FORMAL = "formal"
    PARTY = "party"
    CULTURAL = "cultural"


class Pattern(str, Enum):
    SOLID = "solid"
    STRIPED = "striped"
    PLAID = "plaid"
    FLORAL = "floral"
    PRINTED = "printed"


class Season(str, Enum):
    SUMMER = "summer"
    WINTER = "winter"
    ALL_SEASON = "all_season"


class Fit(str, Enum):
    SLIM = "slim"
    REGULAR = "regular"
    LOOSE = "loose"


class SleeveType(str, Enum):
    FULL = "full"
    HALF = "half"
    SLEEVELESS = "sleeveless"


class Neckline(str, Enum):
    ROUND = "round"
    V_NECK = "v_neck"
    COLLAR = "collar"


class Slot(str, Enum):
    TOP = "top"
    BOTTOM = "bottom"
    FULL_BODY = "full_body"
    OUTERWEAR = "outerwear"
    FOOTWEAR = "footwear"
    DRAPE = "drape"
    ACCESSORY = "accessory"


class OutfitSource(str, Enum):
    WARDROBE_BUILD = "wardrobe_build"
    PHOTO_UPLOAD = "photo_upload"


class ItemStatus(str, Enum):
    PENDING_REVIEW = "pending_review"
    ACTIVE = "active"


class RecommendationType(str, Enum):
    MAKEUP = "makeup"
    JEWELRY = "jewelry"
    ACCESSORY = "accessory"


# Mirrors 003_category_slots.sql. Duplicated here rather than fetched per request because it is
# migration-managed reference data that changes only when the enum changes — and the parity test
# fails if the two drift.
CATEGORY_SLOT: dict[Category, Slot] = {
    Category.SHIRT: Slot.TOP,
    Category.TSHIRT: Slot.TOP,
    Category.KURTA: Slot.TOP,
    Category.KAMEEZ: Slot.TOP,
    Category.BLOUSE: Slot.TOP,
    Category.FROCK: Slot.FULL_BODY,
    Category.DRESS: Slot.FULL_BODY,
    Category.ABAYA: Slot.FULL_BODY,
    Category.WAISTCOAT: Slot.OUTERWEAR,
    Category.JACKET: Slot.OUTERWEAR,
    Category.COAT: Slot.OUTERWEAR,
    Category.SWEATER: Slot.OUTERWEAR,
    Category.TROUSER: Slot.BOTTOM,
    Category.JEANS: Slot.BOTTOM,
    Category.SHALWAR: Slot.BOTTOM,
    Category.SKIRT: Slot.BOTTOM,
    Category.SHORTS: Slot.BOTTOM,
    Category.DUPATTA: Slot.DRAPE,
    Category.SCARF: Slot.DRAPE,
    Category.SHOES: Slot.FOOTWEAR,
    Category.SANDALS: Slot.FOOTWEAR,
    Category.HEELS: Slot.FOOTWEAR,
    Category.ACCESSORY: Slot.ACCESSORY,
}

# How much a patterned garment in this slot contributes to "too many bold patterns" (TRD §6).
# A patterned dupatta reads very differently from a patterned shoe.
SLOT_BOLD_WEIGHT: dict[Slot, float] = {
    Slot.TOP: 1.0,
    Slot.BOTTOM: 1.0,
    Slot.FULL_BODY: 1.0,
    Slot.OUTERWEAR: 0.8,
    Slot.DRAPE: 0.9,
    Slot.FOOTWEAR: 0.3,
    Slot.ACCESSORY: 0.2,
}

BOLD_PATTERNS: frozenset[Pattern] = frozenset(
    {Pattern.FLORAL, Pattern.PRINTED, Pattern.PLAID}
)
