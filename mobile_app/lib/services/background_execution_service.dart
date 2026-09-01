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
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
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

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  late final VelocityReversalEngine engine;
  late final TradingConfig config;
  late final MetaApiService api;

  try {
    final storage = SecureStorageService();

    // The Android trading isolate uses the same authenticated
    // Pips-Miner backend session as the dashboard.
    final token = await storage.getPipsMinerSessionToken();
    final accountId = await storage.getPipsMinerAccountId();
    final storedSymbol = await storage.getTradingSymbol();

    if (token == null ||
        token.trim().isEmpty ||
        accountId == null ||
        accountId.trim().isEmpty) {
      throw Exception(
        'Pips-Miner trading session is not configured. Connect the MT5 account first.',
      );
    }

    api = MetaApiService(
      token: token.trim(),
      accountId: accountId.trim(),
    );

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
    debugPrint('Pips Miner background initialization error: $e');

    service.invoke('engineError', {
      'fatal': true,
      'message': e.toString().replaceFirst('Exception: ', ''),
    });

    service.stopSelf();
    return;
  }

  var stopped = false;

  service.on('stopService').listen((_) {
    stopped = true;
    engine.stop();
    service.stopSelf();
  });

  service.on('ping').listen((_) {
    service.invoke('engineStatus', {
      'running': engine.running,
      'timestamp': DateTime.now().toIso8601String(),
    });
  });

  // Backend/market-data readiness and the first reconciliation are allowed
  // to fail transiently. Do not terminate the foreground service because of
  // a temporary MetaApi/backend/broker-data failure. The engine's existing
  // reconcile logic remains unchanged; we simply retry startup until it can
  // enter its normal one-second execution loop.
  var started = false;
  while (!stopped && !started) {
    try {
      await api.waitUntilReady();
      await engine.start();
      started = engine.running;

      if (started) {
        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: 'Pips Miner',
            content: 'Trading engine is running',
          );
        }

        service.invoke('engineStatus', {
          'running': true,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('Pips Miner startup/reconciliation error: $e');

      service.invoke('engineError', {
        'fatal': false,
        'message': e.toString().replaceFirst('Exception: ', ''),
      });

      if (!stopped) {
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
  }

  if (stopped || !started) return;

  Timer.periodic(const Duration(seconds: 1), (timer) async {
    if (stopped || !engine.running) {
      timer.cancel();
      return;
    }

    try {
      await engine.tick();

      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'Pips Miner',
          content: 'Trading engine running • ${config.symbol}',
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

      service.invoke('engineError', {
        'fatal': false,
        'message': e.toString().replaceFirst('Exception: ', ''),
      });
    }
  });
}