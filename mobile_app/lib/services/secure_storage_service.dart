import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _metaApiTokenKey = 'metaapi_api_token';
  static const String _metaApiAccountIdKey = 'metaapi_account_id';
  static const String _metaApiRegionKey = 'metaapi_region';

  static const String _tradingSymbolKey = 'trading_symbol';
  static const String _mt5LoginKey = 'mt5_login';
  static const String _mt5ServerKey = 'mt5_server';

  Future<void> saveMetaApiCredentials({
    required String token,
    required String accountId,
    String? region,
  }) async {
    await _storage.write(key: _metaApiTokenKey, value: token.trim());
    await _storage.write(key: _metaApiAccountIdKey, value: accountId.trim());

    if (region != null && region.trim().isNotEmpty) {
      await _storage.write(key: _metaApiRegionKey, value: region.trim());
    }
  }

  Future<String?> getMetaApiToken() async {
    return _storage.read(key: _metaApiTokenKey);
  }

  Future<String?> getMetaApiAccountId() async {
    return _storage.read(key: _metaApiAccountIdKey);
  }

  Future<String?> getMetaApiRegion() async {
    return _storage.read(key: _metaApiRegionKey);
  }

  Future<bool> hasMetaApiCredentials() async {
    final token = await getMetaApiToken();
    final accountId = await getMetaApiAccountId();

    return token != null &&
        token.trim().isNotEmpty &&
        accountId != null &&
        accountId.trim().isNotEmpty;
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

  Future<void> clearMetaApiCredentials() async {
    await _storage.delete(key: _metaApiTokenKey);
    await _storage.delete(key: _metaApiAccountIdKey);
    await _storage.delete(key: _metaApiRegionKey);
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
