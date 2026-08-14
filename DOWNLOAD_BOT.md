# PIPS Miner Bot - Quick Download Guide

## 🚀 Download Bot in 3 Ways

### **Method 1: Automatic Installation (Recommended)**

#### Windows:
```bash
REM Download and run installer
curl -O https://raw.githubusercontent.com/JamesLaanyu1/pips-miner/main/install.bat
install.bat
```

#### Mac/Linux:
```bash
# Download and run installer
curl -O https://raw.githubusercontent.com/JamesLaanyu1/pips-miner/main/install.sh
chmod +x install.sh
./install.sh
```

#### Python (All Platforms):
```bash
# Download Python installer
curl -O https://raw.githubusercontent.com/JamesLaanyu1/pips-miner/main/install.py
python3 install.py
```

---

### **Method 2: Manual Git Clone**

```bash
# Clone repository
git clone https://github.com/JamesLaanyu1/pips-miner.git
cd pips-miner

# Create virtual environment
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate          # Linux/Mac
venv\Scripts\activate              # Windows

# Install dependencies
pip install -r requirements.txt

# Create .env file
cat > .env << EOF
METAAPI_TOKEN=your_token_here
METAAPI_ACCOUNT_ID=your_id_here
TRADING_SYMBOL=XAUUSD
EOF
```

---

### **Method 3: Docker (Pre-configured)**

```bash
# Clone and setup Docker
git clone https://github.com/JamesLaanyu1/pips-miner.git
cd pips-miner

# Create .env
cat > .env << EOF
METAAPI_TOKEN=your_token_here
METAAPI_ACCOUNT_ID=your_id_here
EOF

# Build and run
docker-compose up -d
```

---

## ✅ After Download - Configure Credentials

### Step 1: Get MetaAPI Token
```
https://metaapi.cloud → Sign Up → API Keys → Copy Token
```

### Step 2: Link HFM Account
```
https://app.metaapi.cloud → Accounts → Create New → Link HFM → Deploy
```

### Step 3: Edit .env File
```bash
# Open .env and replace:
METAAPI_TOKEN=your_actual_token_here
METAAPI_ACCOUNT_ID=your_actual_id_here
```

### Step 4: Test Connection
```bash
python test_metaapi_bridge.py
```

**Expected output:**
```
✅ Account Connection: PASS
✅ Account Info: PASS
✅ Price Quotes: PASS
✅ Candle Data: PASS
✅ Open Positions: PASS
✅ Trade History: PASS
✅ Indicators: PASS
✅ Position Info: PASS
```

---

## 🤖 Run Bot

```bash
# Start backend
python backend/app.py

# Start bot (new terminal)
python metaapi_bot.py

# Run mobile app (new terminal)
cd mobile_app
flutter run
```

---

## 📋 System Requirements

- Python 3.8+
- Git
- 500MB disk space
- Internet connection

---

## 🆘 Troubleshooting

**Python not found:**
```
Download: https://www.python.org/downloads/
```

**Git not found:**
```
Download: https://git-scm.com/download/
```

**Permission denied (Linux/Mac):**
```bash
chmod +x install.sh
./install.sh
```

**Module not found:**
```bash
pip install -r requirements.txt
```

---

## 📚 Full Documentation

- Setup Guide: [METAAPI_SETUP_GUIDE.md](https://github.com/JamesLaanyu1/pips-miner/blob/main/METAAPI_SETUP_GUIDE.md)
- Quick Start: [METAAPI_QUICKSTART.md](https://github.com/JamesLaanyu1/pips-miner/blob/main/METAAPI_QUICKSTART.md)
- GitHub Repo: https://github.com/JamesLaanyu1/pips-miner

---

**Ready to start trading? Download now! 🚀**
