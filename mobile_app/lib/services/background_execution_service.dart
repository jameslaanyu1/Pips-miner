import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../models/trading_config.dart';
import 'metaapi_service.dart';
import 'secure_storage_service.dart';
import 'velocity_reversal_engine.dart';

const String pipsMinerServiceChannel = 'pips_miner_trading';
const int pipsMinerNotificationId = 26081501;

Future<void> initializePipsMinerBackgroundService() async {
  final service = FlutterBackgroundService();

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
      foregroundServiceTypes: const [
        AndroidForegroundType.specialUse,
      ],
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
Future<void> pipsMinerBackgroundEntrypoint(
  ServiceInstance service,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  final storage = SecureStorageService();

  final token = await storage.getMetaApiToken();
  final accountId = await storage.getMetaApiAccountId();

  if (token == null ||
      token.trim().isEmpty ||
      accountId == null ||
      accountId.trim().isEmpty) {
    service.invoke('engineError', {
      'fatal': true,
      'message': 'MetaApi credentials are not configured.',
    });
    service.stopSelf();
    return;
  }

  final api = MetaApiService(
    token: token.trim(),
    accountId: accountId.trim(),
  );

  final config = TradingConfig(
    symbol: 'XAUUSD',
    trailingPips: 100.0,
    reversalPips: 100.0,
    velocityBaselinePeriod: 14,
    velocityExpansionThreshold: 1.5,
  );

  final engine = VelocityReversalEngine(
    api: api,
    config: config,
  );

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

  try {
    await engine.start();

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
  } catch (e) {
    service.invoke('engineError', {
      'fatal': true,
      'message': e.toString().replaceFirst('Exception: ', ''),
    });

    engine.stop();
    service.stopSelf();
    return;
  }

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
      });
    } catch (e) {
      debugPrint(
        'Pips Miner background engine tick error: $e',
      );

      service.invoke('engineError', {
        'fatal': false,
        'message': e.toString().replaceFirst('Exception: ', ''),
      });
    }
  });
}
