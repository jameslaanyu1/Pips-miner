import 'dart:convert';
import 'package:http/http.dart' as http;

class MetaApiService {
  MetaApiService({
    required this.sessionToken,
    required this.baseUrl,
  });

  final String sessionToken;
  final String baseUrl;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $sessionToken',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  Uri _uri(String path) {
    final clean = baseUrl.replaceFirst(RegExp(r'/$'), '');
    return Uri.parse('$clean$path');
  }

  Future<Map<String, dynamic>> accountInformation() async {
    final response =
        await http.get(_uri('/api/v1/account-information'), headers: _headers);
    return _map(response);
  }

  Future<List<dynamic>> positions() async {
    final response =
        await http.get(_uri('/api/v1/positions'), headers: _headers);
    return _list(response);
  }

  Future<List<dynamic>> orders() async {
    final response =
        await http.get(_uri('/api/v1/orders'), headers: _headers);
    return _list(response);
  }

  Future<Map<String, dynamic>> symbolPrice(String symbol) async {
    final response = await http.get(
      _uri('/api/v1/symbols/${Uri.encodeComponent(symbol)}/current-price'),
      headers: _headers,
    );
    return _map(response);
  }

  Future<Map<String, dynamic>> symbolSpecification(String symbol) async {
    final response = await http.get(
      _uri('/api/v1/symbols/${Uri.encodeComponent(symbol)}/specification'),
      headers: _headers,
    );
    return _map(response);
  }

  Future<List<dynamic>> candles(
    String symbol, {
    String timeframe = '1m',
  }) async {
    final response = await http.get(
      _uri(
        '/api/v1/symbols/${Uri.encodeComponent(symbol)}/current-candles/$timeframe',
      ),
      headers: _headers,
    );
    return _list(response);
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
    final response = await http.post(
      _uri('/api/v1/calculate-margin'),
      headers: _headers,
      body: jsonEncode({
        'symbol': symbol,
        'type': buy ? 'ORDER_TYPE_BUY' : 'ORDER_TYPE_SELL',
        'volume': volume,
        'openPrice': openPrice,
      }),
    );
    return _map(response);
  }

  Future<Map<String, dynamic>> _trade(Map<String, dynamic> body) async {
    final response = await http.post(
      _uri('/api/v1/trade'),
      headers: _headers,
      body: jsonEncode(body),
    );
    return _map(response);
  }

  Map<String, dynamic> _map(http.Response response) {
    _check(response);
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw Exception('Unexpected Pips-Miner response');
  }

  List<dynamic> _list(http.Response response) {
    _check(response);
    final decoded = jsonDecode(response.body);
    if (decoded is List) return decoded;
    throw Exception('Unexpected Pips-Miner list response');
  }

  void _check(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Pips-Miner HTTP ${response.statusCode}: ${response.body}',
      );
    }
  }
}
