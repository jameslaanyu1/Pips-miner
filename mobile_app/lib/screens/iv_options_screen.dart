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

  Widget _strikeRow(String label, double price, Color color, {bool pivot = false}) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color: color.withOpacity(pivot ? .16 : .055),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withOpacity(pivot ? .9 : .25), width: pivot ? 1.5 : 1),
    ),
    child: Row(children: [
      Icon(pivot ? Icons.adjust_rounded : (label.startsWith('R') ? Icons.trending_up : Icons.trending_down), color: color, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, letterSpacing: .4))),
      Text(price.toStringAsFixed(2), style: TextStyle(color: color, fontWeight: FontWeight.w900)),
      if (pivot) ...[
        const SizedBox(width: 8),
        const Icon(Icons.check_circle_outline, color: Colors.amber, size: 17),
      ],
    ]),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('IV OPTIONS ZONES')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Import an options PDF or screenshot. The latest successfully parsed file and all seven trading levels are stored on this device. A new valid file replaces the previous one.', style: TextStyle(height: 1.4)),
      const SizedBox(height: 14),
      FilledButton.icon(onPressed: _busy ? null : _pickAndParse, icon: const Icon(Icons.upload_file), label: Text(_busy ? 'Reading file…' : 'Choose PDF / screenshot')),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
      if (_plan != null) ...[
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.inventory_2_outlined, color: Colors.greenAccent),
              const SizedBox(width: 8),
              const Expanded(child: Text('Saved options file', style: TextStyle(fontWeight: FontWeight.bold))),
            ]),
            if (_savedFileName != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_savedFileName!, style: const TextStyle(fontSize: 12, color: Colors.white70))),
            const SizedBox(height: 10),
            Text('Reference price: ${_plan!.referencePrice.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            if (_plan!.expiry != null) Text('Detected expiry: ${_plan!.expiry}'),
            const SizedBox(height: 14),
            const Text('TRADING LEVELS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
            const SizedBox(height: 8),
            if (_plan!.sevenStrikes.length == 7) ...[
              _strikeRow('R3 • RESISTANCE', _plan!.sevenStrikes[6], Colors.redAccent),
              _strikeRow('R2 • RESISTANCE', _plan!.sevenStrikes[5], Colors.redAccent),
              _strikeRow('R1 • RESISTANCE', _plan!.sevenStrikes[4], Colors.redAccent),
              _strikeRow('PIVOT • TRADABLE', _plan!.sevenStrikes[3], Colors.amber, pivot: true),
              _strikeRow('S1 • SUPPORT', _plan!.sevenStrikes[2], Colors.greenAccent),
              _strikeRow('S2 • SUPPORT', _plan!.sevenStrikes[1], Colors.greenAccent),
              _strikeRow('S3 • SUPPORT', _plan!.sevenStrikes[0], Colors.greenAccent),
            ] else
              const Text('Invalid strike set: exactly seven strikes are required.', style: TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 10),
            const Text('All seven strikes are trading levels. The pivot can trigger buys on fading downward velocity above it, sells on fading upward velocity below it, and entries on confirmed momentum crosses.', style: TextStyle(fontSize: 12, color: Colors.amber)),
            const SizedBox(height: 8),
            const Text('Saved automatically. The source file and parsed levels remain available until a new valid file replaces them.', style: TextStyle(fontSize: 12, color: Colors.greenAccent)),
          ]),
        ),
      ],
    ]),
  );
}
