import hashlib
import os
import secrets
import sqlite3
import time
import uuid
from functools import wraps

import requests
from flask import Flask, jsonify, request
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

METAAPI_TOKEN = os.environ.get("METAAPI_TOKEN", "").strip()
METAAPI_PROVISIONING_URL = os.environ.get(
    "METAAPI_PROVISIONING_URL",
    "https://mt-provisioning-api-v1.agiliumtrade.agiliumtrade.ai",
).rstrip("/")
METAAPI_CLIENT_URL = os.environ.get(
    "METAAPI_CLIENT_URL",
    "https://mt-client-api-v1.london.agiliumtrade.ai",
).rstrip("/")
DATABASE = os.environ.get("PIPSMINER_DATABASE", "/app/data/pips_miner.db")
MAGIC = int(os.environ.get("PIPSMINER_MAGIC", "26081501"))

os.makedirs(os.path.dirname(DATABASE), exist_ok=True)


def db():
    conn = sqlite3.connect(DATABASE)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = db()
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS sessions (
            session_hash TEXT PRIMARY KEY,
            account_id TEXT NOT NULL,
            login TEXT NOT NULL,
            server TEXT NOT NULL,
            platform TEXT NOT NULL,
            created_at INTEGER NOT NULL
        )
        """
    )
    conn.commit()
    conn.close()


init_db()


def error(message, status=400):
    return jsonify({"ok": False, "error": message}), status


def require_session(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        token = request.headers.get("Authorization", "")
        if not token.startswith("Bearer "):
            return error("Authentication required.", 401)

        session = token[7:].strip()
        if not session:
            return error("Authentication required.", 401)

        session_hash = hashlib.sha256(session.encode()).hexdigest()

        conn = db()
        row = conn.execute(
            "SELECT * FROM sessions WHERE session_hash = ?",
            (session_hash,),
        ).fetchone()
        conn.close()

        if row is None:
            return error("Invalid or expired Pips-Miner session.", 401)

        return fn(dict(row), *args, **kwargs)

    return wrapper


def meta_headers(transaction_id=None):
    headers = {
        "auth-token": METAAPI_TOKEN,
        "Accept": "application/json",
        "Content-Type": "application/json",
    }
    if transaction_id:
        headers["transaction-id"] = transaction_id
    return headers


def check_metaapi_config():
    if not METAAPI_TOKEN:
        raise RuntimeError("METAAPI_TOKEN is not configured on the server.")


def create_metaapi_account(login, password, server, platform):
    check_metaapi_config()

    transaction_id = uuid.uuid4().hex[:32]

    payload = {
        "login": login,
        "password": password,
        "name": f"Pips-Miner-{login}",
        "server": server,
        "platform": platform,
        "magic": MAGIC,
        "type": "cloud-g2",
        "reliability": "high",
        "quoteStreamingIntervalInSeconds": 0,
        "tags": ["pips-miner"],
    }

    url = f"{METAAPI_PROVISIONING_URL}/users/current/accounts"

    last_body = None

    for attempt in range(6):
        response = requests.post(
            url,
            headers=meta_headers(transaction_id),
            json=payload,
            timeout=45,
        )

        if response.status_code in (200, 201):
            return response.json()

        last_body = response.text

        if response.status_code == 202:
            time.sleep(10)
            continue

        try:
            data = response.json()
            message = data.get("message") or data.get("error") or response.text
        except Exception:
            message = response.text

        raise RuntimeError(
            f"MetaApi provisioning failed ({response.status_code}): {message}"
        )

    raise RuntimeError(
        f"MetaApi provisioning is still processing. Please retry shortly. {last_body}"
    )


def meta_request(method, account_id, path, **kwargs):
    check_metaapi_config()

    url = (
        f"{METAAPI_CLIENT_URL}/users/current/accounts/"
        f"{account_id}{path}"
    )

    headers = meta_headers()

    response = requests.request(
        method,
        url,
        headers=headers,
        timeout=45,
        **kwargs,
    )

    if response.status_code < 200 or response.status_code >= 300:
        try:
            body = response.json()
        except Exception:
            body = response.text

        return jsonify({
            "ok": False,
            "error": f"MetaApi HTTP {response.status_code}",
            "details": body,
        }), response.status_code

    if not response.content:
        return jsonify({})

    try:
        return jsonify(response.json())
    except Exception:
        return jsonify({"raw": response.text})


@app.get("/health")
def health():
    return jsonify({
        "ok": True,
        "service": "pips-miner-backend",
    })


@app.post("/api/v1/connect")
def connect_account():
    data = request.get_json(silent=True) or {}

    login = str(data.get("login", "")).strip()
    password = str(data.get("password", ""))
    server = str(data.get("server", "")).strip()
    platform = str(data.get("platform", "mt5")).strip().lower()

    if not login.isdigit():
        return error("MT5 account number must contain digits only.")

    if not password:
        return error("MT5 trading password is required.")

    if not server:
        return error("MT5 broker server is required.")

    if platform not in ("mt4", "mt5"):
        return error("Unsupported trading platform.")

    if len(password) > 256 or len(server) > 256:
        return error("Credential fields are too long.")

    try:
        account = create_metaapi_account(
            login=login,
            password=password,
            server=server,
            platform=platform,
        )

        account_id = str(account.get("id", "")).strip()
        state = str(account.get("state", "")).strip()

        if not account_id:
            return error("MetaApi did not return an account ID.", 502)

        session = secrets.token_urlsafe(48)
        session_hash = hashlib.sha256(session.encode()).hexdigest()

        conn = db()
        conn.execute(
            """
            INSERT INTO sessions
            (session_hash, account_id, login, server, platform, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                session_hash,
                account_id,
                login,
                server,
                platform,
                int(time.time()),
            ),
        )
        conn.commit()
        conn.close()

        return jsonify({
            "ok": True,
            "sessionToken": session,
            "accountId": account_id,
            "login": login,
            "server": server,
            "platform": platform,
            "state": state,
        })

    except Exception as exc:
        app.logger.exception("Account provisioning failed")
        return error(str(exc), 502)


@app.post("/api/v1/disconnect")
@require_session
def disconnect_account(session):
    token = request.headers.get("Authorization", "")[7:].strip()
    session_hash = hashlib.sha256(token.encode()).hexdigest()

    conn = db()
    conn.execute(
        "DELETE FROM sessions WHERE session_hash = ?",
        (session_hash,),
    )
    conn.commit()
    conn.close()

    return jsonify({"ok": True})


@app.get("/api/v1/account-information")
@require_session
def account_information(session):
    return meta_request(
        "GET",
        session["account_id"],
        "/account-information",
    )


@app.get("/api/v1/positions")
@require_session
def positions(session):
    return meta_request(
        "GET",
        session["account_id"],
        "/positions",
    )


@app.get("/api/v1/orders")
@require_session
def orders(session):
    return meta_request(
        "GET",
        session["account_id"],
        "/orders",
    )


@app.get("/api/v1/symbols/<path:symbol>/current-price")
@require_session
def symbol_price(session, symbol):
    return meta_request(
        "GET",
        session["account_id"],
        f"/symbols/{symbol}/current-price",
    )


@app.get("/api/v1/symbols/<path:symbol>/specification")
@require_session
def symbol_specification(session, symbol):
    return meta_request(
        "GET",
        session["account_id"],
        f"/symbols/{symbol}/specification",
    )


@app.get("/api/v1/symbols/<path:symbol>/current-candles/<timeframe>")
@require_session
def candles(session, symbol, timeframe):
    return meta_request(
        "GET",
        session["account_id"],
        f"/symbols/{symbol}/current-candles/{timeframe}",
    )


@app.post("/api/v1/trade")
@require_session
def trade(session):
    body = request.get_json(silent=True) or {}
    return meta_request(
        "POST",
        session["account_id"],
        "/trade",
        json=body,
    )


@app.post("/api/v1/calculate-margin")
@require_session
def calculate_margin(session):
    body = request.get_json(silent=True) or {}
    return meta_request(
        "POST",
        session["account_id"],
        "/calculate-margin",
        json=body,
    )


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "5000"))
    app.run(host="0.0.0.0", port=port)
