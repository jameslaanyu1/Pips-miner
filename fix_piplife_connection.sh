from pathlib import Path

# ---------- BotProvider ----------
p = Path("mobile_app/lib/providers/bot_provider.dart")
s = p.read_text()

s = s.replace(
"""  bool _isConnected = false;
  String? _currentPosition;""",
"""  bool _isConnected = false;
  String? _connectionError;
  String? _currentPosition;"""
)

s = s.replace(
"""  bool get isConnected => _isConnected;
  String? get currentPosition => _currentPosition;""",
"""  bool get isConnected => _isConnected;
  String? get connectionError => _connectionError;
  String? get currentPosition => _currentPosition;"""
)

s = s.replace(
"""    _isLiveAccount = isLive;
    notifyListeners();""",
"""    _isLiveAccount = isLive;
    _isConnected = false;
    _connectionError = null;
    notifyListeners();"""
)

start = s.index("  Future<void> connect() async {")
end = s.index("\n  Future<void> startBot() async {", start)

new_connect = r"""  Future<void> connect() async {
    _connectionError = null;
    notifyListeners();

    try {
      final token = await _storage.token();
      final accountId = _isLiveAccount
          ? await _storage.liveAccountId()
          : await _storage.demoAccountId();
      final host = await _storage.host();

      if (token == null || token.trim().isEmpty) {
        _isConnected = false;
        _connectionError =
            'MetaAPI token is missing. Open Settings and save your token.';
        notifyListeners();
        return;
      }

      if (accountId == null || accountId.trim().isEmpty) {
        _isConnected = false;
        _connectionError =
            '${accountMode} account ID is missing. Open Settings and save the account ID.';
        notifyListeners();
        return;
      }

      final apiHost = (host == null || host.trim().isEmpty)
          ? 'https://mt-client-api-v1.london.agiliumtrade.ai'
          : host.trim();

      _api = MetaApiService(
        token: token.trim(),
        accountId: accountId.trim(),
        host: apiHost,
      );

      await _api!.accountInformation();

      _isConnected = true;
      _connectionError = null;

      await _fetchBotStatus();
      notifyListeners();
    } catch (e) {
      _isConnected = false;
      _connectionError = _friendlyConnectionError(e);

      debugPrint('MetaApi connection error: $e');
      notifyListeners();
    }
  }

  String _friendlyConnectionError(Object error) {
    final message = error.toString();
    final lower = message.toLowerCase();

    if (lower.contains('http 401') || lower.contains('http 403')) {
      return 'MetaAPI rejected the token. Check the MetaAPI token in Settings.';
    }

    if (lower.contains('http 404')) {
      return 'MetaAPI could not find this account. Check the selected ${accountMode} account ID.';
    }

    if (lower.contains('http 409')) {
      return 'MetaAPI account is not ready. Check that the account is deployed and connected.';
    }

    if (lower.contains('http 429')) {
      return 'MetaAPI rate limit reached. Please wait and reconnect.';
    }

    if (lower.contains('http 5')) {
      return 'MetaAPI server error. Check the internet connection and try again.';
    }

    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup')) {
      return 'Network connection failed. Check the phone internet connection.';
    }

    if (lower.contains('timeout')) {
      return 'MetaAPI connection timed out. Check the internet connection and try again.';
    }

    return 'MetaAPI connection failed. Open Settings and verify the token, account ID and host.';
  }
"""
s = s[:start] + new_connect + s[end:]

p.write_text(s)

# ---------- Home screen ----------
p = Path("mobile_app/lib/screens/home_screen.dart")
s = p.read_text()

needle = """            const AccountSwitcher(),
            const SizedBox(height: 20),

            // Bot Status Card"""

replacement = """            const AccountSwitcher(),
            const SizedBox(height: 12),

            Consumer<BotProvider>(
              builder: (context, botProvider, _) {
                if (botProvider.isConnected ||
                    botProvider.connectionError == null) {
                  return const SizedBox.shrink();
                }

                return Card(
                  color: Colors.red.withOpacity(0.10),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            botProvider.connectionError!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => botProvider.connect(),
                          child: const Text('RETRY'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 20),

            // Bot Status Card"""

if needle not in s:
    raise SystemExit("Home screen insertion point not found")

s = s.replace(needle, replacement)
p.write_text(s)

# ---------- Version ----------
p = Path("mobile_app/pubspec.yaml")
s = p.read_text()
s = s.replace("version: 1.0.0+1", "version: 1.0.0+2")
p.write_text(s)

print("Pip-life MetaApi connection diagnostics applied.")
