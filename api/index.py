"""
Vercel entry point for Pips Miner.

The persistent trading worker remains outside the serverless runtime.
This module exposes the existing Flask control API through Vercel and provides
public release metadata for the Android updater.
"""

import re

import requests
from flask import jsonify, request

from backend.app import app, meta_request, require_session
import backend.broker_search  # noqa: F401 - registers broker search route


_GITHUB_LATEST_RELEASE = "https://api.github.com/repos/jameslaanyu1/Pips-miner/releases/latest"
_EXPECTED_APK = "Pips-Miner-release.apk"
_VERSION_PATTERN = re.compile(r"^v?(\d+\.\d+\.\d+)$")


@app.get("/api/update")
def app_update():
    """Return the latest published production APK release for the mobile app."""
    try:
        response = requests.get(
            _GITHUB_LATEST_RELEASE,
            headers={
                "Accept": "application/vnd.github+json",
                "User-Agent": "Pips-Miner-Update-Service",
            },
            timeout=10,
        )
    except requests.RequestException as exc:
        return jsonify({"ok": False, "error": "GitHub release lookup failed.", "details": str(exc)}), 502

    if response.status_code == 404:
        return jsonify({"ok": True, "updateAvailable": False, "reason": "no_release"})

    if response.status_code != 200:
        return jsonify({
            "ok": False,
            "error": f"GitHub release lookup returned HTTP {response.status_code}.",
        }), 502

    try:
        release = response.json()
    except ValueError:
        return jsonify({"ok": False, "error": "GitHub returned invalid release data."}), 502

    tag = str(release.get("tag_name", "")).strip()
    match = _VERSION_PATTERN.fullmatch(tag)
    if not match:
        return jsonify({
            "ok": False,
            "error": "The latest GitHub release does not declare a valid Pips Miner version.",
        }), 502

    asset = next(
        (
            item for item in (release.get("assets") or [])
            if str(item.get("name", "")).strip() == _EXPECTED_APK
        ),
        None,
    )
    if not asset:
        return jsonify({
            "ok": False,
            "error": f"The latest release is missing the required {_EXPECTED_APK} asset.",
        }), 502

    download_url = str(asset.get("browser_download_url", "")).strip()
    if not download_url:
        return jsonify({"ok": False, "error": "The release APK has no download URL."}), 502

    return jsonify({
        "ok": True,
        "updateAvailable": True,
        "version": match.group(1),
        "tag": tag,
        "downloadUrl": download_url,
        "releaseUrl": str(release.get("html_url", "")).strip(),
        "assetName": _EXPECTED_APK,
    })


@app.get("/api/v1/symbols")
@require_session
def account_symbols(session):
    """Return the symbols actually exposed by the user's connected MT account.

    The account ID comes from the authenticated Pips-Miner session, so symbol
    discovery is broker/account specific rather than a hard-coded global list.
    An optional `search` parameter is applied locally to the returned symbol
    names to keep the MetaApi symbols call deterministic and inexpensive for
    the mobile selector.
    """
    try:
        result = meta_request("GET", session["account_id"], "/symbols")
        return result
    except Exception as exc:
        return jsonify({"ok": False, "error": str(exc)}), 502


# Vercel's Python runtime discovers the Flask WSGI application as `app`.
