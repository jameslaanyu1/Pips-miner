import 'package:flutter/material.dart';

import '../providers/bot_provider.dart';
import '../services/secure_storage_service.dart';
import '../theme/app_theme.dart';

class BrokerAwareSymbolSection extends StatefulWidget {
  final BotProvider bot;

  const BrokerAwareSymbolSection({super.key, required this.bot});

  @override
  State<BrokerAwareSymbolSection> createState() => _BrokerAwareSymbolSectionState();
}

class _BrokerAwareSymbolSectionState extends State<BrokerAwareSymbolSection> {
  final SecureStorageService _storage = SecureStorageService();
  final TextEditingController _searchController = TextEditingController();
  List<String> _symbols = const [];
  bool _loading = false;
  String? _error;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.bot.addListener(_botChanged);
    if (widget.bot.isConnected) _loadSymbols();
  }

  void _botChanged() {
    if (widget.bot.isConnected && !_loaded && !_loading) _loadSymbols();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.bot.removeListener(_botChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSymbols() async {
    if (!widget.bot.isConnected || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final symbols = await widget.bot.availableSymbols();
      if (!mounted) return;
      setState(() {
        _symbols = symbols;
        _loaded = true;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load symbols directly from MetaApi: $e';
        });
      }
    }
  }

  List<String> _filteredSymbols(String query) {
    final normalized = query.trim().toUpperCase();
    if (normalized.isEmpty) return _symbols.take(40).toList();
    final aliases = <String, List<String>>{
      'GOLD': ['XAU'],
      'SILVER': ['XAG'],
      'OIL': ['OIL', 'WTI', 'BRENT', 'XBR', 'XTI'],
      'BITCOIN': ['BTC'],
      'ETHEREUM': ['ETH'],
      'NASDAQ': ['NAS', 'USTEC', 'NDX'],
      'SP500': ['SPX', 'US500', 'SP500'],
      'DOW': ['DJ', 'US30', 'DOW'],
    };
    final terms = aliases[normalized] ?? [normalized];
    return _symbols.where((symbol) => terms.any(symbol.contains)).take(60).toList();
  }

  Future<void> _selectSymbol(String symbol) async {
    final normalized = symbol.trim().toUpperCase();
    if (normalized.isEmpty || widget.bot.isBotRunning) return;
    widget.bot.updateSettings(symbol: normalized);
    _searchController.text = normalized;
    _searchController.selection = TextSelection.collapsed(offset: normalized.length);
    await _storage.saveTradingSymbol(normalized);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.bot.symbol.toUpperCase();
    final results = _filteredSymbols(_searchController.text);
    final connected = widget.bot.isConnected;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.swap_horiz_rounded, size: 17, color: AppTheme.primaryColor),
              SizedBox(width: 8),
              Text('SYMBOL SWITCH', style: TextStyle(fontSize: 9.5, letterSpacing: 1.1, fontWeight: FontWeight.w800, color: Colors.white54)),
            ]),
            const SizedBox(height: 13),
            TextField(
              controller: _searchController,
              enabled: connected && !widget.bot.isBotRunning,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'SEARCH METAAPI SYMBOLS',
                hintText: 'Gold, EURUSD, XAUUSD.a, etc.',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  tooltip: 'Refresh MetaApi symbols',
                  onPressed: connected && !widget.bot.isBotRunning && !_loading ? _loadSymbols : null,
                  icon: _loading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh_rounded),
                ),
              ),
            ),
            const SizedBox(height: 11),
            if (selected.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primaryColor.withOpacity(.25)),
                ),
                child: Row(children: [
                  const Icon(Icons.check_circle_outline, size: 17, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  const Text('SELECTED', style: TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(selected, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900))),
                ]),
              ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AppTheme.errorColor, fontSize: 9.5)),
            ],
            if (connected && _symbols.isNotEmpty) ...[
              const SizedBox(height: 11),
              if (results.isEmpty)
                const Text('No matching symbol was found on this account.', style: TextStyle(color: Colors.white38, fontSize: 10))
              else
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: results.map((symbol) {
                    final isSelected = symbol == selected;
                    return ChoiceChip(
                      label: Text(symbol),
                      selected: isSelected,
                      onSelected: widget.bot.isBotRunning ? null : (_) => _selectSymbol(symbol),
                      selectedColor: AppTheme.primaryColor.withOpacity(.18),
                      backgroundColor: AppTheme.darkSurfaceVariant,
                      side: BorderSide(color: isSelected ? AppTheme.primaryColor.withOpacity(.55) : AppTheme.darkBorder),
                      labelStyle: TextStyle(color: isSelected ? AppTheme.primaryColor : Colors.white54, fontSize: 10, fontWeight: FontWeight.w800),
                    );
                  }).toList(),
                ),
            ],
            if (!connected)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('Connect MetaApi to load the symbols available on your trading account.', style: TextStyle(color: Colors.white30, fontSize: 9.5)),
              ),
          ],
        ),
      ),
    );
  }
}
