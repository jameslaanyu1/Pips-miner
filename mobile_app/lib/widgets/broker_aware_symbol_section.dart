import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../providers/bot_provider.dart';
import '../services/secure_storage_service.dart';
import '../theme/app_theme.dart';

class BrokerAwareSymbolSection extends StatefulWidget {
  final BotProvider bot;
  final TextEditingController brokerController;
  final TextEditingController serverController;

  const BrokerAwareSymbolSection({
    super.key,
    required this.bot,
    required this.brokerController,
    required this.serverController,
  });

  @override
  State<BrokerAwareSymbolSection> createState() => _BrokerAwareSymbolSectionState();
}

class _BrokerAwareSymbolSectionState extends State<BrokerAwareSymbolSection> {
  final SecureStorageService _storage = SecureStorageService();
  final TextEditingController _searchController = TextEditingController();

  List<String> _brokerSymbols = const [];
  bool _loading = false;
  String? _error;
  bool _loadedForCurrentAccount = false;
  Timer? _brokerChangeDebounce;

  @override
  void initState() {
    super.initState();
    widget.brokerController.addListener(_connectionFieldsChanged);
    widget.serverController.addListener(_connectionFieldsChanged);
    widget.bot.addListener(_botChanged);
    if (widget.bot.isConnected) unawaited(_prepareForAccount());
  }

  @override
  void didUpdateWidget(covariant BrokerAwareSymbolSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bot != widget.bot) {
      oldWidget.bot.removeListener(_botChanged);
      widget.bot.addListener(_botChanged);
    }
  }

  void _botChanged() {
    final connected = widget.bot.isConnected;
    if (connected && !_loadedForCurrentAccount && !_loading) {
      unawaited(_prepareForAccount());
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.brokerController.removeListener(_connectionFieldsChanged);
    widget.serverController.removeListener(_connectionFieldsChanged);
    widget.bot.removeListener(_botChanged);
    _brokerChangeDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _connectionFieldsChanged() {
    _brokerChangeDebounce?.cancel();
    _brokerChangeDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _loadedForCurrentAccount = false;
      _brokerSymbols = const [];
      _error = null;
      if (widget.bot.isConnected) unawaited(_prepareForAccount());
      setState(() {});
    });
  }

  String get _broker => widget.brokerController.text.trim();
  String get _server => widget.serverController.text.trim();

  Future<void> _prepareForAccount() async {
    if (!widget.bot.isConnected || _broker.isEmpty || _server.isEmpty) return;

    final saved = await _storage.getBrokerTradingSymbol(
      broker: _broker,
      server: _server,
    );

    if (!mounted) return;
    if (saved != null && saved.isNotEmpty) {
      widget.bot.updateSettings(symbol: saved);
      _searchController.text = saved;
    }

    if (!_loadedForCurrentAccount) await _loadBrokerSymbols();
  }

  Future<void> _loadBrokerSymbols() async {
    final token = await _storage.getPipsMinerSessionToken();
    if (token == null || token.trim().isEmpty) {
      if (!mounted) return;
      setState(() => _error = 'Connect the MT5 account first so the broker symbol list can be read.');
      return;
    }

    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await http.get(
        Uri.parse('https://pips-miner-backend.vercel.app/api/v1/symbols'),
        headers: {
          'Authorization': 'Bearer ${token.trim()}',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_readError(response.body, response.statusCode));
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) throw Exception('Broker returned an invalid symbol list.');

      final symbols = decoded
          .map((value) => value.toString().trim().toUpperCase())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      if (!mounted) return;
      setState(() {
        _brokerSymbols = symbols;
        _loadedForCurrentAccount = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not read symbols from this broker account: $e';
      });
    }
  }

  String _readError(String body, int status) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic> && decoded['error'] != null) {
        return 'HTTP $status: ${decoded['error']}';
      }
    } catch (_) {}
    return 'HTTP $status';
  }

  List<String> _filteredSymbols(String query) {
    final normalized = query.trim().toUpperCase();
    if (normalized.isEmpty) return _brokerSymbols.take(40).toList();

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
    return _brokerSymbols.where((symbol) => terms.any(symbol.contains)).take(60).toList();
  }

  Future<void> _selectSymbol(String symbol) async {
    final normalized = symbol.trim().toUpperCase();
    if (normalized.isEmpty || widget.bot.isBotRunning) return;

    widget.bot.updateSettings(symbol: normalized);
    _searchController.text = normalized;
    _searchController.selection = TextSelection.collapsed(offset: normalized.length);

    if (_broker.isNotEmpty && _server.isNotEmpty) {
      await _storage.saveBrokerTradingSymbol(
        broker: _broker,
        server: _server,
        symbol: normalized,
      );
    }

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
            const Row(
              children: [
                Icon(Icons.swap_horiz_rounded, size: 17, color: AppTheme.primaryColor),
                SizedBox(width: 8),
                Text('SYMBOL SWITCH', style: TextStyle(fontSize: 9.5, letterSpacing: 1.1, fontWeight: FontWeight.w800, color: Colors.white54)),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              _broker.isEmpty || _server.isEmpty ? 'Connect an MT5 account to load the symbols actually offered by its broker.' : '$_broker • $_server',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
            const SizedBox(height: 13),
            TextField(
              controller: _searchController,
              enabled: connected && !widget.bot.isBotRunning,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'SEARCH BROKER SYMBOLS',
                hintText: 'Gold, EURUSD, XAUUSD.a, etc.',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  tooltip: 'Refresh broker symbols',
                  onPressed: connected && !widget.bot.isBotRunning && !_loading ? () => _loadBrokerSymbols() : null,
                  icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded),
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
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 17, color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    const Text('SELECTED', style: TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(selected, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900))),
                  ],
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AppTheme.errorColor, fontSize: 9.5)),
            ],
            if (connected && _brokerSymbols.isNotEmpty) ...[
              const SizedBox(height: 11),
              if (results.isEmpty)
                const Text('No matching symbol was found on this broker account.', style: TextStyle(color: Colors.white38, fontSize: 10))
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
                child: Text('The symbol list is account-specific, so it becomes available after MT5 connection.', style: TextStyle(color: Colors.white30, fontSize: 9.5)),
              ),
            const SizedBox(height: 13),
            const _BrokerSymbolInfo(),
          ],
        ),
      ),
    );
  }
}

class _BrokerSymbolInfo extends StatelessWidget {
  const _BrokerSymbolInfo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: AppTheme.darkSurfaceVariant, borderRadius: BorderRadius.circular(13)),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.account_tree_rounded, color: AppTheme.accentColor, size: 19),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Broker-aware selection: the bot uses the exact MT5 symbol returned by the connected account. Gold can therefore be XAUUSD.a, XAUUSD.b, XAUUSDm, or another broker-specific name. Risk sizing then uses that symbol’s live broker specification.',
              style: TextStyle(fontSize: 10, color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }
}
