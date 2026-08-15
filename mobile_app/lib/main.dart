import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const PipsMinerApp());

class PipsMinerApp extends StatelessWidget {
  const PipsMinerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pips Miner',
      theme: ThemeData.dark(useMaterial3: true),
      home: const PipsMinerHome(),
    );
  }
}

class PipsMinerHome extends StatefulWidget {
  const PipsMinerHome({super.key});

  @override
  State<PipsMinerHome> createState() => _PipsMinerHomeState();
}

class _PipsMinerHomeState extends State<PipsMinerHome> {
  static const String apiUrl = 'http://127.0.0.1:5000/api';

  bool isLive = false;
  bool running = false;
  bool connected = false;
  bool busy = false;

  String statusText = 'Stopped';
  String marketText =
      'Trading window: 2h after market open → 2h before market close';

  Timer? timer;

  @override
  void initState() {
    super.initState();
    refresh();
    timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => refresh(),
    );
  }

  Future<void> refresh() async {
    try {
      final response = await http
          .get(Uri.parse('$apiUrl/bot/status'))
          .timeout(const Duration(seconds: 3));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (!mounted) return;

      setState(() {
        connected = true;
        running = data['running'] == true;
        statusText = data['status']?.toString() ?? 'Stopped';

        if (data['mode'] == 'LIVE') {
          isLive = true;
        } else if (data['mode'] == 'DEMO') {
          isLive = false;
        }

        marketText = data['market_window']?.toString() ??
            'Trading window: 2h after market open → 2h before market close';
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        connected = false;
      });
    }
  }

  Future<void> setMode(bool live) async {
    if (running || busy) return;

    setState(() {
      busy = true;
    });

    try {
      final response = await http
          .post(
            Uri.parse('$apiUrl/config'),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'mode': live ? 'LIVE' : 'DEMO',
              'symbol': 'XAUUSD',
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        if (!mounted) return;

        setState(() {
          isLive = live;
        });

        await refresh();
      } else {
        showMessage(response.body);
      }
    } catch (e) {
      showMessage('Backend unavailable');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  Future<void> startBot() async {
    if (busy || running) return;

    setState(() {
      busy = true;
    });

    try {
      final response = await http
          .post(Uri.parse('$apiUrl/bot/start'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        await refresh();
      } else {
        showMessage(response.body);
      }
    } catch (_) {
      showMessage('Could not start bot');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  Future<void> stopBot() async {
    if (busy || !running) return;

    setState(() {
      busy = true;
    });

    try {
      final response = await http
          .post(Uri.parse('$apiUrl/bot/stop'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        await refresh();
      } else {
        showMessage(response.body);
      }
    } catch (_) {
      showMessage('Could not stop bot');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Pips Miner',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [

            const Text(
              'XAUUSD',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              connected
                  ? 'Backend connected'
                  : 'Backend disconnected',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: connected
                    ? Colors.green
                    : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 24),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [

                    const Text(
                      'TRADING ACCOUNT',
                      style: TextStyle(
                        fontSize: 13,
                      ),
                    ),

                    const SizedBox(height: 10),

                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,

                      title: Text(
                        isLive
                            ? 'LIVE ACCOUNT'
                            : 'DEMO ACCOUNT',
                      ),

                      subtitle: Text(
                        isLive
                            ? 'Real trading'
                            : 'Demo trading',
                      ),

                      value: isLive,

                      onChanged:
                          running || busy
                              ? null
                              : setMode,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [

                    const Text(
                      'BOT STATUS',
                      style: TextStyle(
                        fontSize: 13,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Icon(
                      running
                          ? Icons.play_circle
                          : Icons.stop_circle,
                      size: 64,
                      color: running
                          ? Colors.green
                          : Colors.red,
                    ),

                    const SizedBox(height: 8),

                    Text(
                      statusText.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      marketText,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            SizedBox(
              height: 58,
              child: ElevatedButton.icon(
                onPressed:
                    busy || running
                        ? null
                        : startBot,

                icon: const Icon(
                  Icons.play_arrow,
                ),

                label: Text(
                  busy
                      ? 'PLEASE WAIT'
                      : 'START BOT',
                ),
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              height: 58,
              child: OutlinedButton.icon(
                onPressed:
                    busy || !running
                        ? null
                        : stopBot,

                icon: const Icon(
                  Icons.stop,
                ),

                label: const Text(
                  'STOP BOT',
                ),
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              'Pips Miner\n'
              'XAUUSD Volatility + Momentum Bot\n\n'
              'The APK controls the trading engine '
              'running locally on this Android phone.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
