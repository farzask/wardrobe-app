"""Garment attribute extraction via Gemini vision — replaces TRD §2's fine-tuned CNN.

Decision #5 (skills/README.md): TRD §2 specified a fine-tuned EfficientNet-B0/MobileNetV3 on a
DeepFashion2-style taxonomy, while TRD §12 conceded no training data exists for the kurta /
shalwar / dupatta categories PRD §4.3 requires. A zero-shot vision model needs no dataset and
handles those categories on day one.

Two things this module does *not* leave to the model:

- **Colour.** Measured from pixels in `colour.py`. Asking a model to name a hex code is guessing at
  something that can be computed exactly.
- **Vocabulary compliance.** The response schema constrains every categorical field to the exact
  enum values in `vocabulary.py`, so an out-of-vocabulary label cannot reach the database. This is
  the whole reason for using structured output rather than parsing prose.

CONFIDENCE IS SELF-REPORTED. The model's `confidence` numbers are not calibrated probabilities —
they are the model's own guess at its own certainty. They are good enough for their one job, which
is ordering the review screen so the user checks the shakiest field first (PRD §8). They must not
be used to auto-accept a field or to gate anything.
"""

from __future__ import annotations

import asyncio
import logging

from google import genai
from google.genai import types
from pydantic import BaseModel, Field

from .config import Settings
from .vocabulary import (
    Category,
    Fit,
    Neckline,
    Occasion,
    Pattern,
    Season,
    SleeveType,
)

logger = logging.getLogger(__name__)


class ExtractionError(RuntimeError):
    def __init__(self, message: str, *, retryable: bool) -> None:
        super().__init__(message)
        self.retryable = retryable


class GarmentAttributes(BaseModel):
    """The structured output contract. Every categorical field is an enum, so the model physically
    cannot return a value the database would reject."""

    category: Category
    style: str = Field(description="Free-form sub-style, e.g. 'button-down', 'polo', 'A-line'.")
    pattern: Pattern
    fabric: str = Field(description="Best guess at fabric, e.g. 'cotton', 'denim', 'silk'.")
    sleeve_type: SleeveType | None = None
    neckline: Neckline | None = None
    fit: Fit
    season: Season
    occasion: Occasion
    primary_color_name: str = Field(description="Plain-English colour name, e.g. 'navy', 'mustard'.")
    secondary_color_name: str | None = None

    # Normalised (x0, y0, x1, y1), each 0–1, of the garment in the frame.
    box_x0: float = 0.0
    box_y0: float = 0.0
    box_x1: float = 1.0
    box_y1: float = 1.0

    confidence: dict[str, float] = Field(
        default_factory=dict,
        description="Self-reported 0-1 confidence per attribute name.",
    )

    @property
    def box(self) -> tuple[float, float, float, float]:
        return (self.box_x0, self.box_y0, self.box_x1, self.box_y1)


class GarmentList(BaseModel):
    garments: list[GarmentAttributes]


_PROMPT_SINGLE = """You are reading a photograph of a single clothing item for a wardrobe app.

Identify the garment and fill in every field. The app supports both Western and South Asian
clothing — kurta, kameez, shalwar, dupatta, abaya are all valid categories and should be used when
they are what you actually see. Do not force a South Asian garment into a Western category.

For `box`, give the normalised bounding box of the garment itself, excluding the background,
hanger, or the person wearing it as far as you can.

For `confidence`, give an honest 0-1 value per attribute you filled in. Use low values where you
are genuinely unsure — the app shows the user your least-confident answers first so they can
correct them, so an overconfident answer is worse than a hesitant one.

Do not guess at colour. Colour is measured separately from the pixels. Fill
`primary_color_name`/`secondary_color_name` with plain names for display only.
"""

_PROMPT_MULTI = """You are reading a photograph of a complete outfit for a wardrobe app — either
worn by a person or laid out flat.

Identify EACH distinct garment separately and return one entry per garment. A typical outfit has
2-5 garments. Include footwear. Do not return the same garment twice, and do not return an entry
for a bag, background object, or body part.

The app supports both Western and South Asian clothing — kurta, kameez, shalwar, dupatta, abaya are
all valid categories and should be used when they are what you actually see.

For each garment's `box`, give its normalised bounding box within the photo. These boxes are used
to sample each garment's colour, so they must be tight enough to contain mostly that garment.

For `confidence`, give an honest 0-1 value per attribute. Low values where you are unsure.

Do not guess at colour; it is measured from the pixels separately.
"""


def _client(settings: Settings) -> genai.Client:
    return genai.Client(api_key=settings.gemini_api_key)


async def _generate(
    settings: Settings,
    image_bytes: bytes,
    mime_type: str,
    prompt: str,
    schema: type[BaseModel],
) -> BaseModel:
    """One Gemini call, with a hard timeout.

    NOTE: verify the `google-genai` call shape against the installed SDK version before relying on
    this in production — the SDK's config surface has moved between releases. `tests/test_extraction.py`
    exercises it against a stub, which proves this module's logic but NOT the SDK signature.
    """
    client = _client(settings)

    def _call() -> object:
        return client.models.generate_content(
            model=settings.gemini_model,
            contents=[
                types.Part.from_bytes(data=image_bytes, mime_type=mime_type),
                prompt,
            ],
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=schema,
                temperature=0.0,  # attribute reading is not a creative task
            ),
        )

    try:
        response = await asyncio.wait_for(
            asyncio.to_thread(_call),
            timeout=settings.extraction_timeout_seconds,
        )
    except asyncio.TimeoutError:
        raise ExtractionError(
            "the vision model did not respond in time", retryable=True
        ) from None
    except Exception as exc:
        # Never log the image or the response body — PRD §4.2. Log the exception type only.
        logger.warning("gemini call failed: %s", type(exc).__name__)
        raise ExtractionError(f"vision model error: {type(exc).__name__}", retryable=True) from exc

    parsed = getattr(response, "parsed", None)
    if parsed is None:
        raise ExtractionError(
            "the vision model returned no usable structured output", retryable=True
        )
    return parsed


async def extract_single(
    settings: Settings, image_bytes: bytes, mime_type: str
) -> GarmentAttributes:
    """PRD §4.2 — one photographed item."""
    result = await _generate(
        settings, image_bytes, mime_type, _PROMPT_SINGLE, GarmentAttributes
    )
    assert isinstance(result, GarmentAttributes)
    return result


async def extract_multiple(
    settings: Settings, image_bytes: bytes, mime_type: str, max_garments: int = 6
) -> list[GarmentAttributes]:
    """PRD §4.4(b) — a whole-outfit photo.

    This is the path TRD §4 never described (issue #2, skills/README.md). It is NOT the single-item
    pipeline run in a loop over the same image — that returns one blended garment every time.
    Multi-garment detection is a genuinely different request, so it gets its own prompt and its own
    schema. It remains the least-validated path in the backend and needs its own test corpus of
    real outfit photos before it can be trusted.
    """
    result = await _generate(settings, image_bytes, mime_type, _PROMPT_MULTI, GarmentList)
    assert isinstance(result, GarmentList)
    garments = result.garments[:max_garments]
    if not garments:
        raise ExtractionError(
            "no garments were found in that photo", retryable=False
        )
    return garments
