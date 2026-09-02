import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/trading_config.dart';
import 'metaapi_service.dart';
import 'metaapi_streaming_service.dart';
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
  await notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
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
    iosConfiguration: IosConfiguration(autoStart: false, onForeground: pipsMinerBackgroundEntrypoint, onBackground: pipsMinerIosBackground),
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
  late final MetaApiStreamingService stream;

  try {
    final storage = SecureStorageService();
    final token = await storage.getPipsMinerSessionToken();
    final accountId = await storage.getPipsMinerAccountId();
    final storedSymbol = await storage.getTradingSymbol();
    if (token == null || token.trim().isEmpty || accountId == null || accountId.trim().isEmpty) {
      throw Exception('No existing Pips-Miner trading session is available. Connect the MT5 account first.');
    }
    api = MetaApiService(token: token.trim(), accountId: accountId.trim());
    final symbol = storedSymbol?.trim().isNotEmpty == true ? storedSymbol!.trim().toUpperCase() : 'XAUUSD';
    config = TradingConfig(symbol: symbol, trailingPips: 100.0, reversalPips: 100.0, velocityBaselinePeriod: 5, velocityExpansionThreshold: 1.0);
    engine = VelocityReversalEngine(api: api, config: config);
    final streamToken = await api.streamToken();
    stream = MetaApiStreamingService(token: streamToken, accountId: accountId.trim());
  } catch (e) {
    service.invoke('engineError', {'fatal': true, 'message': e.toString().replaceFirst('Exception: ', '')});
    service.stopSelf();
    return;
  }

  var stopped = false;
  var streamFailureHandled = false;
  Timer? tradingTimer;
  StreamSubscription<Map<String, dynamic>>? priceSubscription;
  StreamSubscription<Map<String, dynamic>>? streamEventSubscription;

  service.on('stopService').listen((_) {
    stopped = true;
    tradingTimer?.cancel();
    priceSubscription?.cancel();
    streamEventSubscription?.cancel();
    unawaited(stream.dispose());
    engine.stop();
    service.stopSelf();
  });

  service.on('ping').listen((_) {
    service.invoke('engineStatus', {'running': engine.running, 'streaming': stream.connected, 'timestamp': DateTime.now().toIso8601String()});
  });

  Future<void> emergencyCleanupAndShutdown() async {
    if (streamFailureHandled || stopped) return;
    streamFailureHandled = true;
    tradingTimer?.cancel();
    await priceSubscription?.cancel();
    await streamEventSubscription?.cancel();
    engine.stop();
    service.invoke('engineError', {'fatal': false, 'message': 'Live market stream/network connection lost. Trading stopped; protecting active Pips Miner positions and orders.'});
    while (!stopped) {
      try {
        await engine.cleanupManagedExposure();
        service.invoke('engineError', {'fatal': true, 'message': 'Network failure detected. All Pips Miner positions and orders were closed/cancelled before shutdown.'});
        await stream.dispose();
        service.stopSelf();
        return;
      } catch (cleanupError) {
        debugPrint('Pips Miner emergency cleanup pending: $cleanupError');
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }
  }

  try {
    // History is loaded once for the strategy baseline. Signal evaluation after
    // this point is driven by MetaApi tick events, not a timer or REST price poll.
    await api.candles(config.symbol, timeframe: '1m', limit: 100);
    await engine.start();

    streamEventSubscription = stream.events.listen((event) {
      final type = event['type']?.toString();
      if (type == 'disconnected' && !stopped) unawaited(emergencyCleanupAndShutdown());
      if (type == 'error' && !stopped) debugPrint('MetaApi stream error: ${event['message']}');
    });

    priceSubscription = stream.prices.listen((price) {
      if (stopped || !engine.running) return;
      // This callback is invoked by each live MetaApi price packet. No
      // one-second market-data polling remains on the hot signal path.
      unawaited(engine.tickLive(price));
    });

    await stream.connect(config.symbol);
    if (!stream.connected) throw Exception('MetaApi live market stream did not connect.');
  } catch (e) {
    if (MetaApiService.isNetworkFailure(e)) {
      await emergencyCleanupAndShutdown();
      return;
    }
    service.invoke('engineError', {'fatal': true, 'message': e.toString().replaceFirst('Exception: ', '')});
    engine.stop();
    await stream.dispose();
    service.stopSelf();
    return;
  }

  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(title: 'Pips Miner', content: 'LIVE streaming • ${config.symbol}');
  }
  service.invoke('engineStatus', {'running': true, 'streaming': true, 'timestamp': DateTime.now().toIso8601String()});

  // Keep the existing one-second reconciliation only for account-state
  // housekeeping/trailing-stop maintenance. It no longer retrieves market
  // data for signal generation.
  tradingTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
    if (stopped || !engine.running) {
      timer.cancel();
      return;
    }
    try {
      await engine.tick();
      if (service is AndroidServiceInstance) service.setForegroundNotificationInfo(title: 'Pips Miner', content: 'LIVE streaming • ${config.symbol}');
      service.invoke('engineStatus', {
        'running': true,
        'streaming': stream.connected,
        'timestamp': DateTime.now().toIso8601String(),
        'position': engine.activeDirection?.name,
        'entryId': engine.activePositionId,
        'reversalPrice': engine.reversalPrice,
      });
      if (!stream.connected) await emergencyCleanupAndShutdown();
    } catch (e) {
      debugPrint('Pips Miner background engine state tick error: $e');
      if (MetaApiService.isNetworkFailure(e)) {
        await emergencyCleanupAndShutdown();
        return;
      }
      service.invoke('engineError', {'fatal': false, 'message': e.toString().replaceFirst('Exception: ', '')});
    }
  });
}
