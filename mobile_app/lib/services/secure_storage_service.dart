import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage();

  static const _tokenKey = 'metaapi_token';
  static const _demoAccountIdKey = 'metaapi_demo_account_id';
  static const _liveAccountIdKey = 'metaapi_live_account_id';
  static const _hostKey = 'metaapi_host';

  Future<void> saveCredentials({
    required String token,
    required String demoAccountId,
    required String liveAccountId,
    required String host,
  }) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _demoAccountIdKey, value: demoAccountId);
    await _storage.write(key: _liveAccountIdKey, value: liveAccountId);
    await _storage.write(key: _hostKey, value: host);
  }

  Future<String?> token() => _storage.read(key: _tokenKey);
  Future<String?> demoAccountId() => _storage.read(key: _demoAccountIdKey);
  Future<String?> liveAccountId() => _storage.read(key: _liveAccountIdKey);
  Future<String?> host() => _storage.read(key: _hostKey);

  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _demoAccountIdKey);
    await _storage.delete(key: _liveAccountIdKey);
    await _storage.delete(key: _hostKey);
  }
}
