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
    unawaited(_loadSavedSymbol());
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

  Future<void> _loadSavedSymbol() async {
    final saved = await _storage.getTradingSymbol();
    final normalized = saved?.trim().toUpperCase();
    if (normalized == null || normalized.isEmpty) return;

    _symbol = normalized;
    notifyListeners();
  }

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
      final sessionToken = await _storage.getPipsMinerSessionToken();
      final accountId = await _storage.getPipsMinerAccountId();

      if (sessionToken == null || sessionToken.trim().isEmpty || accountId == null || accountId.trim().isEmpty) {
        _isConnected = false;
        _connectionError = 'MT5 account is not connected. Connect the account first.';
        notifyListeners();
        return;
      }

      _api = MetaApiService(token: sessionToken.trim(), accountId: accountId.trim());
      final info = await _api!.accountInformation();

      _isConnected = true;
      _connectionError = null;
      _balance = _number(info['balance']) ?? _balance;

      await _fetchBotStatus();
      notifyListeners();
    } catch (e) {
      _isConnected = false;
      _connectionError = _friendlyConnectionError(e);
      debugPrint('Pips-Miner connection error: $e');
      notifyListeners();
    }
  }

  Future<bool> connectMt5({required String login, required String password, required String server}) async {
    _connectionError = null;
    notifyListeners();

    try {
      final requestedLogin = login.trim();
      final requestedPassword = password;
      final requestedServer = server.trim();

      if (requestedLogin.isEmpty || requestedPassword.isEmpty || requestedServer.isEmpty) {
        throw Exception('MT5 login, password and broker server are required.');
      }

      final response = await http.post(
        Uri.parse('https://pips-miner-backend.vercel.app/api/v1/connect'),
        headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: jsonEncode({'login': requestedLogin, 'password': requestedPassword, 'server': requestedServer, 'platform': 'mt5'}),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        String message = response.body;
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic> && decoded['error'] != null) message = decoded['error'].toString();
        } catch (_) {}
        throw Exception(message);
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw Exception('Invalid Pips-Miner connection response.');

      final sessionToken = decoded['sessionToken']?.toString().trim() ?? '';
      final accountId = decoded['accountId']?.toString().trim() ?? '';
      if (sessionToken.isEmpty || accountId.isEmpty) throw Exception('Pips-Miner did not return a valid trading session.');

      await _storage.savePipsMinerSession(sessionToken: sessionToken, accountId: accountId);
      await _storage.saveMt5Connection(login: requestedLogin, server: requestedServer);

      _api = MetaApiService(token: sessionToken, accountId: accountId);
      final info = await _api!.accountInformation();

      _isConnected = true;
      _connectionError = null;
      _balance = _number(info['balance']) ?? _balance;

      await _fetchBotStatus();
      notifyListeners();
      return true;
    } catch (e) {
      _isConnected = false;
      _connectionError = _friendlyConnectionError(e);
      notifyListeners();
      return false;
    }
  }

  String _friendlyConnectionError(Object error) {
    final message = error.toString();
    final lower = message.toLowerCase();
    if (lower.contains('401') || lower.contains('403')) return 'Pips-Miner authentication failed. Connect the MT5 account again.';
    if (lower.contains('404')) return 'The Pips-Miner backend could not find this account.';
    if (lower.contains('429')) return 'Too many requests. Please wait and reconnect.';
    if (lower.contains('socketexception') || lower.contains('failed host lookup')) return 'Network connection failed. Check the phone internet connection.';
    if (lower.contains('timeout')) return 'Connection timed out. Check the internet connection and try again.';
    return 'Pips-Miner connection failed: $message';
  }

  Future<void> startBot() async {
    if (!_isConnected || _api == null) await connect();
    if (!_isConnected || _api == null) throw Exception('MT5 is not connected. Connect the account first.');

    _engineError = null;
    await _api!.waitUntilReady();

    final service = FlutterBackgroundService();
    final alreadyRunning = await service.isRunning();
    if (!alreadyRunning) {
      final started = await service.startService();
      if (!started) throw Exception('Pips Miner background trading service could not start.');
    }

    _isBotRunning = true;
    _startUpdates();
    notifyListeners();
  }

  Future<void> stopBot() async {
    _engineError = null;
    _updateTimer?.cancel();

    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke('stopService');
      for (int attempt = 0; attempt < 30; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (!await service.isRunning()) break;
      }
    }

    if (_api == null) await connect();
    final api = _api;

    if (api == null || !_isConnected) {
      _isBotRunning = false;
      _engineError = 'Miner stopped, but the server session is unavailable to verify or close account orders.';
      notifyListeners();
      return;
    }

    try {
      await _liquidateAccount(api);
      _isBotRunning = false;
      _engineError = null;
      await _fetchBotStatus();
    } catch (e) {
      _isBotRunning = false;
      _engineError = 'Miner stopped, but account cleanup was incomplete: $e';
    }
    notifyListeners();
  }

  Future<void> _liquidateAccount(MetaApiService api) async {
    Object? lastError;
    for (int attempt = 0; attempt < 3; attempt++) {
      final positions = await api.positions();
      final orders = await api.orders();

      for (final raw in positions) {
        if (raw is! Map) continue;
        final position = Map<String, dynamic>.from(raw);
        final id = position['id']?.toString();
        if (id == null || id.isEmpty) continue;
        try { await api.closePosition(id); } catch (e) { lastError = e; }
      }

      for (final raw in orders) {
        if (raw is! Map) continue;
        final order = Map<String, dynamic>.from(raw);
        final id = order['id']?.toString();
        if (id == null || id.isEmpty) continue;
        try { await api.cancelOrder(id); } catch (e) { lastError = e; }
      }

      await Future<void>.delayed(const Duration(milliseconds: 500));
      final remainingPositions = await api.positions();
      final remainingOrders = await api.orders();
      if (remainingPositions.isEmpty && remainingOrders.isEmpty) return;
    }

    final remainingPositions = await api.positions();
    final remainingOrders = await api.orders();
    if (remainingPositions.isNotEmpty || remainingOrders.isNotEmpty) {
      throw Exception('remaining positions=${remainingPositions.length}, pending orders=${remainingOrders.length}${lastError == null ? '' : '; last error: $lastError'}');
    }
  }

  void _startUpdates() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (_) async { await _fetchBotStatus(); });
  }

  Future<void> _fetchBotStatus() async {
    try {
      final api = _api;
      if (api == null) return;

      final positions = await api.positions();
      final strategy = positions.whereType<Map>().map((p) => Map<String, dynamic>.from(p)).where((p) => p['symbol']?.toString() == _symbol).toList();

      if (strategy.isNotEmpty) {
        final p = strategy.first;
        final type = p['type']?.toString() ?? '';
        _currentPosition = type.contains('SELL') ? 'SELL' : 'BUY';
        _entryPrice = _number(p['openPrice']);
      } else {
        _currentPosition = null;
        _entryPrice = null;
        _stopPrice = null;
      }

      final info = await api.accountInformation();
      _balance = _number(info['balance']) ?? _balance;
      final equity = _number(info['equity']);
      if (equity != null) _profitLoss = equity - _balance;
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
    _updateTimer?.cancel();
    _engineStatusSubscription?.cancel();
    _engineErrorSubscription?.cancel();
    super.dispose();
  }
}
