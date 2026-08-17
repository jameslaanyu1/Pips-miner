import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pips_miner_app/providers/bot_provider.dart';
import 'package:pips_miner_app/widgets/account_switcher.dart';
import 'package:pips_miner_app/widgets/bot_status_card.dart';
import 'package:pips_miner_app/widgets/trading_metrics.dart';
import 'package:pips_miner_app/widgets/live_chart.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BotProvider>().connect();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pip-life', style: TextStyle(fontWeight: FontWeight.w600)),
            Text(
              'life changing pips',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Consumer<BotProvider>(
              builder: (context, botProvider, _) {
                return Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: botProvider.isConnected
                          ? Colors.green.withOpacity(0.2)
                          : Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      botProvider.isConnected ? 'Connected' : 'Disconnected',
                      style: TextStyle(
                        color: botProvider.isConnected
                            ? Colors.green
                            : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Live/Demo Account Switcher
            const AccountSwitcher(),
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

            // Bot Status Card
            const BotStatusCard(),
            const SizedBox(height: 12),

            Consumer<BotProvider>(
              builder: (context, botProvider, _) {
                final hasPosition = botProvider.currentPosition != null;

                final String title;
                final String message;
                final Color color;
                final IconData icon;

                if (!botProvider.isConnected) {
                  title = 'ENGINE OFFLINE';
                  message =
                      botProvider.connectionError ??
                      'Connect the MT5 account before starting the bot.';
                  color = Colors.red;
                  icon = Icons.cloud_off;
                } else if (botProvider.engineError != null) {
                  title = 'ENGINE ERROR';
                  message = botProvider.engineError!;
                  color = Colors.red;
                  icon = Icons.error_outline;
                } else if (!botProvider.isBotRunning) {
                  title = 'ENGINE STOPPED';
                  message = 'Press START to run the trading engine.';
                  color = Colors.orange;
                  icon = Icons.stop_circle_outlined;
                } else if (hasPosition) {
                  title = 'POSITION OPEN';
                  message =
                      '${botProvider.currentPosition} position is active on ${botProvider.symbol}.';
                  color = Colors.green;
                  icon = Icons.trending_up;
                } else {
                  title = 'WAITING FOR ENTRY SIGNAL';
                  message =
                      'Trading engine is running on ${botProvider.symbol} M1 and is waiting for a qualifying velocity + volume expansion.';
                  color = Colors.green;
                  icon = Icons.radar;
                }

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, color: color),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(message),
                              if (botProvider.isBotRunning &&
                                  !hasPosition &&
                                  botProvider.engineError == null) ...[
                                const SizedBox(height: 5),
                                const Text(
                                  'Entry requires both velocity expansion and volume expansion.',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 20),

            // Trading Metrics
            const TradingMetrics(),
            const SizedBox(height: 20),

            // Live Chart
            const LiveChart(),
            const SizedBox(height: 20),

            // Bot Controls
            Consumer<BotProvider>(
              builder: (context, botProvider, _) {
                return Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: botProvider.isBotRunning
                            ? null
                            : () async {
                                try {
                                  await botProvider.startBot();
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: Colors.red,
                                      content: Text('Bot start failed: $e'),
                                      duration: const Duration(seconds: 8),
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('START'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: !botProvider.isBotRunning
                            ? null
                            : () => botProvider.stopBot(),
                        icon: const Icon(Icons.stop),
                        label: const Text('STOP'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
