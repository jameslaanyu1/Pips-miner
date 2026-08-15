import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage();

  static const _sessionTokenKey = 'pipsminer_session_token';
  static const _backendUrlKey = 'pipsminer_backend_url';
  static const _loginKey = 'mt5_login';
  static const _serverKey = 'mt5_server';
  static const _platformKey = 'mt5_platform';

  Future<void> saveConnection({
    required String sessionToken,
    required String backendUrl,
    required String login,
    required String server,
    required String platform,
  }) async {
    await _storage.write(key: _sessionTokenKey, value: sessionToken);
    await _storage.write(key: _backendUrlKey, value: backendUrl);
    await _storage.write(key: _loginKey, value: login);
    await _storage.write(key: _serverKey, value: server);
    await _storage.write(key: _platformKey, value: platform);
  }

  Future<String?> sessionToken() =>
      _storage.read(key: _sessionTokenKey);

  Future<String?> backendUrl() =>
      _storage.read(key: _backendUrlKey);

  Future<String?> login() =>
      _storage.read(key: _loginKey);

  Future<String?> server() =>
      _storage.read(key: _serverKey);

  Future<String?> platform() =>
      _storage.read(key: _platformKey);

  Future<void> clear() async {
    await _storage.delete(key: _sessionTokenKey);
    await _storage.delete(key: _backendUrlKey);
    await _storage.delete(key: _loginKey);
    await _storage.delete(key: _serverKey);
    await _storage.delete(key: _platformKey);
  }
}
