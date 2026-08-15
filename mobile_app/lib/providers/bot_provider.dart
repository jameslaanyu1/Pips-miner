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
  String? _connectionError;
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
  String? get connectionError => _connectionError;
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
    _isConnected = false;
    _connectionError = null;
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
    _connectionError = null;
    notifyListeners();

    try {
      final token = await _storage.token();
      final accountId = _isLiveAccount
          ? await _storage.liveAccountId()
          : await _storage.demoAccountId();
      final host = await _storage.host();

      if (token == null || token.trim().isEmpty) {
        _isConnected = false;
        _connectionError =
            'MetaAPI token is missing. Open Settings and save your token.';
        notifyListeners();
        return;
      }

      if (accountId == null || accountId.trim().isEmpty) {
        _isConnected = false;
        _connectionError =
            '${accountMode} account ID is missing. Open Settings and save the account ID.';
        notifyListeners();
        return;
      }

      final apiHost = (host == null || host.trim().isEmpty)
          ? 'https://mt-client-api-v1.london.agiliumtrade.ai'
          : host.trim();

      _api = MetaApiService(
        token: token.trim(),
        accountId: accountId.trim(),
        host: apiHost,
      );

      await _api!.accountInformation();

      _isConnected = true;
      _connectionError = null;

      await _fetchBotStatus();
      notifyListeners();
    } catch (e) {
      _isConnected = false;
      _connectionError = _friendlyConnectionError(e);

      debugPrint('MetaApi connection error: $e');
      notifyListeners();
    }
  }

  String _friendlyConnectionError(Object error) {
    final message = error.toString();
    final lower = message.toLowerCase();

    if (lower.contains('http 401') || lower.contains('http 403')) {
      return 'MetaAPI rejected the token. Check the MetaAPI token in Settings.';
    }

    if (lower.contains('http 404')) {
      return 'MetaAPI could not find this account. Check the selected ${accountMode} account ID.';
    }

    if (lower.contains('http 409')) {
      return 'MetaAPI account is not ready. Check that the account is deployed and connected.';
    }

    if (lower.contains('http 429')) {
      return 'MetaAPI rate limit reached. Please wait and reconnect.';
    }

    if (lower.contains('http 5')) {
      return 'MetaAPI server error. Check the internet connection and try again.';
    }

    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup')) {
      return 'Network connection failed. Check the phone internet connection.';
    }

    if (lower.contains('timeout')) {
      return 'MetaAPI connection timed out. Check the internet connection and try again.';
    }

    return 'MetaAPI connection failed. Open Settings and verify the token, account ID and host.';
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
