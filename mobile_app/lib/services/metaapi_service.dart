import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class MetaApiService {
  MetaApiService({
    required this.token,
    required this.accountId,
  });

  /// This is the Pips-Miner session token returned by /api/v1/connect.
  /// It is NOT the MetaApi master token.
  final String token;

  /// Kept for compatibility with the existing BotProvider/engine API.
  /// The backend obtains the account ID from the authenticated session.
  final String accountId;

  static const String _base = 'https://pips-miner-backend.vercel.app';

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${token.trim()}',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  Uri _uri(String path) => Uri.parse('$_base$path');

  /// Network failures are the only failures that should force the trading
  /// service into its emergency cleanup/shutdown path.
  static bool isNetworkFailure(Object error) {
    if (error is TimeoutException) return true;

    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('connection reset') ||
        text.contains('connection refused') ||
        text.contains('connection closed') ||
        text.contains('network is unreachable') ||
        text.contains('clientexception') ||
        text.contains('timed out');
  }

  Future<Map<String, dynamic>> accountInformation() async {
    final response = await http
        .get(_uri('/api/v1/account-information'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    return _map(response);
  }

  Future<List<dynamic>> positions() async {
    final response = await http
        .get(_uri('/api/v1/positions'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    return _list(response);
  }

  Future<List<dynamic>> orders() async {
    final response = await http
        .get(_uri('/api/v1/orders'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    return _list(response);
  }

  Future<Map<String, dynamic>> symbolPrice(String symbol) async {
    final response = await http
        .get(
          _uri('/api/v1/symbols/${Uri.encodeComponent(symbol)}/current-price'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 15));
    return _map(response);
  }

  Future<Map<String, dynamic>> symbolSpecification(String symbol) async {
    final response = await http
        .get(
          _uri('/api/v1/symbols/${Uri.encodeComponent(symbol)}/specification'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 15));
    return _map(response);
  }

  Future<List<dynamic>> candles(
    String symbol, {
    String timeframe = '1m',
    int limit = 100,
  }) async {
    final response = await http
        .get(
          _uri(
            '/api/v1/symbols/${Uri.encodeComponent(symbol)}/current-candles/'
            '${Uri.encodeComponent(timeframe)}',
          ),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 15));

    final result = _list(response);
    if (result.length <= limit) return result;
    return result.sublist(result.length - limit);
  }

  Future<Map<String, dynamic>> marketOrder({
    required String symbol,
    required double volume,
    required bool buy,
    String? clientId,
    int? magic,
  }) {
    return _trade({
      'actionType': buy ? 'ORDER_TYPE_BUY' : 'ORDER_TYPE_SELL',
      'symbol': symbol,
      'volume': volume,
      if (clientId != null) 'clientId': clientId,
      if (magic != null) 'magic': magic,
    });
  }

  Future<Map<String, dynamic>> stopOrder({
    required String symbol,
    required double volume,
    required bool buy,
    required double openPrice,
    String? clientId,
    int? magic,
  }) {
    return _trade({
      'actionType': buy ? 'ORDER_TYPE_BUY_STOP' : 'ORDER_TYPE_SELL_STOP',
      'symbol': symbol,
      'volume': volume,
      'openPrice': openPrice,
      if (clientId != null) 'clientId': clientId,
      if (magic != null) 'magic': magic,
    });
  }

  Future<Map<String, dynamic>> modifyOrder({
    required String orderId,
    required double openPrice,
  }) {
    return _trade({
      'actionType': 'ORDER_MODIFY',
      'orderId': orderId,
      'openPrice': openPrice,
    });
  }

  Future<Map<String, dynamic>> cancelOrder(String orderId) {
    return _trade({
      'actionType': 'ORDER_CANCEL',
      'orderId': orderId,
    });
  }

  Future<Map<String, dynamic>> closePosition(String positionId) {
    return _trade({
      'actionType': 'POSITION_CLOSE_ID',
      'positionId': positionId,
    });
  }

  Future<Map<String, dynamic>> calculateMargin({
    required String symbol,
    required double volume,
    required bool buy,
    required double openPrice,
  }) async {
    final response = await http
        .post(
          _uri('/api/v1/calculate-margin'),
          headers: _headers,
          body: jsonEncode({
            'symbol': symbol,
            'type': buy ? 'ORDER_TYPE_BUY' : 'ORDER_TYPE_SELL',
            'volume': volume,
            'openPrice': openPrice,
          }),
        )
        .timeout(const Duration(seconds: 15));
    return _map(response);
  }

  Future<Map<String, dynamic>> _trade(Map<String, dynamic> body) async {
    final response = await http
        .post(
          _uri('/api/v1/trade'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    return _map(response);
  }

  Map<String, dynamic> _map(http.Response response) {
    _check(response);
    if (response.body.trim().isEmpty) return <String, dynamic>{};

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;

    throw Exception('Unexpected Pips-Miner response.');
  }

  List<dynamic> _list(http.Response response) {
    _check(response);
    if (response.body.trim().isEmpty) return <dynamic>[];

    final decoded = jsonDecode(response.body);
    if (decoded is List) return decoded;

    if (decoded is Map<String, dynamic>) {
      final items = decoded['items'];
      if (items is List) return items;
    }

    throw Exception('Unexpected Pips-Miner list response.');
  }

  void _check(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = response.body;

      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['error'] != null) {
          message = decoded['error'].toString();
        }
      } catch (_) {}

      throw Exception('Pips-Miner HTTP ${response.statusCode}: $message');
    }
  }
}
