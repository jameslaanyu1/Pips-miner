import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class MetaApiService {
  MetaApiService({required this.token, required this.accountId});
  final String token;
  final String accountId;
  static const String _base = 'https://pips-miner-backend.vercel.app';
  Map<String, String> get _headers => {'Authorization': 'Bearer ${token.trim()}', 'Accept': 'application/json', 'Content-Type': 'application/json'};
  Uri _uri(String path) => Uri.parse('$_base$path');

  static bool isNetworkFailure(Object error) {
    if (error is TimeoutException) return true;
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') || text.contains('failed host lookup') || text.contains('connection reset') || text.contains('connection refused') || text.contains('connection closed') || text.contains('network is unreachable') || text.contains('clientexception') || text.contains('timed out');
  }

  Future<Map<String, dynamic>> accountInformation() async => _map(await http.get(_uri('/api/v1/account-information'), headers: _headers).timeout(const Duration(seconds: 15)));
  Future<List<dynamic>> positions() async => _list(await http.get(_uri('/api/v1/positions'), headers: _headers).timeout(const Duration(seconds: 15)));
  Future<List<dynamic>> orders() async => _list(await http.get(_uri('/api/v1/orders'), headers: _headers).timeout(const Duration(seconds: 15)));
  Future<Map<String, dynamic>> symbolPrice(String symbol) async => _map(await http.get(_uri('/api/v1/symbols/${Uri.encodeComponent(symbol)}/current-price'), headers: _headers).timeout(const Duration(seconds: 15)));
  Future<Map<String, dynamic>> symbolSpecification(String symbol) async => _map(await http.get(_uri('/api/v1/symbols/${Uri.encodeComponent(symbol)}/specification'), headers: _headers).timeout(const Duration(seconds: 15)));

  Future<List<dynamic>> candles(String symbol, {String timeframe = '1m', int limit = 100}) async {
    final result = _list(await http.get(_uri('/api/v1/symbols/${Uri.encodeComponent(symbol)}/current-candles/${Uri.encodeComponent(timeframe)}'), headers: _headers).timeout(const Duration(seconds: 15)));
    return result.length <= limit ? result : result.sublist(result.length - limit);
  }

  Future<Map<String, dynamic>> streamConfiguration() async => _map(await http.get(_uri('/api/v1/stream-token'), headers: _headers).timeout(const Duration(seconds: 15)));

  Future<String> streamToken() async {
    final body = await streamConfiguration();
    final value = body['token']?.toString().trim() ?? '';
    if (value.isEmpty) throw Exception('Pips-Miner did not return a MetaApi streaming token.');
    return value;
  }

  Future<String> streamUrl() async {
    final body = await streamConfiguration();
    final value = body['streamUrl']?.toString().trim() ?? '';
    if (value.isEmpty) throw Exception('Pips-Miner did not return the MetaApi streaming endpoint.');
    return value;
  }

  Future<Map<String, dynamic>> marketOrder({required String symbol, required double volume, required bool buy, String? clientId, int? magic}) => _trade({'actionType': buy ? 'ORDER_TYPE_BUY' : 'ORDER_TYPE_SELL', 'symbol': symbol, 'volume': volume, if (clientId != null) 'clientId': clientId, if (magic != null) 'magic': magic});
  Future<Map<String, dynamic>> stopOrder({required String symbol, required double volume, required bool buy, required double openPrice, String? clientId, int? magic}) => _trade({'actionType': buy ? 'ORDER_TYPE_BUY_STOP' : 'ORDER_TYPE_SELL_STOP', 'symbol': symbol, 'volume': volume, 'openPrice': openPrice, if (clientId != null) 'clientId': clientId, if (magic != null) 'magic': magic});
  Future<Map<String, dynamic>> modifyOrder({required String orderId, required double openPrice}) => _trade({'actionType': 'ORDER_MODIFY', 'orderId': orderId, 'openPrice': openPrice});
  Future<Map<String, dynamic>> cancelOrder(String orderId) => _trade({'actionType': 'ORDER_CANCEL', 'orderId': orderId});
  Future<Map<String, dynamic>> closePosition(String positionId) => _trade({'actionType': 'POSITION_CLOSE_ID', 'positionId': positionId});
  Future<Map<String, dynamic>> calculateMargin({required String symbol, required double volume, required bool buy, required double openPrice}) async => _map(await http.post(_uri('/api/v1/calculate-margin'), headers: _headers, body: jsonEncode({'symbol': symbol, 'type': buy ? 'ORDER_TYPE_BUY' : 'ORDER_TYPE_SELL', 'volume': volume, 'openPrice': openPrice})).timeout(const Duration(seconds: 15)));
  Future<Map<String, dynamic>> _trade(Map<String, dynamic> body) async => _map(await http.post(_uri('/api/v1/trade'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15)));

  Map<String, dynamic> _map(http.Response response) { _check(response); if (response.body.trim().isEmpty) return <String, dynamic>{}; final decoded = jsonDecode(response.body); if (decoded is Map<String, dynamic>) return decoded; throw Exception('Unexpected Pips-Miner response.'); }
  List<dynamic> _list(http.Response response) { _check(response); if (response.body.trim().isEmpty) return <dynamic>[]; final decoded = jsonDecode(response.body); if (decoded is List) return decoded; if (decoded is Map<String, dynamic> && decoded['items'] is List) return decoded['items'] as List; throw Exception('Unexpected Pips-Miner list response.'); }
  void _check(http.Response response) { if (response.statusCode < 200 || response.statusCode >= 300) { String message = response.body; try { final decoded = jsonDecode(response.body); if (decoded is Map<String, dynamic> && decoded['error'] != null) message = decoded['error'].toString(); } catch (_) {} throw Exception('Pips-Miner HTTP ${response.statusCode}: $message'); } }
}
