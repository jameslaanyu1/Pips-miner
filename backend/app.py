from flask import Flask, jsonify, request
from flask_cors import CORS
import os
import signal
import subprocess
import sys
from datetime import datetime, timezone

app = Flask(__name__)
CORS(app)

bot_process = None
bot_mode = "DEMO"
bot_symbol = "XAUUSD"


def bot_running():
    return bot_process is not None and bot_process.poll() is None


def account_credentials(mode):
    mode = mode.upper()

    account_id = (
        os.getenv("METAAPI_LIVE_ACCOUNT_ID")
        if mode == "LIVE"
        else os.getenv("METAAPI_DEMO_ACCOUNT_ID")
    )

    token = os.getenv("METAAPI_TOKEN")

    if not token:
        raise RuntimeError("METAAPI_TOKEN is missing")

    if not account_id:
        raise RuntimeError(
            f"METAAPI_{mode}_ACCOUNT_ID is missing"
        )

    return token, account_id


@app.get("/api/health")
def health():
    return jsonify({
        "status": "healthy",
        "bot_running": bot_running(),
        "mode": bot_mode,
        "symbol": bot_symbol,
        "timestamp": datetime.now(timezone.utc).isoformat()
    })


@app.post("/api/config")
def configure():
    global bot_mode, bot_symbol

    data = request.get_json(silent=True) or {}

    mode = str(
        data.get("mode", "DEMO")
    ).upper()

    symbol = str(
        data.get("symbol", "XAUUSD")
    ).upper()

    if mode not in ("DEMO", "LIVE"):
        return jsonify({
            "error": "Mode must be DEMO or LIVE"
        }), 400

    if bot_running():
        return jsonify({
            "error": "Stop the bot before changing account"
        }), 409

    try:
        account_credentials(mode)
    except Exception as e:
        return jsonify({
            "error": str(e)
        }), 400

    bot_mode = mode
    bot_symbol = symbol

    return jsonify({
        "status": "configured",
        "mode": bot_mode,
        "symbol": bot_symbol
    })


@app.post("/api/bot/start")
def start_bot():
    global bot_process

    if bot_running():
        return jsonify({
            "error": "Bot already running"
        }), 409

    try:
        token, account_id = account_credentials(bot_mode)
    except Exception as e:
        return jsonify({
            "error": str(e)
        }), 400

    root = os.path.dirname(
        os.path.dirname(__file__)
    )

    env = os.environ.copy()

    env["METAAPI_TOKEN"] = token
    env["METAAPI_ACCOUNT_ID"] = account_id
    env["SYMBOL"] = bot_symbol
    env["EXECUTE_ORDERS"] = "true"
    env["PYTHONUNBUFFERED"] = "1"

    runner = os.path.join(
        root,
        "backend",
        "velocity_runner.py"
    )

    bot_process = subprocess.Popen(
        [sys.executable, runner],
        cwd=root,
        env=env,
        start_new_session=True
    )

    return jsonify({
        "status": "started",
        "mode": bot_mode,
        "symbol": bot_symbol,
        "pid": bot_process.pid
    })


@app.post("/api/bot/stop")
def stop_bot():
    global bot_process

    if not bot_running():
        bot_process = None

        return jsonify({
            "status": "stopped"
        })

    try:
        os.killpg(
            os.getpgid(bot_process.pid),
            signal.SIGTERM
        )
    except Exception:
        try:
            bot_process.terminate()
        except Exception:
            pass

    bot_process = None

    return jsonify({
        "status": "stopped"
    })


@app.get("/api/bot/status")
def status():
    return jsonify({
        "status": "running" if bot_running() else "stopped",
        "running": bot_running(),
        "mode": bot_mode,
        "symbol": bot_symbol,
        "strategy": "FAST VELOCITY EXPANSION",
        "exit": "OPPOSITE STOP TRAILS FAVORABLE PRICE",
        "trailing_pips": 100,
        "timestamp": datetime.now(timezone.utc).isoformat()
    })


if __name__ == "__main__":
    port = int(
        os.getenv("PORT", "5000")
    )

    app.run(
        host="127.0.0.1",
        port=port,
        debug=False
    )
