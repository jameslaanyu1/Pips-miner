import os
import secrets
import time
import uuid
import sqlite3
from functools import wraps
from urllib.parse import urlencode

import requests
from flask import Flask, jsonify, request
from flask_cors import CORS

from user_auth import create_session, get_session

app = Flask(__name__)

# Mobile apps do not send browser CORS headers, but keeping CORS enabled
# makes the API usable for future web/admin clients too.
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
CONNECT_LIMIT_SECONDS = int(os.environ.get("CONNECT_LIMIT_SECONDS", "60"))

os.makedirs(os.path.dirname(DATABASE), exist_ok=True)

def db():
    conn = sqlite3.connect(DATABASE)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = db()
    conn.execute("""
        CREATE TABLE IF NOT EXISTS connect_attempts (
            client_key TEXT PRIMARY KEY,
            started_at INTEGER NOT NULL
        )
    """)
    conn.commit()
    conn.close()

init_db()

def error(message, status=400, details=None):
    body = {"ok": False, "error": message}
    if details is not None:
        body["details"] = details
    return jsonify(body), status

def require_session(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        authorization = request.headers.get("Authorization", "")
        if not authorization.startswith("Bearer "):
            return error("Authentication required.", 401)

        token = authorization[7:].strip()
        session = get_session(token)
        if not session:
            return error("Invalid or expired Pips-Miner session.", 401)

        return fn(session, *args, **kwargs)

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

def require_metaapi():
    if not METAAPI_TOKEN:
        raise RuntimeError("METAAPI_TOKEN is not configured on the Pips-Miner backend.")

def meta_raw(method, base_url, path="", **kwargs):
    require_metaapi()
    response = requests.request(
        method,
        f"{base_url}{path}",
        headers=meta_headers(kwargs.pop("transaction_id", None)),
        timeout=45,
        **kwargs,
    )
    return response

def response_body(response):
    try:
        return response.json()
    except Exception:
        return response.text

def list_metaapi_accounts(login):
    query = urlencode({"query": login, "limit": 100})
    response = meta_raw(
        "GET",
        METAAPI_PROVISIONING_URL,
        f"/users/current/accounts?{query}",
    )
    if response.status_code != 200:
        raise RuntimeError(
            f"MetaApi account lookup failed ({response.status_code}): "
            f"{response_body(response)}"
        )

    data = response_body(response)
    if isinstance(data, dict):
        return data.get("items", [])
    return data if isinstance(data, list) else []

def find_existing_account(login, server, platform):
    wanted_platform = platform.lower()
    for account in list_metaapi_accounts(login):
        if str(account.get("login", "")).strip() != login:
            continue
        if str(account.get("server", "")).strip().lower() != server.lower():
            continue

        account_type = str(account.get("type", "")).lower()
        if wanted_platform == "mt5" and "mt5" not in account_type and account_type not in (
            "cloud", "cloud-g1", "cloud-g2"
        ):
            continue

        return account
    return None

def update_existing_credentials(account_id, login, password, server):
    response = meta_raw(
        "PUT",
        METAAPI_PROVISIONING_URL,
        f"/users/current/accounts/{account_id}/credentials",
        json={"login": login, "password": password},
    )
    if response.status_code not in (200, 204):
        raise RuntimeError(
            f"MetaApi credential update failed ({response.status_code}): "
            f"{response_body(response)}"
        )

def create_metaapi_account(login, password, server, platform):
    # Lookup-only: the administrator's MetaApi account is provisioned first.
    existing = find_existing_account(login, server, platform)

    if existing:
        account_id = str(existing.get("_id") or existing.get("id") or "").strip()
        if not account_id:
            raise RuntimeError("MetaApi returned an account without an ID.")

        # Password is sent only to MetaApi to refresh the existing account
        # credentials; Pips-Miner does not persist the MT5 password.
        update_existing_credentials(account_id, login, password, server)
        return account_id, "reused"

    raise RuntimeError(
        "This MT5 account is not registered in the administrator MetaApi account. "
        "Ask the administrator to provision and deploy it first."
    )

def deploy_metaapi_account(account_id):
    response = meta_raw(
        "POST",
        METAAPI_PROVISIONING_URL,
        f"/users/current/accounts/{account_id}/deploy",
    )
    if response.status_code not in (200, 204):
        body = response_body(response)
        if isinstance(body, dict):
            message = body.get("message") or body.get("error") or str(body)
        else:
            message = str(body)
        raise RuntimeError(
            f"MetaApi deployment failed ({response.status_code}): {message}"
        )

def provisioning_account(account_id):
    response = meta_raw(
        "GET",
        METAAPI_PROVISIONING_URL,
        f"/users/current/accounts/{account_id}",
    )
    if response.status_code != 200:
        raise RuntimeError(
            f"MetaApi account status failed ({response.status_code}): "
            f"{response_body(response)}"
        )
    return response_body(response)

def wait_for_account_connection(account_id):
    # Deployment can take time. We poll provisioning status, then verify
    # the client REST API can read account information.
    deadline = time.time() + CONNECT_LIMIT_SECONDS

    last_status = None
    while time.time() < deadline:
        try:
            status = provisioning_account(account_id)
            last_status = status

            state = str(status.get("state", "")).upper()
            connection = str(status.get("connectionStatus", "")).upper()

            if state == "DEPLOYED" and connection in ("CONNECTED", "SYNCHRONIZED"):
                response = meta_raw(
                    "GET",
                    METAAPI_CLIENT_URL,
                    f"/users/current/accounts/{account_id}/account-information",
                )
                if 200 <= response.status_code < 300:
                    return status
        except Exception:
            pass

        time.sleep(3)

    return last_status or {}

@app.get("/health")
def health():
    return jsonify({
        "ok": True,
        "service": "pips-miner-backend",
        "metaapiConfigured": bool(METAAPI_TOKEN),
    })

@app.get("/ready")
def ready():
    if not METAAPI_TOKEN:
        return error("METAAPI_TOKEN is not configured.", 503)
    try:
        # Cheap authentication/configuration check against MetaApi.
        response = meta_raw(
            "GET",
            METAAPI_PROVISIONING_URL,
            "/users/current/accounts?limit=1",
        )
        if response.status_code == 200:
            return jsonify({"ok": True, "metaapi": "reachable"})
        return error("MetaApi is not reachable or the token is invalid.", 503)
    except Exception as exc:
        return error(str(exc), 503)

@app.post("/api/v1/connect")
def connect_account():
    # Basic abuse protection. This is intentionally local to one instance.
    client_key = request.headers.get("X-Forwarded-For", request.remote_addr or "unknown")
    conn = db()
    row = conn.execute(
        "SELECT started_at FROM connect_attempts WHERE client_key = ?",
        (client_key,),
    ).fetchone()
    now = int(time.time())
    if row and now - int(row["started_at"]) < CONNECT_LIMIT_SECONDS:
        conn.close()
        return error("Please wait before trying to connect again.", 429)
    conn.execute(
        "INSERT OR REPLACE INTO connect_attempts(client_key, started_at) VALUES (?, ?)",
        (client_key, now),
    )
    conn.commit()
    conn.close()

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
    if len(login) > 32 or len(password) > 256 or len(server) > 256:
        return error("Credential fields are too long.")

    try:
        account_id, action = create_metaapi_account(
            login=login,
            password=password,
            server=server,
            platform=platform,
        )

        deploy_metaapi_account(account_id)
        status = wait_for_account_connection(account_id)

        session_token = create_session(
            account_id=account_id,
            mode=platform,
            login=login,
            server=server,
        )

        connection_status = str(
            status.get("connectionStatus", "")
        ).upper()
        deployed = str(status.get("state", "")).upper() == "DEPLOYED"

        return jsonify({
            "ok": True,
            "sessionToken": session_token,
            "accountId": account_id,
            "login": login,
            "server": server,
            "platform": platform,
            "state": status.get("state"),
            "connectionStatus": status.get("connectionStatus"),
            "connected": deployed and connection_status in (
                "CONNECTED",
                "SYNCHRONIZED",
            ),
            "action": action,
        })

    except requests.RequestException as exc:
        app.logger.exception("MetaApi network error")
        return error(
            "Could not reach MetaApi. Check backend internet connectivity.",
            502,
            str(exc),
        )
    except Exception as exc:
        app.logger.exception("MT5 connection failed")
        return error(str(exc), 502)

@app.post("/api/v1/disconnect")
@require_session
def disconnect_account(session):
    # The MT account remains in MetaApi; this only ends the mobile session.
    return jsonify({"ok": True})

def meta_request(method, account_id, path, **kwargs):
    try:
        response = meta_raw(
            method,
            METAAPI_CLIENT_URL,
            f"/users/current/accounts/{account_id}{path}",
            **kwargs,
        )
    except requests.RequestException as exc:
        return error("MetaApi network request failed.", 502, str(exc))

    body = response_body(response)

    if response.status_code < 200 or response.status_code >= 300:
        return error(
            f"MetaApi HTTP {response.status_code}",
            response.status_code,
            body,
        )

    if body == "":
        return jsonify({})
    return jsonify(body)

@app.get("/api/v1/account-information")
@require_session
def account_information(session):
    return meta_request("GET", session["account_id"], "/account-information")

@app.get("/api/v1/positions")
@require_session
def positions(session):
    return meta_request("GET", session["account_id"], "/positions")

@app.get("/api/v1/orders")
@require_session
def orders(session):
    return meta_request("GET", session["account_id"], "/orders")

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
    if not isinstance(body, dict):
        return error("Trade request must be a JSON object.")
    return meta_request("POST", session["account_id"], "/trade", json=body)

@app.post("/api/v1/calculate-margin")
@require_session
def calculate_margin(session):
    body = request.get_json(silent=True) or {}
    if not isinstance(body, dict):
        return error("Margin request must be a JSON object.")
    return meta_request(
        "POST",
        session["account_id"],
        "/calculate-margin",
        json=body,
    )

if __name__ == "__main__":
    port = int(os.environ.get("PORT", "5000"))
    app.run(host="0.0.0.0", port=port)
