# Complete MetaAPI Setup Guide for PIPS Miner Bot

## 📋 Table of Contents
1. [Prerequisites](#prerequisites)
2. [Step 1: Create MetaAPI Account](#step-1-create-metaapi-account)
3. [Step 2: Get MetaAPI Token](#step-2-get-metaapi-token)
4. [Step 3: Link HFM Account](#step-3-link-hfm-account)
5. [Step 4: Configure Environment](#step-4-configure-environment)
6. [Step 5: Test Connection](#step-5-test-connection)
7. [Step 6: Run Trading Bot](#step-6-run-trading-bot)
8. [Troubleshooting](#troubleshooting)
9. [Demo to Live Switch](#demo-to-live-switch)

---

## Prerequisites

✅ **Required Software:**
- Python 3.8+ installed
- pip (Python package manager)
- Git installed
- Text editor (VS Code recommended)

✅ **Required Accounts:**
- MetaAPI account (free tier available)
- HFM Demo or Live account

✅ **Internet Connection:**
- Stable connection for API calls
- No firewall blocks to metaapi.cloud

---

## Step 1: Create MetaAPI Account

### 1.1 Go to MetaAPI Website
```
https://metaapi.cloud/
```

### 1.2 Sign Up
- Click **"Sign Up"** in top right
- Enter email address
- Create strong password
- Accept terms and conditions
- Click **"Sign Up"**

### 1.3 Verify Email
- Check your email inbox
- Click verification link
- Confirm email address

### 1.4 Complete Profile
- Fill in your name
- Select your country
- Accept risk acknowledgment
- Click **"Create Account"**

✅ **You now have a MetaAPI account!**

---

## Step 2: Get MetaAPI Token

### 2.1 Login to MetaAPI Dashboard
```
https://app.metaapi.cloud/
```

### 2.2 Navigate to API Keys
1. Click your **profile icon** (top right)
2. Select **"API Keys"**
3. You should see your API tokens

### 2.3 Copy Your API Token
- Look for a token starting with `eyJ`
- Click **Copy** button next to it
- **IMPORTANT:** Keep this secret! Never share it!

### 2.4 Example Token Format
```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c
```

✅ **Token copied! Save it in a safe place.**

---

## Step 3: Link HFM Account

### 3.1 Create HFM Account (if you don't have one)

**Option A: Create Demo Account**
```
https://www.hfm.com/open-demo-account
```
- Click **"Open Demo Account"**
- Fill in your details
- Choose account currency (USD recommended)
- Set initial balance (e.g., $10,000)
- Create account
- Save login credentials

**Option B: Create Live Account**
```
https://www.hfm.com/open-live-account
```
- Complete KYC verification
- Deposit funds
- Get trading account credentials

### 3.2 Link HFM to MetaAPI

1. **Go to MetaAPI Accounts Page**
   - Login to https://app.metaapi.cloud/
   - Click **"Accounts"** in left sidebar
   - Click **"Create New Account"** or **"+"** button

2. **Select Broker**
   - Search for **"HFM"** or **"Hotforex"**
   - Click to select

3. **Enter Trading Credentials**
   - **Login:** Your HFM account number (e.g., `12345678`)
   - **Password:** Your HFM account password
   - **Server:** Select correct server (e.g., `HFM-Demo`, `HFM-Live`)

4. **Configure Account Settings**
   - **Name:** Give it a friendly name (e.g., "XAUUSD Trading Demo")
   - **Account Type:** Select DEMO or LIVE
   - **Platform:** MT4 or MT5 (check HFM)

5. **Deploy Account**
   - Click **"Deploy"**
   - Wait 1-2 minutes for deployment
   - Status should change to **"DEPLOYED"**

✅ **HFM Account successfully linked to MetaAPI!**

### 3.3 Get Your Account ID

1. In MetaAPI **Accounts** page
2. Find your linked account
3. Copy the **Account ID** (looks like a long string of numbers/letters)
4. Save it alongside your API token

---

## Step 4: Configure Environment

### 4.1 Create .env File

**Navigate to project folder:**
```bash
cd ~/pips-miner
```

**Create .env file:**
```bash
cat > .env << EOF
METAAPI_TOKEN=your_api_token_here
METAAPI_ACCOUNT_ID=your_account_id_here
TRADING_SYMBOL=XAUUSD
TRADING_VOLUME=0.01
STOP_PIPS=50
FLASK_ENV=development
EOF
```

### 4.2 Edit .env File

**Using VS Code:**
```bash
code .env
```

**Using nano:**
```bash
nano .env
```

**Copy and paste your credentials:**
```
METAAPI_TOKEN=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
METAAPI_ACCOUNT_ID=1a2b3c4d5e6f7g8h9i0j
TRADING_SYMBOL=XAUUSD
TRADING_VOLUME=0.01
STOP_PIPS=50
```

### 4.3 Save File
- **VS Code:** Ctrl+S (Windows) or Cmd+S (Mac)
- **Nano:** Ctrl+X, then Y, then Enter

✅ **.env file created and configured!**

---

## Step 5: Test Connection

### 5.1 Install Dependencies

```bash
pip install -r requirements.txt
```

**If you don't have requirements.txt installed, run:**
```bash
pip install metaapi-cloud-sdk python-dotenv asyncio
```

### 5.2 Run Test Suite

```bash
python test_metaapi_bridge.py
```

### 5.3 Check Output

**Expected output:**
```
================================================================================
🧪 METAAPI BRIDGE TEST SUITE - XAUUSD (GOLD)
================================================================================

🔌 TEST 1: Account Connection
--------------------------------------------------------------------------------
✅ PASS: Connected to account your_account_id

📊 TEST 2: Account Information
--------------------------------------------------------------------------------
Account ID: your_account_id
Account Type: DEMO
Broker: HFM
Balance: $10,000.00
Equity: $10,000.00
Free Margin: $10,000.00
Margin Level: 100000.00%
Leverage: 1:500
Currency: USD
Connected: True
Synchronized: True
✅ PASS: Account info retrieved successfully

💱 TEST 3: Price Quotes
--------------------------------------------------------------------------------
XAUUSD: Bid=2045.30 Ask=2045.50 Mid=2045.40
EURUSD: Bid=1.08567 Ask=1.08570 Mid=1.08568
GBPUSD: Bid=1.27845 Ask=1.27850 Mid=1.27847
✅ PASS: Retrieved quotes for 3/3 symbols

📈 TEST 4: Candle Data
--------------------------------------------------------------------------------
Retrieved 10 M1 candles for XAUUSD
Last 3 candles:
  1. O:2045.25 H:2045.60 L:2045.10 C:2045.40 V:1234
  2. O:2045.40 H:2045.55 L:2045.30 C:2045.45 V:1456
  3. O:2045.45 H:2045.70 L:2045.35 C:2045.65 V:1678
✅ PASS: Candle data retrieved successfully

...

================================================================================
📋 TEST SUMMARY - XAUUSD GOLD TRADING
================================================================================
✅ Account Connection: PASS
✅ Account Info: PASS
✅ Price Quotes: PASS
✅ Candle Data: PASS
✅ Open Positions: PASS
✅ Trade History: PASS
✅ Indicators: PASS
✅ Position Info: PASS

Overall: 8/8 tests passed
================================================================================
```

✅ **All tests passed! MetaAPI is connected and working!**

---

## Step 6: Run Trading Bot

### 6.1 Start Backend Server

```bash
python backend/app.py
```

**Expected output:**
```
 * Running on http://127.0.0.1:5000
 * Debug mode: off
```

### 6.2 Start Trading Bot (in new terminal)

```bash
python metaapi_bot.py
```

**Expected output:**
```
🤖 Starting Volatility + Momentum Bot
⏱️  Checking every 60 seconds
✅ Connected to MetaAPI account: your_account_id
📍 Trading symbol: XAUUSD
```

### 6.3 Launch Mobile App

**In Flutter mobile directory:**
```bash
cd mobile_app
flutter run
```

✅ **Bot is now running!**

---

## Troubleshooting

### Issue 1: "Invalid API Token"

**Solution:**
1. Check token is copied correctly (no extra spaces)
2. Go to MetaAPI → API Keys
3. Regenerate token if needed
4. Update .env file with new token

### Issue 2: "Account Not Found"

**Solution:**
1. Verify Account ID is correct (check MetaAPI dashboard)
2. Ensure account is DEPLOYED (status should be "DEPLOYED")
3. Wait 30 seconds and try again
4. Check if account type matches (Demo vs Live)

### Issue 3: "Connection Timeout"

**Solution:**
1. Check internet connection
2. Verify firewall isn't blocking metaapi.cloud
3. Try connecting with VPN if in restricted region
4. Restart the connection: Stop bot and start again

### Issue 4: "Insufficient Balance"

**Solution:**
1. Deposit more funds to HFM account
2. Reduce trade volume in .env file
3. Check Account Info shows correct balance

### Issue 5: "Symbol Not Available"

**Solution:**
1. Verify symbol exists on HFM (check trading platform)
2. Use alternative symbol:
   - EURUSD (common forex)
   - GBPUSD (common forex)
   - XAUUSD (gold)
3. Check market hours (forex 24/5, commodities have specific hours)

### Debug Mode

**Enable verbose logging:**
```bash
export LOGLEVEL=DEBUG
python test_metaapi_bridge.py
```

---

## Demo to Live Switch

### Step 1: Test on Demo Account First

✅ Make sure bot passes all tests on demo
✅ Verify strategy profitability
✅ Run for at least 1-2 weeks

### Step 2: Create Live HFM Account

1. Go to https://www.hfm.com/open-live-account
2. Complete KYC verification
3. Deposit funds (start small)
4. Get trading credentials

### Step 3: Link Live Account to MetaAPI

1. MetaAPI → Accounts → Create New
2. Select HFM broker
3. Enter live account credentials
4. Select "LIVE" account type
5. Deploy account
6. Copy new Account ID

### Step 4: Update .env for Live

```bash
# Old (Demo)
# METAAPI_ACCOUNT_ID=demo_account_id

# New (Live)
METAAPI_ACCOUNT_ID=live_account_id
```

### Step 5: Test Live Connection

```bash
python test_metaapi_bridge.py
```

✅ Should pass all tests with LIVE account info

### Step 6: Start Bot on Live

**⚠️ WARNING: Trading with real money!**

```bash
python metaapi_bot.py
```

**⚠️ Start with small volume:**
- Use 0.01 lot size initially
- Monitor performance closely
- Only increase after consistent profits

### Step 7: Monitor in Mobile App

1. Launch Flutter app
2. Go to Settings
3. Toggle to **LIVE** mode (Red button)
4. **WARNING** will appear
5. Start bot and monitor trades

---

## Environment Variables Reference

```bash
# Required
METAAPI_TOKEN              # Your MetaAPI token (from https://app.metaapi.cloud/)
METAAPI_ACCOUNT_ID         # Account ID linked to HFM

# Optional (with defaults)
TRADING_SYMBOL=XAUUSD      # Symbol to trade (default: XAUUSD)
TRADING_VOLUME=0.01        # Lot size (default: 0.01)
STOP_PIPS=50               # Stop loss distance in pips (default: 50)
FLASK_ENV=production       # Flask environment (default: production)
PORT=5000                  # Backend port (default: 5000)
DEBUG=False                # Debug mode (default: False)
```

---

## Quick Start Command Reference

```bash
# 1. Install dependencies
pip install -r requirements.txt

# 2. Test connection
python test_metaapi_bridge.py

# 3. Start backend
python backend/app.py

# 4. Start bot (new terminal)
python metaapi_bot.py

# 5. Run mobile app (new terminal)
cd mobile_app && flutter run
```

---

## Support Resources

- **MetaAPI Docs:** https://metaapi.cloud/docs/client/
- **HFM Support:** https://www.hfm.com/support
- **GitHub Issues:** https://github.com/JamesLaanyu1/pips-miner/issues
- **Forex Hours:** https://www.forex.com/en/market-hours/

---

## Security Best Practices

✅ **DO:**
- Keep .env file in .gitignore
- Use strong passwords for HFM account
- Enable 2FA on MetaAPI if available
- Keep API token secret
- Use DEMO account for testing
- Start with small volumes on LIVE

❌ **DON'T:**
- Share your API token
- Commit .env to GitHub
- Use same password for multiple accounts
- Trade with funds you can't afford to lose
- Ignore risk warnings

---

## Congratulations! 🎉

You now have:
✅ MetaAPI configured
✅ HFM account linked
✅ Trading bot connected
✅ Mobile app ready to control bot
✅ Demo account for safe testing
✅ Path to live trading

**Happy trading! 📈**
