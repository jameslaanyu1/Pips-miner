import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage();

  static const _tokenKey = 'metaapi_token';
  static const _accountIdKey = 'metaapi_account_id';
  static const _hostKey = 'metaapi_host';

  Future<void> saveCredentials({
    required String token,
    required String accountId,
    required String host,
  }) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _accountIdKey, value: accountId);
    await _storage.write(key: _hostKey, value: host);
  }

  Future<String?> token() => _storage.read(key: _tokenKey);
  Future<String?> accountId() => _storage.read(key: _accountIdKey);
  Future<String?> host() => _storage.read(key: _hostKey);

  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _accountIdKey);
    await _storage.delete(key: _hostKey);
  }
}
