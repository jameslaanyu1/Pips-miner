import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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

  void updateSettings({String? symbol}) {
    if (symbol != null && symbol.trim().isNotEmpty) {
      _symbol = symbol.trim().toUpperCase();
    }
    notifyListeners();
  }

  Future<void> connect() async {
    _connectionError = null;
    notifyListeners();

    try {
      final session = await _storage.sessionToken();
      final backend = await _storage.backendUrl();

      if (session == null || session.isEmpty) {
        _isConnected = false;
        _connectionError =
            'MT5 account is not connected. Open Settings and connect your account.';
        notifyListeners();
        return;
      }

      if (backend == null || backend.isEmpty) {
        _isConnected = false;
        _connectionError = 'Pips-Miner backend address is not configured.';
        notifyListeners();
        return;
      }

      _api = MetaApiService(
        sessionToken: session,
        baseUrl: backend,
      );

      await _api!.accountInformation();

      _isConnected = true;
      _connectionError = null;

      await _fetchBotStatus();
      notifyListeners();
    } catch (e) {
      _isConnected = false;
      _connectionError = _friendlyConnectionError(e);
      debugPrint('Pips-Miner connection error: $e');
      notifyListeners();
    }
  }

  Future<bool> connectMt5({
    required String backendUrl,
    required String login,
    required String password,
    required String server,
  }) async {
    _connectionError = null;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse(
          '${backendUrl.replaceFirst(RegExp(r'/$'), '')}/api/v1/connect',
        ),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'login': login.trim(),
          'password': password,
          'server': server.trim(),
          'platform': 'mt5',
        }),
      );

      final decoded = jsonDecode(response.body);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          decoded is Map && decoded['error'] != null
              ? decoded['error'].toString()
              : 'MT5 connection failed.',
        );
      }

      if (decoded is! Map || decoded['sessionToken'] == null) {
        throw Exception('Backend did not return a valid session.');
      }

      await _storage.saveConnection(
        sessionToken: decoded['sessionToken'].toString(),
        backendUrl: backendUrl.trim(),
        login: login.trim(),
        server: server.trim(),
        platform: 'mt5',
      );

      await connect();
      return _isConnected;
    } catch (e) {
      _isConnected = false;
      _connectionError = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  String _friendlyConnectionError(Object error) {
    final message = error.toString();
    final lower = message.toLowerCase();

    if (lower.contains('401') || lower.contains('403')) {
      return 'Pips-Miner authentication failed. Connect the MT5 account again.';
    }

    if (lower.contains('404')) {
      return 'The Pips-Miner backend could not find this account.';
    }

    if (lower.contains('429')) {
      return 'Too many requests. Please wait and reconnect.';
    }

    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup')) {
      return 'Network connection failed. Check the phone internet connection.';
    }

    if (lower.contains('timeout')) {
      return 'Connection timed out. Check the internet connection and try again.';
    }

    return 'Pips-Miner connection failed: $message';
  }

  Future<void> startBot() async {
    if (!_isConnected || _api == null) {
      await connect();
    }

    if (!_isConnected || _api == null) {
      throw Exception(
        'MT5 is not connected. Connect the account first.',
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

      final strategy = positions
          .whereType<Map>()
          .map((p) => Map<String, dynamic>.from(p))
          .where((p) => p['symbol']?.toString() == _symbol)
          .toList();

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

      final equity = _number(info['equity']);
      if (equity != null) {
        _profitLoss = equity - _balance;
      }

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
