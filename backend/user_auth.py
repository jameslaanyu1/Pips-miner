import hashlib
import hmac
import os
import secrets
import time
from typing import Optional

# In-memory session store for the initial implementation.
# Production deployment should replace this with Redis/database storage.
_sessions = {}


def _session_ttl() -> int:
    return int(os.getenv("SESSION_TTL_SECONDS", "86400"))


def create_session(account_id: str, mode: str) -> str:
    token = secrets.token_urlsafe(48)

    _sessions[token] = {
        "account_id": account_id,
        "mode": mode.upper(),
        "created": time.time(),
        "expires": time.time() + _session_ttl(),
    }

    return token


def get_session(token: Optional[str]):
    if not token:
        return None

    session = _sessions.get(token)

    if not session:
        return None

    if time.time() >= session["expires"]:
        _sessions.pop(token, None)
        return None

    return session


def revoke_session(token: str):
    _sessions.pop(token, None)


def hash_identifier(value: str) -> str:
    return hashlib.sha256(
        value.strip().encode("utf-8")
    ).hexdigest()


def constant_time_equal(left: str, right: str) -> bool:
    return hmac.compare_digest(left, right)
