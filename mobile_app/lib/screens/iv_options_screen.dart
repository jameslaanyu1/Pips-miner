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

  static const _panel = Color(0xFF1B3040);
  static const _cell = Color(0xFF29445D);
  static const _line = Color(0xFF35536D);
  static const _text = Color(0xFFF1F5F9);
  static const _muted = Color(0xFFB7C5D2);

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

  String _number(double? value, {int digits = 2}) =>
      value == null ? '—' : value.toStringAsFixed(digits);

  Widget _groupHeader(String title, int span, {Color color = _muted}) =>
      Expanded(
        flex: span,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Text(title, textAlign: TextAlign.center,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      );

  Widget _columnHeader(String title, int flex) => Expanded(
        flex: flex,
        child: Container(
          alignment: Alignment.center,
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: _line),
              bottom: BorderSide(color: _line),
            ),
          ),
          child: Text(title, textAlign: TextAlign.center,
              style: const TextStyle(color: _text, fontSize: 11, fontStyle: FontStyle.italic)),
        ),
      );

  Widget _dataCell(String value, int flex, {bool highlighted = false}) =>
      Expanded(
        flex: flex,
        child: Container(
          alignment: Alignment.center,
          constraints: const BoxConstraints(minHeight: 49),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          decoration: BoxDecoration(
            color: highlighted ? const Color(0xFF304D68) : _cell,
            border: const Border(
              right: BorderSide(color: _line, width: 0.7),
              bottom: BorderSide(color: _line, width: 0.7),
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: const TextStyle(color: _text, fontSize: 13)),
          ),
        ),
      );

  Widget _optionsChainTable(List<OptionStrikeData> strikes) {
    if (strikes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('No complete options-chain rows were parsed. Choose a clearer screenshot or a text-based PDF.',
            style: TextStyle(color: _muted)),
      );
    }
    const flexes = [3, 3, 3, 3, 3, 3];
    return Container(
      decoration: BoxDecoration(
        color: _panel,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Row(children: [
            _groupHeader('PUT OPTIONS', 6),
            _groupHeader('STRIKE', 3, color: _text),
            _groupHeader('CALL OPTIONS', 9),
          ]),
          Row(children: [
            _columnHeader('Delta', flexes[0]),
            _columnHeader('Price', flexes[1]),
            _columnHeader('Strike', flexes[2]),
            _columnHeader('Price', flexes[3]),
            _columnHeader('Delta', flexes[4]),
            _columnHeader('Imp. Vol.', flexes[5]),
          ]),
          ...strikes.map((s) => Row(children: [
            _dataCell(_number(s.putDelta), 3),
            _dataCell(_number(s.putPrice), 3),
            _dataCell(_number(s.strike, digits: 1), 3, highlighted: true),
            _dataCell(_number(s.callPrice), 3),
            _dataCell(_number(s.callDelta), 3),
            _dataCell(s.impliedVolatility == null ? '—' : '${_number(s.impliedVolatility)}%', 3),
          ])),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('IV OPTIONS ZONES')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text(
        'Import an options PDF or screenshot. The reader extracts the values and reconstructs the options chain as a table. The latest successfully parsed file and its zones are saved on this device.',
        style: TextStyle(height: 1.4),
      ),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: _busy ? null : _pickAndParse,
        icon: const Icon(Icons.upload_file),
        label: Text(_busy ? 'Reading and parsing file…' : 'Choose PDF / screenshot'),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
        ),
      if (_plan != null) ...[
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.table_chart, color: Colors.greenAccent),
                const SizedBox(width: 8),
                const Expanded(child: Text('RECONSTRUCTED OPTIONS CHAIN',
                    style: TextStyle(fontWeight: FontWeight.bold))),
              ]),
              if (_savedFileName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(_savedFileName!,
                      style: const TextStyle(fontSize: 12, color: Colors.white70)),
                ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 510),
                  child: _optionsChainTable(_plan!.strikes),
                ),
              ),
              const SizedBox(height: 16),
              Text('Reference price: ${_plan!.referencePrice.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              if (_plan!.expiry != null) Text('Detected expiry: ${_plan!.expiry}'),
              const SizedBox(height: 12),
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
                      Text('PIVOT — MIDDLE STRIKE',
                          style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                      SizedBox(height: 3),
                      Text('Reference level only; excluded from the six zones.',
                          style: TextStyle(fontSize: 12)),
                    ],
                  )),
                  Text(_plan!.middleStrike.toStringAsFixed(2),
                      style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
                ]),
              ),
              const SizedBox(height: 14),
              const Text('Six support/resistance zones:', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              ..._plan!.zones.map((z) => ListTile(
                dense: true,
                leading: Icon(
                  z.isResistance ? Icons.trending_up : Icons.trending_down,
                  color: z.isResistance ? Colors.redAccent : Colors.green,
                ),
                title: Text(z.isResistance ? 'Resistance ${z.label}' : 'Support ${z.label}'),
                trailing: Text(z.price.toStringAsFixed(2),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              )),
              const SizedBox(height: 8),
              const Text(
                'The bot uses the saved pivot and six-zone plan until a new valid file replaces it.',
                style: TextStyle(fontSize: 12, color: Colors.greenAccent),
              ),
            ]),
          ),
        ),
      ],
    ]),
  );
}
