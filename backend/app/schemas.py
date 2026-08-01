"""API request/response models — TRD §8, with the additions the UI actually needs.

Deviations from TRD §8, all deliberate:

- `user_id` is accepted but never trusted; identity comes from the JWT (see `auth.py`).
- Responses carry per-field `confidence`, without which the review screen cannot sort the shakiest
  fields to the top — the behaviour PRD §8 hangs the app's retention on.
- `thumbnail_path` replaces TRD's `thumbnail_url`: it is an object path, not a URL. Signed URLs
  expire, and a persisted expired URL is a permanently broken thumbnail.
- Errors use one envelope, so the client can distinguish retryable from fatal. An HTTP status alone
  cannot express that, and the UI has separate states for the two.
- `/evaluate-outfit` is split into two routes rather than one route accepting either JSON or
  multipart. Same two paths as TRD §8(a) and §8(b); a single route switching on content type is
  harder to validate and harder to document.
"""

from __future__ import annotations

from pydantic import BaseModel, Field

from .vocabulary import (
    Category,
    Fit,
    Neckline,
    Occasion,
    Pattern,
    RecommendationType,
    Season,
    SleeveType,
)


class ErrorBody(BaseModel):
    code: str
    message: str
    retryable: bool


class ErrorResponse(BaseModel):
    error: ErrorBody


class PaletteColour(BaseModel):
    hex: str
    weight: float


class ExtractedAttributes(BaseModel):
    category: Category
    style: str | None = None
    pattern: Pattern
    fabric: str | None = None
    sleeve_type: SleeveType | None = None
    neckline: Neckline | None = None
    fit: Fit
    season: Season
    occasion: Occasion

    primary_color: str
    secondary_color: str | None = None
    color_hex: str
    color_palette: list[PaletteColour]
    lab_l: float
    lab_a: float
    lab_b: float


class ExtractResponse(BaseModel):
    """The row is already written as `pending_review`; the client confirms it via the review screen.

    This inverts TRD §4.7 (Flutter inserts after review) in favour of TRD §1's own recommendation
    that the backend persist, so the client never handles raw model output — and so an abandoned
    review leaves a findable row rather than an orphaned storage object.
    """

    item_id: str
    attributes: ExtractedAttributes
    confidence: dict[str, float] = Field(default_factory=dict)
    thumbnail_path: str | None = None


class EvaluateRequest(BaseModel):
    """TRD §8(a) — build from already-digitized wardrobe items."""

    wardrobe_item_ids: list[str] = Field(min_length=2)
    user_id: str | None = None
    name: str | None = None
    persist: bool = True


class SwapSuggestion(BaseModel):
    replacement_item_id: str
    replaces_item_id: str
    new_score: int
    delta: int
    reason: str


class StyleRecommendation(BaseModel):
    type: RecommendationType
    suggestion_text: str


class EvaluateResponse(BaseModel):
    compatibility_score: int
    weak_item_id: str | None
    suggestion_text: str
    suggestions: list[SwapSuggestion] = Field(default_factory=list)
    recommendations: list[StyleRecommendation] = Field(default_factory=list)
    completeness_warning: str | None = None
    ruleset_version: str
    outfit_id: str | None = None


class DetectedGarment(BaseModel):
    """A garment found in an uploaded outfit photo (TRD §8(b)). Has no `wardrobe_items` row —
    nothing was digitized — so it is identified by index within this response only."""

    index: int
    attributes: ExtractedAttributes
    confidence: dict[str, float] = Field(default_factory=dict)


class EvaluatePhotoResponse(BaseModel):
    compatibility_score: int
    garments: list[DetectedGarment]
    # Index into `garments`, not a wardrobe_items id — these garments are not in the wardrobe.
    weak_garment_index: int | None
    suggestion_text: str
    recommendations: list[StyleRecommendation] = Field(default_factory=list)
    completeness_warning: str | None = None
    ruleset_version: str
    outfit_id: str | None = None
