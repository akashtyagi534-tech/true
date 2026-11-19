import base64
import hashlib
import hmac
import json
import time
import uuid

import httpx
from fastapi import Depends, HTTPException, Request
from sqlalchemy.orm import Session as DbSession

from .config import settings
from .db import UserRow, get_db

TOKEN_TTL = 60 * 60 * 24 * 14  # 14 days


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _unb64(s: str) -> bytes:
    pad = "=" * (-len(s) % 4)
    return base64.urlsafe_b64decode(s + pad)


def sign_token(payload: dict) -> str:
    body = dict(payload)
    body["exp"] = int(time.time()) + TOKEN_TTL
    raw = _b64(json.dumps(body, separators=(",", ":")).encode())
    sig = _b64(hmac.new(settings.jwt_secret.encode(), raw.encode(), hashlib.sha256).digest())
    return f"{raw}.{sig}"


def verify_token(token: str) -> dict | None:
    try:
        raw, sig = token.split(".", 1)
        expected = _b64(hmac.new(settings.jwt_secret.encode(), raw.encode(), hashlib.sha256).digest())
        if not hmac.compare_digest(sig, expected):
            return None
        data = json.loads(_unb64(raw).decode())
        if data.get("exp", 0) < time.time():
            return None
        return data
    except Exception:
        return None


async def verify_google_id_token(id_token: str) -> dict:
    """Verify Google Identity Services JWT via Google tokeninfo endpoint."""
    async with httpx.AsyncClient(timeout=8.0) as client:
        res = await client.get(
            "https://oauth2.googleapis.com/tokeninfo",
            params={"id_token": id_token},
        )
    if res.status_code != 200:
        raise HTTPException(status_code=401, detail="Invalid Google token")
    info = res.json()
    if settings.google_client_id and info.get("aud") != settings.google_client_id:
        raise HTTPException(status_code=401, detail="Google client ID mismatch")
    if not info.get("email"):
        raise HTTPException(status_code=401, detail="Google account email missing")
    return info


def upsert_user(db: DbSession, email: str, name: str, picture: str = "", google_sub: str | None = None) -> UserRow:
    email_low = email.strip().lower()
    user = db.query(UserRow).filter(UserRow.email == email_low).first()
    is_admin = email_low in settings.admin_email_set
    if user is None:
        user = UserRow(
            id=uuid.uuid4().hex[:16],
            google_sub=google_sub,
            email=email_low,
            name=name.strip() or email_low.split("@")[0],
            picture=picture,
            is_admin=is_admin,
        )
        db.add(user)
    else:
        if name:
            user.name = name
        if picture:
            user.picture = picture
        if google_sub and not user.google_sub:
            user.google_sub = google_sub
        if is_admin:
            user.is_admin = True
    db.commit()
    db.refresh(user)
    return user


def get_current_user(request: Request, db: DbSession = Depends(get_db)) -> UserRow:
    auth = request.headers.get("Authorization", "")
    token = auth.replace("Bearer ", "", 1).strip() if auth.startswith("Bearer ") else request.cookies.get("tl_token", "")
    if not token:
        raise HTTPException(status_code=401, detail="Login required")
    data = verify_token(token)
    if not data or not data.get("uid"):
        raise HTTPException(status_code=401, detail="Session expired, please login again")
    user = db.get(UserRow, data["uid"])
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    if user.is_banned:
        raise HTTPException(status_code=403, detail="Account suspended by Admin")
    return user


def get_admin_user(user: UserRow = Depends(get_current_user)) -> UserRow:
    if not user.is_admin:
        raise HTTPException(status_code=403, detail="Admin access required")
    return user
