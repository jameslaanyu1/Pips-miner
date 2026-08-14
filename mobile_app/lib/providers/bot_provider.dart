import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class BotProvider extends ChangeNotifier {
  // Account settings
  bool _isLiveAccount = false;
  String? _apiToken;
  String? _demoAccountId;
  String? _liveAccountId;
  String? _symbol = 'EURUSD';
  double? _volume = 0.01;

  // Bot status
  bool _isBotRunning = false;
  bool _isConnected = false;
  String? _currentPosition;
  double? _entryPrice;
  double? _stopPrice;

  // Trading metrics
  int _totalTrades = 0;
  double _winRate = 0.0;
  double _profitLoss = 0.0;
  double _balance = 10000.0;
  double _priceChange = 0.0;

  // WebSocket
  late String _apiUrl;
  Timer? _updateTimer;

  // Getters
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

  BotProvider() {
    _apiUrl = 'http://localhost:5000/api';
  }

  // Set account mode (Demo/Live)
  void setAccountMode(bool isLive) {
    _isLiveAccount = isLive;
    notifyListeners();
  }

  // Update settings
  void updateSettings({
    required String apiToken,
    required String demoAccountId,
    required String liveAccountId,
    required String symbol,
    required double volume,
  }) {
    _apiToken = apiToken;
    _demoAccountId = demoAccountId;
    _liveAccountId = liveAccountId;
    _symbol = symbol;
    _volume = volume;
    notifyListeners();
  }

  // Connect to backend
  Future<void> connect() async {
    try {
      final response = await http.get(
        Uri.parse('$_apiUrl/health'),
      );
      if (response.statusCode == 200) {
        _isConnected = true;
        notifyListeners();
      }
    } catch (e) {
      _isConnected = false;
      print('Connection error: $e');
    }
  }

  // Start bot
  Future<void> startBot() async {
    try {
      final accountId =
          _isLiveAccount ? _liveAccountId : _demoAccountId;

      if (accountId == null || _apiToken == null) {
        throw Exception('Account credentials not configured');
      }

      // Configure bot
      final configResponse = await http.post(
        Uri.parse('$_apiUrl/config'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'account_id': accountId,
          'api_token': _apiToken,
          'symbol': _symbol,
        }),
      );

      if (configResponse.statusCode != 200) {
        throw Exception('Failed to configure bot');
      }

      // Start bot
      final startResponse = await http.post(
        Uri.parse('$_apiUrl/bot/start'),
      );

      if (startResponse.statusCode == 200) {
        _isBotRunning = true;
        _startUpdates();
        notifyListeners();
      }
    } catch (e) {
      print('Error starting bot: $e');
    }
  }

  // Stop bot
  Future<void> stopBot() async {
    try {
      final response = await http.post(
        Uri.parse('$_apiUrl/bot/stop'),
      );

      if (response.statusCode == 200) {
        _isBotRunning = false;
        _updateTimer?.cancel();
        notifyListeners();
      }
    } catch (e) {
      print('Error stopping bot: $e');
    }
  }

  // Start periodic updates
  void _startUpdates() {
    _updateTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _fetchBotStatus();
    });
  }

  // Fetch bot status
  Future<void> _fetchBotStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$_apiUrl/bot/status'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _currentPosition = data['position'];
        _entryPrice = data['entry_price']?.toDouble();
        _stopPrice = data['stop_price']?.toDouble();
        _totalTrades = data['trade_count'] ?? 0;
        notifyListeners();
      }
    } catch (e) {
      print('Error fetching status: $e');
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }
}
