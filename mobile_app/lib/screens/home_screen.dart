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
    return Consumer<BotProvider>(builder: (context, bot, _) => Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(bot),
          const SizedBox(height: 30),
          _accountOverview(bot),
          const SizedBox(height: 24),
          _marketOverview(bot),
          const SizedBox(height: 26),
          _EngineChronometer(running: bot.isBotRunning, cycle: bot.engineCycle, activeTrades: bot.activeTrades, trailingTrades: bot.trailingTrades),
          const SizedBox(height: 24),
          _botControl(bot),
          const SizedBox(height: 20),
          _ivOptionsButton(context),
        ]),
      )),
    ));
  }

  Widget _accountOverview(BotProvider bot) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [const Text('ACCOUNT EQUITY', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5)), const Spacer(), Text(bot.isLiveAccount ? 'LIVE ACCOUNT' : 'DEMO ACCOUNT', style: TextStyle(color: bot.isLiveAccount ? AppTheme.warningColor : AppTheme.secondaryColor, fontSize: 9, fontWeight: FontWeight.w900))]),
    const SizedBox(height: 7),
    Text('Ksh ${bot.balance.toStringAsFixed(2)}', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1.2)),
    const SizedBox(height: 17),
    Row(children: [
      Expanded(child: _metric('P/L', 'Ksh ${bot.profitLoss >= 0 ? '+' : ''}${bot.profitLoss.toStringAsFixed(2)}', bot.profitLoss >= 0 ? AppTheme.successColor : AppTheme.errorColor)),
      Expanded(child: _metric('TRADES', '${bot.totalTrades}', Colors.white)),
      Expanded(child: _metric('WIN RATE', '${bot.winRate.toStringAsFixed(1)}%', AppTheme.accentColor)),
    ]),
    const SizedBox(height: 18), Container(height: 1, color: Colors.white12),
  ]);

  Widget _marketOverview(BotProvider bot) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Text(bot.symbol.toUpperCase(), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: .8)), const Spacer(), Text(bot.priceChange >= 0 ? '+${bot.priceChange.toStringAsFixed(2)}%' : '${bot.priceChange.toStringAsFixed(2)}%', style: TextStyle(color: bot.priceChange >= 0 ? AppTheme.successColor : AppTheme.errorColor, fontWeight: FontWeight.w800, fontSize: 12))]),
    const SizedBox(height: 8),
    SizedBox(height: 100, width: double.infinity, child: CustomPaint(painter: _MarketPainter(seed: bot.priceChange))),
    const SizedBox(height: 7),
    Row(children: [Icon(Icons.radar_rounded, size: 14, color: bot.isBotRunning ? const Color(0xFF39FF75) : AppTheme.accentColor), const SizedBox(width: 7), Text(bot.isBotRunning ? 'ENGINE SCANNING' : 'ENGINE STANDBY', style: TextStyle(color: bot.isBotRunning ? const Color(0xFF39FF75) : Colors.white38, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)), const Spacer(), const Text('1 MIN / VOLATILITY + MOMENTUM', style: TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.w700))]),
    const SizedBox(height: 18), Container(height: 1, color: Colors.white12),
  ]);

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

  Widget _botControl(BotProvider bot) => Row(children: [
    Expanded(child: _PulseButton(label: 'START MINER', startAction: true, enabled: !bot.isBotRunning, onTap: bot.isBotRunning ? null : () { bot.startBot(); })),
    const SizedBox(width: 18),
    Expanded(child: _PulseButton(label: 'STOP MINER', startAction: false, enabled: bot.isBotRunning, onTap: bot.isBotRunning ? () { bot.stopBot(); } : null)),
  ]);

  Widget _panel({required Widget child, EdgeInsets padding = const EdgeInsets.all(16)}) => Container(padding: padding, decoration: BoxDecoration(color: AppTheme.darkSurface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.darkBorder)), child: child);
  Widget _badge(String text, Color color) => Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(.30))), child: Text(text, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: .6)));
  Widget _metric(String label, String value, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900))]);
}


class _PulseButton extends StatefulWidget {
  const _PulseButton({required this.label, required this.startAction, required this.enabled, required this.onTap});
  final String label;
  final bool startAction;
  final bool enabled;
  final VoidCallback? onTap;
  @override State<_PulseButton> createState() => _PulseButtonState();
}

class _PulseButtonState extends State<_PulseButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
  @override void dispose() { _pulse.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final color = widget.startAction ? const Color(0xFF39FF75) : const Color(0xFFFF334F);
    return AnimatedBuilder(animation: _pulse, builder: (context, _) {
      return GestureDetector(onTap: widget.onTap, child: SizedBox(height: 126, child: Stack(alignment: Alignment.center, children: [
        for (var ring = 0; ring < 3; ring++)
          Transform.scale(scale: 1 + ((_pulse.value + ring / 3) % 1) * .42,
            child: Container(width: 78, height: 78, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color.withOpacity(widget.enabled ? (1 - ((_pulse.value + ring / 3) % 1)) * .30 : .04), width: 1.4)))),
        Container(width: 82, height: 82, decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: color.withOpacity(widget.enabled ? .18 : .02), blurRadius: 24, spreadRadius: 2)])),
        Container(width: 72, height: 72, decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(widget.enabled ? .11 : .025), border: Border.all(color: color.withOpacity(widget.enabled ? .95 : .20), width: 1.8), boxShadow: [BoxShadow(color: color.withOpacity(widget.enabled ? .24 : .02), blurRadius: 18)]), child: Icon(widget.startAction ? Icons.play_arrow_rounded : Icons.stop_rounded, color: color.withOpacity(widget.enabled ? 1 : .32), size: 36)),
        Positioned(bottom: 0, child: Column(children: [
          Text(widget.label, style: TextStyle(color: color.withOpacity(widget.enabled ? 1 : .36), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
          const SizedBox(height: 4),
          Text(widget.startAction ? (widget.enabled ? 'TAP TO START' : 'ENGINE ACTIVE') : (widget.enabled ? 'TAP TO STOP' : 'ENGINE OFF'), style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: .8)),
        ])),
      ])));
    });
  }
}

class _EngineChronometer extends StatefulWidget {
  const _EngineChronometer({required this.running, required this.cycle, required this.activeTrades, required this.trailingTrades});
  final bool running;
  final int cycle;
  final List<DynamicTradeRow> activeTrades;
  final List<DynamicTradeRow> trailingTrades;
  @override State<_EngineChronometer> createState() => _EngineChronometerState();
}

class _EngineChronometerState extends State<_EngineChronometer> {
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  @override void initState() { super.initState(); if (widget.running) _startedAt = DateTime.now(); }
  @override void didUpdateWidget(covariant _EngineChronometer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.running && !oldWidget.running) { _startedAt = DateTime.now(); _elapsed = Duration.zero; }
    if (!widget.running && oldWidget.running && _startedAt != null) _elapsed = DateTime.now().difference(_startedAt!);
  }
  String _format(Duration d) => '${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  @override Widget build(BuildContext context) {
    final color = widget.running ? const Color(0xFF39FF75) : Colors.white38;
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.memory_rounded, color: color, size: 15), const SizedBox(width: 7), Text('ACTIVE ENGINE', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)), const SizedBox(width: 8), Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color.withOpacity(.7), blurRadius: 8)]))]),
      const SizedBox(height: 12),
      StreamBuilder<int>(stream: Stream<int>.periodic(const Duration(seconds: 1), (n) => n), initialData: 0, builder: (context, snapshot) {
        final elapsed = widget.running && _startedAt != null ? DateTime.now().difference(_startedAt!) : _elapsed;
        return Text(_format(elapsed), style: TextStyle(color: color, fontSize: 35, fontWeight: FontWeight.w300, letterSpacing: 4, fontFamily: 'monospace', shadows: widget.running ? [Shadow(color: color.withOpacity(.38), blurRadius: 20)] : null));
      }),
      const SizedBox(height: 6),
      Text(widget.running ? 'ENGINE RUNNING • LIVE CHRONOMETER' : 'ENGINE STOPPED • CHRONOMETER PAUSED', style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
      const SizedBox(height: 15),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _readout('CYCLE', '${widget.cycle}'), Container(width: 1, height: 27, color: Colors.white12, margin: const EdgeInsets.symmetric(horizontal: 22)),
        _readout('ACTIVE', '${widget.activeTrades.length}'), Container(width: 1, height: 27, color: Colors.white12, margin: const EdgeInsets.symmetric(horizontal: 22)),
        _readout('TRAILING', '${widget.trailingTrades.length}'),
      ]),
      if (widget.activeTrades.isNotEmpty || widget.trailingTrades.isNotEmpty) ...[
        const SizedBox(height: 13),
        Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 7, children: [
          ...widget.activeTrades.map((t) => Text('● ${t.direction} ${t.entryPrice?.toStringAsFixed(2) ?? ''}', style: TextStyle(color: t.direction == 'BUY' ? const Color(0xFF39FF75) : const Color(0xFFFF334F), fontSize: 9, fontWeight: FontWeight.w800))),
          ...widget.trailingTrades.map((t) => Text('○ ${t.direction} ${t.price?.toStringAsFixed(2) ?? ''}', style: TextStyle(color: t.direction == 'BUY' ? const Color(0xFF39FF75) : const Color(0xFFFF334F), fontSize: 9, fontWeight: FontWeight.w700))),
        ]),
      ],
    ]);
  }
  Widget _readout(String label, String value) => Column(children: [Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(label, style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1.2))]);
}

class _MarketPainter extends CustomPainter { final double seed; _MarketPainter({required this.seed}); @override void paint(Canvas canvas, Size size) { final paint = Paint()..color = AppTheme.accentColor.withOpacity(.75)..strokeWidth = 2.0..style = PaintingStyle.stroke; final path = Path(); final random = math.Random(seed.abs().toInt() + 7); final points = <Offset>[]; for (var i = 0; i < 32; i++) { final x = size.width * i / 31; final noise = (random.nextDouble() - .5) * 18; final trend = (seed >= 0 ? -1 : 1) * i * .8; final y = size.height * .55 + noise + trend; points.add(Offset(x, y.clamp(8, size.height - 8))); } path.moveTo(points.first.dx, points.first.dy); for (var i = 1; i < points.length; i++) { path.lineTo(points[i].dx, points[i].dy); } canvas.drawPath(path, paint); } @override bool shouldRepaint(covariant _MarketPainter oldDelegate) => oldDelegate.seed != seed; }