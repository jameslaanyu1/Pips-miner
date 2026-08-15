import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/trading_config.dart';
import '../services/metaapi_service.dart';
import '../services/secure_storage_service.dart';
import '../services/velocity_reversal_engine.dart';

class BotProvider extends ChangeNotifier {
  BotProvider();

  final SecureStorageService _storage = SecureStorageService();

  bool _isLiveAccount = false;
  String _symbol = 'XAUUSD';

  bool _isBotRunning = false;
  bool _isConnected = false;
  String? _currentPosition;
  double? _entryPrice;
  double? _stopPrice;

  int _totalTrades = 0;
  double _winRate = 0.0;
  double _profitLoss = 0.0;
  double _balance = 0.0;
  double _priceChange = 0.0;

  Timer? _updateTimer;
  MetaApiService? _api;
  VelocityReversalEngine? _engine;

  bool get isLiveAccount => _isLiveAccount;
  bool get isBotRunning => _isBotRunning;
  bool get isConnected => _isConnected;
  String? get currentPosition => _currentPosition;
  double? get entryPrice => _entryPrice;
  double? get stopPrice => _stopPrice;
  int get totalTrades => _totalTrades;
  double get winRate => _winRate;
  double get profitLoss => _profitLoss;
  double get balance => _balance;
  double get priceChange => _priceChange;
  String get symbol => _symbol;
  String get accountMode => _isLiveAccount ? 'LIVE' : 'DEMO';

  void setAccountMode(bool isLive) {
    if (_isBotRunning) return;
    _isLiveAccount = isLive;
    notifyListeners();
  }

  void updateSettings({
    String? symbol,
  }) {
    if (symbol != null && symbol.trim().isNotEmpty) {
      _symbol = symbol.trim().toUpperCase();
    }
    notifyListeners();
  }

  Future<void> connect() async {
    try {
      final token = await _storage.token();
      final accountId = _isLiveAccount
          ? await _storage.liveAccountId()
          : await _storage.demoAccountId();
      final host = await _storage.host();

      if (token == null ||
          token.isEmpty ||
          accountId == null ||
          accountId.isEmpty) {
        _isConnected = false;
        notifyListeners();
        return;
      }

      _api = MetaApiService(
        token: token,
        accountId: accountId,
        host: (host == null || host.isEmpty)
            ? 'https://mt-client-api-v1.london.agiliumtrade.ai'
            : host,
      );

      await _api!.accountInformation();
      _isConnected = true;
      await _fetchBotStatus();
      notifyListeners();
    } catch (e) {
      _isConnected = false;
      debugPrint('MetaApi connection error: $e');
      notifyListeners();
    }
  }

  Future<void> startBot() async {
    try {
      if (!_isConnected || _api == null) {
        await connect();
      }

      if (!_isConnected || _api == null) {
        throw Exception(
          'MetaApi is not connected. Save the token and account ID first.',
        );
      }

      final config = TradingConfig(
        symbol: _symbol,
        trailingPips: 100.0,
        reversalPips: 100.0,
        velocityBaselinePeriod: 14,
        velocityExpansionThreshold: 1.5,
      );

      _engine = VelocityReversalEngine(
        api: _api!,
        config: config,
      );

      await _engine!.start();
      _isBotRunning = true;
      _startUpdates();
      notifyListeners();
    } catch (e) {
      debugPrint('Error starting velocity engine: $e');
      rethrow;
    }
  }

  Future<void> stopBot() async {
    _engine?.stop();
    _engine = null;
    _isBotRunning = false;
    _updateTimer?.cancel();
    await _fetchBotStatus();
    notifyListeners();
  }

  void _startUpdates() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) async {
        if (_engine != null) {
          try {
            await _engine!.tick();
          } catch (e) {
            debugPrint('Velocity engine tick error: $e');
          }
        }
        await _fetchBotStatus();
      },
    );
  }

  Future<void> _fetchBotStatus() async {
    try {
      final api = _api;
      if (api == null) return;

      final positions = await api.positions();
      final strategy = positions.whereType<Map>().map(
        (p) => Map<String, dynamic>.from(p),
      ).where((p) => p['symbol']?.toString() == _symbol).toList();

      if (strategy.isNotEmpty) {
        final p = strategy.first;
        final type = p['type']?.toString() ?? '';
        _currentPosition = type.contains('SELL') ? 'SELL' : 'BUY';
        _entryPrice = _number(p['openPrice']);
        _stopPrice = _engine?.reversalPrice;
      } else {
        _currentPosition = null;
        _entryPrice = null;
        _stopPrice = null;
      }

      final info = await api.accountInformation();
      _balance = _number(info['balance']) ?? _balance;
      _profitLoss = _number(info['equity']) != null
          ? (_number(info['equity'])! - _balance)
          : _profitLoss;

      _isBotRunning = _engine?.running ?? false;
    } catch (e) {
      debugPrint('Status error: $e');
    }
    notifyListeners();
  }

  double? _number(dynamic value) {
    if (value == null) return null;
    return double.tryParse(value.toString());
  }

  @override
  void dispose() {
    _engine?.stop();
    _updateTimer?.cancel();
    super.dispose();
  }
}
