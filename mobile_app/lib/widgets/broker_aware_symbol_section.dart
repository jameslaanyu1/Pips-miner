import 'dart:async';
import 'package:flutter/material.dart';
import '../providers/bot_provider.dart';
import '../services/secure_storage_service.dart';
import '../theme/app_theme.dart';

class BrokerAwareSymbolSection extends StatefulWidget {
  final BotProvider bot;
  final TextEditingController brokerController;
  final TextEditingController serverController;
  const BrokerAwareSymbolSection({super.key, required this.bot, required this.brokerController, required this.serverController});
  @override
  State<BrokerAwareSymbolSection> createState() => _BrokerAwareSymbolSectionState();
}

class _BrokerAwareSymbolSectionState extends State<BrokerAwareSymbolSection> {
  final SecureStorageService _storage = SecureStorageService();
  final TextEditingController _search = TextEditingController();
  List<String> _symbols = const [];
  bool _loading = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    widget.bot.addListener(_changed);
    if (widget.bot.isConnected) unawaited(_load());
  }
  void _changed() {
    if (widget.bot.isConnected && _symbols.isEmpty && !_loading) unawaited(_load());
    if (mounted) setState(() {});
  }
  @override
  void dispose() {
    widget.bot.removeListener(_changed);
    _search.dispose();
    super.dispose();
  }
  Future<void> _load() async {
    if (!widget.bot.isConnected || _loading) return;
    setState(() { _loading = true; _error = null; });
    try {
      final values = await widget.bot.availableSymbols();
      if (!mounted) return;
      setState(() { _symbols = values; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }
  Future<void> _select(String symbol) async {
    if (widget.bot.isBotRunning) return;
    widget.bot.updateSettings(symbol: symbol);
    await _storage.saveTradingSymbol(symbol);
    if (mounted) setState(() { _search.text = symbol; });
  }
  @override
  Widget build(BuildContext context) {
    final selected = widget.bot.symbol.toUpperCase();
    final query = _search.text.trim().toUpperCase();
    final results = _symbols.where((s) => query.isEmpty || s.contains(query)).take(60).toList();
    return Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [Icon(Icons.swap_horiz_rounded, size: 17, color: AppTheme.primaryColor), SizedBox(width: 8), Text('SYMBOL SWITCH', style: TextStyle(fontSize: 9.5, letterSpacing: 1.1, fontWeight: FontWeight.w800, color: Colors.white54))]),
      const SizedBox(height: 13),
      TextField(controller: _search, enabled: widget.bot.isConnected && !widget.bot.isBotRunning, textCapitalization: TextCapitalization.characters, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: 'SEARCH METAAPI SYMBOLS', hintText: 'XAUUSD, EURUSD, GOLD…', prefixIcon: const Icon(Icons.search_rounded), suffixIcon: IconButton(tooltip: 'Refresh symbols', onPressed: widget.bot.isConnected && !widget.bot.isBotRunning && !_loading ? _load : null, icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded)))),
      const SizedBox(height: 11),
      Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.primaryColor.withOpacity(.25))), child: Row(children: [const Text('SELECTED', style: TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.w800)), const SizedBox(width: 8), Expanded(child: Text(selected, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)))])),
      if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: const TextStyle(color: AppTheme.errorColor, fontSize: 9.5))],
      if (widget.bot.isConnected && _symbols.isNotEmpty) ...[const SizedBox(height: 11), if (results.isEmpty) const Text('No matching symbol on this MetaApi account.', style: TextStyle(color: Colors.white38, fontSize: 10)) else Wrap(spacing: 7, runSpacing: 7, children: results.map((symbol) { final isSelected = symbol == selected; return ChoiceChip(label: Text(symbol), selected: isSelected, onSelected: widget.bot.isBotRunning ? null : (_) => _select(symbol), selectedColor: AppTheme.primaryColor.withOpacity(.18), backgroundColor: AppTheme.darkSurfaceVariant, side: BorderSide(color: isSelected ? AppTheme.primaryColor.withOpacity(.55) : AppTheme.darkBorder), labelStyle: TextStyle(color: isSelected ? AppTheme.primaryColor : Colors.white54, fontSize: 10, fontWeight: FontWeight.w800)); }).toList())],
      if (!widget.bot.isConnected) const Padding(padding: EdgeInsets.only(top: 10), child: Text('Connect MetaApi to load this account’s symbols.', style: TextStyle(color: Colors.white30, fontSize: 9.5))),
    ])));
  }
}
