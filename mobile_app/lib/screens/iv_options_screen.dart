import 'package:flutter/material.dart';

import '../services/iv_options_parser.dart';

class IvOptionsScreen extends StatefulWidget {
  const IvOptionsScreen({super.key});
  @override
  State<IvOptionsScreen> createState() => _IvOptionsScreenState();
}

class _IvOptionsScreenState extends State<IvOptionsScreen> {
  final _parser = IvOptionsParser();
  OptionsZonePlan? _plan;
  bool _busy = false;
  String? _error;
  bool _approved = false;

  Future<void> _pickAndParse() async {
    setState(() { _busy = true; _error = null; _approved = false; });
    try {
      final plan = await _parser.parsePickedFile();
      if (mounted) setState(() => _plan = plan);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('FormatException: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    final plan = _plan;
    if (plan == null || plan.sevenStrikes.length != 7 || plan.pivotPrice != plan.sevenStrikes[3]) {
      setState(() => _error = 'Cannot approve: the 4th strike must be identified as the non-trading pivot.');
      return;
    }
    await _parser.saveApprovedPlan(plan);
    if (mounted) setState(() => _approved = true);
  }

  Widget _strikeRow(String label, double price, Color color, {bool pivot = false}) => Container(
    margin: const EdgeInsets.only(bottom: 5),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: color.withOpacity(pivot ? .16 : .055),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withOpacity(pivot ? .9 : .25), width: pivot ? 1.5 : 1),
    ),
    child: Row(children: [
      Icon(pivot ? Icons.horizontal_rule_rounded : (label.startsWith('R') ? Icons.trending_up : Icons.trending_down), color: color, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, letterSpacing: .4))),
      Text(price.toStringAsFixed(2), style: TextStyle(color: color, fontWeight: FontWeight.w900, fontFeatures: const [])),
      if (pivot) ...[
        const SizedBox(width: 8),
        const Icon(Icons.block, color: Colors.amber, size: 16),
      ],
    ]),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('IV OPTIONS ZONES')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Import an options PDF or screenshot. Review all seven strikes. The 4th strike is highlighted as the pivot and is never a trading level.', style: TextStyle(height: 1.4)),
      const SizedBox(height: 14),
      FilledButton.icon(onPressed: _busy ? null : _pickAndParse, icon: const Icon(Icons.upload_file), label: Text(_busy ? 'Reading file…' : 'Choose PDF / screenshot')),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
      if (_plan != null) ...[
        const SizedBox(height: 18),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Reference price: ${_plan!.referencePrice.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          if (_plan!.expiry != null) Text('Detected expiry: ${_plan!.expiry}'),
          const SizedBox(height: 12),
          const Text('SEVEN DETECTED STRIKES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
          const SizedBox(height: 8),
          if (_plan!.sevenStrikes.length == 7) ...[
            _strikeRow('R3 • RESISTANCE', _plan!.sevenStrikes[6], Colors.redAccent),
            _strikeRow('R2 • RESISTANCE', _plan!.sevenStrikes[5], Colors.redAccent),
            _strikeRow('R1 • RESISTANCE', _plan!.sevenStrikes[4], Colors.redAccent),
            _strikeRow('PIVOT • NOT TRADEABLE', _plan!.sevenStrikes[3], Colors.amber, pivot: true),
            _strikeRow('S1 • SUPPORT', _plan!.sevenStrikes[2], Colors.greenAccent),
            _strikeRow('S2 • SUPPORT', _plan!.sevenStrikes[1], Colors.greenAccent),
            _strikeRow('S3 • SUPPORT', _plan!.sevenStrikes[0], Colors.greenAccent),
          ] else
            const Text('Invalid strike set: exactly seven strikes are required.', style: TextStyle(color: Colors.redAccent)),
          const SizedBox(height: 14),
          const Text('BOT TRADING ZONES (PIVOT EXCLUDED)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
          const SizedBox(height: 6),
          ..._plan!.zones.map((z) => ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(z.isResistance ? Icons.trending_up : Icons.trending_down, color: z.isResistance ? Colors.redAccent : Colors.greenAccent),
            title: Text(z.isResistance ? 'Resistance ${z.label}' : 'Support ${z.label}'),
            trailing: Text(z.price.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
          )),
          const SizedBox(height: 8),
          const Text('The pivot is displayed for reference only. Entry and breakout decisions use the six R/S zones only.', style: TextStyle(fontSize: 12, color: Colors.amber)),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: _approve, icon: const Icon(Icons.verified), label: const Text('Approve and save zones')),
          if (_approved) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Six trading zones saved. The pivot remains non-tradeable.', style: TextStyle(color: Colors.greenAccent))),
        ]))),
      ],
    ]),
  );
}
