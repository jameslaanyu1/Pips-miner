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
        final hasPosition = bot.currentPosition != null;
        final isBuy = bot.currentPosition == 'BUY';

        return SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _Header(bot: bot),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _BotControlCard(bot: bot),
                    const SizedBox(height: 14),
                    _AccountCard(bot: bot),
                    const SizedBox(height: 14),
                    _PositionCard(
                      bot: bot,
                      hasPosition: hasPosition,
                      isBuy: isBuy,
                    ),
                    const SizedBox(height: 14),
                    _MarketCard(bot: bot),
                    const SizedBox(height: 14),
                    _ChartCard(bot: bot),
                    const SizedBox(height: 14),
                    _MetricsCard(bot: bot),
                    const SizedBox(height: 14),
                    const _ExecutionLog(),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final BotProvider bot;

  const _Header({required this.bot});

  @override
  Widget build(BuildContext context) {
    final connected = bot.isConnected;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Row(
        children: [
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withOpacity(.11),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.accentColor.withOpacity(.32),
              ),
            ),
            child: const Icon(
              Icons.engineering_rounded,
              color: AppTheme.accentColor,
              size: 25,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pips-Miner',
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.6,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'AUTOMATED TRADING ENGINE',
                  style: TextStyle(
                    fontSize: 8.5,
                    letterSpacing: 1.25,
                    fontWeight: FontWeight.w700,
                    color: Colors.white38,
                  ),
                ),
              ],
            ),
          ),
          _StatusPill(
            label: connected ? 'CONNECTED' : 'OFFLINE',
            color: connected
                ? AppTheme.successColor
                : AppTheme.errorColor,
          ),
        ],
      ),
    );
  }
}

class _BotControlCard extends StatelessWidget {
  final BotProvider bot;

  const _BotControlCard({required this.bot});

  @override
  Widget build(BuildContext context) {
    final running = bot.isBotRunning;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        AppTheme.primaryColor,
                        Color(0xFFB76CFF),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    running
                        ? Icons.bolt_rounded
                        : Icons.pause_rounded,
                    color: Colors.white,
                    size: 27,
                  ),
                ),
                const SizedBox(width: 13),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mining Engine',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Velocity expansion + momentum',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusPill(
                  label: running ? 'RUNNING' : 'STOPPED',
                  color: running
                      ? AppTheme.successColor
                      : Colors.white38,
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => _toggleBot(context, bot),
                icon: Icon(
                  running
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline,
                ),
                label: Text(
                  running ? 'STOP MINER' : 'START MINER',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: .6,
                  ),
                ),
              ),
            ),
            if (bot.engineError != null) ...[
              const SizedBox(height: 12),
              _ErrorBanner(message: bot.engineError!),
            ],
            if (bot.connectionError != null) ...[
              const SizedBox(height: 12),
              _ErrorBanner(message: bot.connectionError!),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _toggleBot(
    BuildContext context,
    BotProvider bot,
  ) async {
    try {
      if (bot.isBotRunning) {
        await bot.stopBot();
      } else {
        await bot.startBot();
      }
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    }
  }
}

class _AccountCard extends StatelessWidget {
  final BotProvider bot;

  const _AccountCard({required this.bot});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(
              title: 'ACCOUNT',
              icon: Icons.account_balance_wallet_outlined,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _ValueBox(
                    label: 'MODE',
                    value: bot.accountMode,
                    valueColor: bot.isLiveAccount
                        ? AppTheme.warningColor
                        : AppTheme.secondaryColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ValueBox(
                    label: 'SYMBOL',
                    value: bot.symbol,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _ValueBox(
                    label: 'BALANCE',
                    value: _money(bot.balance),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ValueBox(
                    label: 'P/L',
                    value: _money(bot.profitLoss),
                    valueColor: bot.profitLoss >= 0
                        ? AppTheme.successColor
                        : AppTheme.errorColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PositionCard extends StatelessWidget {
  final BotProvider bot;
  final bool hasPosition;
  final bool isBuy;

  const _PositionCard({
    required this.bot,
    required this.hasPosition,
    required this.isBuy,
  });

  @override
  Widget build(BuildContext context) {
    final positionColor = isBuy
        ? AppTheme.successColor
        : AppTheme.errorColor;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(
              title: 'ACTIVE POSITION',
              icon: Icons.swap_vert_rounded,
            ),
            const SizedBox(height: 14),
            if (!hasPosition)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 25),
                decoration: BoxDecoration(
                  color: AppTheme.darkSurfaceVariant,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.radar_rounded,
                      color: Colors.white30,
                      size: 30,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'NO ACTIVE POSITION',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w800,
                        color: Colors.white38,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Pips-Miner is scanning for a valid setup',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white24,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: _ValueBox(
                      label: 'DIRECTION',
                      value: bot.currentPosition!,
                      valueColor: positionColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ValueBox(
                      label: 'ENTRY',
                      value: _price(bot.entryPrice),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _ValueBox(
                label: 'REVERSAL STOP',
                value: _price(bot.stopPrice),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MarketCard extends StatelessWidget {
  final BotProvider bot;

  const _MarketCard({required this.bot});

  @override
  Widget build(BuildContext context) {
    final change = bot.priceChange;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 47,
              height: 47,
              decoration: BoxDecoration(
                color: AppTheme.secondaryColor.withOpacity(.09),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.insights_rounded,
                color: AppTheme.secondaryColor,
              ),
            ),
            const SizedBox(width: 13),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MARKET ENGINE',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.white38,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Velocity + momentum analysis',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'PRICE Δ',
                  style: TextStyle(
                    fontSize: 8,
                    color: Colors.white30,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: change >= 0
                        ? AppTheme.successColor
                        : AppTheme.errorColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final BotProvider bot;

  const _ChartCard({required this.bot});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(
              title: 'MARKET VIEW',
              icon: Icons.candlestick_chart_rounded,
            ),
            const SizedBox(height: 12),
            Container(
              height: 185,
              decoration: BoxDecoration(
                color: AppTheme.darkSurfaceVariant,
                borderRadius: BorderRadius.circular(14),
              ),
              child: CustomPaint(
                painter: _MarketPainter(),
                child: Center(
                  child: Text(
                    bot.isConnected
                        ? 'LIVE MARKET STREAM'
                        : 'CONNECT MT5 TO VIEW MARKET',
                    style: const TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.1,
                      color: Colors.white24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withOpacity(.035)
      ..strokeWidth = 1;

    for (double y = 25; y < size.height; y += 35) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        grid,
      );
    }

    for (double x = 20; x < size.width; x += 45) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        grid,
      );
    }

    final line = Paint()
      ..color = AppTheme.primaryColor
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;

    final path = Path();
    const points = [
      .72, .68, .70, .63, .66, .58,
      .61, .52, .55, .48, .52, .42,
      .46, .49, .40, .37, .42, .33,
      .30, .35, .27, .23, .28, .20,
    ];

    for (var i = 0; i < points.length; i++) {
      final x = i * size.width / (points.length - 1);
      final y = points[i] * size.height;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MetricsCard extends StatelessWidget {
  final BotProvider bot;

  const _MetricsCard({required this.bot});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Metric(
            label: 'WIN RATE',
            value: '${bot.winRate.toStringAsFixed(1)}%',
            icon: Icons.emoji_events_outlined,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Metric(
            label: 'TRADES',
            value: bot.totalTrades.toString(),
            icon: Icons.swap_horiz_rounded,
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _Metric({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Icon(
              icon,
              color: AppTheme.accentColor,
              size: 21,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 8,
                      color: Colors.white30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExecutionLog extends StatelessWidget {
  const _ExecutionLog();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(
              title: 'EXECUTION LOG',
              icon: Icons.receipt_long_outlined,
            ),
            const SizedBox(height: 13),
            _LogRow(
              message: 'Engine monitoring market conditions',
              color: AppTheme.secondaryColor,
            ),
            _LogRow(
              message: 'Velocity expansion + momentum confirmation required',
              color: Colors.white30,
            ),
            _LogRow(
              message: 'Opposite reversal stop managed by engine',
              color: Colors.white30,
            ),
          ],
        ),
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  final String message;
  final Color color;

  const _LogRow({
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 10.5,
                color: Colors.white54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionTitle({
    required this.title,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 17,
          color: AppTheme.primaryColor,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 9.5,
            letterSpacing: 1.15,
            fontWeight: FontWeight.w800,
            color: Colors.white54,
          ),
        ),
      ],
    );
  }
}

class _ValueBox extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _ValueBox({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.darkSurfaceVariant,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 8,
              color: Colors.white30,
              fontWeight: FontWeight.w800,
              letterSpacing: .7,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withOpacity(.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.errorColor.withOpacity(.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.errorColor.withOpacity(.22),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            color: AppTheme.errorColor,
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _price(double? value) {
  if (value == null || value == 0) return '--';
  return value.toStringAsFixed(5);
}

String _money(double value) {
  return value.toStringAsFixed(2);
}
