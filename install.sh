#!/bin/bash

# PIPS Miner Bot - Installation Script
# Downloads and sets up the complete trading bot

echo ""
echo "========================================"
echo "🤖 PIPS MINER - VOLATILITY + MOMENTUM BOT"
echo "========================================"
echo ""

# Check if Git is installed
if ! command -v git &> /dev/null; then
    echo "❌ Git is not installed. Please install Git first."
    echo "   Windows: https://git-scm.com/download/win"
    echo "   Mac: brew install git"
    echo "   Linux: sudo apt install git"
    exit 1
fi

echo "✅ Git found"

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is not installed. Please install Python first."
    echo "   Download from: https://www.python.org/downloads/"
    exit 1
fi

echo "✅ Python 3 found: $(python3 --version)"

# Create project directory
echo ""
echo "📁 Creating project directory..."
mkdir -p ~/pips-miner
cd ~/pips-miner || exit
echo "✅ Directory: ~/pips-miner"

# Clone repository
echo ""
echo "📥 Downloading bot from GitHub..."
git clone https://github.com/JamesLaanyu1/pips-miner.git .
echo "✅ Bot downloaded successfully"

# Create virtual environment
echo ""
echo "🔧 Creating Python virtual environment..."
python3 -m venv venv
echo "✅ Virtual environment created"

# Activate virtual environment
echo ""
echo "🔌 Activating virtual environment..."
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    source venv/Scripts/activate
else
    source venv/bin/activate
fi
echo "✅ Virtual environment activated"

# Install dependencies
echo ""
echo "📦 Installing dependencies..."
pip install --upgrade pip
pip install -r requirements.txt
echo "✅ Dependencies installed"

# Create .env file
echo ""
echo "📝 Creating .env configuration file..."
cat > .env << 'EOF'
# MetaAPI Configuration
METAAPI_TOKEN=your_metaapi_token_here
METAAPI_ACCOUNT_ID=your_account_id_here

# Trading Configuration
TRADING_SYMBOL=XAUUSD
TRADING_VOLUME=0.01
STOP_PIPS=50

# Server Configuration
PORT=5000
FLASK_ENV=production
DEBUG=False
EOF

echo "✅ .env file created"

# Display next steps
echo ""
echo "========================================"
echo "✅ INSTALLATION COMPLETE!"
echo "========================================"
echo ""
echo "📋 NEXT STEPS:"
echo ""
echo "1️⃣  GET YOUR CREDENTIALS:"
echo "   • Visit: https://metaapi.cloud/"
echo "   • Sign up and get your API token"
echo "   • Link your HFM account"
echo "   • Copy your Account ID"
echo ""
echo "2️⃣  CONFIGURE CREDENTIALS:"
echo "   • Edit: ~/.env"
echo "   • Add your MetaAPI token"
echo "   • Add your Account ID"
echo ""
echo "3️⃣  TEST CONNECTION:"
echo "   cd ~/pips-miner"
echo "   source venv/bin/activate  (Linux/Mac)"
echo "   venv\\Scripts\\activate   (Windows)"
echo "   python test_metaapi_bridge.py"
echo ""
echo "4️⃣  RUN BOT:"
echo "   python metaapi_bot.py"
echo ""
echo "5️⃣  RUN MOBILE APP:"
echo "   cd mobile_app"
echo "   flutter run"
echo ""
echo "📖 FULL GUIDE: https://github.com/JamesLaanyu1/pips-miner/blob/main/METAAPI_SETUP_GUIDE.md"
echo ""
echo "Support: https://www.hfm.com/support"
echo "========================================"
echo ""
