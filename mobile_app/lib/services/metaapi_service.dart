import 'dart:convert';
import 'package:http/http.dart' as http;

class MetaApiService {
  MetaApiService({
    required this.token,
    required this.accountId,
    required this.host,
  });

  final String token;
  final String accountId;
  final String host;

  Map<String, String> get _headers => {
        'auth-token': token,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  Uri _uri(String path) {
    final cleanHost = host.replaceFirst(RegExp(r'/$'), '');
    return Uri.parse(
      '$cleanHost/users/current/accounts/$accountId$path',
    );
  }

  Future<Map<String, dynamic>> accountInformation() async {
    final response = await http.get(
      _uri('/account-information'),
      headers: _headers,
    );
    return _map(response);
  }

  Future<List<dynamic>> positions() async {
    final response = await http.get(
      _uri('/positions'),
      headers: _headers,
    );
    return _list(response);
  }

  Future<List<dynamic>> orders() async {
    final response = await http.get(
      _uri('/orders'),
      headers: _headers,
    );
    return _list(response);
  }

  Future<Map<String, dynamic>> symbolPrice(String symbol) async {
    final response = await http.get(
      _uri('/symbols/${Uri.encodeComponent(symbol)}/current-price'),
      headers: _headers,
    );
    return _map(response);
  }

  Future<Map<String, dynamic>> symbolSpecification(String symbol) async {
    final response = await http.get(
      _uri('/symbols/${Uri.encodeComponent(symbol)}/specification'),
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
        '/symbols/${Uri.encodeComponent(symbol)}/current-candles/$timeframe',
      ),
      headers: _headers,
    );
    return _list(response);
  }

  Map<String, dynamic> _map(http.Response response) {
    _check(response);

    final decoded = jsonDecode(response.body);

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    throw Exception('Unexpected MetaApi response');
  }

  List<dynamic> _list(http.Response response) {
    _check(response);

    final decoded = jsonDecode(response.body);

    if (decoded is List) {
      return decoded;
    }

    throw Exception('Unexpected MetaApi list response');
  }

  void _check(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'MetaApi HTTP ${response.statusCode}: ${response.body}',
      );
    }
  }
}
