import base64
import hashlib
import hmac
import json
import os
import secrets
import time
from typing import Optional

def _secret():
    value = os.getenv("PIPSMINER_SESSION_SECRET", "").strip()
    if len(value) < 32:
        raise RuntimeError(
            "PIPSMINER_SESSION_SECRET must contain at least 32 characters."
        )
    return value.encode("utf-8")

def _ttl():
    value = int(os.getenv("SESSION_TTL_SECONDS", "86400"))
    return max(300, min(value, 7 * 86400))

def create_session(account_id: str, mode: str, login: str = "", server: str = ""):
    now = int(time.time())
    payload = {
        "sid": secrets.token_urlsafe(18),
        "account_id": account_id,
        "mode": mode.upper(),
        "login": login,
        "server": server,
        "created": now,
        "expires": now + _ttl(),
    }
    raw = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()
    body = base64.urlsafe_b64encode(raw).rstrip(b"=").decode()
    sig = hmac.new(_secret(), body.encode(), hashlib.sha256).digest()
    encoded_sig = base64.urlsafe_b64encode(sig).rstrip(b"=").decode()
    return f"{body}.{encoded_sig}"

def get_session(token: Optional[str]):
    if not token:
        return None
    try:
        body, supplied = token.split(".", 1)
        expected = hmac.new(
            _secret(), body.encode(), hashlib.sha256
        ).digest()
        expected = base64.urlsafe_b64encode(expected).rstrip(b"=").decode()
        if not hmac.compare_digest(supplied, expected):
            return None
        padded = body + "=" * (-len(body) % 4)
        payload = json.loads(base64.urlsafe_b64decode(padded.encode()))
        if time.time() >= int(payload.get("expires", 0)):
            return None
        return payload
    except Exception:
        return None
