import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/trading_config.dart';
import 'metaapi_service.dart';
import 'secure_storage_service.dart';
import 'velocity_reversal_engine.dart';

const String pipsMinerServiceChannel = 'pips_miner_trading';
const int pipsMinerNotificationId = 26081501;

Future<void> initializePipsMinerBackgroundService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    pipsMinerServiceChannel,
    'Pips Miner Trading',
    description: 'Foreground notification for the Pips Miner trading engine.',
    importance: Importance.low,
  );

  final notifications = FlutterLocalNotificationsPlugin();
  await notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: pipsMinerBackgroundEntrypoint,
      autoStart: false,
      autoStartOnBoot: false,
      isForegroundMode: true,
      notificationChannelId: pipsMinerServiceChannel,
      initialNotificationTitle: 'Pips Miner',
      initialNotificationContent: 'Trading engine is running',
      foregroundServiceNotificationId: pipsMinerNotificationId,
      foregroundServiceTypes: const [AndroidForegroundType.specialUse],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: pipsMinerBackgroundEntrypoint,
      onBackground: pipsMinerIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> pipsMinerIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
Future<void> pipsMinerBackgroundEntrypoint(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) service.setAsForegroundService();

  late final VelocityReversalEngine engine;
  late final TradingConfig config;
  late final MetaApiService api;

  try {
    final storage = SecureStorageService();
    final token = await storage.getPipsMinerSessionToken();
    final accountId = await storage.getPipsMinerAccountId();
    final storedSymbol = await storage.getTradingSymbol();

    if (token == null || token.trim().isEmpty || accountId == null || accountId.trim().isEmpty) {
      throw Exception('No existing Pips-Miner trading session is available. Connect the MT5 account first.');
    }

    api = MetaApiService(token: token.trim(), accountId: accountId.trim());

    final symbol = storedSymbol?.trim().isNotEmpty == true
        ? storedSymbol!.trim().toUpperCase()
        : 'XAUUSD';

    config = TradingConfig(
      symbol: symbol,
      trailingPips: 100.0,
      reversalPips: 100.0,
      velocityBaselinePeriod: 14,
      velocityExpansionThreshold: 1.5,
    );

    engine = VelocityReversalEngine(api: api, config: config);
  } catch (e) {
    service.invoke('engineError', {
      'fatal': true,
      'message': e.toString().replaceFirst('Exception: ', ''),
    });
    service.stopSelf();
    return;
  }

  var stopped = false;
  Timer? tradingTimer;

  service.on('stopService').listen((_) {
    stopped = true;
    tradingTimer?.cancel();
    engine.stop();
    service.stopSelf();
  });

  service.on('ping').listen((_) {
    service.invoke('engineStatus', {
      'running': engine.running,
      'timestamp': DateTime.now().toIso8601String(),
    });
  });

  Future<void> emergencyCleanupAndShutdown() async {
    tradingTimer?.cancel();
    engine.stop();

    service.invoke('engineError', {
      'fatal': false,
      'message': 'Network connection lost. Trading stopped; protecting active Pips Miner positions and orders.',
    });

    // If the network is completely down, cleanup cannot be sent to MetaApi.
    // Keep this foreground service alive without trading and retry until the
    // connection returns. Shutdown occurs only after cleanup is verified.
    while (!stopped) {
      try {
        await engine.cleanupManagedExposure();
        service.invoke('engineError', {
          'fatal': true,
          'message': 'Network failure detected. All Pips Miner positions and orders were closed/cancelled before shutdown.',
        });
        service.stopSelf();
        return;
      } catch (cleanupError) {
        debugPrint('Pips Miner emergency cleanup pending: $cleanupError');
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }
  }

  try {
    // Start queries market data only. The existing authenticated account
    // session is reused; there is no account readiness/reconnection wait.
    await api.candles(config.symbol, timeframe: '1m', limit: 100);
    await engine.start();
  } catch (e) {
    if (MetaApiService.isNetworkFailure(e)) {
      await emergencyCleanupAndShutdown();
      return;
    }

    // Non-network problems do not turn the bot off. Start the engine and let
    // its normal one-second loop retry market data on subsequent cycles.
    service.invoke('engineError', {
      'fatal': false,
      'message': e.toString().replaceFirst('Exception: ', ''),
    });
    await engine.start();
  }

  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: 'Pips Miner',
      content: 'Scanning market • ${config.symbol}',
    );
  }

  service.invoke('engineStatus', {
    'running': true,
    'timestamp': DateTime.now().toIso8601String(),
  });

  tradingTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
    if (stopped || !engine.running) {
      timer.cancel();
      return;
    }

    try {
      await engine.tick();

      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'Pips Miner',
          content: 'Scanning market • ${config.symbol}',
        );
      }

      service.invoke('engineStatus', {
        'running': true,
        'timestamp': DateTime.now().toIso8601String(),
        'position': engine.activeDirection?.name,
        'entryId': engine.activePositionId,
        'reversalPrice': engine.reversalPrice,
      });
    } catch (e) {
      debugPrint('Pips Miner background engine tick error: $e');

      if (MetaApiService.isNetworkFailure(e)) {
        await emergencyCleanupAndShutdown();
        return;
      }

      service.invoke('engineError', {
        'fatal': false,
        'message': e.toString().replaceFirst('Exception: ', ''),
      });
    }
  });
}
