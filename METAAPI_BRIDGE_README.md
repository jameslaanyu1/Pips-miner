# MetaAPI Bridge Testing Guide

## Prerequisites

1. **MetaAPI Account**
   - Sign up at https://metaapi.cloud
   - Get your API token
   - Get your account ID from MetaAPI dashboard

2. **HFM Account** (Demo or Live)
   - Create account at https://www.hfm.com/
   - Link to MetaAPI
   - Get account ID from MetaAPI

3. **Python Dependencies**
   ```bash
   pip install metaapi-cloud-sdk python-dotenv asyncio
   ```

## Setup

### 1. Create `.env` File

```bash
cat > .env << EOF
METAAPI_TOKEN=your_token_here
METAAPI_ACCOUNT_ID=your_account_id_here
TRADING_SYMBOL=EURUSD
EOF
```

### 2. Get MetaAPI Token

1. Go to https://metaapi.cloud
2. Sign up or login
3. Go to **API Keys** section
4. Copy your **API Token**

### 3. Get Account ID

1. In MetaAPI dashboard, go to **Accounts**
2. Connect your HFM account
3. Copy the **Account ID**

## Running Tests

### Test All Functionalities

```bash
python test_metaapi_bridge.py
```

This runs 8 comprehensive tests:
- ✅ Account Connection
- ✅ Account Information (balance, equity, margin)
- ✅ Price Quotes (Bid/Ask/Mid)
- ✅ Candle Data (OHLCV)
- ✅ Open Positions
- ✅ Trade History
- ✅ Indicator Calculation (ATR, RSI)
- ✅ Position Information

### Test Individual Functions

```python
import asyncio
from metaapi_bridge import MetaAPIBridge

async def test():
    bridge = MetaAPIBridge('your_token')
    
    # Set active account
    await bridge.set_active_account('account_id')
    
    # Get account info
    info = await bridge.get_account_info()
    print(f"Balance: ${info.balance}")
    
    # Get price
    quote = await bridge.get_quote('EURUSD')
    print(f"Price: {quote.mid}")
    
    # Get candles
    candles = await bridge.get_candles('EURUSD', 'M1', 10)
    print(f"Candles: {len(candles)}")
    
    # Get positions
    positions = await bridge.get_open_positions()
    print(f"Positions: {len(positions)}")
    
    await bridge.close()

asyncio.run(test())
```

## MetaAPI Bridge API Reference

### Connection Methods

```python
# Initialize bridge
bridge = MetaAPIBridge(api_token)

# Set active trading account
await bridge.set_active_account(account_id)

# Close all connections
await bridge.close()
```

### Account Methods

```python
# Get account information
info = await bridge.get_account_info()
# Returns: AccountInfo object with balance, equity, leverage, etc.

# Get current price quote
quote = await bridge.get_quote('EURUSD')
# Returns: Quote object with bid, ask, mid prices

# Get candle data
candles = await bridge.get_candles('EURUSD', 'M1', 50)
# Returns: List of candle dictionaries
```

### Trading Methods

```python
# Open position
trade = await bridge.open_position(
    symbol='EURUSD',
    order_type='BUY',
    volume=0.01,
    stop_loss=1.05000,
    take_profit=1.10000,
    comment='Vol-Mom Bot'
)

# Close position
await bridge.close_position(ticket_id)

# Modify position
await bridge.modify_position(
    ticket=ticket_id,
    stop_loss=1.04500,
    take_profit=1.10500
)
```

### Position Methods

```python
# Get open positions
positions = await bridge.get_open_positions()
# Optional filter by symbol:
positions = await bridge.get_open_positions('EURUSD')

# Get trade history
trades = await bridge.get_trade_history(limit=50)
```

## Troubleshooting

### "Connection Failed"
- Verify MetaAPI token is correct
- Check account ID is valid
- Ensure HFM account is connected to MetaAPI
- Check internet connection

### "Account Not Synchronized"
- Wait 30 seconds for sync to complete
- Check if account is deployed in MetaAPI dashboard
- Restart the connection

### "No Candle Data"
- Verify symbol is correct (e.g., 'EURUSD')
- Check if market is open (forex 24/5)
- Try different timeframe (M1, M5, H1, etc.)

### "Order Failed"
- Verify sufficient balance
- Check spread is acceptable
- Ensure position volume is valid
- Check trading hours for symbol

## Production Deployment

### Using with Flask Backend

```python
from flask import Flask, jsonify
from metaapi_bridge import MetaAPIBridge
import asyncio

app = Flask(__name__)
bridge = MetaAPIBridge(os.getenv('METAAPI_TOKEN'))

@app.route('/api/price/<symbol>')
async def get_price(symbol):
    quote = await bridge.get_quote(symbol)
    return jsonify(quote.to_dict())

@app.route('/api/positions')
async def get_positions():
    positions = await bridge.get_open_positions()
    return jsonify([p.to_dict() for p in positions])
```

### Using with Async Bot

The bridge integrates seamlessly with the `MetaAPITradingBot`:

```python
from metaapi_bot import MetaAPITradingBot

bot = MetaAPITradingBot(
    account_id='your_account_id',
    api_token='your_token',
    symbol='EURUSD'
)

await bot.run(interval=60)
```

## Demo to Live Account Switching

1. **Test on Demo**
   ```bash
   export METAAPI_ACCOUNT_ID=demo_account_id
   python test_metaapi_bridge.py
   ```

2. **Switch to Live** (after backtesting passes)
   ```bash
   export METAAPI_ACCOUNT_ID=live_account_id
   python test_metaapi_bridge.py
   ```

3. **In Mobile App**
   - Use the Demo/Live toggle in Settings
   - Blue = Demo, Red = Live
   - Warning shown for Live mode

## Support

- MetaAPI Docs: https://metaapi.cloud/docs/client/
- HFM Support: https://www.hfm.com/support
- Issues: Check logs and error messages
