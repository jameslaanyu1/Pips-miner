import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/bot_provider.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/enhanced_settings_screen.dart';
import 'services/app_update_service.dart';
import 'services/background_execution_service.dart';
import 'services/pips_notification_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializePipsMinerBackgroundService();
  await PipsNotificationService.instance.initialize();
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
  BotProvider? _bot;
  bool _wasConnected = false;
  bool _wasBotRunning = false;
  bool _wasLiveAccount = false;
  String? _lastConnectionError;

  final List<Widget> _screens = const [
    HomeScreen(),
    EnhancedSettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bot = context.read<BotProvider>();
      _bot = bot;
      _wasConnected = bot.isConnected;
      _wasBotRunning = bot.isBotRunning;
      _wasLiveAccount = bot.isLiveAccount;
      _lastConnectionError = bot.connectionError;
      bot.addListener(_handleBotEvents);
      _checkForUpdate();
    });
    _updateTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _checkForUpdate(),
    );
  }

  void _handleBotEvents() {
    if (!mounted) return;
    final bot = _bot;
    if (bot == null) return;

    if (!_wasConnected && bot.isConnected) {
      unawaited(PipsNotificationService.instance.mt5Connected());
    }

    final error = bot.connectionError;
    if (error != null && error.isNotEmpty && error != _lastConnectionError && !bot.isConnected) {
      unawaited(PipsNotificationService.instance.mt5ConnectionFailed(error));
    }

    if (!_wasBotRunning && bot.isBotRunning) {
      unawaited(PipsNotificationService.instance.botStarted());
    } else if (_wasBotRunning && !bot.isBotRunning && bot.engineError == null) {
      unawaited(PipsNotificationService.instance.botStopped());
    }

    if (_wasLiveAccount != bot.isLiveAccount) {
      unawaited(PipsNotificationService.instance.accountModeChanged(bot.accountMode));
    }

    _wasConnected = bot.isConnected;
    _wasBotRunning = bot.isBotRunning;
    _wasLiveAccount = bot.isLiveAccount;
    _lastConnectionError = error;
  }

  Future<void> _checkForUpdate() async {
    if (!mounted || _updatePromptOpen) return;
    _updatePromptOpen = true;
    try {
      final result = await AppUpdateService.instance.promptIfUpdateAvailable(context);

      // Only a successful no-update check is surfaced to the user. Network
      // or service failures are retried on the next scheduled check and do
      // not appear as a scary technical error on the dashboard.
      if (!_initialUpdateCheckReported &&
          mounted &&
          result.status == UpdateCheckStatus.upToDate) {
        _initialUpdateCheckReported = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            duration: const Duration(seconds: 4),
          ),
        );
      } else if (result.status == UpdateCheckStatus.upToDate) {
        _initialUpdateCheckReported = true;
      }
    } finally {
      _updatePromptOpen = false;
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _bot?.removeListener(_handleBotEvents);
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
