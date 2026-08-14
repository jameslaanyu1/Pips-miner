import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pips_miner_app/providers/bot_provider.dart';

class AccountSwitcher extends StatelessWidget {
  const AccountSwitcher({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<BotProvider>(
      builder: (context, botProvider, _) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.account_balance, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Trading Account',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        botProvider.isLiveAccount ? 'LIVE ACCOUNT' : 'DEMO ACCOUNT',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: botProvider.isLiveAccount,
                  onChanged: botProvider.isBotRunning
                      ? null
                      : (value) => botProvider.setAccountMode(value),
                  activeColor: Colors.red,
                  inactiveThumbColor: Colors.blue,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
