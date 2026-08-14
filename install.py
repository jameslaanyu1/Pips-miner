#!/usr/bin/env python3
"""
PIPS Miner Bot - Quick Download & Setup Script
Downloads and configures the trading bot automatically
"""

import os
import sys
import subprocess
import platform
from pathlib import Path


class BotInstaller:
    """Bot installation helper"""

    def __init__(self):
        self.home_dir = Path.home()
        self.project_dir = self.home_dir / 'pips-miner'
        self.platform = platform.system()

    def print_header(self):
        """Print welcome header"""
        print("\n" + "="*50)
        print("🤖 PIPS MINER - TRADING BOT INSTALLER")
        print("="*50 + "\n")

    def check_prerequisites(self):
        """Check if required software is installed"""
        print("📋 Checking prerequisites...\n")

        # Check Git
        try:
            subprocess.run(['git', '--version'], capture_output=True, check=True)
            print("✅ Git found")
        except (subprocess.CalledProcessError, FileNotFoundError):
            print("❌ Git not found")
            print("   Download: https://git-scm.com/download/")
            return False

        # Check Python
        try:
            result = subprocess.run(
                [sys.executable, '--version'],
                capture_output=True,
                text=True,
                check=True
            )
            print(f"✅ Python found: {result.stdout.strip()}")
        except (subprocess.CalledProcessError, FileNotFoundError):
            print("❌ Python 3 not found")
            print("   Download: https://www.python.org/downloads/")
            return False

        return True

    def create_project_dir(self):
        """Create project directory"""
        print("\n📁 Creating project directory...")
        self.project_dir.mkdir(parents=True, exist_ok=True)
        os.chdir(self.project_dir)
        print(f"✅ Directory: {self.project_dir}")

    def clone_repository(self):
        """Clone GitHub repository"""
        print("\n📥 Downloading bot from GitHub...")
        try:
            # Check if already cloned
            if (self.project_dir / '.git').exists():
                print("✅ Repository already exists")
                # Update
                subprocess.run(['git', 'pull'], cwd=self.project_dir, check=True)
                print("✅ Repository updated")
            else:
                subprocess.run(
                    ['git', 'clone', 'https://github.com/JamesLaanyu1/pips-miner.git', '.'],
                    cwd=self.project_dir,
                    check=True
                )
                print("✅ Bot downloaded successfully")
            return True
        except subprocess.CalledProcessError as e:
            print(f"❌ Failed to clone repository: {e}")
            return False

    def create_venv(self):
        """Create Python virtual environment"""
        print("\n🔧 Creating Python virtual environment...")
        try:
            venv_dir = self.project_dir / 'venv'
            subprocess.run(
                [sys.executable, '-m', 'venv', str(venv_dir)],
                check=True
            )
            print("✅ Virtual environment created")
            return venv_dir
        except subprocess.CalledProcessError as e:
            print(f"❌ Failed to create virtual environment: {e}")
            return None

    def install_dependencies(self, venv_dir):
        """Install Python dependencies"""
        print("\n📦 Installing dependencies...")
        try:
            if self.platform == 'Windows':
                pip_exe = venv_dir / 'Scripts' / 'pip.exe'
            else:
                pip_exe = venv_dir / 'bin' / 'pip'

            # Upgrade pip
            subprocess.run([str(pip_exe), 'install', '--upgrade', 'pip'], check=True)

            # Install requirements
            requirements = self.project_dir / 'requirements.txt'
            if requirements.exists():
                subprocess.run([str(pip_exe), 'install', '-r', str(requirements)], check=True)
                print("✅ Dependencies installed")
                return True
            else:
                print("⚠️  requirements.txt not found")
                return False
        except subprocess.CalledProcessError as e:
            print(f"❌ Failed to install dependencies: {e}")
            return False

    def create_env_file(self):
        """Create .env configuration file"""
        print("\n📝 Creating .env configuration file...")
        env_file = self.project_dir / '.env'

        env_content = """# MetaAPI Configuration
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
"""

        try:
            env_file.write_text(env_content)
            print("✅ .env file created")
            print(f"   Location: {env_file}")
            return True
        except IOError as e:
            print(f"❌ Failed to create .env file: {e}")
            return False

    def create_gitignore(self):
        """Create .gitignore to protect credentials"""
        print("\n🔐 Creating .gitignore...")
        gitignore = self.project_dir / '.gitignore'

        gitignore_content = """# Environment
.env
.env.local
.env.*.local

# Virtual Environment
venv/
env/

# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
*.egg-info/
dist/
build/

# IDE
.vscode/
.idea/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Logs
*.log
logs/

# Database
*.db
*.sqlite
"""

        try:
            if not gitignore.exists():
                gitignore.write_text(gitignore_content)
                print("✅ .gitignore created")
            return True
        except IOError as e:
            print(f"⚠️  Could not create .gitignore: {e}")
            return False

    def print_next_steps(self):
        """Print next steps after installation"""
        print("\n" + "="*50)
        print("✅ INSTALLATION COMPLETE!")
        print("="*50)
        print("\n📋 NEXT STEPS:\n")
        print("1️⃣  GET YOUR CREDENTIALS:")
        print("   • Visit: https://metaapi.cloud/")
        print("   • Sign up and get your API token")
        print("   • Link your HFM account")
        print("   • Copy your Account ID\n")
        print("2️⃣  CONFIGURE CREDENTIALS:")
        print(f"   • Edit: {self.project_dir / '.env'}")
        print("   • Add your MetaAPI token")
        print("   • Add your Account ID\n")
        print("3️⃣  TEST CONNECTION:")
        print(f"   cd {self.project_dir}")
        if self.platform == 'Windows':
            print("   venv\\Scripts\\activate")
        else:
            print("   source venv/bin/activate")
        print("   python test_metaapi_bridge.py\n")
        print("4️⃣  RUN BOT:")
        print("   python metaapi_bot.py\n")
        print("5️⃣  RUN MOBILE APP:")
        print("   cd mobile_app")
        print("   flutter run\n")
        print("📖 FULL GUIDE:")
        print("   https://github.com/JamesLaanyu1/pips-miner/blob/main/METAAPI_SETUP_GUIDE.md\n")
        print("Support: https://www.hfm.com/support")
        print("="*50 + "\n")

    def run(self):
        """Run installation"""
        self.print_header()

        if not self.check_prerequisites():
            print("\n❌ Installation failed: Missing prerequisites")
            return False

        self.create_project_dir()

        if not self.clone_repository():
            print("\n❌ Installation failed: Could not download repository")
            return False

        venv_dir = self.create_venv()
        if not venv_dir:
            print("\n❌ Installation failed: Could not create virtual environment")
            return False

        if not self.install_dependencies(venv_dir):
            print("\n❌ Installation failed: Could not install dependencies")
            return False

        if not self.create_env_file():
            print("\n❌ Installation failed: Could not create .env file")
            return False

        self.create_gitignore()
        self.print_next_steps()
        return True


def main():
    """Main entry point"""
    try:
        installer = BotInstaller()
        success = installer.run()
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n\n❌ Installation cancelled by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Installation failed: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
