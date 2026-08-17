import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pips_miner_app/providers/bot_provider.dart';
import 'package:pips_miner_app/services/secure_storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SecureStorageService _storage = SecureStorageService();

  late final TextEditingController _loginController;
  late final TextEditingController _serverController;
  late final TextEditingController _passwordController;
  late final TextEditingController _symbolController;

  @override
  void initState() {
    super.initState();

    _loginController = TextEditingController();
    _serverController = TextEditingController();
    _passwordController = TextEditingController();
    _symbolController = TextEditingController(text: 'XAUUSD');

    _loadConnection();
  }

  @override
  void dispose() {
    _loginController.dispose();
    _serverController.dispose();
    _passwordController.dispose();
    _symbolController.dispose();
    super.dispose();
  }

  Future<void> _loadConnection() async {
    final login = await _storage.getMt5Login();
    final server = await _storage.getMt5Server();
    if (!mounted) return;

    setState(() {
      _loginController.text = login ?? '';
      _serverController.text = server ?? '';
    });
  }

  Future<void> _setupMetaApi() async {
    final tokenController = TextEditingController();
    final accountIdController = TextEditingController();

    final existingToken = await _storage.getMetaApiToken();
    final existingAccountId = await _storage.getMetaApiAccountId();

    if (existingToken != null) {
      tokenController.text = existingToken;
    }
    if (existingAccountId != null) {
      accountIdController.text = existingAccountId;
    }

    if (!mounted) {
      tokenController.dispose();
      accountIdController.dispose();
      return;
    }

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('MetaApi Setup'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter the MetaApi credentials assigned to this app. '
                  'They are stored securely on this device and will not '
                  'be requested again unless cleared.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: tokenController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'MetaApi API Token',
                    prefixIcon: Icon(Icons.key),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: accountIdController,
                  decoration: const InputDecoration(
                    labelText: 'MetaApi Account ID',
                    prefixIcon: Icon(Icons.account_circle),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () async {
                final token = tokenController.text.trim();
                final accountId = accountIdController.text.trim();

                if (token.isEmpty || accountId.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Enter both the MetaApi API token and account ID.',
                      ),
                    ),
                  );
                  return;
                }

                await _storage.saveMetaApiCredentials(
                  token: token,
                  accountId: accountId,
                );

                if (context.mounted) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('SAVE'),
            ),
          ],
        );
      },
    );

    tokenController.dispose();
    accountIdController.dispose();

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('MetaApi credentials stored securely on this device.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _connect(BotProvider bot) async {
    final login = _loginController.text.trim();
    final password = _passwordController.text;
    final server = _serverController.text.trim();

    if (login.isEmpty ||
        password.isEmpty ||
        server.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter your MT5 account number, broker server and trading password.',
          ),
        ),
      );
      return;
    }

    final success = await bot.connectMt5(
      login: login,
      password: password,
      server: server,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'MT5 account connected successfully.'
              : bot.connectionError ?? 'MT5 connection failed.',
        ),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pips-Miner Settings'),
        elevation: 0,
      ),
      body: Consumer<BotProvider>(
        builder: (context, bot, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'MT5 Account',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Enter your MT5 broker details. Pips-Miner connects directly to your MetaApi account.',
                        ),
                        const SizedBox(height: 16),

                        TextField(
                          controller: _loginController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'MT5 Account Number',
                            prefixIcon: Icon(Icons.account_balance),
                          ),
                        ),

                        const SizedBox(height: 12),

                        TextField(
                          controller: _serverController,
                          decoration: const InputDecoration(
                            labelText: 'Broker Server',
                            hintText: 'Example: Broker-MT5',
                            prefixIcon: Icon(Icons.dns),
                          ),
                        ),

                        const SizedBox(height: 12),

                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'MT5 Trading Password',
                            prefixIcon: Icon(Icons.lock),
                          ),
                        ),

                        const SizedBox(height: 16),

                        FutureBuilder<bool>(
                          future: _storage.hasMetaApiCredentials(),
                          builder: (context, snapshot) {
                            final configured = snapshot.data == true;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      configured
                                          ? Icons.verified
                                          : Icons.warning_amber,
                                      color: configured
                                          ? Colors.green
                                          : Colors.orange,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        configured
                                            ? 'MetaApi credentials configured for this app.'
                                            : 'MetaApi credentials are not configured.',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: configured
                                              ? Colors.green
                                              : Colors.orange,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: bot.isBotRunning
                                        ? null
                                        : _setupMetaApi,
                                    icon: const Icon(Icons.key),
                                    label: Text(
                                      configured
                                          ? 'UPDATE METAAPI CREDENTIALS'
                                          : 'SET UP METAAPI',
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),

                        const SizedBox(height: 16),

                        const Text(
                          'Pips-Miner securely uses the MetaApi credentials stored for this app. '
                          'You only need to provide your MT5 account number, broker server and trading password.',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),

                        const SizedBox(height: 16),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed:
                                bot.isBotRunning ? null : () => _connect(bot),
                            icon: const Icon(Icons.link),
                            label: const Text('CONNECT MT5'),
                            style: ElevatedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),

                        if (bot.isConnected) ...[
                          const SizedBox(height: 12),
                          const Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green),
                              SizedBox(width: 8),
                              Text(
                                'MT5 CONNECTED',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],

                        if (bot.connectionError != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            bot.connectionError!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Account Type',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => bot.setAccountMode(false),
                                child: const Text('DEMO'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => bot.setAccountMode(true),
                                child: const Text('LIVE'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          bot.isLiveAccount
                              ? 'LIVE MODE — real money'
                              : 'DEMO MODE — practice account',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: bot.isLiveAccount
                                ? Colors.red
                                : Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Trading Parameters',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _symbolController,
                          decoration: const InputDecoration(
                            labelText: 'Trading Symbol',
                            hintText: 'XAUUSD',
                            prefixIcon: Icon(Icons.trending_up),
                          ),
                          onChanged: (value) {
                            bot.updateSettings(symbol: value);
                          },
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Automatic position sizing uses the connected account balance and the broker\'s live symbol specification.',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Reversal distance: 100 pips\nTrailing distance: 100 pips',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
