import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PipsNotificationService {
  PipsNotificationService._();

  static final PipsNotificationService instance = PipsNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'pips_miner_events',
    'Pips Miner Events',
    description: 'Important Pips Miner connection and bot events.',
    importance: Importance.high,
    playSound: true,
  );

  Future<void> initialize() async {
    if (_initialized) return;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await _plugin.initialize(settings);

    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_channel);
    await android?.requestNotificationsPermission();

    _initialized = true;
  }

  Future<void> show({required String title, required String body}) async {
    await initialize();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'pips_miner_events',
        'Pips Miner Events',
        channelDescription: 'Important Pips Miner connection and bot events.',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
      title,
      body,
      details,
    );
  }

  Future<void> mt5Connected() => show(
        title: 'MT5 Connected',
        body: 'Your MT5 account is connected successfully.',
      );

  Future<void> mt5ConnectionFailed(String message) => show(
        title: 'MT5 Connection Failed',
        body: message,
      );

  Future<void> botStarted() => show(
        title: 'Bot Started',
        body: 'Pips Miner has started trading.',
      );

  Future<void> botStopped() => show(
        title: 'Bot Stopped',
        body: 'Pips Miner has stopped trading.',
      );

  Future<void> accountModeChanged(String mode) => show(
        title: 'Trading Mode Changed',
        body: 'Switched to $mode mode.',
      );
}
