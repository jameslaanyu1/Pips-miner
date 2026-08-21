import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/bot_provider.dart';
import '../theme/app_theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BotProvider>(
      builder: (context, bot, _) {
        return Scaffold(
          backgroundColor: AppTheme.darkBg,
          body: SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _header(bot),
                      const SizedBox(height: 18),
                      _accountCard(bot),
                      const SizedBox(height: 14),
                      _marketCard(bot),
                      const SizedBox(height: 14),
                      _engineCard(bot),
                      const SizedBox(height: 14),
                      _botControl(bot),
                      const SizedBox(height: 14),
                      _positionCard(bot),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header(BotProvider bot) {
    final connected = bot.isConnected;

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.accentColor.withOpacity(.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.accentColor.withOpacity(.28),
            ),
          ),
          child: const Icon(
            Icons.auto_graph_rounded,
            color: AppTheme.accentColor,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PIPS MINER',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'AUTONOMOUS TRADING ENGINE',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: connected
                ? AppTheme.successColor.withOpacity(.10)
                : Colors.white.withOpacity(.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: connected
                  ? AppTheme.successColor.withOpacity(.30)
                  : Colors.white12,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: connected
                      ? AppTheme.successColor
                      : Colors.white30,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                connected ? 'ONLINE' : 'OFFLINE',
                style: TextStyle(
                  color: connected
                      ? AppTheme.successColor
                      : Colors.white54,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _accountCard(BotProvider bot) {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'ACCOUNT EQUITY',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              _badge(
                bot.accountMode,
                bot.isLiveAccount
                    ? AppTheme.warningColor
                    : AppTheme.secondaryColor,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '\$${bot.balance.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _metric(
                  'P/L',
                  '${bot.profitLoss >= 0 ? '+' : ''}${bot.profitLoss.toStringAsFixed(2)}',
                  bot.profitLoss >= 0
                      ? AppTheme.successColor
                      : AppTheme.errorColor,
                ),
              ),
              Expanded(
                child: _metric(
                  'TRADES',
                  '${bot.totalTrades}',
                  Colors.white,
                ),
              ),
              Expanded(
                child: _metric(
                  'WIN RATE',
                  '${bot.winRate.toStringAsFixed(1)}%',
                  AppTheme.accentColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _marketCard(BotProvider bot) {
    return _panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 10),
            child: Row(
              children: [
                const Text(
                  'XAUUSD',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 8),
                _badge('GOLD', AppTheme.accentColor),
                const Spacer(),
                Text(
                  bot.priceChange >= 0
                      ? '+${bot.priceChange.toStringAsFixed(2)}%'
                      : '${bot.priceChange.toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: bot.priceChange >= 0
                        ? AppTheme.successColor
                        : AppTheme.errorColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 125,
            width: double.infinity,
            child: CustomPaint(
              painter: _MarketPainter(
                seed: bot.priceChange,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '1 MIN',
                  style: TextStyle(
                    color: Colors.white30,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'VOLATILITY • MOMENTUM',
                  style: TextStyle(
                    color: Colors.white30,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _engineCard(BotProvider bot) {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.radar_rounded,
                size: 18,
                color: AppTheme.accentColor,
              ),
              const SizedBox(width: 8),
              const Text(
                'SIGNAL ENGINE',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Text(
                bot.isBotRunning ? 'SCANNING' : 'STANDBY',
                style: TextStyle(
                  color: bot.isBotRunning
                      ? AppTheme.successColor
                      : Colors.white38,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _signal(
                  'VOLATILITY',
                  bot.isBotRunning ? 'HIGH' : 'READY',
                  bot.isBotRunning
                      ? AppTheme.warningColor
                      : Colors.white54,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _signal(
                  'MOMENTUM',
                  bot.isBotRunning ? 'ACTIVE' : 'WAIT',
                  bot.isBotRunning
                      ? AppTheme.successColor
                      : Colors.white54,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _signal(
                  'BIAS',
                  bot.currentPosition ?? 'NEUTRAL',
                  AppTheme.accentColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _botControl(BotProvider bot) {
    final running = bot.isBotRunning;

    return GestureDetector(
      onTap: () {
        if (running) {
          bot.stopBot();
        } else {
          bot.startBot();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 76,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: running
                ? [
                    AppTheme.errorColor.withOpacity(.22),
                    AppTheme.errorColor.withOpacity(.08),
                  ]
                : [
                    AppTheme.accentColor.withOpacity(.22),
                    AppTheme.accentColor.withOpacity(.07),
                  ],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: running
                ? AppTheme.errorColor.withOpacity(.45)
                : AppTheme.accentColor.withOpacity(.45),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              running
                  ? Icons.stop_circle_outlined
                  : Icons.play_circle_outline_rounded,
              size: 31,
              color: running
                  ? AppTheme.errorColor
                  : AppTheme.accentColor,
            ),
            const SizedBox(width: 12),
            Text(
              running ? 'STOP MINER' : 'START MINER',
              style: TextStyle(
                color: running
                    ? AppTheme.errorColor
                    : AppTheme.accentColor,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _positionCard(BotProvider bot) {
    final position = bot.currentPosition;

    return _panel(
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'ACTIVE POSITION',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              _badge(
                position ?? 'NONE',
                position == null
                    ? Colors.white38
                    : AppTheme.successColor,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _positionMetric(
                  'ENTRY',
                  bot.entryPrice == null
                      ? '--'
                      : bot.entryPrice!.toStringAsFixed(2),
                ),
              ),
              Expanded(
                child: _positionMetric(
                  'REVERSAL',
                  bot.stopPrice == null
                      ? '--'
                      : bot.stopPrice!.toStringAsFixed(2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _panel({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(16),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.darkBorder,
        ),
      ),
      child: child,
    );
  }

  Widget _metric(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white30,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _positionMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white30,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _signal(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.025),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white30,
              fontSize: 8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(.25),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: .8,
        ),
      ),
    );
  }
}

class _MarketPainter extends CustomPainter {
  final double seed;

  _MarketPainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withOpacity(.035)
      ..strokeWidth = 1;

    for (var i = 1; i < 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        grid,
      );
    }

    final line = Paint()
      ..color = AppTheme.accentColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();

    for (var i = 0; i <= 80; i++) {
      final x = size.width * i / 80;
      final wave =
          math.sin(i / 5.2) * 13 +
          math.sin(i / 11) * 8 +
          math.sin(i / 2.8) * 3;

      final trend = seed * i * .35;
      final y = size.height * .55 - wave - trend;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _MarketPainter oldDelegate) {
    return oldDelegate.seed != seed;
  }
}
