"""Supabase access, as the calling user.

Every function here takes the caller's JWT and forwards it to PostgREST/Storage. The consequence
worth internalising: **RLS is still in force.** If a query here forgets a `user_id` filter, the
result is empty rows, not another user's data. See the design note in `config.py`.

Uses PostgREST's HTTP API directly rather than a client library — the REST surface is small,
stable, and its behaviour is visible at the call site, which matters for a service whose main
security property is "what exactly did we ask the database for".
"""

from __future__ import annotations

from typing import Any

import httpx

from .config import Settings


class DbError(RuntimeError):
    def __init__(self, message: str, *, status: int, retryable: bool) -> None:
        super().__init__(message)
        self.status = status
        self.retryable = retryable


def _headers(settings: Settings, user_jwt: str, **extra: str) -> dict[str, str]:
    return {
        "apikey": settings.supabase_anon_key,
        "Authorization": f"Bearer {user_jwt}",
        **extra,
    }


def _raise_for(response: httpx.Response, what: str) -> None:
    if response.is_success:
        return
    # 5xx and 429 are worth retrying; a 4xx means the request itself is wrong.
    retryable = response.status_code >= 500 or response.status_code == 429
    raise DbError(
        f"{what} failed ({response.status_code}): {response.text[:300]}",
        status=response.status_code,
        retryable=retryable,
    )


class SupabaseClient:
    def __init__(self, settings: Settings, user_jwt: str, http: httpx.AsyncClient) -> None:
        self._s = settings
        self._jwt = user_jwt
        self._http = http

    # --- Postgres ------------------------------------------------------------

    async def select(
        self,
        table: str,
        *,
        columns: str,
        filters: dict[str, str] | None = None,
        order: str | None = None,
        limit: int | None = None,
    ) -> list[dict[str, Any]]:
        """Column-list every read (skills/database/SKILL.md §1.5): `select *` means adding a column
        can change a payload shape or break a model's fromJson without anyone touching this code."""
        params: dict[str, str] = {"select": columns}
        params.update(filters or {})
        if order:
            params["order"] = order
        if limit is not None:
            params["limit"] = str(limit)

        response = await self._http.get(
            f"{self._s.supabase_url}/rest/v1/{table}",
            params=params,
            headers=_headers(self._s, self._jwt),
        )
        _raise_for(response, f"select from {table}")
        return response.json()

    async def insert(
        self, table: str, rows: list[dict[str, Any]], *, returning: str = "representation"
    ) -> list[dict[str, Any]]:
        response = await self._http.post(
            f"{self._s.supabase_url}/rest/v1/{table}",
            json=rows,
            headers=_headers(
                self._s,
                self._jwt,
                **{"Content-Type": "application/json", "Prefer": f"return={returning}"},
            ),
        )
        _raise_for(response, f"insert into {table}")
        return response.json() if returning == "representation" else []

    async def update(
        self, table: str, filters: dict[str, str], values: dict[str, Any]
    ) -> list[dict[str, Any]]:
        response = await self._http.patch(
            f"{self._s.supabase_url}/rest/v1/{table}",
            params=filters,
            json=values,
            headers=_headers(
                self._s,
                self._jwt,
                **{"Content-Type": "application/json", "Prefer": "return=representation"},
            ),
        )
        _raise_for(response, f"update {table}")
        return response.json()

    # --- Storage -------------------------------------------------------------

    async def upload_thumbnail(self, path: str, data: bytes) -> str:
        """Upload to wardrobe-thumbnails/{user_id}/{item_id}.webp (TRD §4.5).

        Returns the object PATH, not a URL. The bucket is private and signed URLs expire; persisting
        an expired URL is a permanently broken thumbnail (skills/database/SKILL.md §7). The client
        signs on read.
        """
        response = await self._http.post(
            f"{self._s.supabase_url}/storage/v1/object/{self._s.storage_bucket}/{path}",
            content=data,
            headers=_headers(
                self._s,
                self._jwt,
                **{"Content-Type": "image/webp", "x-upsert": "true"},
            ),
        )
        _raise_for(response, "thumbnail upload")
        return path

    # --- Queries the endpoints actually need ---------------------------------

    ITEM_COLUMNS = (
        "id,category,pattern,occasion,season,fit,color_hex,color_palette,"
        "lab_l,lab_a,lab_b,primary_color,secondary_color,thumbnail_path,status,deleted_at"
    )

    async def get_profile(self, user_id: str) -> dict[str, Any] | None:
        rows = await self.select(
            "profiles",
            columns="id,gender,wears_accessories,display_name",
            filters={"id": f"eq.{user_id}"},
            limit=1,
        )
        return rows[0] if rows else None

    async def get_items(self, item_ids: list[str]) -> list[dict[str, Any]]:
        if not item_ids:
            return []
        joined = ",".join(item_ids)
        return await self.select(
            "wardrobe_items",
            columns=self.ITEM_COLUMNS,
            filters={
                "id": f"in.({joined})",
                # Both predicates on every wardrobe read. Omitting either returns rows the user
                # should not see — deleted items, or half-extracted ones awaiting review.
                "deleted_at": "is.null",
                "status": "eq.active",
            },
        )

    async def get_swap_candidates(
        self, categories: list[str], exclude_id: str, limit: int = 40
    ) -> list[dict[str, Any]]:
        """Candidate replacements for the weak item, restricted to its slot's categories.

        Bounded on purpose (skills/backend/SKILL.md §3): scoring the entire wardrobe on every
        evaluation is O(items) graph rebuilds for a feature that shows at most two results.
        """
        if not categories:
            return []
        return await self.select(
            "wardrobe_items",
            columns=self.ITEM_COLUMNS,
            filters={
                "category": f"in.({','.join(categories)})",
                "id": f"neq.{exclude_id}",
                "deleted_at": "is.null",
                "status": "eq.active",
            },
            order="created_at.desc",
            limit=limit,
        )
