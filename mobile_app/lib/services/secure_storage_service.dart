import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _pipsMinerSessionTokenKey = 'pips_miner_session_token';
  static const String _pipsMinerAccountIdKey = 'pips_miner_account_id';

  static const String _tradingSymbolKey = 'trading_symbol';
  static const String _mt5LoginKey = 'mt5_login';
  static const String _mt5ServerKey = 'mt5_server';

  Future<void> savePipsMinerSession({
    required String sessionToken,
    required String accountId,
  }) async {
    await _storage.write(
      key: _pipsMinerSessionTokenKey,
      value: sessionToken.trim(),
    );
    await _storage.write(
      key: _pipsMinerAccountIdKey,
      value: accountId.trim(),
    );
  }

  Future<String?> getPipsMinerSessionToken() async {
    return _storage.read(key: _pipsMinerSessionTokenKey);
  }

  Future<String?> getPipsMinerAccountId() async {
    return _storage.read(key: _pipsMinerAccountIdKey);
  }

  Future<bool> hasPipsMinerSession() async {
    final token = await getPipsMinerSessionToken();
    final accountId = await getPipsMinerAccountId();

    return token != null &&
        token.trim().isNotEmpty &&
        accountId != null &&
        accountId.trim().isNotEmpty;
  }

  Future<void> clearPipsMinerSession() async {
    await _storage.delete(key: _pipsMinerSessionTokenKey);
    await _storage.delete(key: _pipsMinerAccountIdKey);
  }

  Future<void> saveTradingSymbol(String symbol) async {
    await _storage.write(
      key: _tradingSymbolKey,
      value: symbol.trim().toUpperCase(),
    );
  }

  Future<String?> getTradingSymbol() async {
    return _storage.read(key: _tradingSymbolKey);
  }

  Future<void> saveMt5Connection({
    required String login,
    required String server,
  }) async {
    await _storage.write(key: _mt5LoginKey, value: login.trim());

    await _storage.write(key: _mt5ServerKey, value: server.trim());
  }

  Future<String?> getMt5Login() async {
    return _storage.read(key: _mt5LoginKey);
  }

  Future<String?> getMt5Server() async {
    return _storage.read(key: _mt5ServerKey);
  }

  Future<void> clearMt5Connection() async {
    await _storage.delete(key: _mt5LoginKey);
    await _storage.delete(key: _mt5ServerKey);
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
