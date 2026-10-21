import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Direct MetaApi REST client. No Pips-Miner/Vercel proxy is required.
/// Use an account-scoped MetaApi token with only the permissions the bot needs.
class MetaApiService {
  MetaApiService({required this.token, required this.accountId});
  final String token;
  final String accountId;
  String? _region;
  Map<String, String> get _headers => {'auth-token': token.trim(), 'Accept': 'application/json', 'Content-Type': 'application/json'};
  Uri _uri(String path) => Uri.parse('${_clientBase()}$path');
  String _clientBase() => 'https://mt-client-api-v1.${_region ?? 'new-york'}.agiliumtrade.ai';

  static bool isNetworkFailure(Object error) {
    if (error is TimeoutException) return true;
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') || text.contains('failed host lookup') || text.contains('connection reset') || text.contains('connection refused') || text.contains('connection closed') || text.contains('network is unreachable') || text.contains('clientexception') || text.contains('timed out');
  }

  Future<void> _ensureRegion() async {
    if (_region != null) return;
    final response = await http.get(
      Uri.parse('https://mt-provisioning-api-v1.agiliumtrade.ai/users/current/accounts/${Uri.encodeComponent(accountId)}'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    _check(response);
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) throw Exception('MetaApi account details response was invalid.');
    final region = data['region']?.toString().trim().toLowerCase();
    if (region == null || !RegExp(r'^[a-z0-9-]+$').hasMatch(region)) {
      throw Exception('MetaApi did not return a valid account region. Check the MetaApi account ID.');
    }
    _region = region;
  }

  Future<Map<String, dynamic>> accountInformation() async { await _ensureRegion(); return _map(await http.get(_uri('/users/current/accounts/$accountId/account-information'), headers: _headers).timeout(const Duration(seconds: 15))); }
  Future<List<dynamic>> positions() async { await _ensureRegion(); return _list(await http.get(_uri('/users/current/accounts/$accountId/positions'), headers: _headers).timeout(const Duration(seconds: 15))); }
  Future<List<dynamic>> orders() async { await _ensureRegion(); return _list(await http.get(_uri('/users/current/accounts/$accountId/orders'), headers: _headers).timeout(const Duration(seconds: 15))); }
  Future<Map<String, dynamic>> symbolPrice(String symbol) async { await _ensureRegion(); return _map(await http.get(_uri('/users/current/accounts/$accountId/symbols/${Uri.encodeComponent(symbol)}/current-price'), headers: _headers).timeout(const Duration(seconds: 15))); }
  Future<Map<String, dynamic>> symbolSpecification(String symbol) async { await _ensureRegion(); return _map(await http.get(_uri('/users/current/accounts/$accountId/symbols/${Uri.encodeComponent(symbol)}/specification'), headers: _headers).timeout(const Duration(seconds: 15))); }

  Future<List<dynamic>> candles(String symbol, {String timeframe = '1m', int limit = 100}) async {
    await _ensureRegion();
    final result = _list(await http.get(_uri('/users/current/accounts/$accountId/symbols/${Uri.encodeComponent(symbol)}/current-candles/${Uri.encodeComponent(timeframe)}'), headers: _headers).timeout(const Duration(seconds: 15)));
    return result.length <= limit ? result : result.sublist(result.length - limit);
  }

  Future<Map<String, dynamic>> streamConfiguration() async {
    await _ensureRegion();
    return {'token': token.trim(), 'streamUrl': _clientBase()};
  }
  Future<String> streamToken() async => token.trim();
  Future<String> streamUrl() async { await _ensureRegion(); return _clientBase(); }

  Future<List<dynamic>> symbols() async {
    await _ensureRegion();
    return _list(await http.get(_uri('/users/current/accounts/$accountId/symbols'), headers: _headers).timeout(const Duration(seconds: 20)));
  }
  Future<Map<String, dynamic>> marketOrder({required String symbol, required double volume, required bool buy, String? clientId, int? magic}) async => _trade({'actionType': buy ? 'ORDER_TYPE_BUY' : 'ORDER_TYPE_SELL', 'symbol': symbol, 'volume': volume, if (clientId != null) 'clientId': clientId, if (magic != null) 'magic': magic});
  Future<Map<String, dynamic>> stopOrder({required String symbol, required double volume, required bool buy, required double openPrice, String? clientId, int? magic}) async => _trade({'actionType': buy ? 'ORDER_TYPE_BUY_STOP' : 'ORDER_TYPE_SELL_STOP', 'symbol': symbol, 'volume': volume, 'openPrice': openPrice, if (clientId != null) 'clientId': clientId, if (magic != null) 'magic': magic});
  Future<Map<String, dynamic>> modifyOrder({required String orderId, required double openPrice}) async => _trade({'actionType': 'ORDER_MODIFY', 'orderId': orderId, 'openPrice': openPrice});
  Future<Map<String, dynamic>> cancelOrder(String orderId) async => _trade({'actionType': 'ORDER_CANCEL', 'orderId': orderId});
  Future<Map<String, dynamic>> closePosition(String positionId) async => _trade({'actionType': 'POSITION_CLOSE_ID', 'positionId': positionId});
  Future<Map<String, dynamic>> calculateMargin({required String symbol, required double volume, required bool buy, required double openPrice}) async {
    await _ensureRegion();
    return _map(await http.post(_uri('/users/current/accounts/$accountId/calculate-margin'), headers: _headers, body: jsonEncode({'symbol': symbol, 'type': buy ? 'ORDER_TYPE_BUY' : 'ORDER_TYPE_SELL', 'volume': volume, 'openPrice': openPrice})).timeout(const Duration(seconds: 15)));
  }
  Future<Map<String, dynamic>> _trade(Map<String, dynamic> body) async {
    await _ensureRegion();
    return _map(await http.post(_uri('/users/current/accounts/$accountId/trade'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 20)));
  }

  Map<String, dynamic> _map(http.Response response) {
    _check(response);
    if (response.body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw Exception('Unexpected MetaApi response.');
  }
  List<dynamic> _list(http.Response response) {
    _check(response);
    if (response.body.trim().isEmpty) return <dynamic>[];
    final decoded = jsonDecode(response.body);
    if (decoded is List) return decoded;
    if (decoded is Map<String, dynamic> && decoded['items'] is List) return decoded['items'] as List;
    throw Exception('Unexpected MetaApi list response.');
  }
  void _check(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = response.body;
      try { final decoded = jsonDecode(response.body); if (decoded is Map<String, dynamic>) message = (decoded['message'] ?? decoded['error'] ?? message).toString(); } catch (_) {}
      throw Exception('MetaApi HTTP ${response.statusCode}: $message');
    }
  }
}
