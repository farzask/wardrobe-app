"""Runtime configuration. Everything comes from the environment; nothing is committed.

DESIGN NOTE — why there is no service-role key here.

The obvious way to build this backend is with `SUPABASE_SERVICE_ROLE_KEY`, which bypasses RLS. That
turns every RLS policy in migrations 002–007 into decoration as far as this service is concerned:
a single missing `user_id` filter in one query silently exposes every user's wardrobe, and no
policy would stop it.

Instead this service forwards the **caller's own JWT** to PostgREST with the anon key. Supabase then
applies exactly the same RLS policies to the backend that it applies to the phone. A missing filter
becomes an empty result, not a leak. The service-role key stays out of the process entirely, so it
cannot be logged, leaked in a stack trace, or reached by a compromised dependency.

The cost is that genuinely cross-user work — the orphan-thumbnail reaper in 007_storage.sql — cannot
run here. That is a scheduled job, and it can hold its own credential when someone builds it.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache


class ConfigError(RuntimeError):
    pass


def _required(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise ConfigError(
            f"{name} is not set. See supabase/SETUP.md §2 — the backend refuses to start "
            f"rather than run with a missing credential."
        )
    return value


@dataclass(frozen=True)
class Settings:
    supabase_url: str
    supabase_anon_key: str
    supabase_jwt_secret: str
    gemini_api_key: str

    gemini_model: str = "gemini-2.5-flash"

    # Client-side downscale means uploads are already small; this ceiling is a backstop against a
    # client that ignores it, not the working size.
    max_upload_bytes: int = 8 * 1024 * 1024

    # TRD §4.4: ~320px wide WebP, quality 65–75, target ≤30 KB.
    thumbnail_width: int = 320
    thumbnail_quality: int = 70
    thumbnail_target_bytes: int = 30 * 1024

    # Resolution the vision model sees. Larger buys nothing for attribute reading and costs latency,
    # which PRD §6 cares about more than it cares about exact accuracy.
    inference_max_edge: int = 1024

    # PRD §6 targets "a few seconds". A request with no timeout hangs the UI indefinitely instead.
    extraction_timeout_seconds: float = 25.0

    storage_bucket: str = "wardrobe-thumbnails"


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings(
        supabase_url=_required("SUPABASE_URL").rstrip("/"),
        supabase_anon_key=_required("SUPABASE_ANON_KEY"),
        supabase_jwt_secret=_required("SUPABASE_JWT_SECRET"),
        gemini_api_key=_required("GEMINI_API_KEY"),
        gemini_model=os.environ.get("GEMINI_MODEL", "gemini-2.5-flash"),
    )
