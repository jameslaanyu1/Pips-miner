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
                      const SizedBox(height: 10),
                      _accountModeSelector(bot),
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
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.accentColor.withOpacity(.28),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            'assets/pips_miner_pro_icon.png',
            fit: BoxFit.cover,
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
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'life changing pips',
                style: TextStyle(
                  color: AppTheme.accentColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .8,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
                  color: connected ? AppTheme.successColor : Colors.white30,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                connected ? 'ONLINE' : 'OFFLINE',
                style: TextStyle(
                  color: connected ? AppTheme.successColor : Colors.white54,
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
          Row(children: [
            const Text('ACCOUNT EQUITY', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            const Spacer(),
            _badge(bot.accountMode, bot.isLiveAccount ? AppTheme.warningColor : AppTheme.secondaryColor),
          ]),
          const SizedBox(height: 8),
          Text('Ksh ${bot.balance.toStringAsFixed(2)}', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _metric('P/L', 'Ksh ${bot.profitLoss >= 0 ? '+' : ''}${bot.profitLoss.toStringAsFixed(2)}', bot.profitLoss >= 0 ? AppTheme.successColor : AppTheme.errorColor)),
            Expanded(child: _metric('TRADES', '${bot.totalTrades}', Colors.white)),
            Expanded(child: _metric('WIN RATE', '${bot.winRate.toStringAsFixed(1)}%', AppTheme.accentColor)),
          ]),
        ],
      ),
    );
  }

  Widget _accountModeSelector(BotProvider bot) {
    final live = bot.isLiveAccount;
    return _panel(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        const Icon(Icons.shield_outlined, size: 18, color: AppTheme.primaryColor),
        const SizedBox(width: 9),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ACCOUNT MODE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
          SizedBox(height: 2),
          Text('Select trading environment', style: TextStyle(color: Colors.white38, fontSize: 9)),
        ])),
        SegmentedButton<bool>(
          segments: const [ButtonSegment<bool>(value: false, label: Text('DEMO')), ButtonSegment<bool>(value: true, label: Text('LIVE'))],
          selected: {live},
          onSelectionChanged: bot.isBotRunning ? null : (selection) { if (selection.isNotEmpty) bot.setAccountMode(selection.first); },
          style: const ButtonStyle(visualDensity: VisualDensity.compact, textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 9, fontWeight: FontWeight.w800))),
        ),
      ]),
    );
  }

  Widget _marketCard(BotProvider bot) {
    return _panel(
      padding: EdgeInsets.zero,
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 15, 16, 10), child: Row(children: [
          const Text('XAUUSD', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(width: 8),
          _badge('GOLD', AppTheme.accentColor),
          const Spacer(),
          Text(bot.priceChange >= 0 ? '+${bot.priceChange.toStringAsFixed(2)}%' : '${bot.priceChange.toStringAsFixed(2)}%', style: TextStyle(color: bot.priceChange >= 0 ? AppTheme.successColor : AppTheme.errorColor, fontWeight: FontWeight.w800, fontSize: 12)),
        ])),
        SizedBox(height: 125, width: double.infinity, child: CustomPaint(painter: _MarketPainter(seed: bot.priceChange))),
        const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 15), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('1 MIN', style: TextStyle(color: Colors.white30, fontSize: 9, fontWeight: FontWeight.w700)),
          Text('VOLATILITY • MOMENTUM', style: TextStyle(color: Colors.white30, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: .8)),
        ])),
      ]),
    );
  }

  Widget _engineCard(BotProvider bot) {
    return _panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.radar_rounded, size: 18, color: AppTheme.accentColor),
        const SizedBox(width: 8),
        const Text('SIGNAL ENGINE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1)),
        const Spacer(),
        Text(bot.isBotRunning ? 'SCANNING' : 'STANDBY', style: TextStyle(color: bot.isBotRunning ? AppTheme.successColor : Colors.white38, fontSize: 9, fontWeight: FontWeight.w800)),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: _signal('VOLATILITY', bot.isBotRunning ? 'HIGH' : 'READY', bot.isBotRunning ? AppTheme.warningColor : Colors.white54)),
        const SizedBox(width: 10),
        Expanded(child: _signal('MOMENTUM', bot.isBotRunning ? 'ACTIVE' : 'WAIT', bot.isBotRunning ? AppTheme.successColor : Colors.white54)),
        const SizedBox(width: 10),
        Expanded(child: _signal('BIAS', bot.currentPosition ?? 'NEUTRAL', AppTheme.accentColor)),
      ]),
    ]));
  }

  Widget _botControl(BotProvider bot) {
    final running = bot.isBotRunning;
    return Row(children: [
      Expanded(child: GestureDetector(onTap: running ? null : () { bot.startBot(); }, child: AnimatedContainer(duration: const Duration(milliseconds: 250), height: 76, decoration: BoxDecoration(gradient: LinearGradient(colors: running ? [AppTheme.successColor.withOpacity(.30), AppTheme.successColor.withOpacity(.10)] : [AppTheme.accentColor.withOpacity(.22), AppTheme.accentColor.withOpacity(.07)]), borderRadius: BorderRadius.circular(22), border: Border.all(color: running ? AppTheme.successColor.withOpacity(.65) : AppTheme.accentColor.withOpacity(.45)), boxShadow: running ? [BoxShadow(color: AppTheme.successColor.withOpacity(.18), blurRadius: 18, spreadRadius: 1)] : null), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.play_circle_outline_rounded, size: 28, color: running ? AppTheme.successColor : AppTheme.accentColor), const SizedBox(width: 8), Flexible(child: Text('START MINER', overflow: TextOverflow.ellipsis, style: TextStyle(color: running ? AppTheme.successColor : AppTheme.accentColor, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.0)))])))),
      const SizedBox(width: 10),
      Expanded(child: GestureDetector(onTap: running ? () { bot.stopBot(); } : null, child: AnimatedContainer(duration: const Duration(milliseconds: 250), height: 76, decoration: BoxDecoration(gradient: LinearGradient(colors: [AppTheme.errorColor.withOpacity(running ? .30 : .12), AppTheme.errorColor.withOpacity(running ? .10 : .04)]), borderRadius: BorderRadius.circular(22), border: Border.all(color: AppTheme.errorColor.withOpacity(running ? .65 : .25)), boxShadow: running ? [BoxShadow(color: AppTheme.errorColor.withOpacity(.18), blurRadius: 18, spreadRadius: 1)] : null), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.stop_circle_outlined, size: 28, color: AppTheme.errorColor.withOpacity(running ? 1.0 : .45)), const SizedBox(width: 8), Flexible(child: Text('STOP MINER', overflow: TextOverflow.ellipsis, style: TextStyle(color: AppTheme.errorColor.withOpacity(running ? 1.0 : .45), fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.0)))])))),
    ]);
  }

  Widget _positionCard(BotProvider bot) {
    final position = bot.currentPosition;
    return _panel(child: Column(children: [
      Row(children: [
        const Text('ACTIVE POSITION', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
        const Spacer(),
        _badge(position ?? 'NONE', position == null ? Colors.white38 : AppTheme.successColor),
      ]),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(child: _positionMetric('ENTRY', bot.entryPrice == null ? '--' : bot.entryPrice!.toStringAsFixed(2))),
        Expanded(child: _positionMetric('REVERSAL', bot.stopPrice == null ? '--' : bot.stopPrice!.toStringAsFixed(2))),
      ]),
    ]));
  }

  Widget _panel({required Widget child, EdgeInsets padding = const EdgeInsets.all(16)}) {
    return Container(padding: padding, decoration: BoxDecoration(color: AppTheme.darkSurface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.darkBorder)), child: child);
  }

  Widget _badge(String text, Color color) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(.30))), child: Text(text, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: .6)));
  }

  Widget _metric(String label, String value, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900))]);
  }

  Widget _signal(String label, String value, Color color) {
    return Container(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8), decoration: BoxDecoration(color: color.withOpacity(.07), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(.20))), child: Column(children: [Text(label, style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text(value, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900))]));
  }

  Widget _positionMetric(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w700)), const SizedBox(height: 5), Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))]);
  }
}

class _MarketPainter extends CustomPainter {
  final double seed;
  _MarketPainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppTheme.accentColor.withOpacity(.75)..strokeWidth = 2.0..style = PaintingStyle.stroke;
    final path = Path();
    final random = math.Random(seed.abs().toInt() + 7);
    final points = <Offset>[];
    for (var i = 0; i < 32; i++) {
      final x = size.width * i / 31;
      final noise = (random.nextDouble() - .5) * 18;
      final trend = (seed >= 0 ? -1 : 1) * i * .8;
      final y = size.height * .55 + noise + trend;
      points.add(Offset(x, y.clamp(8, size.height - 8)));
    }
    path.moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) { path.lineTo(points[i].dx, points[i].dy); }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MarketPainter oldDelegate) => oldDelegate.seed != seed;
}
