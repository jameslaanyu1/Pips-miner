import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/bot_provider.dart';
import 'iv_options_screen.dart';
import '../theme/app_theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BotProvider>(builder: (context, bot, _) => Scaffold(backgroundColor: AppTheme.darkBg, body: SafeArea(child: CustomScrollView(slivers: [SliverPadding(padding: const EdgeInsets.fromLTRB(18, 18, 18, 32), sliver: SliverList(delegate: SliverChildListDelegate([_header(bot), const SizedBox(height: 18), _accountCard(bot), const SizedBox(height: 10), _accountModeDisplay(bot), const SizedBox(height: 14), _marketCard(bot), const SizedBox(height: 10), _LiveTradingChronometer(isRunning: bot.isBotRunning), const SizedBox(height: 14), _positionCard(bot), const SizedBox(height: 14), _botControl(bot), const SizedBox(height: 12), _ivOptionsButton(context)])))]))));
  }

  Widget _ivOptionsButton(BuildContext context) => SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IvOptionsScreen())), icon: const Icon(Icons.analytics_outlined), label: const Text('IV OPTIONS • IMPORT ZONES')));

  Widget _header(BotProvider bot) => Row(children: [Container(width: 44, height: 44, decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.accentColor.withOpacity(.28))), clipBehavior: Clip.antiAlias, child: Image.asset('assets/pips_miner_pro_icon.png', fit: BoxFit.cover)), const SizedBox(width: 12), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Pips-Miner', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.0)), SizedBox(height: 2), Text('life changing pips', style: TextStyle(color: AppTheme.accentColor, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: .8))])), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: bot.isConnected ? AppTheme.successColor.withOpacity(.10) : Colors.white.withOpacity(.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: bot.isConnected ? AppTheme.successColor.withOpacity(.30) : Colors.white12)), child: Row(children: [Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: bot.isConnected ? AppTheme.successColor : Colors.white30)), const SizedBox(width: 6), Text(bot.isConnected ? 'ONLINE' : 'OFFLINE', style: TextStyle(color: bot.isConnected ? AppTheme.successColor : Colors.white54, fontSize: 9, fontWeight: FontWeight.w800))]))]);

  Widget _accountCard(BotProvider bot) => _panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const Text('ACCOUNT EQUITY', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2)), const Spacer(), _badge(bot.accountMode, bot.isLiveAccount ? AppTheme.warningColor : AppTheme.secondaryColor)]), const SizedBox(height: 8), Text('Ksh ${bot.balance.toStringAsFixed(2)}', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1)), const SizedBox(height: 16), Row(children: [Expanded(child: _metric('P/L', 'Ksh ${bot.profitLoss >= 0 ? '+' : ''}${bot.profitLoss.toStringAsFixed(2)}', bot.profitLoss >= 0 ? AppTheme.successColor : AppTheme.errorColor)), Expanded(child: _metric('TRADES', '${bot.totalTrades}', Colors.white)), Expanded(child: _metric('WIN RATE', '${bot.winRate.toStringAsFixed(1)}%', AppTheme.accentColor))]) ]));

  Widget _accountModeDisplay(BotProvider bot) => _panel(padding: const EdgeInsets.all(12), child: Row(children: [Icon(bot.isLiveAccount ? Icons.shield_rounded : Icons.shield_outlined, size: 18, color: bot.isLiveAccount ? AppTheme.warningColor : AppTheme.secondaryColor), const SizedBox(width: 9), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('ACCOUNT MODE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)), SizedBox(height: 2), Text('Selected in Settings', style: TextStyle(color: Colors.white38, fontSize: 9))])), _badge(bot.isLiveAccount ? 'LIVE ACCOUNT' : 'DEMO ACCOUNT', bot.isLiveAccount ? AppTheme.warningColor : AppTheme.secondaryColor)]));

  Widget _marketCard(BotProvider bot) => _panel(padding: EdgeInsets.zero, child: Column(children: [Padding(padding: const EdgeInsets.fromLTRB(16, 15, 16, 10), child: Row(children: [Text(bot.symbol.toUpperCase(), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const Spacer(), Text(bot.priceChange >= 0 ? '+${bot.priceChange.toStringAsFixed(2)}%' : '${bot.priceChange.toStringAsFixed(2)}%', style: TextStyle(color: bot.priceChange >= 0 ? AppTheme.successColor : AppTheme.errorColor, fontWeight: FontWeight.w800, fontSize: 12))])), SizedBox(height: 125, width: double.infinity, child: CustomPaint(painter: _MarketPainter(seed: bot.priceChange))), Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 15), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('1 MIN • ${bot.symbol.toUpperCase()}', style: const TextStyle(color: Colors.white30, fontSize: 9, fontWeight: FontWeight.w700)), const Text('VOLATILITY • MOMENTUM', style: TextStyle(color: Colors.white30, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: .8))])), const Divider(height: 1, color: AppTheme.darkBorder), Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 12), child: Row(children: [const Icon(Icons.radar_rounded, size: 15, color: AppTheme.accentColor), const SizedBox(width: 7), const Text('SIGNAL ENGINE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 9, letterSpacing: .8)), const SizedBox(width: 8), Text(bot.isBotRunning ? 'SCANNING' : 'STANDBY', style: TextStyle(color: bot.isBotRunning ? AppTheme.successColor : Colors.white38, fontSize: 8, fontWeight: FontWeight.w800)), const Spacer(), _compactSignal('V', bot.isBotRunning ? 'HIGH' : 'READY', bot.isBotRunning ? AppTheme.warningColor : Colors.white54), const SizedBox(width: 5), _compactSignal('M', bot.isBotRunning ? 'ACTIVE' : 'WAIT', bot.isBotRunning ? AppTheme.successColor : Colors.white54), const SizedBox(width: 5), _compactSignal('B', bot.currentPosition ?? 'NEUTRAL', bot.currentPosition == 'BUY' ? AppTheme.successColor : bot.currentPosition == 'SELL' ? AppTheme.errorColor : AppTheme.accentColor)]))]));

  Widget _positionCard(BotProvider bot) {
    final active = bot.activeTrades;
    final trailing = bot.trailingTrades;
    final rowCount = math.max(active.length, trailing.length);
    return _panel(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const Text('ACTIVE ENGINE', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.1)), const Spacer(), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(color: bot.isBotRunning ? AppTheme.successColor.withOpacity(.10) : Colors.white.withOpacity(.04), borderRadius: BorderRadius.circular(10), border: Border.all(color: bot.isBotRunning ? AppTheme.successColor.withOpacity(.30) : AppTheme.darkBorder)), child: Text(bot.isBotRunning ? 'LIVE • CYCLE ${bot.engineCycle}' : 'STANDBY', style: TextStyle(color: bot.isBotRunning ? AppTheme.successColor : Colors.white38, fontSize: 8, fontWeight: FontWeight.w900)))]), const SizedBox(height: 12), _engineHeader(), const SizedBox(height: 5), if (rowCount == 0) _emptyEngine() else ...List.generate(rowCount, (index) => _engineRow(index, index < active.length ? active[index] : null, index < trailing.length ? trailing[index] : null)), const SizedBox(height: 10), Row(children: [const Icon(Icons.sync_rounded, size: 13, color: AppTheme.accentColor), const SizedBox(width: 6), Text(bot.isBotRunning ? 'Live state • switches automatically on every trigger' : 'Start miner to activate the dynamic engine', style: const TextStyle(color: Colors.white30, fontSize: 9))]) ]));
  }

  Widget _engineHeader() => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), decoration: BoxDecoration(color: Colors.white.withOpacity(.025), borderRadius: BorderRadius.circular(10)), child: const Row(children: [Expanded(child: Text('ACTIVE', style: TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1))), Expanded(child: Text('TRAILING', style: TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1)))]));

  Widget _engineRow(int index, DynamicTradeRow? active, DynamicTradeRow? trailing) => Container(margin: const EdgeInsets.only(top: 5), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), decoration: BoxDecoration(color: Colors.white.withOpacity(.018), borderRadius: BorderRadius.circular(11), border: Border.all(color: AppTheme.darkBorder)), child: Row(children: [Expanded(child: _tradeCell(active, true, index)), Expanded(child: _tradeCell(trailing, false, index))]));

  Widget _tradeCell(DynamicTradeRow? trade, bool active, int index) {
    if (trade == null) return const Text('—', style: TextStyle(color: Colors.white24, fontSize: 12));
    final buy = trade.direction == 'BUY';
    final color = buy ? AppTheme.successColor : AppTheme.errorColor;
    final title = active ? 'Entry ${index + 1} ${trade.direction.toLowerCase()}' : '${trade.direction[0]}${trade.direction.substring(1).toLowerCase()} ${index + 1}';
    final price = active ? trade.entryPrice : trade.price;
    return Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color, boxShadow: [BoxShadow(color: color.withOpacity(.45), blurRadius: 7)])), const SizedBox(width: 7), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900)), if (price != null) Text(price.toStringAsFixed(2), style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.w700))]))]);
  }

  Widget _emptyEngine() => Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 22), child: Column(children: [const Icon(Icons.swap_vert_rounded, color: Colors.white24, size: 28), const SizedBox(height: 6), const Text('No active / trailing pair yet', style: TextStyle(color: Colors.white30, fontSize: 9)), const SizedBox(height: 3), Text('The next trigger creates the first active + opposite trailing pair.', style: TextStyle(color: Colors.white.withOpacity(.12), fontSize: 8))]));

  Widget _compactSignal(String label, String value, Color color) => Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(.07), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(.20))), child: Text('$label:$value', style: TextStyle(color: color, fontSize: 7, fontWeight: FontWeight.w900)));

  Widget _botControl(BotProvider bot) {
    final running = bot.isBotRunning;
    return Row(children: [
      Expanded(child: _RippleActionButton(
        label: 'START MINER',
        icon: Icons.play_arrow_rounded,
        color: AppTheme.successColor,
        active: running,
        enabled: !running,
        onTap: () => bot.startBot(),
      )),
      const SizedBox(width: 10),
      Expanded(child: _RippleActionButton(
        label: 'STOP MINER',
        icon: Icons.stop_rounded,
        color: AppTheme.errorColor,
        active: running,
        enabled: running,
        onTap: () => bot.stopBot(),
      )),
    ]);
  }

  Widget _panel({required Widget child, EdgeInsets padding = const EdgeInsets.all(16)}) => Container(padding: padding, decoration: BoxDecoration(color: AppTheme.darkSurface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.darkBorder)), child: child);
  Widget _badge(String text, Color color) => Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(.30))), child: Text(text, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: .6)));
  Widget _metric(String label, String value, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900))]);
}



/// Animated dashboard-only visualisation. It reflects the bot's running state;
/// it does not create market data or alter trading decisions.
class _LiveTradingChronometer extends StatefulWidget {
  const _LiveTradingChronometer({required this.isRunning});
  final bool isRunning;

  @override
  State<_LiveTradingChronometer> createState() => _LiveTradingChronometerState();
}

class _LiveTradingChronometerState extends State<_LiveTradingChronometer>
    with TickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  @override
  void dispose() {
    _motion.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final green = AppTheme.successColor;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF03100D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: green.withOpacity(.28)),
        boxShadow: [BoxShadow(color: green.withOpacity(.055), blurRadius: 22, spreadRadius: 1)],
      ),
      child: Column(children: [
        Row(children: [
          Icon(Icons.timelapse_rounded, size: 17, color: green),
          const SizedBox(width: 8),
          const Expanded(child: Text('LIVE TRADING CHRONOMETER',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.05))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: (widget.isRunning ? green : Colors.white24).withOpacity(.09),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: (widget.isRunning ? green : Colors.white24).withOpacity(.28)),
            ),
            child: Text(widget.isRunning ? 'ENGINE LIVE' : 'STANDBY',
              style: TextStyle(color: widget.isRunning ? green : Colors.white38, fontSize: 8, fontWeight: FontWeight.w900)),
          ),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 178,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: Listenable.merge([_motion, _pulse]),
            builder: (context, _) => CustomPaint(
              painter: _ChronometerPainter(
                rotation: _motion.value * math.pi * 2,
                pulse: _pulse.value,
                active: widget.isRunning,
                color: green,
              ),
              child: Center(
                child: Container(
                  width: 82, height: 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF03100D),
                    border: Border.all(color: green.withOpacity(widget.isRunning ? .95 : .3), width: 2),
                    boxShadow: widget.isRunning ? [BoxShadow(color: green.withOpacity(.35), blurRadius: 22, spreadRadius: 2)] : const [],
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.bolt_rounded, color: widget.isRunning ? green : Colors.white30, size: 27),
                    Text(widget.isRunning ? 'LIVE' : 'IDLE',
                      style: TextStyle(color: widget.isRunning ? green : Colors.white38, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                  ]),
                ),
              ),
            ),
          ),
        ),
        Row(children: [
          Expanded(child: _pulseLegend(green, 'ENGINE PULSE', widget.isRunning ? '1 pulse / sec' : 'Paused')),
          Container(width: 1, height: 28, color: green.withOpacity(.18)),
          Expanded(child: _pulseLegend(green, 'GEAR MOTION', widget.isRunning ? 'In motion' : 'Standby'),),
        ]),
      ]),
    );
  }

  Widget _pulseLegend(Color color, String title, String value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: .6)),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(color: widget.isRunning ? color : Colors.white38, fontSize: 11, fontWeight: FontWeight.w800)),
    ]),
  );
}

class _ChronometerPainter extends CustomPainter {
  _ChronometerPainter({required this.rotation, required this.pulse, required this.active, required this.color});
  final double rotation;
  final double pulse;
  final bool active;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width * .36, size.height * .43);
    final dim = active ? color : Colors.white24;
    final base = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2..color = dim.withOpacity(active ? .25 : .12);
    for (var i = 0; i < 4; i++) {
      canvas.drawCircle(center, radius * (.55 + i * .15), base);
    }
    if (active) {
      for (var i = 0; i < 3; i++) {
        final phase = (pulse + i / 3) % 1.0;
        final ripple = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8 * (1 - phase) + .3
          ..color = color.withOpacity((1 - phase) * .55);
        canvas.drawCircle(center, radius * (.42 + phase * .62), ripple);
      }
    }
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    for (var i = 0; i < 24; i++) {
      final angle = i * math.pi / 12;
      final p = Paint()..color = dim.withOpacity(active ? (i % 3 == 0 ? .95 : .48) : .22)..strokeWidth = i % 3 == 0 ? 3.2 : 1.4..strokeCap = StrokeCap.round;
      final inner = radius * .78;
      final outer = radius * (i % 3 == 0 ? .96 : .89);
      canvas.drawLine(
        Offset(math.cos(angle) * inner, math.sin(angle) * inner),
        Offset(math.cos(angle) * outer, math.sin(angle) * outer), p);
    }
    final arcPaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 3.5..strokeCap = StrokeCap.round..color = dim.withOpacity(active ? .95 : .22);
    canvas.drawArc(Rect.fromCircle(center: Offset.zero, radius: radius * .72), rotation * .25, math.pi * 1.35, false, arcPaint);
    canvas.restore();

    // Small gear wheels around the core, rotating at different apparent speeds.
    for (var i = 0; i < 3; i++) {
      final angle = rotation * (i.isEven ? 1 : -0.72) + i * math.pi * 2 / 3;
      final offset = Offset(center.dx + math.cos(angle) * radius * .48, center.dy + math.sin(angle) * radius * .48);
      final gearRadius = radius * (i == 1 ? .18 : .145);
      final gearPaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = dim.withOpacity(active ? .75 : .2);
      canvas.drawCircle(offset, gearRadius, gearPaint);
      for (var tooth = 0; tooth < 8; tooth++) {
        final a = angle + tooth * math.pi / 4;
        canvas.drawLine(
          Offset(offset.dx + math.cos(a) * gearRadius * .8, offset.dy + math.sin(a) * gearRadius * .8),
          Offset(offset.dx + math.cos(a) * gearRadius * 1.22, offset.dy + math.sin(a) * gearRadius * 1.22),
          gearPaint..strokeCap = StrokeCap.round,
        );
      }
      canvas.drawCircle(offset, gearRadius * .34, Paint()..color = dim.withOpacity(active ? .55 : .15));
    }
    canvas.drawCircle(center, radius * .39, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = dim.withOpacity(active ? .65 : .2));
  }

  @override
  bool shouldRepaint(covariant _ChronometerPainter oldDelegate) =>
      oldDelegate.rotation != rotation || oldDelegate.pulse != pulse || oldDelegate.active != active || oldDelegate.color != color;
}

class _RippleActionButton extends StatefulWidget {
  const _RippleActionButton({required this.label, required this.icon, required this.color, required this.active, required this.enabled, required this.onTap});
  final String label;
  final IconData icon;
  final Color color;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_RippleActionButton> createState() => _RippleActionButtonState();
}

class _RippleActionButtonState extends State<_RippleActionButton> with SingleTickerProviderStateMixin {
  late final AnimationController _ripple = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();

  @override
  void dispose() {
    _ripple.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    return GestureDetector(
      onTap: widget.enabled ? widget.onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 84,
        decoration: BoxDecoration(
          color: color.withOpacity(widget.enabled ? .075 : .025),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: color.withOpacity(widget.enabled ? .65 : .2)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(21),
          child: AnimatedBuilder(
            animation: _ripple,
            builder: (context, _) => Stack(fit: StackFit.expand, children: [
              CustomPaint(painter: _ButtonRipplePainter(progress: _ripple.value, color: color, enabled: widget.enabled)),
              Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(widget.icon, size: 26, color: color.withOpacity(widget.enabled ? 1 : .35)),
                const SizedBox(width: 7),
                Flexible(child: Text(widget.label, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color.withOpacity(widget.enabled ? 1 : .4), fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: .7))),
              ])),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ButtonRipplePainter extends CustomPainter {
  _ButtonRipplePainter({required this.progress, required this.color, required this.enabled});
  final double progress;
  final Color color;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    if (!enabled) return;
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.sqrt(size.width * size.width + size.height * size.height) * .62;
    for (var i = 0; i < 3; i++) {
      final phase = (progress + i / 3) % 1.0;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = color.withOpacity((1 - phase) * .22);
      canvas.drawCircle(center, maxRadius * phase, paint);
    }
    final line = Paint()..color = color.withOpacity(.5)..strokeWidth = 1;
    for (var i = 0; i < 9; i++) {
      final x = size.width * i / 8;
      canvas.drawCircle(Offset(x, size.height / 2), 1.2 + (i % 3) * .25, line);
    }
  }

  @override
  bool shouldRepaint(covariant _ButtonRipplePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color || oldDelegate.enabled != enabled;
}

class _MarketPainter extends CustomPainter { final double seed; _MarketPainter({required this.seed}); @override void paint(Canvas canvas, Size size) { final paint = Paint()..color = AppTheme.accentColor.withOpacity(.75)..strokeWidth = 2.0..style = PaintingStyle.stroke; final path = Path(); final random = math.Random(seed.abs().toInt() + 7); final points = <Offset>[]; for (var i = 0; i < 32; i++) { final x = size.width * i / 31; final noise = (random.nextDouble() - .5) * 18; final trend = (seed >= 0 ? -1 : 1) * i * .8; final y = size.height * .55 + noise + trend; points.add(Offset(x, y.clamp(8, size.height - 8))); } path.moveTo(points.first.dx, points.first.dy); for (var i = 1; i < points.length; i++) { path.lineTo(points[i].dx, points[i].dy); } canvas.drawPath(path, paint); } @override bool shouldRepaint(covariant _MarketPainter oldDelegate) => oldDelegate.seed != seed; }