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
    if (plan == null) return;
    await _parser.saveApprovedPlan(plan);
    if (mounted) setState(() => _approved = true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('IV OPTIONS ZONES')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Import an options PDF or screenshot. Check every extracted level before approving it for the bot.', style: TextStyle(height: 1.4)),
      const SizedBox(height: 14),
      FilledButton.icon(onPressed: _busy ? null : _pickAndParse, icon: const Icon(Icons.upload_file), label: Text(_busy ? 'Reading file…' : 'Choose PDF / screenshot')),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
      if (_plan != null) ...[
        const SizedBox(height: 18),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Reference price: ${_plan!.referencePrice.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          if (_plan!.expiry != null) Text('Detected expiry: ${_plan!.expiry}'),
          const SizedBox(height: 8),
          const Text('Review levels (automatically inferred from detected strikes):', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          ..._plan!.zones.map((z) => ListTile(
            dense: true,
            leading: Icon(z.isResistance ? Icons.trending_up : Icons.trending_down, color: z.isResistance ? Colors.redAccent : Colors.green),
            title: Text(z.isResistance ? 'Resistance ${z.label}' : 'Support ${z.label}'),
            trailing: Text(z.price.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
          )),
          const SizedBox(height: 8),
          const Text('This first parser version extracts text and ranks nearby strikes; it does not infer options-market positioning from delta/IV alone. Confirm the levels against the source before enabling them.', style: TextStyle(fontSize: 12, color: Colors.orangeAccent)),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: _approve, icon: const Icon(Icons.verified), label: const Text('Approve and save zones')),
          if (_approved) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Zones saved. The IV-zone scalping plan will guide entries while the bot is running.', style: TextStyle(color: Colors.greenAccent))),
        ]))),
      ],
    ]),
  );
}
