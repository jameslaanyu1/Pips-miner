import 'dart:convert';
import 'package:http/http.dart' as http;

class MetaApiService {
  MetaApiService({
    required this.token,
    required this.accountId,
    this.region = 'new-york',
  });

  final String token;
  final String accountId;
  final String region;

  static const String _provisioningBase =
      'https://mt-provisioning-api-v1.agiliumtrade.agiliumtrade.ai';

  String get _clientBase =>
      'https://mt-client-api-v1.$region.agiliumtrade.ai';

  Map<String, String> get _headers => {
        'auth-token': token,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  Uri _provisioning(String path) =>
      Uri.parse('$_provisioningBase$path');

  Uri _client(String path) =>
      Uri.parse('$_clientBase/users/current/accounts/$accountId$path');

  Future<Map<String, dynamic>> account() async {
    final response = await http.get(
      _provisioning('/users/current/accounts/$accountId'),
      headers: _headers,
    );

    return _map(response);
  }

  Future<Map<String, dynamic>> waitUntilReady({
    Duration timeout = const Duration(seconds: 60),
    Duration pollInterval = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    Object? lastError;

    while (DateTime.now().isBefore(deadline)) {
      try {
        final status = await account();
        final state = status['state']?.toString().toUpperCase();

        if (state == 'UNDEPLOYED') {
          throw Exception(
            'MetaApi account is not deployed. Deploy the MT5 account first.',
          );
        }

        if (state == 'DEPLOY_FAILED' ||
            state == 'UNDEPLOY_FAILED' ||
            state == 'REDEPLOY_FAILED') {
          throw Exception(
            'MetaApi account deployment failed (state: $state).',
          );
        }

        if (state == 'DEPLOYED') {
          try {
            // The client API is the authoritative readiness check.
            return await accountInformation();
          } catch (e) {
            lastError = e;
          }
        } else {
          lastError = Exception(
            'MetaApi account is still starting (state: ${state ?? 'UNKNOWN'}).',
          );
        }
      } catch (e) {
        if (e.toString().contains('is not deployed') ||
            e.toString().contains('deployment failed')) {
          rethrow;
        }
        lastError = e;
      }

      await Future<void>.delayed(pollInterval);
    }

    throw Exception(
      'MetaApi account did not become ready within '
      '${timeout.inSeconds} seconds.'
      '${lastError == null ? '' : ' Last error: $lastError'}',
    );
  }

  Future<List<dynamic>> accounts() async {
    final response = await http.get(
      _provisioning('/users/current/accounts'),
      headers: _headers,
    );

    return _list(response);
  }

  Future<Map<String, dynamic>> configureCredentials({
    required String login,
    required String password,
  }) async {
    final response = await http.put(
      _provisioning(
        '/users/current/accounts/$accountId/credentials',
      ),
      headers: _headers,
      body: jsonEncode({
        'login': login.trim(),
        'password': password,
      }),
    );

    return _map(response);
  }

  Future<void> deploy() async {
    final response = await http.post(
      _provisioning(
        '/users/current/accounts/$accountId/deploy',
      ),
      headers: _headers,
    );

    if (response.statusCode != 204 &&
        response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw Exception(
        'MetaApi deployment failed: ${response.body}',
      );
    }
  }

  Future<Map<String, dynamic>> accountInformation() async {
    final response = await http.get(
      _client('/account-information'),
      headers: _headers,
    );

    return _map(response);
  }

  Future<List<dynamic>> positions() async {
    final response = await http.get(
      _client('/positions'),
      headers: _headers,
    );

    return _list(response);
  }

  Future<List<dynamic>> orders() async {
    final response = await http.get(
      _client('/orders'),
      headers: _headers,
    );

    return _list(response);
  }

  Future<Map<String, dynamic>> symbolPrice(String symbol) async {
    final response = await http.get(
      _client(
        '/symbols/${Uri.encodeComponent(symbol)}/current-price',
      ),
      headers: _headers,
    );

    return _map(response);
  }

  Future<Map<String, dynamic>> symbolSpecification(
    String symbol,
  ) async {
    final response = await http.get(
      _client(
        '/symbols/${Uri.encodeComponent(symbol)}/specification',
      ),
      headers: _headers,
    );

    return _map(response);
  }

  Future<List<dynamic>> candles(
    String symbol, {
    String timeframe = '1m',
    int limit = 100,
  }) async {
    // MetaApi current-candles returns ONE candle.
    // The velocity engine needs a rolling M1 history for its
    // 14-candle velocity and volume baselines.
    final marketDataBase =
        'https://mt-market-data-client-api-v1.$region.agiliumtrade.ai';

    final uri = Uri.parse(
      '$marketDataBase/users/current/accounts/$accountId'
      '/historical-market-data/symbols/${Uri.encodeComponent(symbol)}'
      '/timeframes/$timeframe/candles',
    ).replace(
      queryParameters: {
        'limit': limit.toString(),
      },
    );

    final response = await http.get(
      uri,
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
      'actionType': buy
          ? 'ORDER_TYPE_BUY'
          : 'ORDER_TYPE_SELL',
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
      'actionType': buy
          ? 'ORDER_TYPE_BUY_STOP'
          : 'ORDER_TYPE_SELL_STOP',
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

  Future<Map<String, dynamic>> cancelOrder(
    String orderId,
  ) {
    return _trade({
      'actionType': 'ORDER_CANCEL',
      'orderId': orderId,
    });
  }

  Future<Map<String, dynamic>> closePosition(
    String positionId,
  ) {
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
      _client('/calculate-margin'),
      headers: _headers,
      body: jsonEncode({
        'symbol': symbol,
        'type': buy
            ? 'ORDER_TYPE_BUY'
            : 'ORDER_TYPE_SELL',
        'volume': volume,
        'openPrice': openPrice,
      }),
    );

    return _map(response);
  }

  Future<Map<String, dynamic>> _trade(
    Map<String, dynamic> body,
  ) async {
    final response = await http.post(
      _client('/trade'),
      headers: _headers,
      body: jsonEncode(body),
    );

    return _map(response);
  }

  Map<String, dynamic> _map(http.Response response) {
    _check(response);

    final decoded = jsonDecode(response.body);

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    throw Exception(
      'Unexpected MetaApi response',
    );
  }

  List<dynamic> _list(http.Response response) {
    _check(response);

    final decoded = jsonDecode(response.body);

    if (decoded is List) {
      return decoded;
    }

    // MetaApi provisioning may return a paginated object:
    // {"count": ..., "items": [...]}
    if (decoded is Map<String, dynamic>) {
      final items = decoded['items'];
      if (items is List) {
        return items;
      }
    }

    throw Exception(
      'Unexpected MetaApi list response',
    );
  }

  void _check(http.Response response) {
    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw Exception(
        'MetaApi HTTP ${response.statusCode}: ${response.body}',
      );
    }
  }
}
