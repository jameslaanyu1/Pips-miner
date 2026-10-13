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
  String? _savedFileName;

  @override
  void initState() {
    super.initState();
    _restoreSavedPlan();
  }

  Future<void> _restoreSavedPlan() async {
    try {
      final saved = await _parser.loadSavedPlan();
      final fileName = await _parser.loadSavedSourceName();
      if (!mounted) return;
      setState(() {
        _plan = saved == null ? null : OptionsZonePlan.fromJson(saved);
        _savedFileName = fileName;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not restore the saved options file: $e');
    }
  }

  Future<void> _pickAndParse() async {
    setState(() { _busy = true; _error = null; });
    try {
      final plan = await _parser.parsePickedFile();
      final fileName = await _parser.loadSavedSourceName();
      if (mounted) setState(() {
        _plan = plan;
        _savedFileName = fileName;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('FormatException: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('IV OPTIONS ZONES')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Import an options PDF or screenshot. The latest successfully parsed file and its zones are saved on this device and restored when you reopen this screen. A new valid file replaces the saved one.', style: TextStyle(height: 1.4)),
      const SizedBox(height: 14),
      FilledButton.icon(onPressed: _busy ? null : _pickAndParse, icon: const Icon(Icons.upload_file), label: Text(_busy ? 'Reading file…' : 'Choose PDF / screenshot')),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
      if (_plan != null) ...[
        const SizedBox(height: 18),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.inventory_2_outlined, color: Colors.greenAccent),
            const SizedBox(width: 8),
            const Expanded(child: Text('Saved options file', style: TextStyle(fontWeight: FontWeight.bold))),
          ]),
          if (_savedFileName != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_savedFileName!, style: const TextStyle(fontSize: 12, color: Colors.white70))),
          const SizedBox(height: 10),
          Text('Reference price: ${_plan!.referencePrice.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          if (_plan!.expiry != null) Text('Detected expiry: ${_plan!.expiry}'),
          const SizedBox(height: 8),
          const Text('Six zones (the middle strike is excluded):', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          ..._plan!.zones.map((z) => ListTile(
            dense: true,
            leading: Icon(z.isResistance ? Icons.trending_up : Icons.trending_down, color: z.isResistance ? Colors.redAccent : Colors.green),
            title: Text(z.isResistance ? 'Resistance ${z.label}' : 'Support ${z.label}'),
            trailing: Text(z.price.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
          )),
          const SizedBox(height: 8),
          const Text('The saved six-zone plan is available to the bot until a new valid file replaces it.', style: TextStyle(fontSize: 12, color: Colors.greenAccent)),
        ]))),
      ],
    ]),
  );
}
