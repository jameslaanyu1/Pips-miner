import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pips_miner_app/providers/bot_provider.dart';

class BotStatusCard extends StatelessWidget {
  const BotStatusCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<BotProvider>(
      builder: (context, botProvider, _) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Bot Status',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: botProvider.isBotRunning
                            ? Colors.green.withOpacity(0.2)
                            : Colors.grey.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: botProvider.isBotRunning
                                  ? Colors.green
                                  : Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            botProvider.isBotRunning ? 'RUNNING' : 'STOPPED',
                            style: TextStyle(
                              color: botProvider.isBotRunning
                                  ? Colors.green
                                  : Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Position Status
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Current Position:'),
                    Text(
                      botProvider.currentPosition ?? 'NONE',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: botProvider.currentPosition == 'LONG'
                            ? Colors.green
                            : botProvider.currentPosition == 'SHORT'
                                ? Colors.red
                                : Colors.grey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Entry Price
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Entry Price:'),
                    Text(
                      botProvider.entryPrice != null
                          ? '${botProvider.entryPrice!.toStringAsFixed(5)}'
                          : 'N/A',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Stop Price
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Stop Price:'),
                    Text(
                      botProvider.stopPrice != null
                          ? '${botProvider.stopPrice!.toStringAsFixed(5)}'
                          : 'N/A',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
