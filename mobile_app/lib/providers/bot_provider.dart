import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../models/trading_config.dart';
import '../services/background_execution_service.dart';
import '../services/metaapi_service.dart';
import '../services/secure_storage_service.dart';

class BotProvider extends ChangeNotifier {
  BotProvider() {
    _bindBackgroundService();
  }

  final SecureStorageService _storage = SecureStorageService();

  bool _isLiveAccount = false;
  String _symbol = 'XAUUSD';

  bool _isBotRunning = false;
  bool _isConnected = false;
  String? _connectionError;
  String? _engineError;
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

  StreamSubscription<Map<String, dynamic>?>? _engineStatusSubscription;
  StreamSubscription<Map<String, dynamic>?>? _engineErrorSubscription;

  bool get isLiveAccount => _isLiveAccount;
  bool get isBotRunning => _isBotRunning;
  bool get isConnected => _isConnected;
  String? get connectionError => _connectionError;
  String? get engineError => _engineError;
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

  void _bindBackgroundService() {
    final service = FlutterBackgroundService();

    _engineStatusSubscription = service.on('engineStatus').listen((event) {
      final running = event?['running'] == true;

      _isBotRunning = running;
      _stopPrice = _number(event?['reversalPrice']);

      if (running) {
        _engineError = null;
      }

      notifyListeners();
    });

    _engineErrorSubscription = service.on('engineError').listen((event) {
      final message = event?['message']?.toString();
      final fatal = event?['fatal'] == true;

      if (message != null && message.isNotEmpty) {
        _engineError = message;
      }

      if (fatal) {
        _isBotRunning = false;
      }

      notifyListeners();
    });
  }

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
      unawaited(_storage.saveTradingSymbol(_symbol));
    }
    notifyListeners();
  }

  Future<void> connect() async {
    _connectionError = null;
    notifyListeners();

    try {
      final token = await _storage.getMetaApiToken();
      final accountId = await _storage.getMetaApiAccountId();
      final region = await _storage.getMetaApiRegion();

      if (token == null ||
          token.trim().isEmpty ||
          accountId == null ||
          accountId.trim().isEmpty) {
        _isConnected = false;
        _connectionError = 'MetaApi credentials are not configured.';
        notifyListeners();
        return;
      }

      _api = MetaApiService(
        token: token.trim(),
        accountId: accountId.trim(),
        region: region?.trim().isNotEmpty == true ? region!.trim() : 'new-york',
      );

      await _api!.accountInformation();

      _isConnected = true;
      _connectionError = null;

      await _fetchBotStatus();
      notifyListeners();
    } catch (e) {
      _isConnected = false;
      _connectionError = _friendlyConnectionError(e);
      debugPrint('Pips-Miner MetaApi connection error: $e');
      notifyListeners();
    }
  }

  Future<bool> connectMt5({
    required String login,
    required String password,
    required String server,
  }) async {
    _connectionError = null;
    notifyListeners();

    try {
      final token = await _storage.getMetaApiToken();
      final accountId = await _storage.getMetaApiAccountId();

      if (token == null ||
          token.trim().isEmpty ||
          accountId == null ||
          accountId.trim().isEmpty) {
        throw Exception(
          'MetaApi credentials have not been configured for this app.',
        );
      }

      final provisioning = MetaApiService(
        token: token.trim(),
        accountId: accountId.trim(),
      );

      // Resolve the MetaApi account from the token + MT5 credentials.
      // This prevents a stale/mismatched stored account ID from causing
      // "Configuration token does not match the account id".
      final accounts = await provisioning.accounts();

      final requestedLogin = login.trim();
      final requestedServer = server.trim();

      Map<String, dynamic>? matchedAccount;

      for (final item in accounts) {
        if (item is! Map) continue;

        final candidate = Map<String, dynamic>.from(item);
        final candidateLogin = candidate['login']?.toString().trim() ?? '';
        final candidateServer = candidate['server']?.toString().trim() ?? '';

        if (candidateLogin == requestedLogin &&
            candidateServer.toLowerCase() == requestedServer.toLowerCase()) {
          matchedAccount = candidate;
          break;
        }
      }

      if (matchedAccount == null) {
        throw Exception(
          'No MetaApi account matches MT5 account '
          '$requestedLogin on server $requestedServer.',
        );
      }

      final resolvedAccountId =
          (matchedAccount['_id'] ??
                  matchedAccount['id'] ??
                  matchedAccount['accountId'])
              ?.toString()
              .trim() ??
          '';

      if (resolvedAccountId.isEmpty) {
        throw Exception(
          'MetaApi returned the matching account without an account ID.',
        );
      }

      final region = matchedAccount['region']?.toString().trim() ?? 'new-york';

      final api = MetaApiService(
        token: token.trim(),
        accountId: resolvedAccountId,
        region: region.isEmpty ? 'new-york' : region,
      );

      // Persist the account ID that actually belongs to this token.
      await _storage.saveMetaApiCredentials(
        token: token.trim(),
        accountId: resolvedAccountId,
        region: region.isEmpty ? 'new-york' : region,
      );

      await api.configureCredentials(login: login.trim(), password: password);

      await api.deploy();

      _api = api;

      await api.accountInformation();

      await _storage.saveMt5Connection(
        login: login.trim(),
        server: server.trim(),
      );

      _isConnected = true;
      _connectionError = null;

      await _fetchBotStatus();
      notifyListeners();

      return true;
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
      throw Exception('MT5 is not connected. Connect the account first.');
    }

    _engineError = null;

    final service = FlutterBackgroundService();
    final alreadyRunning = await service.isRunning();

    if (!alreadyRunning) {
      final started = await service.startService();

      if (!started) {
        throw Exception(
          'Pips Miner background trading service could not start.',
        );
      }
    }

    _isBotRunning = true;
    _startUpdates();
    notifyListeners();
  }

  Future<void> stopBot() async {
    final service = FlutterBackgroundService();

    if (await service.isRunning()) {
      service.invoke('stopService');
    }

    _isBotRunning = false;
    _engineError = null;
    _updateTimer?.cancel();

    await Future<void>.delayed(const Duration(milliseconds: 250));

    await _fetchBotStatus();
    notifyListeners();
  }

  void _startUpdates() {
    _updateTimer?.cancel();

    _updateTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      await _fetchBotStatus();
    });
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
        // Reversal price is supplied by the Android background engine
        // through the engineStatus event. Do not reference an out-of-scope
        // event here or overwrite the engine's reversal price.
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

      _isBotRunning = await FlutterBackgroundService().isRunning();
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
    // The Android foreground service owns the trading engine.
    // Closing the dashboard must NOT stop trading.
    _updateTimer?.cancel();
    _engineStatusSubscription?.cancel();
    _engineErrorSubscription?.cancel();
    super.dispose();
  }
}
