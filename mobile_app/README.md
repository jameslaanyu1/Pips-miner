# PIPS Miner - Mobile App

Flutter mobile application for Volatility + Momentum Trading Bot with MetaAPI integration.

## Features

✅ **Demo/Live Account Switcher** - Toggle between risk-free demo and live trading  
✅ **Real-time Bot Control** - Start/Stop bot from mobile  
✅ **Live Trading Metrics** - View balance, profit/loss, win rate  
✅ **MetaAPI Integration** - Connect to HFM accounts  
✅ **Account Configuration** - Easy setup for API credentials  
✅ **Price Charts** - Live price visualization  
✅ **WebSocket Updates** - Real-time bot status updates  

## Setup

### Prerequisites
- Flutter SDK 3.13+
- Android SDK for APK building
- MetaAPI account and token
- HFM Demo/Live account

### Installation

```bash
cd mobile_app
flutter pub get
```

### Configure Backend

1. Update `lib/providers/bot_provider.dart` with your backend URL
2. Add MetaAPI token and account IDs in app settings

### Build APK

```bash
# Debug APK
flutter build apk --debug

# Release APK (Optimized)
flutter build apk --release

# Output: build/app/outputs/flutter-app.apk
```

### Build AAB (Google Play)

```bash
flutter build appbundle --release
```

## Account Switcher

The app includes a **Smart Account Switcher** that:
- Toggles between Demo (Blue) and Live (Red) modes
- Shows warning when in Live mode
- Disables switching while bot is running
- Automatically uses correct account ID based on selection

## Backend API Integration

The app connects to Flask backend at `http://localhost:5000/api` with endpoints:

- `GET /api/health` - Health check
- `POST /api/config` - Configure bot
- `POST /api/bot/start` - Start bot
- `POST /api/bot/stop` - Stop bot
- `GET /api/bot/status` - Get bot status
- `GET /api/positions` - Get open positions
- `GET /api/account/balance` - Get account balance

## Usage

1. **Configure Account**
   - Go to Settings
   - Enter MetaAPI token
   - Add Demo and Live account IDs
   - Set trading symbol and volume
   - Save settings

2. **Select Account Mode**
   - Use toggle in home screen
   - Demo = Blue, Live = Red
   - Warning shown for Live mode

3. **Start Trading**
   - Click START button
   - Monitor live metrics
   - View positions and P&L

4. **Stop Bot**
   - Click STOP button
   - Positions will close
   - Bot will stop
