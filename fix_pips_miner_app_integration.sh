#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd ~/Pips-miner

python3 - <<'PY'
from pathlib import Path

p = Path("mobile_app/lib/main.dart")
p.write_text(r"""import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/bot_provider.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const PipsMinerApp());
}

class PipsMinerApp extends StatelessWidget {
  const PipsMinerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BotProvider()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Pips Miner',
        theme: AppTheme.darkTheme,
        home: const MainScreen(),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
""")
PY

python3 - <<'PY'
from pathlib import Path
p = Path(".github/workflows/build-apk.yml")
s = p.read_text()
s = s.replace("--project-name=pips_miner_app", "--project-name=pips_miner")
p.write_text(s)
PY

git diff --check
git add mobile_app/lib/main.dart .github/workflows/build-apk.yml
git commit -m "Wire direct MetaApi velocity engine into Pips Miner app"
git push -u origin agent/pips-miner-rebuild
git status --short
git log -2 --oneline
