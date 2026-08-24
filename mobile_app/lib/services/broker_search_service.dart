import 'dart:convert';

import 'package:http/http.dart' as http;

class BrokerServerGroup {
  const BrokerServerGroup({required this.broker, required this.servers});

  final String broker;
  final List<String> servers;
}

class BrokerSearchService {
  BrokerSearchService._();

  static final BrokerSearchService instance = BrokerSearchService._();

  static const String _baseUrl = 'https://pips-miner-backend.vercel.app';

  Future<List<BrokerServerGroup>> search(String brokerName) async {
    final query = brokerName.trim();
    if (query.length < 2) {
      throw Exception('Enter at least 2 characters of the broker name.');
    }

    final uri = Uri.parse('$_baseUrl/api/v1/broker-servers').replace(
      queryParameters: <String, String>{'query': query},
    );

    final response = await http.get(
      uri,
      headers: const {'Accept': 'application/json'},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Broker search failed (${response.statusCode}).';
      try {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic> && body['error'] != null) {
          message = body['error'].toString();
        }
      } catch (_) {}
      throw Exception(message);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected broker search response.');
    }

    final raw = decoded['brokers'];
    if (raw is! List) return const <BrokerServerGroup>[];

    return raw.whereType<Map>().map((item) {
      final servers = item['servers'];
      return BrokerServerGroup(
        broker: item['broker']?.toString() ?? 'Unknown broker',
        servers: servers is List
            ? servers.map((server) => server.toString()).toList()
            : const <String>[],
      );
    }).where((group) => group.servers.isNotEmpty).toList();
  }
}
