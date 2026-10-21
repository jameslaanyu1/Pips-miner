import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Direct client for the MetaApi REST API. No Pips-Miner backend is used.
/// The account region is resolved from MetaApi's provisioning API and then
/// cached for the lifetime of this service.
class MetaApiService {
  MetaApiService({required this.token, required this.accountId});

  final String token;
  final String accountId;

  static const String _provisioningBase =
      'https://mt-provisioning-api-v1.agiliumtrade.agiliumtrade.ai';
  String? _region;
  Future<String>? _regionFuture;

  Map<String, String> get _headers => {
        'auth-token': token.trim(),
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

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

  Future<String> _resolveRegion() {
    if (_region != null) return Future.value(_region);
    return _regionFuture ??= _fetchRegion();
  }

  Future<String> _fetchRegion() async {
    final uri = Uri.parse(
      '$_provisioningBase/users/current/accounts/${Uri.encodeComponent(accountId)}',
    );
    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));
    final data = _decodeMap(response, context: 'MetaApi account details');
    final region = data['region']?.toString().trim().toLowerCase() ?? '';
    if (region.isEmpty ||
        !RegExp(r'^[a-z0-9-]+$').hasMatch(region)) {
      throw Exception(
        'MetaApi did not return a valid region for this account. Check the account ID and API token permissions.',
      );
    }
    _region = region;
    return region;
  }

  Future<Uri> _uri(String path, {bool historicalMarketData = false}) async {
    final region = await _resolveRegion();
    final host = historicalMarketData
        ? 'mt-market-data-client-api-v1.$region.agiliumtrade.ai'
        : 'mt-client-api-v1.$region.agiliumtrade.ai';
    return Uri.https(host, '/users/current/accounts/${Uri.encodeComponent(accountId)}$path');
  }

  Future<Map<String, dynamic>> accountInformation() async =>
      _getMap('/account-information');

  Future<List<dynamic>> positions() async => _getList('/positions');

  Future<List<dynamic>> orders() async => _getList('/orders');

  Future<List<String>> symbols() async {
    final result = await _getList('/symbols');
    return result.map((value) => value.toString().trim().toUpperCase())
        .where((value) => value.isNotEmpty).toSet().toList()..sort();
  }

  Future<Map<String, dynamic>> symbolPrice(String symbol) async =>
      _getMap('/symbols/${Uri.encodeComponent(symbol)}/current-price');

  Future<Map<String, dynamic>> symbolSpecification(String symbol) async =>
      _getMap('/symbols/${Uri.encodeComponent(symbol)}/specification');

  Future<List<dynamic>> candles(
    String symbol, {
    String timeframe = '1m',
    int limit = 100,
  }) async {
    final safeLimit = limit.clamp(1, 1000);
    final uri = await _uri(
      '/historical-market-data/symbols/${Uri.encodeComponent(symbol)}/timeframes/${Uri.encodeComponent(timeframe)}/candles',
      historicalMarketData: true,
    );
    final response = await http.get(
      uri.replace(queryParameters: {'limit': '$safeLimit'}),
      headers: _headers,
    ).timeout(const Duration(seconds: 30));
    return _decodeList(response, context: 'MetaApi historical candles');
  }

  Future<String> streamUrl() async {
    final region = await _resolveRegion();
    return 'https://mt-client-api-v1.$region.agiliumtrade.ai';
  }

  Future<Map<String, dynamic>> marketOrder({
    required String symbol,
    required double volume,
    required bool buy,
    String? clientId,
    int? magic,
  }) =>
      _trade({
        'actionType': buy ? 'ORDER_TYPE_BUY' : 'ORDER_TYPE_SELL',
        'symbol': symbol,
        'volume': volume,
        if (clientId != null) 'clientId': clientId,
        if (magic != null) 'magic': magic,
      });

  Future<Map<String, dynamic>> stopOrder({
    required String symbol,
    required double volume,
    required bool buy,
    required double openPrice,
    String? clientId,
    int? magic,
  }) =>
      _trade({
        'actionType': buy ? 'ORDER_TYPE_BUY_STOP' : 'ORDER_TYPE_SELL_STOP',
        'symbol': symbol,
        'volume': volume,
        'openPrice': openPrice,
        if (clientId != null) 'clientId': clientId,
        if (magic != null) 'magic': magic,
      });

  Future<Map<String, dynamic>> modifyOrder({
    required String orderId,
    required double openPrice,
  }) =>
      _trade({
        'actionType': 'ORDER_MODIFY',
        'orderId': orderId,
        'openPrice': openPrice,
      });

  Future<Map<String, dynamic>> cancelOrder(String orderId) =>
      _trade({'actionType': 'ORDER_CANCEL', 'orderId': orderId});

  Future<Map<String, dynamic>> closePosition(String positionId) =>
      _trade({
        'actionType': 'POSITION_CLOSE_ID',
        'positionId': positionId,
      });

  Future<Map<String, dynamic>> calculateMargin({
    required String symbol,
    required double volume,
    required bool buy,
    required double openPrice,
  }) =>
      _postMap('/calculate-margin', {
        'symbol': symbol,
        'type': buy ? 'ORDER_TYPE_BUY' : 'ORDER_TYPE_SELL',
        'volume': volume,
        'openPrice': openPrice,
      });

  Future<Map<String, dynamic>> _trade(Map<String, dynamic> body) =>
      _postMap('/trade', body);

  Future<Map<String, dynamic>> _getMap(String path) async {
    final uri = await _uri(path);
    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));
    return _decodeMap(response, context: 'MetaApi');
  }

  Future<List<dynamic>> _getList(String path) async {
    final uri = await _uri(path);
    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));
    return _decodeList(response, context: 'MetaApi');
  }

  Future<Map<String, dynamic>> _postMap(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = await _uri(path);
    final response = await http
        .post(uri, headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    return _decodeMap(response, context: 'MetaApi');
  }

  Map<String, dynamic> _decodeMap(
    http.Response response, {
    required String context,
  }) {
    _check(response, context: context);
    if (response.body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw Exception('Unexpected $context response.');
  }

  List<dynamic> _decodeList(
    http.Response response, {
    required String context,
  }) {
    _check(response, context: context);
    if (response.body.trim().isEmpty) return <dynamic>[];
    final decoded = jsonDecode(response.body);
    if (decoded is List) return decoded;
    if (decoded is Map<String, dynamic> && decoded['items'] is List) {
      return decoded['items'] as List;
    }
    throw Exception('Unexpected $context list response.');
  }

  void _check(http.Response response, {required String context}) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = response.body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          message = (decoded['message'] ?? decoded['error'] ?? message).toString();
        }
      } catch (_) {}
      throw Exception('$context HTTP ${response.statusCode}: $message');
    }
  }
}
