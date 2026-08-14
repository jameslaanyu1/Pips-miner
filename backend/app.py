"""
Flask Backend API for Volatility + Momentum Trading Bot
Provides REST endpoints for bot control and monitoring
"""

from flask import Flask, jsonify, request
from flask_cors import CORS
from flask_socketio import SocketIO, emit, join_room
import asyncio
import logging
from datetime import datetime
import os
from dotenv import load_dotenv
from metaapi_bot import MetaAPITradingBot
import threading
import json

load_dotenv()

app = Flask(__name__)
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global bot instance
bot = None
bot_thread = None
bot_running = False


@app.route('/api/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'bot_running': bot_running
    })


@app.route('/api/config', methods=['POST'])
def configure_bot():
    """Configure bot with account credentials"""
    try:
        data = request.json
        account_id = data.get('account_id')
        api_token = data.get('api_token')
        symbol = data.get('symbol', 'EURUSD')
        
        global bot
        bot = MetaAPITradingBot(
            account_id=account_id,
            api_token=api_token,
            symbol=symbol
        )
        
        return jsonify({
            'status': 'configured',
            'account_id': account_id,
            'symbol': symbol
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 400


@app.route('/api/bot/start', methods=['POST'])
def start_bot():
    """Start the trading bot"""
    global bot, bot_running, bot_thread
    
    if not bot:
        return jsonify({'error': 'Bot not configured'}), 400
    
    if bot_running:
        return jsonify({'error': 'Bot already running'}), 400
    
    try:
        bot_running = True
        
        def run_bot():
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            try:
                loop.run_until_complete(bot.run(interval=60))
            finally:
                loop.close()
        
        bot_thread = threading.Thread(target=run_bot, daemon=True)
        bot_thread.start()
        
        logger.info("Bot started successfully")
        return jsonify({'status': 'started'})
    except Exception as e:
        bot_running = False
        return jsonify({'error': str(e)}), 500


@app.route('/api/bot/stop', methods=['POST'])
def stop_bot():
    """Stop the trading bot"""
    global bot_running, bot
    
    if not bot_running:
        return jsonify({'error': 'Bot not running'}), 400
    
    try:
        bot_running = False
        logger.info("Bot stop requested")
        return jsonify({'status': 'stopped'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/bot/status', methods=['GET'])
def bot_status():
    """Get current bot status"""
    global bot, bot_running
    
    if not bot:
        return jsonify({'status': 'not_configured'})
    
    return jsonify({
        'status': 'running' if bot_running else 'stopped',
        'symbol': bot.symbol,
        'position': bot.position,
        'entry_price': bot.entry_price,
        'stop_price': bot.stop_price,
        'trade_count': bot.trade_count,
        'timestamp': datetime.now().isoformat()
    })


@app.route('/api/positions', methods=['GET'])
async def get_positions():
    """Get current open positions"""
    if not bot or not bot.connection:
        return jsonify({'error': 'Bot not initialized'}), 400
    
    try:
        positions = await bot.check_positions()
        return jsonify({
            'positions': positions,
            'count': len(positions)
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/account/balance', methods=['GET'])
async def get_balance():
    """Get account balance and equity"""
    if not bot or not bot.connection:
        return jsonify({'error': 'Bot not initialized'}), 400
    
    try:
        balance = await bot.get_account_balance()
        return jsonify(balance)
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/manual/close', methods=['POST'])
async def manual_close_position():
    """Manually close current position"""
    if not bot or not bot.connection:
        return jsonify({'error': 'Bot not initialized'}), 400
    
    try:
        success = await bot.close_position()
        return jsonify({
            'status': 'closed' if success else 'no_position',
            'success': success
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@socketio.on('connect')
def handle_connect():
    """Handle WebSocket connection"""
    logger.info(f"Client connected: {request.sid}")
    emit('response', {'data': 'Connected to bot API'})


@socketio.on('subscribe')
def handle_subscribe(data):
    """Subscribe to bot updates"""
    room = data.get('room', 'bot_updates')
    join_room(room)
    emit('response', {'data': f'Subscribed to {room}'})


@socketio.on('disconnect')
def handle_disconnect():
    """Handle WebSocket disconnection"""
    logger.info(f"Client disconnected: {request.sid}")


def emit_bot_update(data):
    """Emit bot update to connected clients"""
    socketio.emit('bot_update', data, room='bot_updates')


if __name__ == '__main__':
    port = int(os.getenv('PORT', 5000))
    socketio.run(app, host='0.0.0.0', port=port, debug=False)
