import 'package:flutter/material.dart';
import 'package:pips_miner_app/providers/bot_provider.dart';
import 'package:pips_miner_app/theme/app_theme.dart';

class BrokerConnectionSection extends StatelessWidget {
  final BotProvider bot;
  final dynamic storage;
  final Future<void> Function(BotProvider) onConnect;
  final TextEditingController brokerController;
  final TextEditingController loginController;
  final TextEditingController serverController;
  final TextEditingController passwordController;

  const BrokerConnectionSection({
    super.key,
    required this.bot,
    required this.storage,
    required this.onConnect,
    required this.brokerController,
    required this.loginController,
    required this.serverController,
    required this.passwordController,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.hub_outlined, size: 18, color: AppTheme.primaryColor),
            SizedBox(width: 8),
            Text('METAAPI BRIDGE', style: TextStyle(fontSize: 10, letterSpacing: 1.1, fontWeight: FontWeight.w800, color: Colors.white54)),
          ]),
          const SizedBox(height: 8),
          const Text('Connect directly to MetaApi. No MT5 password or Vercel bridge is needed. Use a restricted token with account/provisioning read, REST trading, and streaming permissions; avoid a full admin token.', style: TextStyle(color: Colors.white38, fontSize: 10.5)),
          const SizedBox(height: 16),
          TextField(
            controller: loginController,
            enabled: !bot.isBotRunning,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'METAAPI ACCOUNT ID', prefixIcon: Icon(Icons.account_balance_outlined), hintText: 'MetaApi UUID — not your MT5 login'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: passwordController,
            enabled: !bot.isBotRunning,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'METAAPI BRIDGE KEY / API TOKEN', prefixIcon: Icon(Icons.key_outlined), hintText: 'Paste account-scoped token'),
          ),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(
            onPressed: bot.isBotRunning ? null : () => onConnect(bot),
            icon: const Icon(Icons.link_rounded),
            label: const Text('CONNECT METAAPI ACCOUNT', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .4)),
          )),
          if (bot.isConnected) ...[
            const SizedBox(height: 12),
            const Text('METAAPI CONNECTED • PIPS-MINER READY', style: TextStyle(color: AppTheme.successColor, fontSize: 10, fontWeight: FontWeight.w800)),
          ],
          if (bot.connectionError != null) ...[
            const SizedBox(height: 12),
            Text(bot.connectionError!, style: const TextStyle(color: AppTheme.errorColor, fontSize: 10)),
          ],
        ]),
      ),
    );
  }
}
