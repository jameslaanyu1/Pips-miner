"""
Vercel entry point for Pips Miner.

The persistent trading worker remains outside the serverless runtime.
This module exposes the existing Flask control API through Vercel and provides
public release metadata for the Android updater.
"""

import asyncio
import re

import requests
from flask import jsonify, request
from metaapi_cloud_sdk import MetaApi

import backend.app as backend_app
from backend.app import app, meta_request, require_session
import backend.broker_search  # noqa: F401 - registers broker search route

_GITHUB_LATEST_RELEASE = "https://api.github.com/repos/jameslaanyu1/Pips-miner/releases/latest"
_EXPECTED_APK = "Pips-Miner-release.apk"
_VERSION_PATTERN = re.compile(r"^v?(\d+\.\d+\.\d+)$")
_ACCOUNT_PATH_PATTERN = re.compile(r"/users/current/accounts/([^/]+)")
_REGION_PATTERN = re.compile(r"^[a-z0-9-]+$")
_ACCOUNT_REGIONS = {}
_ORIGINAL_META_RAW = backend_app.meta_raw
_ORIGINAL_UPDATE_CREDENTIALS = backend_app.update_existing_credentials


def _region_aware_meta_raw(method, base_url, path="", **kwargs):
    """Route MetaApi client requests to the region where the account lives."""
    if base_url.rstrip("/") != backend_app.METAAPI_CLIENT_URL.rstrip("/"):
        return _ORIGINAL_META_RAW(method, base_url, path, **kwargs)
    match = _ACCOUNT_PATH_PATTERN.search(path)
    if not match:
        return _ORIGINAL_META_RAW(method, base_url, path, **kwargs)
    account_id = match.group(1)
    region = _ACCOUNT_REGIONS.get(account_id)
    if not region:
        status_response = _ORIGINAL_META_RAW("GET", backend_app.METAAPI_PROVISIONING_URL, f"/users/current/accounts/{account_id}")
        if status_response.status_code == 200:
            try:
                account = status_response.json()
                region = str(account.get("region", "")).strip().lower()
                if not region:
                    replicas = account.get("replicas") or []
                    if isinstance(replicas, list) and replicas:
                        region = str(replicas[0].get("region", "")).strip().lower()
                if region and _REGION_PATTERN.fullmatch(region):
                    _ACCOUNT_REGIONS[account_id] = region
                else:
                    region = None
            except (TypeError, ValueError):
                region = None
    if region:
        base_url = f"https://mt-client-api-v1.{region}.agiliumtrade.ai"
    return _ORIGINAL_META_RAW(method, base_url, path, **kwargs)

backend_app.meta_raw = _region_aware_meta_raw


def _update_account_with_provisioning_token(account_id, login, password, server):
    """Legacy compatibility hook: existing accounts are never mutated here."""
    return

backend_app.update_existing_credentials = _update_account_with_provisioning_token


def _reuse_existing_account(login, password, server, platform):
    """Resolve the canonical pre-provisioned MetaApi account without mutating it."""
    existing = backend_app.find_existing_account(login, server, platform)
    if not existing:
        raise RuntimeError("This MT5 account is not registered in the administrator MetaApi account. Ask the administrator to provision and deploy it first.")
    account_id = str(existing.get("_id") or existing.get("id") or "").strip()
    if not account_id:
        raise RuntimeError("MetaApi returned an account without an ID.")
    return account_id, "reused"

backend_app.create_metaapi_account = _reuse_existing_account


def _deploy_only_when_undeployed(account_id):
    """Do not call deployAccount for accounts that are already deployed."""
    status = backend_app.provisioning_account(account_id)
    state = str(status.get("state", "")).upper()
    if state == "DEPLOYED":
        return
    response = _ORIGINAL_META_RAW("POST", backend_app.METAAPI_PROVISIONING_URL, f"/users/current/accounts/{account_id}/deploy")
    if response.status_code not in (200, 204):
        body = backend_app.response_body(response)
        message = body.get("message") or body.get("error") or str(body) if isinstance(body, dict) else str(body)
        raise RuntimeError(f"MetaApi account is not deployed and this token cannot deploy it ({response.status_code}): {message}")

backend_app.deploy_metaapi_account = _deploy_only_when_undeployed


@app.get("/api/update")
def app_update():
    """Return the latest published production APK release for the mobile app."""
    try:
        response = requests.get(_GITHUB_LATEST_RELEASE, headers={"Accept": "application/vnd.github+json", "User-Agent": "Pips-Miner-Update-Service"}, timeout=10)
    except requests.RequestException as exc:
        return jsonify({"ok": False, "error": "GitHub release lookup failed.", "details": str(exc)}), 502
    if response.status_code == 404:
        return jsonify({"ok": True, "updateAvailable": False, "reason": "no_release"})
    if response.status_code != 200:
        return jsonify({"ok": False, "error": f"GitHub release lookup returned HTTP {response.status_code}."}), 502
    try:
        release = response.json()
    except ValueError:
        return jsonify({"ok": False, "error": "GitHub returned invalid release data."}), 502
    tag = str(release.get("tag_name", "")).strip()
    match = _VERSION_PATTERN.fullmatch(tag)
    if not match:
        return jsonify({"ok": False, "error": "The latest GitHub release does not declare a valid Pips Miner version."}), 502
    asset = next((item for item in (release.get("assets") or []) if str(item.get("name", "")).strip() == _EXPECTED_APK), None)
    if not asset:
        return jsonify({"ok": False, "error": f"The latest release is missing the required {_EXPECTED_APK} asset."}), 502
    download_url = str(asset.get("browser_download_url", "")).strip()
    if not download_url:
        return jsonify({"ok": False, "error": "The release APK has no download URL."}), 502
    return jsonify({"ok": True, "updateAvailable": True, "version": match.group(1), "tag": tag, "downloadUrl": download_url, "releaseUrl": str(release.get("html_url", "")).strip(), "assetName": _EXPECTED_APK})


@app.get("/api/v1/symbols")
@require_session
def account_symbols(session):
    """Return the symbols exposed by the user's connected MT account."""
    try:
        return meta_request("GET", session["account_id"], "/symbols")
    except Exception as exc:
        return jsonify({"ok": False, "error": str(exc)}), 502


@app.get("/api/v1/stream-token")
@require_session
def stream_token(session):
    """Issue a least-privilege MetaApi token for direct market streaming."""
    account_id = str(session.get("account_id", "")).strip()
    if not account_id:
        return jsonify({"ok": False, "error": "Trading account is missing from session."}), 401
    try:
        async def create_stream_token():
            api = MetaApi(backend_app.METAAPI_TOKEN)
            try:
                return await api.token_management_api.narrow_down_token(
                    {
                        "applications": ["metaapi-real-time-streaming-api"],
                        "roles": ["reader"],
                        "resources": [{"entity": "account", "id": account_id}],
                    },
                    24,
                )
            finally:
                try:
                    await api.close()
                except Exception:
                    pass

        token = asyncio.run(create_stream_token())
        account = backend_app.provisioning_account(account_id)
        region = str(account.get("region", "")).strip().lower()
        if not region:
            replicas = account.get("replicas") or []
            if isinstance(replicas, list) and replicas:
                region = str(replicas[0].get("region", "")).strip().lower()
        if not region or not _REGION_PATTERN.fullmatch(region):
            raise RuntimeError("MetaApi account region is unavailable for real-time streaming.")
        _ACCOUNT_REGIONS[account_id] = region
        return jsonify({
            "ok": True,
            "accountId": account_id,
            "token": token,
            "expiresInHours": 24,
            "streaming": True,
            "streamUrl": f"https://mt-client-api-v1.{region}.agiliumtrade.ai",
        })
    except Exception as exc:
        app.logger.exception("MetaApi streaming token generation failed")
        return jsonify({"ok": False, "error": str(exc)}), 502


# Vercel's Python runtime discovers the Flask WSGI application as `app`.
