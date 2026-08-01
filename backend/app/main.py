"""FitCheck backend — FastAPI.

Two heavy operations, exactly as TRD §1 scopes them: attribute extraction and outfit evaluation.
Everything else (reading the wardrobe, saving outfits) goes from Flutter straight to Supabase.

Routes are versioned from the first commit. Retrofitting a version prefix onto shipped mobile
clients is impossible — old app versions keep calling the old path forever.
"""

from __future__ import annotations

import logging
import uuid
from contextlib import asynccontextmanager
from typing import Annotated

import httpx
from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, UploadFile, status
from fastapi.responses import JSONResponse

from . import colour, engine, extraction, imaging, recommendations
from .auth import assert_matches_body, require_user
from .config import ConfigError, Settings, get_settings
from .db import DbError, SupabaseClient
from .ruleset import DEFAULT_RULESET
from .schemas import (
    DetectedGarment,
    ErrorBody,
    ErrorResponse,
    EvaluatePhotoResponse,
    EvaluateRequest,
    EvaluateResponse,
    ExtractedAttributes,
    ExtractResponse,
    PaletteColour,
    StyleRecommendation,
    SwapSuggestion,
)
from .vocabulary import CATEGORY_SLOT, Category, Gender

logger = logging.getLogger(__name__)

ALLOWED_MIME = {"image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"}


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Fail at startup on a missing credential rather than on the first user request.
    get_settings()
    async with httpx.AsyncClient(timeout=20.0) as client:
        app.state.http = client
        yield


app = FastAPI(title="FitCheck backend", version="0.1.0", lifespan=lifespan)


def _error(code: str, message: str, *, status_code: int, retryable: bool) -> JSONResponse:
    return JSONResponse(
        status_code=status_code,
        content=ErrorResponse(
            error=ErrorBody(code=code, message=message, retryable=retryable)
        ).model_dump(),
    )


@app.exception_handler(extraction.ExtractionError)
async def _extraction_error(_: Request, exc: extraction.ExtractionError) -> JSONResponse:
    return _error(
        "extraction_failed",
        str(exc),
        status_code=status.HTTP_502_BAD_GATEWAY if exc.retryable else status.HTTP_422_UNPROCESSABLE_ENTITY,
        retryable=exc.retryable,
    )


@app.exception_handler(imaging.ImageError)
async def _image_error(_: Request, exc: imaging.ImageError) -> JSONResponse:
    return _error("bad_image", str(exc), status_code=status.HTTP_400_BAD_REQUEST, retryable=False)


@app.exception_handler(DbError)
async def _db_error(_: Request, exc: DbError) -> JSONResponse:
    return _error(
        "database_error",
        str(exc),
        status_code=status.HTTP_502_BAD_GATEWAY if exc.retryable else status.HTTP_400_BAD_REQUEST,
        retryable=exc.retryable,
    )


@app.exception_handler(ConfigError)
async def _config_error(_: Request, exc: ConfigError) -> JSONResponse:
    logger.error("configuration error: %s", exc)
    return _error(
        "misconfigured",
        "the server is not configured correctly",
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        retryable=False,
    )


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "ruleset": DEFAULT_RULESET.version}


def _client(request: Request, user_jwt: str, settings: Settings) -> SupabaseClient:
    return SupabaseClient(settings, user_jwt, request.app.state.http)


def _bearer(request: Request) -> str:
    return request.headers["Authorization"].split(" ", 1)[1]


async def _read_upload(image: UploadFile, settings: Settings) -> tuple[bytes, str]:
    if image.content_type not in ALLOWED_MIME:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail={
                "error": {
                    "code": "unsupported_type",
                    "message": f"{image.content_type} is not an accepted image type",
                    "retryable": False,
                }
            },
        )
    data = await image.read()
    if len(data) > settings.max_upload_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail={
                "error": {
                    "code": "too_large",
                    "message": "image exceeds the upload limit; downscale before sending",
                    "retryable": False,
                }
            },
        )
    if not data:
        raise imaging.ImageError("the uploaded file is empty")
    return data, image.content_type or "image/jpeg"


def _attributes_from(
    garment: extraction.GarmentAttributes, palette: list[colour.PaletteEntry]
) -> ExtractedAttributes:
    dominant = palette[0]
    return ExtractedAttributes(
        category=garment.category,
        style=garment.style,
        pattern=garment.pattern,
        fabric=garment.fabric,
        sleeve_type=garment.sleeve_type,
        neckline=garment.neckline,
        fit=garment.fit,
        season=garment.season,
        occasion=garment.occasion,
        primary_color=garment.primary_color_name,
        secondary_color=garment.secondary_color_name,
        color_hex=dominant.hex,
        color_palette=[PaletteColour(hex=e.hex, weight=e.weight) for e in palette],
        lab_l=dominant.lab.l,
        lab_a=dominant.lab.a,
        lab_b=dominant.lab.b,
    )


# --- POST /v1/extract-attributes ---------------------------------------------


@app.post("/v1/extract-attributes", response_model=ExtractResponse)
async def extract_attributes(
    request: Request,
    image: Annotated[UploadFile, File()],
    user_id: Annotated[str | None, Form()] = None,
    user: str = Depends(require_user),
) -> ExtractResponse:
    """TRD §4. The original image is held in memory for the duration of this call and never
    written anywhere — see `imaging.py` and `tests/test_no_persistence.py`."""
    assert_matches_body(user, user_id)
    settings = get_settings()
    db = _client(request, _bearer(request), settings)

    data, _mime = await _read_upload(image, settings)
    original = imaging.load_image(data)
    del data  # drop the raw upload bytes as soon as they are decoded

    inference_image = imaging.downscale_for_inference(original, settings.inference_max_edge)
    garment = await extraction.extract_single(settings, _encode(inference_image), "image/webp")

    cropped = imaging.crop_to_box(original, garment.box)
    palette = colour.extract_palette(imaging.garment_pixels(cropped))
    thumbnail = imaging.make_thumbnail(
        cropped, settings.thumbnail_width, settings.thumbnail_quality, settings.thumbnail_target_bytes
    )

    item_id = str(uuid.uuid4())
    thumbnail_path = await db.upload_thumbnail(f"{user}/{item_id}.webp", thumbnail)

    attributes = _attributes_from(garment, palette)
    await db.insert(
        "wardrobe_items",
        [
            {
                "id": item_id,
                "user_id": user,
                **attributes.model_dump(mode="json"),
                "color_palette": [p.model_dump() for p in attributes.color_palette],
                "thumbnail_path": thumbnail_path,
                "extraction_confidence": garment.confidence,
                "status": "pending_review",
            }
        ],
        returning="minimal",
    )

    # `original`, `inference_image` and `cropped` go out of scope here and are never persisted.
    return ExtractResponse(
        item_id=item_id,
        attributes=attributes,
        confidence=garment.confidence,
        thumbnail_path=thumbnail_path,
    )


def _encode(image) -> bytes:
    """Re-encode the downscaled image for upload to the vision model. WebP keeps the request small,
    which is the dominant term in the latency PRD §6 cares about."""
    import io

    buffer = io.BytesIO()
    image.convert("RGB").save(buffer, format="WEBP", quality=85, method=4)
    return buffer.getvalue()


# --- POST /v1/evaluate-outfit -------------------------------------------------


def _row_to_item(row: dict) -> engine.Item:
    return engine.Item(
        id=row["id"],
        category=Category(row["category"]),
        pattern=row["pattern"],
        occasion=row["occasion"],
        season=row["season"],
        fit=row["fit"],
        color_hex=row["color_hex"],
        lab=colour.Lab(row["lab_l"], row["lab_a"], row["lab_b"]),
        primary_color=row["primary_color"] or row["color_hex"],
    )


async def _recommendations_for(
    db: SupabaseClient, user: str, occasion, dominant: colour.Lab
) -> list[StyleRecommendation]:
    """The gate lives here, server-side, read from the profile (PRD §4.5).

    Gating in the UI instead would still compute and ship the suggestion, leaking the user's
    `wears_accessories` flag to anyone reading the response body.
    """
    profile = await db.get_profile(user)
    if profile is None:
        return []
    gender = Gender(profile["gender"]) if profile.get("gender") else None
    built = recommendations.build_recommendations(
        gender=gender,
        wears_accessories=profile.get("wears_accessories"),
        occasion=occasion,
        dominant=dominant,
    )
    return [StyleRecommendation(type=r.type, suggestion_text=r.suggestion_text) for r in built]


@app.post("/v1/evaluate-outfit", response_model=EvaluateResponse)
async def evaluate_outfit(
    request: Request,
    body: EvaluateRequest,
    user: str = Depends(require_user),
) -> EvaluateResponse:
    """TRD §8(a) — the primary path. No image processing: everything is computed from attributes
    already stored, so this is pure arithmetic over rows the user already owns."""
    assert_matches_body(user, body.user_id)
    settings = get_settings()
    db = _client(request, _bearer(request), settings)

    rows = await db.get_items(body.wardrobe_item_ids)
    if len(rows) < 2:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={
                "error": {
                    "code": "not_enough_items",
                    "message": "an outfit needs at least two of your items to compare",
                    "retryable": False,
                }
            },
        )

    items = [_row_to_item(r) for r in rows]
    result = engine.evaluate(items, DEFAULT_RULESET)
    warning = engine.completeness_warning(items)

    suggestions: list[SwapSuggestion] = []
    if result.weak_item_id:
        weak = next(i for i in items if i.id == result.weak_item_id)
        same_slot = [c.value for c, s in CATEGORY_SLOT.items() if s == weak.slot]
        candidate_rows = await db.get_swap_candidates(same_slot, weak.id)
        chosen = {i.id for i in items}
        candidates = [_row_to_item(r) for r in candidate_rows if r["id"] not in chosen]
        suggestions = [
            SwapSuggestion(**vars(s))
            for s in engine.suggest_swaps(items, weak.id, candidates, DEFAULT_RULESET)
        ]

    occasion = _dominant_occasion(items)
    recs = await _recommendations_for(db, user, occasion, _dominant_colour(items))

    outfit_id: str | None = None
    if body.persist:
        outfit_id = await _persist(db, user, body.name, occasion, result, "wardrobe_build", recs,
                                   item_ids=[i.id for i in items])

    return EvaluateResponse(
        compatibility_score=result.score,
        weak_item_id=result.weak_item_id,
        suggestion_text=result.feedback,
        suggestions=suggestions,
        recommendations=recs,
        completeness_warning=warning,
        ruleset_version=result.ruleset_version,
        outfit_id=outfit_id,
    )


@app.post("/v1/evaluate-outfit/photo", response_model=EvaluatePhotoResponse)
async def evaluate_outfit_photo(
    request: Request,
    image: Annotated[UploadFile, File()],
    user_id: Annotated[str | None, Form()] = None,
    persist: Annotated[bool, Form()] = False,
    user: str = Depends(require_user),
) -> EvaluatePhotoResponse:
    """TRD §8(b) — an ad-hoc outfit photo.

    The detected garments are NOT written to the wardrobe: PRD §4.4(b) is explicitly about an
    outfit "not yet in their digitized wardrobe". So this path saves no `outfit_items` rows and
    reports its weak link by index into the response, not by wardrobe item id.

    This is the least-validated path in the backend (issue #2, skills/README.md). It needs its own
    corpus of real outfit photos before it can be trusted.
    """
    assert_matches_body(user, user_id)
    settings = get_settings()
    db = _client(request, _bearer(request), settings)

    data, _mime = await _read_upload(image, settings)
    original = imaging.load_image(data)
    del data

    inference_image = imaging.downscale_for_inference(original, settings.inference_max_edge)
    garments = await extraction.extract_multiple(settings, _encode(inference_image), "image/webp")

    detected: list[DetectedGarment] = []
    items: list[engine.Item] = []
    for index, garment in enumerate(garments):
        cropped = imaging.crop_to_box(original, garment.box)
        palette = colour.extract_palette(imaging.garment_pixels(cropped))
        attributes = _attributes_from(garment, palette)
        detected.append(
            DetectedGarment(index=index, attributes=attributes, confidence=garment.confidence)
        )
        items.append(
            engine.Item(
                id=str(index),
                category=attributes.category,
                pattern=attributes.pattern,
                occasion=attributes.occasion,
                season=attributes.season,
                fit=attributes.fit,
                color_hex=attributes.color_hex,
                lab=colour.Lab(attributes.lab_l, attributes.lab_a, attributes.lab_b),
                primary_color=attributes.primary_color,
            )
        )

    if len(items) < 2:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={
                "error": {
                    "code": "not_enough_garments",
                    "message": "only one garment was visible; photograph the whole outfit",
                    "retryable": False,
                }
            },
        )

    result = engine.evaluate(items, DEFAULT_RULESET)
    occasion = _dominant_occasion(items)
    recs = await _recommendations_for(db, user, occasion, _dominant_colour(items))

    outfit_id: str | None = None
    if persist:
        outfit_id = await _persist(db, user, None, occasion, result, "photo_upload", recs,
                                   item_ids=None)

    return EvaluatePhotoResponse(
        compatibility_score=result.score,
        garments=detected,
        weak_garment_index=int(result.weak_item_id) if result.weak_item_id is not None else None,
        suggestion_text=result.feedback,
        recommendations=recs,
        completeness_warning=engine.completeness_warning(items),
        ruleset_version=result.ruleset_version,
        outfit_id=outfit_id,
    )


def _dominant_colour(items: list[engine.Item]) -> colour.Lab:
    """The colour the recommendation engine keys off (TRD §7).

    The garment occupying the largest visual area drives how an outfit reads, so a full-body piece
    wins, then the top, then whatever else is present. Averaging every item's colour would be
    wrong for the same reason averaging a striped shirt is wrong — the mean of navy and mustard is
    a colour nobody is wearing.
    """
    from .vocabulary import Slot

    priority = [Slot.FULL_BODY, Slot.TOP, Slot.BOTTOM, Slot.OUTERWEAR, Slot.DRAPE]
    for slot in priority:
        for item in items:
            if item.slot == slot:
                return item.lab
    return items[0].lab


def _dominant_occasion(items: list[engine.Item]):
    """The outfit's occasion is the most common one among its garments, ties broken by the most
    formal — a formal shirt with casual jeans is a formal-ish outfit that has a problem, not a
    casual outfit."""
    from collections import Counter

    from .vocabulary import Occasion

    order = [Occasion.FORMAL, Occasion.CULTURAL, Occasion.PARTY, Occasion.CASUAL]
    counts = Counter(i.occasion for i in items)
    best = max(counts.values())
    tied = [o for o, c in counts.items() if c == best]
    return next(o for o in order if o in tied)


async def _persist(
    db: SupabaseClient,
    user: str,
    name: str | None,
    occasion,
    result: engine.Evaluation,
    source: str,
    recs: list[StyleRecommendation],
    *,
    item_ids: list[str] | None,
) -> str:
    outfit_id = str(uuid.uuid4())
    await db.insert(
        "outfits",
        [
            {
                "id": outfit_id,
                "user_id": user,
                "name": name,
                "occasion": occasion.value,
                "compatibility_score": result.score,
                "ai_feedback": result.feedback,
                # For photo_upload the weak garment has no wardrobe row, so this stays null and the
                # weak link is conveyed by index in the response instead.
                "weak_item_id": result.weak_item_id if item_ids else None,
                "source": source,
                "ruleset_version": result.ruleset_version,
            }
        ],
        returning="minimal",
    )
    if item_ids:
        await db.insert(
            "outfit_items",
            [{"outfit_id": outfit_id, "wardrobe_item_id": i} for i in item_ids],
            returning="minimal",
        )
    if recs:
        await db.insert(
            "style_recommendations",
            [
                {"outfit_id": outfit_id, "type": r.type.value, "suggestion_text": r.suggestion_text}
                for r in recs
            ],
            returning="minimal",
        )
    return outfit_id
