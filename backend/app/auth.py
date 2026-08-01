"""Supabase JWT validation — TRD §9.

The rule that matters (skills/backend/SKILL.md §1.2): **`user_id` is derived from the token, never
from the request body.** TRD §8 shows `user_id` as a request field. Trusting that field would let
any authenticated user read and write any other user's wardrobe by changing one value — a complete
bypass of every RLS policy, since this service holds the service-role key.

`require_user` below is the only place a user identity enters the system.
"""

from __future__ import annotations

import jwt
from fastapi import Depends, HTTPException, Request, status

from .config import get_settings


class AuthError(HTTPException):
    def __init__(self, detail: str) -> None:
        super().__init__(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error": {"code": "unauthenticated", "message": detail, "retryable": False}},
            headers={"WWW-Authenticate": "Bearer"},
        )


def _bearer_token(request: Request) -> str:
    header = request.headers.get("Authorization", "")
    scheme, _, token = header.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise AuthError("missing bearer token")
    return token


def require_user(request: Request) -> str:
    """Validate the Supabase access token and return the authenticated user's id.

    NOTE ON SIGNING: this verifies the legacy HS256 project JWT secret. If the Supabase project has
    been migrated to asymmetric signing keys (ES256/RS256), this must be switched to JWKS
    verification against {SUPABASE_URL}/auth/v1/.well-known/jwks.json. Which scheme your project
    uses is visible in the dashboard under Settings → API → JWT keys. Verify before deploying —
    do not assume from this comment.
    """
    settings = get_settings()
    token = _bearer_token(request)

    try:
        claims = jwt.decode(
            token,
            settings.supabase_jwt_secret,
            algorithms=["HS256"],
            audience="authenticated",
            options={"require": ["sub", "exp"]},
        )
    except jwt.ExpiredSignatureError:
        raise AuthError("token expired") from None
    except jwt.InvalidTokenError as exc:
        raise AuthError(f"invalid token: {exc}") from None

    user_id = claims.get("sub")
    if not user_id:
        raise AuthError("token has no subject")
    return str(user_id)


def assert_matches_body(authenticated_user_id: str, body_user_id: str | None) -> None:
    """TRD §8 puts `user_id` in the request body. Accept it for contract compatibility, but treat a
    mismatch as an attack rather than a typo."""
    if body_user_id is not None and body_user_id != authenticated_user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "error": {
                    "code": "user_mismatch",
                    "message": "user_id does not match the authenticated user",
                    "retryable": False,
                }
            },
        )


CurrentUser = Depends(require_user)
