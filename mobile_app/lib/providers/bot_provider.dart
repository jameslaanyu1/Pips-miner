import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class BotProvider extends ChangeNotifier {
  bool _isLiveAccount = false;
  String? _symbol = 'XAUUSD';
  double? _volume = 0.01;

  bool _isBotRunning = false;
  bool _isConnected = false;
  String? _currentPosition;
  double? _entryPrice;
  double? _stopPrice;

  int _totalTrades = 0;
  double _winRate = 0.0;
  double _profitLoss = 0.0;
  double _balance = 10000.0;
  double _priceChange = 0.0;

  late String _apiUrl;
  Timer? _updateTimer;

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
  String? get symbol => _symbol;
  double? get volume => _volume;

  String get accountMode => _isLiveAccount ? 'LIVE' : 'DEMO';

  BotProvider() {
    // Android emulator -> host computer
    // Change to your computer's LAN IP for a physical Android phone.
    _apiUrl = 'http://10.0.2.2:5000/api';
  }

  void setAccountMode(bool isLive) {
    if (_isBotRunning) return;

    _isLiveAccount = isLive;
    notifyListeners();
  }

  void updateSettings({
    String? symbol,
    double? volume,
  }) {
    if (symbol != null && symbol.trim().isNotEmpty) {
      _symbol = symbol.toUpperCase();
    }

    if (volume != null && volume > 0) {
      _volume = volume;
    }

    notifyListeners();
  }

  Future<void> connect() async {
    try {
      final response = await http
          .get(Uri.parse('$_apiUrl/health'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        _isConnected = true;

        final data = jsonDecode(response.body);

        if (data['mode'] == 'LIVE') {
          _isLiveAccount = true;
        } else {
          _isLiveAccount = false;
        }

        if (data['symbol'] != null) {
          _symbol = data['symbol'];
        }

        _isBotRunning = data['bot_running'] == true;

        notifyListeners();
      } else {
        _isConnected = false;
        notifyListeners();
      }
    } catch (e) {
      _isConnected = false;
      debugPrint('Connection error: $e');
      notifyListeners();
    }
  }

  Future<void> startBot() async {
    try {
      if (!_isConnected) {
        await connect();
      }

      if (!_isConnected) {
        throw Exception('Backend is not connected');
      }

      final configResponse = await http
          .post(
            Uri.parse('$_apiUrl/config'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'mode': accountMode,
              'symbol': _symbol,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (configResponse.statusCode != 200) {
        final data = jsonDecode(configResponse.body);
        throw Exception(data['error'] ?? 'Failed to configure bot');
      }

      final startResponse = await http
          .post(Uri.parse('$_apiUrl/bot/start'))
          .timeout(const Duration(seconds: 10));

      if (startResponse.statusCode != 200) {
        final data = jsonDecode(startResponse.body);
        throw Exception(data['error'] ?? 'Failed to start bot');
      }

      _isBotRunning = true;
      _startUpdates();
      notifyListeners();
    } catch (e) {
      debugPrint('Error starting bot: $e');
      rethrow;
    }
  }

  Future<void> stopBot() async {
    try {
      final response = await http
          .post(Uri.parse('$_apiUrl/bot/stop'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _isBotRunning = false;
        _updateTimer?.cancel();
        notifyListeners();
      } else {
        final data = jsonDecode(response.body);
        throw Exception(data['error'] ?? 'Failed to stop bot');
      }
    } catch (e) {
      debugPrint('Error stopping bot: $e');
      rethrow;
    }
  }

  void _startUpdates() {
    _updateTimer?.cancel();

    _updateTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) async {
        await _fetchBotStatus();
      },
    );
  }

  Future<void> _fetchBotStatus() async {
    try {
      final response = await http
          .get(Uri.parse('$_apiUrl/bot/status'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        _isBotRunning = data['running'] == true;
        _currentPosition = data['position'];
        _entryPrice = data['entry_price']?.toDouble();
        _stopPrice = data['stop_price']?.toDouble();
        _totalTrades = data['trade_count'] ?? 0;

        if (data['mode'] == 'LIVE') {
          _isLiveAccount = true;
        } else {
          _isLiveAccount = false;
        }

        if (data['symbol'] != null) {
          _symbol = data['symbol'];
        }

        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching status: $e');
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }
}
