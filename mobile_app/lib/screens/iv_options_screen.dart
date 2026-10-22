import 'dart:io';

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

  List<List<String>> _extractedRows(String source) {
    final lines = source
        .replaceAll('\r', '')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return lines.map((line) {
      // Preserve columns when OCR/PDF extraction exposes tabs or aligned spacing.
      var cells = line.split(RegExp(r'\\t+|\\s{2,}')).map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
      // ML Kit sometimes collapses table spacing to single spaces; retain all
      // recognized values as cells rather than dropping the line.
      if (cells.length < 2) cells = line.split(RegExp(r'\\s+')).where((v) => v.isNotEmpty).toList();
      return cells;
    }).toList();
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
          const SizedBox(height: 14),
          const Text('EXTRACTED FILE CONTENTS', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Builder(builder: (context) {
            final rows = _extractedRows(_plan!.sourceText);
            final columnCount = rows.fold<int>(0, (max, row) => row.length > max ? row.length : max);
            if (rows.isEmpty || columnCount == 0) {
              return const Text('No readable rows were extracted from this file.');
            }
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: List.generate(columnCount, (index) => DataColumn(
                  label: Text(index == 0 ? 'Content / column 1' : 'Column ${index + 1}'),
                )),
                rows: rows.map((row) => DataRow(
                  cells: List.generate(columnCount, (index) => DataCell(
                    Text(index < row.length ? row[index] : '—'),
                  )),
                )).toList(),
              ),
            );
          }),
          const SizedBox(height: 10),
          Text('Reference price: ${_plan!.referencePrice.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
 ${_plan!.referencePrice.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          if (_plan!.expiry != null) Text('Detected expiry: ${_plan!.expiry}'),
          const SizedBox(height: 12),
          // The middle strike is shown separately in amber and is not a support/resistance zone.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.14),
              border: Border.all(color: Colors.amber, width: 1.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              const Icon(Icons.adjust, color: Colors.amber, size: 26),
              const SizedBox(width: 10),
              const Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('PIVOT — MIDDLE STRIKE', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                  SizedBox(height: 3),
                  Text('Reference level only; excluded from the six zones.', style: TextStyle(fontSize: 12)),
                ],
              )),
              Text(_plan!.middleStrike.toStringAsFixed(2), style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
          ),
          const SizedBox(height: 14),
          const Text('Six support/resistance zones:', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          ..._plan!.zones.map((z) => ListTile(
            dense: true,
            leading: Icon(z.isResistance ? Icons.trending_up : Icons.trending_down, color: z.isResistance ? Colors.redAccent : Colors.green),
            title: Text(z.isResistance ? 'Resistance ${z.label}' : 'Support ${z.label}'),
            trailing: Text(z.price.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
          )),
          if (_plan!.strikes.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Parsed option data — seven strikes', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Strike')),
                  DataColumn(label: Text('Put Δ')),
                  DataColumn(label: Text('Put price')),
                  DataColumn(label: Text('Call price')),
                  DataColumn(label: Text('Call Δ')),
                  DataColumn(label: Text('IV')),
                ],
                rows: _plan!.strikes.map((s) => DataRow(cells: [
                  DataCell(Text(s.strike.toStringAsFixed(1))),
                  DataCell(Text(s.putDelta?.toStringAsFixed(2) ?? '—')),
                  DataCell(Text(s.putPrice?.toStringAsFixed(2) ?? '—')),
                  DataCell(Text(s.callPrice?.toStringAsFixed(2) ?? '—')),
                  DataCell(Text(s.callDelta?.toStringAsFixed(2) ?? '—')),
                  DataCell(Text(s.impliedVolatility == null ? '—' : '${s.impliedVolatility!.toStringAsFixed(2)}%')),
                ])).toList(),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Signal rule: call Δ > +0.50 and call price > put price = buy toward next higher strike; put Δ < −0.50 and put price > call price = sell toward next lower strike.', style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
          const SizedBox(height: 8),
          const Text('The saved pivot and six-zone plan are available to the bot until a new valid file replaces them.', style: TextStyle(fontSize: 12, color: Colors.greenAccent)),
        ]))),
      ],
    ]),
  );
}
