import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/bot_provider.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'services/app_update_service.dart';
import 'services/background_execution_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializePipsMinerBackgroundService();
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
        title: 'Pips-Miner',
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
  Timer? _updateTimer;
  bool _updatePromptOpen = false;
  bool _initialUpdateCheckReported = false;

  final List<Widget> _screens = const [
    HomeScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
    _updateTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _checkForUpdate(),
    );
  }

  Future<void> _checkForUpdate() async {
    if (!mounted || _updatePromptOpen) return;
    _updatePromptOpen = true;
    try {
      final result = await AppUpdateService.instance.promptIfUpdateAvailable(context);

      // The first automatic check reports its exact decision once. This makes
      // update failures/version mismatches visible instead of silently hiding
      // them, while keeping subsequent background checks quiet.
      if (!_initialUpdateCheckReported && mounted &&
          result.status != UpdateCheckStatus.updateAvailable) {
        _initialUpdateCheckReported = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            duration: const Duration(seconds: 8),
          ),
        );
      } else if (!_initialUpdateCheckReported) {
        _initialUpdateCheckReported = true;
      }
    } finally {
      _updatePromptOpen = false;
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        height: 72,
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.candlestick_chart_outlined),
            selectedIcon: Icon(Icons.candlestick_chart),
            label: 'Trading',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
