@echo off
REM PIPS Miner Bot - Installation Script for Windows
REM Downloads and sets up the complete trading bot

echo.
echo ========================================
echo 🤖 PIPS MINER - VOLATILITY + MOMENTUM BOT
echo ========================================
echo.

REM Check if Git is installed
git --version >nul 2>&1
if errorlevel 1 (
    echo ❌ Git is not installed. Please install Git first.
    echo    Download from: https://git-scm.com/download/win
    pause
    exit /b 1
)

echo ✅ Git found

REM Check if Python is installed
python --version >nul 2>&1
if errorlevel 1 (
    echo ❌ Python 3 is not installed. Please install Python first.
    echo    Download from: https://www.python.org/downloads/
    pause
    exit /b 1
)

for /f "tokens=*" %%i in ('python --version') do set PYTHON_VERSION=%%i
echo ✅ Python found: %PYTHON_VERSION%

REM Create project directory
echo.
echo 📁 Creating project directory...
if not exist "%USERPROFILE%\pips-miner" (
    mkdir "%USERPROFILE%\pips-miner"
)
cd /d "%USERPROFILE%\pips-miner" || exit /b 1
echo ✅ Directory: %USERPROFILE%\pips-miner

REM Clone repository
echo.
echo 📥 Downloading bot from GitHub...
git clone https://github.com/JamesLaanyu1/pips-miner.git .
echo ✅ Bot downloaded successfully

REM Create virtual environment
echo.
echo 🔧 Creating Python virtual environment...
python -m venv venv
echo ✅ Virtual environment created

REM Activate virtual environment
echo.
echo 🔌 Activating virtual environment...
call venv\Scripts\activate.bat
echo ✅ Virtual environment activated

REM Install dependencies
echo.
echo 📦 Installing dependencies...
python -m pip install --upgrade pip
pip install -r requirements.txt
echo ✅ Dependencies installed

REM Create .env file
echo.
echo 📝 Creating .env configuration file...
(
    echo # MetaAPI Configuration
    echo METAAPI_TOKEN=your_metaapi_token_here
    echo METAAPI_ACCOUNT_ID=your_account_id_here
    echo.
    echo # Trading Configuration
    echo TRADING_SYMBOL=XAUUSD
    echo TRADING_VOLUME=0.01
    echo STOP_PIPS=50
    echo.
    echo # Server Configuration
    echo PORT=5000
    echo FLASK_ENV=production
    echo DEBUG=False
) > .env

echo ✅ .env file created

REM Display next steps
echo.
echo ========================================
echo ✅ INSTALLATION COMPLETE!
echo ========================================
echo.
echo 📋 NEXT STEPS:
echo.
echo 1️⃣  GET YOUR CREDENTIALS:
echo    • Visit: https://metaapi.cloud/
echo    • Sign up and get your API token
echo    • Link your HFM account
echo    • Copy your Account ID
echo.
echo 2️⃣  CONFIGURE CREDENTIALS:
echo    • Edit: %USERPROFILE%\.env
echo    • Add your MetaAPI token
echo    • Add your Account ID
echo.
echo 3️⃣  TEST CONNECTION:
echo    cd %USERPROFILE%\pips-miner
echo    venv\Scripts\activate
echo    python test_metaapi_bridge.py
echo.
echo 4️⃣  RUN BOT:
echo    python metaapi_bot.py
echo.
echo 5️⃣  RUN MOBILE APP:
echo    cd mobile_app
echo    flutter run
echo.
echo 📖 FULL GUIDE: https://github.com/JamesLaanyu1/pips-miner/blob/main/METAAPI_SETUP_GUIDE.md
echo.
echo Support: https://www.hfm.com/support
echo ========================================
echo.

pause
