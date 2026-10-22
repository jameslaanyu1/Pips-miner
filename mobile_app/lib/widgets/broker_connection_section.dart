import 'package:flutter/material.dart';

import 'package:pips_miner_app/providers/bot_provider.dart';
import 'package:pips_miner_app/theme/app_theme.dart';

class BrokerConnectionSection extends StatelessWidget {
  final BotProvider bot;
  final Future<void> Function(BotProvider) onConnect;
  final TextEditingController apiTokenController;
  final TextEditingController accountIdController;

  const BrokerConnectionSection({
    super.key,
    required this.bot,
    required this.onConnect,
    required this.apiTokenController,
    required this.accountIdController,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.link_rounded, size: 17, color: AppTheme.primaryColor),
                SizedBox(width: 8),
                Text(
                  'DIRECT METAAPI CONNECTION',
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w800,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Connect to your existing MetaApi account. Pips-Miner no longer uses a separate backend or asks for your MT5 password.',
              style: TextStyle(color: Colors.white38, fontSize: 10.5),
            ),
            const SizedBox(height: 17),
            TextField(
              controller: apiTokenController,
              enabled: !bot.isBotRunning,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'METAAPI API ACCESS TOKEN',
                hintText: 'Paste your MetaApi token',
                prefixIcon: Icon(Icons.key_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: accountIdController,
              enabled: !bot.isBotRunning,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'METAAPI ACCOUNT ID',
                hintText: 'Your connected MT5 account ID in MetaApi',
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: bot.isBotRunning ? null : () => onConnect(bot),
                icon: const Icon(Icons.link_rounded),
                label: const Text(
                  'CONNECT METAAPI',
                  style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .5),
                ),
              ),
            ),
            if (bot.isConnected) ...[
              const SizedBox(height: 12),
              const _ConnectionStatus(
                connected: true,
                message: 'METAAPI CONNECTED • LIVE ACCOUNT READY',
              ),
            ],
            if (bot.connectionError != null) ...[
              const SizedBox(height: 12),
              _ConnectionStatus(
                connected: false,
                message: bot.connectionError!,
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Keep the API token private. A token entered into a mobile app is still recoverable from a modified APK; use a dedicated token with only the permissions needed for this account.',
              style: TextStyle(color: Colors.white30, fontSize: 9.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionStatus extends StatelessWidget {
  final bool connected;
  final String message;

  const _ConnectionStatus({required this.connected, required this.message});

  @override
  Widget build(BuildContext context) {
    final color = connected ? AppTheme.successColor : AppTheme.errorColor;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(.20)),
      ),
      child: Row(
        children: [
          Icon(
            connected ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
