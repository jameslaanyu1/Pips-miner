import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _pipsMinerSessionTokenKey = 'pips_miner_session_token';
  static const String _pipsMinerAccountIdKey = 'pips_miner_account_id';

  static const String _tradingSymbolKey = 'trading_symbol';
  static const String _brokerSymbolMapKey = 'broker_symbol_map';
  static const String _mt5BrokerKey = 'mt5_broker';
  static const String _mt5LoginKey = 'mt5_login';
  static const String _mt5ServerKey = 'mt5_server';
  static const String _mt5PasswordKey = 'mt5_password';

  Future<void> savePipsMinerSession({
    required String sessionToken,
    required String accountId,
  }) async {
    await _storage.write(key: _pipsMinerSessionTokenKey, value: sessionToken.trim());
    await _storage.write(key: _pipsMinerAccountIdKey, value: accountId.trim());
  }

  Future<String?> getPipsMinerSessionToken() async => _storage.read(key: _pipsMinerSessionTokenKey);

  Future<String?> getPipsMinerAccountId() async => _storage.read(key: _pipsMinerAccountIdKey);

  Future<bool> hasPipsMinerSession() async {
    final token = await getPipsMinerSessionToken();
    final accountId = await getPipsMinerAccountId();
    return token != null && token.trim().isNotEmpty && accountId != null && accountId.trim().isNotEmpty;
  }

  Future<void> clearPipsMinerSession() async {
    await _storage.delete(key: _pipsMinerSessionTokenKey);
    await _storage.delete(key: _pipsMinerAccountIdKey);
  }

  Future<void> saveTradingSymbol(String symbol) async {
    final normalized = symbol.trim().toUpperCase();
    if (normalized.isEmpty) return;
    await _storage.write(key: _tradingSymbolKey, value: normalized);
  }

  Future<String?> getTradingSymbol() async => _storage.read(key: _tradingSymbolKey);

  Future<void> saveBrokerTradingSymbol({
    required String broker,
    required String server,
    required String symbol,
  }) async {
    final normalizedSymbol = symbol.trim().toUpperCase();
    final key = _brokerSymbolKey(broker, server);
    if (normalizedSymbol.isEmpty || key.isEmpty) return;

    final raw = await _storage.read(key: _brokerSymbolMapKey);
    Map<String, dynamic> mappings = <String, dynamic>{};
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) mappings = decoded;
      } catch (_) {}
    }
    mappings[key] = normalizedSymbol;
    await _storage.write(key: _brokerSymbolMapKey, value: jsonEncode(mappings));
    await saveTradingSymbol(normalizedSymbol);
  }

  Future<String?> getBrokerTradingSymbol({
    required String broker,
    required String server,
  }) async {
    final key = _brokerSymbolKey(broker, server);
    if (key.isEmpty) return null;
    final raw = await _storage.read(key: _brokerSymbolMapKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final value = decoded[key]?.toString().trim();
        if (value != null && value.isNotEmpty) return value.toUpperCase();
      }
    } catch (_) {}
    return null;
  }

  String _brokerSymbolKey(String broker, String server) {
    final normalizedBroker = broker.trim().toLowerCase();
    final normalizedServer = server.trim().toLowerCase();
    if (normalizedBroker.isEmpty && normalizedServer.isEmpty) return '';
    return '$normalizedBroker|$normalizedServer';
  }

  Future<void> saveMt5Connection({
    required String login,
    required String server,
    String broker = '',
    String password = '',
  }) async {
    await _storage.write(key: _mt5BrokerKey, value: broker.trim());
    await _storage.write(key: _mt5LoginKey, value: login.trim());
    await _storage.write(key: _mt5ServerKey, value: server.trim());
    await _storage.write(key: _mt5PasswordKey, value: password);
  }

  Future<String?> getMt5Broker() async => _storage.read(key: _mt5BrokerKey);

  Future<String?> getMt5Login() async => _storage.read(key: _mt5LoginKey);

  Future<String?> getMt5Server() async => _storage.read(key: _mt5ServerKey);

  Future<String?> getMt5Password() async => _storage.read(key: _mt5PasswordKey);

  Future<void> clearMt5Connection() async {
    await _storage.delete(key: _mt5BrokerKey);
    await _storage.delete(key: _mt5LoginKey);
    await _storage.delete(key: _mt5ServerKey);
    await _storage.delete(key: _mt5PasswordKey);
  }

  Future<void> clearAll() async => _storage.deleteAll();
}
