import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/candle.dart';
import '../models/trading_config.dart';
import '../strategy/velocity_expansion.dart';
import 'metaapi_service.dart';

enum EnginePositionDirection { buy, sell }

class VelocityReversalEngine {
  VelocityReversalEngine({required this.api, required this.config, this.magic = 26081501});

  final MetaApiService api;
  final TradingConfig config;
  final int magic;
  static const String _clientPrefix = 'PIPSMINER';

  bool _running = false;
  bool _busy = false;
  List<Candle> _liveCandles = const [];

  String? _activePositionId;
  EnginePositionDirection? _activeDirection;
  double _activeVolume = 0.01;
  String? _reversalOrderId;
  EnginePositionDirection? _reversalDirection;
  double? _lastReversalPrice;
  double? _optionsExitPrice;
  bool _optionsTrade = false;
  String? _ivHedgePositionId;
  String? _ivHedgeParentId;
  double? _ivEntryPrice;
  bool _ivResistanceTested = false;
  bool _ivBreakoutConfirmed = false;
  int _ivBias = 1;
  static const String _ivStateKey = 'pips_miner_iv_trade_state';

  bool get running => _running;
  String? get activePositionId => _activePositionId;
  EnginePositionDirection? get activeDirection => _activeDirection;
  String? get reversalOrderId => _reversalOrderId;
  EnginePositionDirection? get reversalDirection => _reversalDirection;
  double? get reversalPrice => _lastReversalPrice;

  Future<void> start() async {
    if (_running) return;
    _running = true;
  }

  void stop() => _running = false;

  /// Legacy one-second reconciliation remains available for account state and
  /// trailing-stop maintenance. New entries are driven by tick streaming via
  /// tickLive(), not by this timer.
  Future<void> tick() async {
    if (!_running || _busy) return;
    _busy = true;
    try {
      await reconcile();
    } finally {
      _busy = false;
    }
  }

  /// Process a MetaApi live quote immediately. This is the fast entry path:
  /// no REST price request and no candle wait occurs before signal evaluation.
  Future<void> tickLive(Map<String, dynamic> livePrice) async {
    if (!_running || _busy) return;

    final bid = _number(livePrice['bid'] ?? livePrice['Bid'] ?? livePrice['last']);
    final ask = _number(livePrice['ask'] ?? livePrice['Ask'] ?? livePrice['last']);
    if (bid == null || ask == null || bid <= 0 || ask <= 0) return;
    final liveMid = (bid + ask) / 2.0;
    final plan = await _loadOptionsPlan();
    if (_liveCandles.length < config.velocityBaselinePeriod + 1) {
      final raw = await api.candles(config.symbol, timeframe: '1m', limit: 100);
      _liveCandles = raw.whereType<Map>()
          .map((c) => Candle.fromJson(Map<String, dynamic>.from(c)))
          .toList()
        ..sort((a, b) => a.time.compareTo(b.time));
    }
    if (_liveCandles.length < config.velocityBaselinePeriod + 1) return;

    final signal = VelocityExpansion.analyze(
      _liveCandles,
      baselinePeriod: config.velocityBaselinePeriod,
      expansionThreshold: config.velocityExpansionThreshold,
      volumeBaselinePeriod: config.volumeBaselinePeriod,
      volumeExpansionThreshold: config.volumeExpansionThreshold,
      livePrice: liveMid,
    );

    if (_activePositionId != null) {
      if (plan != null && _optionsTrade) {
        _busy = true;
        try { await _manageOptionsPosition(plan, liveMid, signal); }
        finally { _busy = false; }
      }
      return;
    }

    if (plan != null) {
      await _restoreIvState();
      final zoneSignal = _zoneEntry(plan, liveMid, signal);
      if (zoneSignal == null) return;
      _busy = true;
      try {
        final buy = zoneSignal['buy'] as bool;
        _optionsExitPrice = null;
        _optionsTrade = true;
        await _restoreIvState();
        _activeVolume = await _calculatePositionVolume(buy: buy);
        await api.marketOrder(
          symbol: config.symbol,
          volume: _activeVolume,
          buy: buy,
          clientId: '${_clientPrefix}_IV_${DateTime.now().microsecondsSinceEpoch}',
          magic: magic,
        );
        for (int attempt = 0; attempt < 5; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          final positions = await api.positions();
          final match = positions.whereType<Map>()
              .map((p) => Map<String, dynamic>.from(p))
              .where(_isStrategyPosition)
              .where((p) => p['symbol'] == config.symbol)
              .where((p) => _positionDirection(p) == (buy ? EnginePositionDirection.buy : EnginePositionDirection.sell))
              .firstOrNull;
          if (match != null) {
            _activePositionId = match['id']?.toString();
            _activeDirection = buy ? EnginePositionDirection.buy : EnginePositionDirection.sell;
            final actualVolume = _number(match['volume'] ?? match['lots'] ?? match['currentVolume']);
            if (actualVolume != null && actualVolume > 0) _activeVolume = actualVolume;
            _ivEntryPrice = _number(match['openPrice'] ?? match['price']);
            await _saveIvState();
            return;
          }
        }
        _optionsTrade = false;
        throw Exception('IV-zone order sent but the position was not confirmed.');
      } finally {
        _busy = false;
      }
    }

    if (_liveCandles.length < config.velocityBaselinePeriod + 1) {
      final raw = await api.candles(config.symbol, timeframe: '1m', limit: 100);
      _liveCandles = raw.whereType<Map>()
          .map((c) => Candle.fromJson(Map<String, dynamic>.from(c)))
          .toList()
        ..sort((a, b) => a.time.compareTo(b.time));
    }
    if (_liveCandles.length < config.velocityBaselinePeriod + 1) return;

    _busy = true;
    try {
      final signal = VelocityExpansion.analyze(
        _liveCandles,
        baselinePeriod: config.velocityBaselinePeriod,
        expansionThreshold: config.velocityExpansionThreshold,
        volumeBaselinePeriod: config.volumeBaselinePeriod,
        volumeExpansionThreshold: config.volumeExpansionThreshold,
        livePrice: liveMid,
      );

      if (!signal.expanded || signal.direction == VelocityDirection.neutral) return;

      final buy = signal.direction == VelocityDirection.bullish;
      _activeVolume = await _calculatePositionVolume(buy: buy);
      final clientId = '${_clientPrefix}_${DateTime.now().microsecondsSinceEpoch}';

      await api.marketOrder(
        symbol: config.symbol,
        volume: _activeVolume,
        buy: buy,
        clientId: clientId,
        magic: magic,
      );

      // The broker confirms the position asynchronously. Poll only after the
      // trade request, rather than polling market data before every decision.
      for (int attempt = 0; attempt < 5; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        final positions = await api.positions();
        final match = positions.whereType<Map>()
            .map((p) => Map<String, dynamic>.from(p))
            .where(_isStrategyPosition)
            .where((p) => p['symbol'] == config.symbol)
            .where((p) => _positionDirection(p) ==
                (buy ? EnginePositionDirection.buy : EnginePositionDirection.sell))
            .firstOrNull;
        if (match != null) {
          _activePositionId = match['id']?.toString();
          _activeDirection = buy ? EnginePositionDirection.buy : EnginePositionDirection.sell;
          final actualVolume = _number(match['volume'] ?? match['lots'] ?? match['currentVolume']);
          if (actualVolume != null && actualVolume > 0) _activeVolume = actualVolume;
          await _createReversalStop(_opposite(_activeDirection!));
          return;
        }
      }
      throw Exception('Market order succeeded but the new position was not visible after terminal-state checks.');
    } finally {
      _busy = false;
    }
  }


  Future<Map<String, dynamic>?> _loadOptionsPlan() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('pips_miner_iv_options_zone_plan');
    if (raw == null || raw.isEmpty) return null;
    try { return Map<String, dynamic>.from(jsonDecode(raw) as Map); } catch (_) { return null; }
  }
  Future<void> _restoreIvState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_ivStateKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final state = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      _ivBias = (state['bias'] as num?)?.toInt() ?? _ivBias;
      _ivResistanceTested = state['resistanceTested'] == true;
      _ivBreakoutConfirmed = state['breakoutConfirmed'] == true;
      _ivHedgePositionId = state['hedgePositionId']?.toString();
      _ivHedgeParentId = state['hedgeParentId']?.toString();
      _ivEntryPrice = _number(state['entryPrice']) ?? _ivEntryPrice;
    } catch (_) {}
  }

  Future<void> _saveIvState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ivStateKey, jsonEncode({
      'bias': _ivBias, 'resistanceTested': _ivResistanceTested,
      'breakoutConfirmed': _ivBreakoutConfirmed,
      'hedgePositionId': _ivHedgePositionId, 'hedgeParentId': _ivHedgeParentId,
      'entryPrice': _ivEntryPrice,
    }));
  }

  Future<void> _clearIvTradeState() async {
    _activePositionId = null;
    _activeDirection = null;
    _ivEntryPrice = null;
    _ivHedgePositionId = null;
    _ivHedgeParentId = null;
    _optionsExitPrice = null;
    _optionsTrade = false;
    await _saveIvState();
  }

  double _positionProfit(Map<String, dynamic> p) =>
      (_number(p['profit'] ?? p['unrealizedProfit'] ?? p['currentProfit'] ?? p['floatingProfit']) ?? 0) +
      (_number(p['swap']) ?? 0) + (_number(p['commission']) ?? 0);

  Future<void> _manageOptionsPosition(
    Map<String, dynamic> plan, double price, VelocityExpansionResult signal,
  ) async {
    await _restoreIvState();
    final all = (await api.positions()).whereType<Map>()
        .map((p) => Map<String, dynamic>.from(p))
        .where(_isStrategyPosition).where((p) => p['symbol']?.toString() == config.symbol).toList();
    final active = all.where((p) => p['id']?.toString() == _activePositionId).firstOrNull;
    if (active == null) {
      await _clearIvTradeState();
      return;
    }
    final hedge = all.where((p) => p['id']?.toString() == _ivHedgePositionId ||
        (p['clientId']?.toString() ?? '').contains('_IV_HEDGE_')).firstOrNull;
    if (hedge != null) {
      _ivHedgePositionId = hedge['id']?.toString();
      _ivHedgeParentId = active['id']?.toString();
      final basketProfit = all.fold<double>(0, (sum, p) => sum + _positionProfit(p));
      await _saveIvState();
      if (basketProfit >= 0) {
        final ids = all.map((p) => p['id']?.toString()).whereType<String>().toSet();
        for (final id in ids) { await api.closePosition(id); }
        final remaining = (await api.positions()).whereType<Map>()
            .map((p) => Map<String, dynamic>.from(p)).where(_isStrategyPosition)
            .where((p) => p['symbol']?.toString() == config.symbol)
            .where((p) => ids.contains(p['id']?.toString())).toList();
        if (remaining.isEmpty) await _clearIvTradeState();
      }
      return; // No new trades while a hedge basket is unresolved.
    }

    final direction = _positionDirection(active);
    final openPrice = _number(active['openPrice'] ?? active['price']) ?? _ivEntryPrice;
    if (direction == null || openPrice == null) return;
    _ivEntryPrice = openPrice;
    final pipSize = await _pipSize();
    final favorable = direction == EnginePositionDirection.buy ? price - openPrice : openPrice - price;
    final adverse = -favorable;
    if (favorable >= 350 * pipSize) {
      final id = active['id']?.toString();
      if (id == null) return;
      await api.closePosition(id);
      final remaining = (await api.positions()).whereType<Map>()
          .map((p) => Map<String, dynamic>.from(p)).any((p) => p['id']?.toString() == id);
      if (!remaining) await _clearIvTradeState();
      return;
    }
    if (adverse >= 200 * pipSize) {
      final net = all.fold<double>(0, (sum, p) {
        final volume = _number(p['volume'] ?? p['lots'] ?? p['currentVolume']) ?? 0;
        final d = _positionDirection(p);
        return sum + (d == EnginePositionDirection.buy ? volume : d == EnginePositionDirection.sell ? -volume : 0);
      });
      if (net.abs() <= 0) return;
      final hedgeBuy = net < 0;
      final riskLimited = await _calculatePositionVolume(buy: hedgeBuy, riskDistancePips: 200);
      final spec = await api.symbolSpecification(config.symbol);
      final minVolume = _number(spec['minVolume'] ?? spec['volumeMin']) ?? config.minimumVolume;
      final step = _number(spec['volumeStep'] ?? spec['lotStep']) ?? config.volumeStep;
      final hedgeVolume = _floorToStep(net.abs().clamp(0.0, riskLimited).toDouble(), step);
      if (hedgeVolume < minVolume) return;
      await api.marketOrder(symbol: config.symbol, volume: hedgeVolume, buy: hedgeBuy,
        clientId: '${_clientPrefix}_IV_HEDGE_${DateTime.now().microsecondsSinceEpoch}', magic: magic);
      for (var attempt = 0; attempt < 5; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final refreshed = (await api.positions()).whereType<Map>()
            .map((p) => Map<String, dynamic>.from(p)).where(_isStrategyPosition)
            .where((p) => (p['clientId']?.toString() ?? '').contains('_IV_HEDGE_'))
            .where((p) => p['symbol']?.toString() == config.symbol).firstOrNull;
        if (refreshed != null) {
          _ivHedgePositionId = refreshed['id']?.toString();
          _ivHedgeParentId = active['id']?.toString();
          await _saveIvState();
          return;
        }
      }
      throw Exception('IV hedge request sent but broker confirmation was not received; verify account positions before retrying.');
    }
    await _saveIvState();
  }


  Map<String, dynamic>? _zoneEntry(Map<String, dynamic> plan, double price, VelocityExpansionResult signal) {
    final rawZones = plan['zones'];
    if (rawZones is! List || _liveCandles.length < 3) return null;
    final zones = rawZones.whereType<Map>().map((z) => Map<String, dynamic>.from(z))
      .map((z) => {'label': z['label']?.toString() ?? '', 'price': _number(z['price']), 'isResistance': z['isResistance'] == true})
      .where((z) => z['price'] != null && (z['price'] as double) > 0).toList();
    final supports = zones.where((z) => z['isResistance'] == false).toList()
      ..sort((a,b) => (b['price'] as double).compareTo(a['price'] as double));
    final resistances = zones.where((z) => z['isResistance'] == true).toList()
      ..sort((a,b) => (a['price'] as double).compareTo(b['price'] as double));
    if (supports.length != 3 || resistances.length != 3) return null;
    final previous = _liveCandles[_liveCandles.length - 2].close - _liveCandles[_liveCandles.length - 3].close;
    final current = signal.currentVelocity;
    final tolerance = (_number(plan['zoneTolerancePercent']) ?? 0.05) / 100.0;
    bool near(double level) => (price - level).abs() / level <= tolerance;
    final topResistance = resistances.last['price'] as double;

    if (price > topResistance * (1 + tolerance)) {
      _ivBias = 1;
      _ivBreakoutConfirmed = true;
      _ivResistanceTested = true;
      _saveIvState();
      return null; // Confirm the break, then wait for a retest rather than chase.
    }
    if (_ivBreakoutConfirmed && _ivBias > 0 && near(topResistance) && current > 0) {
      return {'buy': true}; // Bullish continuation after a broken-resistance retest.
    }
    for (final zone in resistances) {
      final level = zone['price'] as double;
      if (!near(level)) continue;
      _ivResistanceTested = true;
      if (!_ivBreakoutConfirmed && previous > 0 && current < 0 && price <= level) {
        _ivBias = -1;
        _ivBreakoutConfirmed = false;
        _saveIvState();
        return {'buy': false};
      }
      return null;
    }
    if (_ivBias >= 0) {
      for (final zone in supports) {
        final level = zone['price'] as double;
        // Previous candle moved down; live tick has turned up: downward impulse faded.
        if (near(level) && previous < 0 && current > 0 && price >= level) return {'buy': true};
      }
    } else {
      for (final zone in supports) {
        final level = zone['price'] as double;
        if (near(level) && previous < 0 && current < 0 && signal.expanded) return {'buy': false};
      }
    }
    return null; // Explicit no-trade area between zones.
  }

  Future<void> cleanupManagedExposure() async {
    final positions = await api.positions();
    final orders = await api.orders();
    for (final raw in positions) {
      if (raw is! Map) continue;
      final position = Map<String, dynamic>.from(raw);
      if (!_isStrategyPosition(position) || position['symbol']?.toString() != config.symbol) continue;
      final id = position['id']?.toString();
      if (id != null && id.isNotEmpty) await api.closePosition(id);
    }
    for (final raw in orders) {
      if (raw is! Map) continue;
      final order = Map<String, dynamic>.from(raw);
      if (!_isStrategyOrder(order) || order['symbol']?.toString() != config.symbol) continue;
      final id = order['id']?.toString();
      if (id != null && id.isNotEmpty) await api.cancelOrder(id);
    }

    final remainingPositions = await api.positions();
    final remainingOrders = await api.orders();
    final remainingStrategyPositions = remainingPositions.whereType<Map>()
        .map((p) => Map<String, dynamic>.from(p)).where(_isStrategyPosition)
        .where((p) => p['symbol']?.toString() == config.symbol).toList();
    final remainingStrategyOrders = remainingOrders.whereType<Map>()
        .map((o) => Map<String, dynamic>.from(o)).where(_isStrategyOrder)
        .where((o) => o['symbol']?.toString() == config.symbol).toList();
    if (remainingStrategyPositions.isNotEmpty || remainingStrategyOrders.isNotEmpty) {
      throw Exception('Pips Miner cleanup incomplete: positions=${remainingStrategyPositions.length}, orders=${remainingStrategyOrders.length}');
    }
    _activePositionId = null;
    _activeDirection = null;
    _reversalOrderId = null;
    _reversalDirection = null;
    _lastReversalPrice = null;
    _optionsExitPrice = null;
    _optionsTrade = false;
  }

  Future<void> reconcile() async {
    if (!_running) return;
    final rawCandles = await api.candles(config.symbol, timeframe: '1m');
    final candles = rawCandles.whereType<Map>()
        .map((c) => Candle.fromJson(Map<String, dynamic>.from(c))).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    _liveCandles = candles;
    if (candles.length < config.velocityBaselinePeriod + 1) return;

    final positions = await api.positions();
    final orders = await api.orders();
    final strategyPositions = positions.whereType<Map>()
        .map((p) => Map<String, dynamic>.from(p)).where(_isStrategyPosition)
        .where((p) => p['symbol'] == config.symbol).toList();
    final strategyOrders = orders.whereType<Map>()
        .map((o) => Map<String, dynamic>.from(o)).where(_isStrategyOrder)
        .where((o) => o['symbol'] == config.symbol).toList();

    await _restoreIvState();
    final hasIvPlan = await _loadOptionsPlan() != null;
    final active = hasIvPlan
        ? (strategyPositions.where((p) {
            final id = p['clientId']?.toString() ?? '';
            return id.contains('_IV_') && !id.contains('_IV_HEDGE_');
          }).firstOrNull ?? _findActivePosition(strategyPositions))
        : _findActivePosition(strategyPositions);
    if (active != null) {
      final detectedDirection = _positionDirection(active);
      if (detectedDirection != null) {
        final previousPositionId = _activePositionId;
        final reversalTriggered = _activeDirection != null && detectedDirection != _activeDirection && _reversalOrderId != null;
        if (reversalTriggered && previousPositionId != null && previousPositionId != active['id'].toString()) {
          await _closeIfStillOpen(strategyPositions, previousPositionId);
        }
        _activePositionId = active['id']?.toString();
        _activeDirection = detectedDirection;
        final detectedVolume = _number(active['volume'] ?? active['lots'] ?? active['currentVolume']);
        if (detectedVolume != null && detectedVolume > 0) _activeVolume = detectedVolume;
        final clientId = active['clientId']?.toString() ?? '';
        if (clientId.contains('_IV_')) {
          _optionsTrade = true;
          _ivEntryPrice = _number(active['openPrice'] ?? active['price']) ?? _ivEntryPrice;
        }
      }
    }

    if (_activePositionId == null) return;
    if (await _loadOptionsPlan() != null) return; // IV plan manages exits; do not place legacy reversal stops.
    final expectedReversal = _opposite(_activeDirection!);
    final pending = strategyOrders.where((o) => _orderDirection(o) == expectedReversal).toList();
    if (pending.isEmpty) {
      await _createReversalStop(expectedReversal);
      return;
    }
    final primary = pending.first;
    for (final duplicate in pending.skip(1)) {
      final id = duplicate['id']?.toString();
      if (id != null) await api.cancelOrder(id);
    }
    _reversalOrderId = primary['id']?.toString();
    _reversalDirection = expectedReversal;
    await _trailReversalStop(primary);
  }

  Future<void> _lookForInitialVelocityEntry(List<Candle> candles) async {
    final live = await api.symbolPrice(config.symbol);
    final bid = _number(live['bid'] ?? live['Bid'] ?? live['last']);
    final ask = _number(live['ask'] ?? live['Ask'] ?? live['last']);
    if (bid == null || ask == null || bid <= 0 || ask <= 0) return;
    final signal = VelocityExpansion.analyze(candles, baselinePeriod: config.velocityBaselinePeriod,
      expansionThreshold: config.velocityExpansionThreshold, volumeBaselinePeriod: config.volumeBaselinePeriod,
      volumeExpansionThreshold: config.volumeExpansionThreshold, livePrice: (bid + ask) / 2.0);
    if (!signal.expanded || signal.direction == VelocityDirection.neutral) return;
    final buy = signal.direction == VelocityDirection.bullish;
    _activeVolume = await _calculatePositionVolume(buy: buy);
    await api.marketOrder(symbol: config.symbol, volume: _activeVolume, buy: buy,
      clientId: '${_clientPrefix}_${DateTime.now().microsecondsSinceEpoch}', magic: magic);
    for (int attempt = 0; attempt < 5; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final currentPositions = await api.positions();
      final match = currentPositions.whereType<Map>().map((p) => Map<String, dynamic>.from(p))
        .where(_isStrategyPosition).where((p) => p['symbol'] == config.symbol)
        .where((p) => _positionDirection(p) == (buy ? EnginePositionDirection.buy : EnginePositionDirection.sell)).firstOrNull;
      if (match != null) {
        _activePositionId = match['id']?.toString();
        _activeDirection = buy ? EnginePositionDirection.buy : EnginePositionDirection.sell;
        await _createReversalStop(_opposite(_activeDirection!));
        return;
      }
    }
    throw Exception('Market order succeeded but the new position was not visible after terminal-state checks.');
  }

  Future<double> _calculatePositionVolume({required bool buy}) async {
    final account = await api.accountInformation();
    final specification = await api.symbolSpecification(config.symbol);
    final price = await api.symbolPrice(config.symbol);
    final balance = _number(account['balance']);
    final freeMargin = _number(account['freeMargin']);
    if (balance == null || balance <= 0) throw Exception('Invalid account balance.');
    if (freeMargin == null || freeMargin <= 0) throw Exception('Account free margin is unavailable.');
    final minVolume = _number(specification['minVolume'] ?? specification['volumeMin']) ?? config.minimumVolume;
    final maxVolume = _number(specification['maxVolume'] ?? specification['volumeMax']) ?? config.maximumVolume;
    final volumeStep = _number(specification['volumeStep'] ?? specification['lotStep']) ?? config.volumeStep;
    if (minVolume <= 0 || maxVolume < minVolume || volumeStep <= 0) throw Exception('Invalid broker volume limits for ${config.symbol}.');
    final bid = _number(price['bid'] ?? price['Bid'] ?? price['last']);
    final ask = _number(price['ask'] ?? price['Ask'] ?? price['last']);
    if (bid == null || ask == null || bid <= 0 || ask <= 0) throw Exception('MetaApi did not return a valid bid/ask for ${config.symbol}.');
    final tickSize = _number(specification['tickSize'] ?? specification['tradeTickSize'] ?? specification['point']);
    final tickValue = _number(specification['tradeTickValue'] ?? specification['tickValue'] ?? specification['tickValueLoss'] ?? specification['tickValueProfit'] ?? specification['tradeTickValueLoss'] ?? specification['tradeTickValueProfit'] ?? price['lossTickValue'] ?? price['profitTickValue']);
    if (tickSize == null || tickSize <= 0 || tickValue == null || tickValue <= 0) {
      throw Exception('Broker tick size/value unavailable; refusing to guess a risk-based volume.');
    }
    double desiredVolume = minVolume;
    if (tickSize > 0 && tickValue > 0) {
      final riskAmount = balance * (config.riskPercent / 100.0);
      final pipSize = await _pipSizeFromSpecification(specification);
      final stopDistance = (riskDistancePips ?? config.reversalPips) * pipSize;
      final lossPerLot = (stopDistance / tickSize) * tickValue;
      if (lossPerLot <= 0) throw Exception('Invalid calculated loss per lot.');
      final riskVolume = riskAmount / lossPerLot;
      if (riskVolume < minVolume) {
        throw Exception('Broker minimum lot exceeds the configured risk limit; refusing the trade.');
      }
      desiredVolume = riskVolume.clamp(minVolume, maxVolume).toDouble();
    }
    desiredVolume = _floorToStep(desiredVolume, volumeStep);
    if (desiredVolume < minVolume) desiredVolume = minVolume;
    final marginBudget = freeMargin * 0.50;
    try {
      var margin = await api.calculateMargin(symbol: config.symbol, volume: desiredVolume, buy: buy, openPrice: _normalizePrice(buy ? ask : bid));
      var requiredMargin = _number(margin['margin']);
      if (requiredMargin == null || requiredMargin < 0) throw Exception('Broker did not return a valid margin estimate.');
      if (requiredMargin > marginBudget) {
        desiredVolume = _floorToStep(desiredVolume * marginBudget / requiredMargin, volumeStep);
        if (desiredVolume < minVolume) throw Exception('Broker minimum volume exceeds the 50% free-margin safety cap.');
        margin = await api.calculateMargin(symbol: config.symbol, volume: desiredVolume, buy: buy, openPrice: _normalizePrice(buy ? ask : bid));
        requiredMargin = _number(margin['margin']);
        if (requiredMargin == null || requiredMargin < 0) throw Exception('Broker did not return a valid margin estimate.');
        if (requiredMargin > marginBudget) throw Exception('Calculated position exceeds the 50% free-margin safety cap.');
      }
    } catch (e) {
      rethrow; // Do not silently bypass margin/risk checks by falling back to minimum lot.
    }
    return double.parse(desiredVolume.toStringAsFixed(8));
  }

  double _floorToStep(double value, double step) => step <= 0 ? value : (value / step).floor() * step;

  Future<double> _pipSizeFromSpecification(Map<String, dynamic> specification) async {
    final explicit = _number(specification['pipSize']);
    if (explicit != null && explicit > 0) return explicit;
    final point = _number(specification['point']);
    final digits = int.tryParse(specification['digits']?.toString() ?? '') ?? 0;
    if (point == null || point <= 0) throw Exception('MetaApi symbol specification has no valid point size.');
    return (digits == 3 || digits == 5) ? point * 10 : point;
  }

  Future<void> _createReversalStop(EnginePositionDirection direction) async {
    if (_activePositionId == null) return;
    final price = await api.symbolPrice(config.symbol);
    final pipSize = await _pipSize();
    final bid = _number(price['bid'] ?? price['Bid'] ?? price['last']);
    final ask = _number(price['ask'] ?? price['Ask'] ?? price['last']);
    if (bid == null || ask == null) throw Exception('MetaApi current price did not contain bid/ask.');
    final openPrice = direction == EnginePositionDirection.buy ? ask + config.reversalPips * pipSize : bid - config.reversalPips * pipSize;
    final result = await api.stopOrder(symbol: config.symbol, volume: _activeVolume, buy: direction == EnginePositionDirection.buy,
      openPrice: _normalizePrice(openPrice), clientId: '${_clientPrefix}_REV_${DateTime.now().microsecondsSinceEpoch}', magic: magic);
    _reversalOrderId = result['orderId']?.toString();
    _reversalDirection = direction;
    _lastReversalPrice = openPrice;
  }

  Future<void> _trailReversalStop(Map<String, dynamic> order) async {
    final orderId = order['id']?.toString();
    if (orderId == null) return;
    final price = await api.symbolPrice(config.symbol);
    final pipSize = await _pipSize();
    final bid = _number(price['bid'] ?? price['Bid'] ?? price['last']);
    final ask = _number(price['ask'] ?? price['Ask'] ?? price['last']);
    if (bid == null || ask == null) return;
    final current = _number(order['openPrice']);
    final proposed = _reversalDirection == EnginePositionDirection.buy ? ask + config.trailingPips * pipSize : bid - config.trailingPips * pipSize;
    final shouldMove = current == null || (_reversalDirection == EnginePositionDirection.buy ? proposed > current : proposed < current);
    if (!shouldMove) { _lastReversalPrice = current; return; }
    final normalized = _normalizePrice(proposed);
    if (current != null && normalized == current) return;
    await api.modifyOrder(orderId: orderId, openPrice: normalized);
    _lastReversalPrice = normalized;
  }

  Future<void> _closeIfStillOpen(List<Map<String, dynamic>> positions, String positionId) async {
    if (positions.any((p) => p['id']?.toString() == positionId)) await api.closePosition(positionId);
  }

  Map<String, dynamic>? _findActivePosition(List<Map<String, dynamic>> positions) {
    if (positions.isEmpty) return null;
    if (_activeDirection != null) {
      final opposite = _opposite(_activeDirection!);
      for (final p in positions) if (_positionDirection(p) == opposite) return p;
    }
    if (_activePositionId != null) for (final p in positions) if (p['id']?.toString() == _activePositionId) return p;
    return positions.first;
  }

  bool _isStrategyPosition(Map<String, dynamic> p) => (p['clientId']?.toString() ?? '').startsWith(_clientPrefix) || p['magic']?.toString() == magic.toString();
  bool _isStrategyOrder(Map<String, dynamic> o) => (o['clientId']?.toString() ?? '').startsWith(_clientPrefix) || o['magic']?.toString() == magic.toString();

  EnginePositionDirection? _positionDirection(Map<String, dynamic> p) {
    final type = p['type']?.toString();
    if (type == 'POSITION_TYPE_BUY') return EnginePositionDirection.buy;
    if (type == 'POSITION_TYPE_SELL') return EnginePositionDirection.sell;
    return null;
  }

  EnginePositionDirection? _orderDirection(Map<String, dynamic> o) {
    final type = o['type']?.toString();
    if (type == 'ORDER_TYPE_BUY_STOP') return EnginePositionDirection.buy;
    if (type == 'ORDER_TYPE_SELL_STOP') return EnginePositionDirection.sell;
    return null;
  }

  EnginePositionDirection _opposite(EnginePositionDirection direction) => direction == EnginePositionDirection.buy ? EnginePositionDirection.sell : EnginePositionDirection.buy;
  Future<double> _pipSize() async => _pipSizeFromSpecification(await api.symbolSpecification(config.symbol));
  double _normalizePrice(double price) => double.parse(price.toStringAsFixed(8));
  double? _number(dynamic value) => value == null ? null : double.tryParse(value.toString());
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) return iterator.current;
    return null;
  }
}
