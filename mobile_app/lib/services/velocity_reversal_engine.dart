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
      if (plan != null && _optionsTrade && !signal.velocityExpanded) {
        final positions = await api.positions();
        final active = positions.whereType<Map>()
            .map((p) => Map<String, dynamic>.from(p))
            .where((p) => p['id']?.toString() == _activePositionId)
            .firstOrNull;
        final profit = active == null ? null : _number(
          active['profit'] ?? active['unrealizedProfit'] ?? active['currentProfit'] ?? active['floatingProfit']);
        if (profit != null && profit > 0) {
          await api.closePosition(_activePositionId!);
          _activePositionId = null;
          _activeDirection = null;
          _optionsExitPrice = null;
          _optionsTrade = false;
        }
      }
      return;
    }

    if (plan != null) {
      final zoneSignal = _zoneEntry(plan, liveMid, signal);
      if (zoneSignal == null) return;
      _busy = true;
      try {
        final buy = zoneSignal['buy'] as bool;
        _optionsExitPrice = null; // Scalps exit on profitable velocity fade, not at the next zone.
        _optionsTrade = true;
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
            return;
          }
        }
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

  Map<String, dynamic>? _zoneEntry(Map<String, dynamic> plan, double price, VelocityExpansionResult signal) {
    final rawZones = plan['zones'];
    if (rawZones is! List) return null;
    final zones = rawZones.whereType<Map>().map((z) => Map<String, dynamic>.from(z))
      .map((z) => {'label': z['label']?.toString() ?? '', 'price': (z['price'] as num?)?.toDouble(), 'isResistance': z['isResistance'] == true})
      .where((z) => z['price'] != null).toList();
    if (zones.length != 6) return null;
    final supports = zones.where((z) => z['isResistance'] == false).toList()
      ..sort((a,b) => (b['price'] as double).compareTo(a['price'] as double));
    final resistances = zones.where((z) => z['isResistance'] == true).toList()
      ..sort((a,b) => (a['price'] as double).compareTo(b['price'] as double));
    if (!signal.expanded || signal.direction == VelocityDirection.neutral) return null;
    for (final z in supports) {
      final level = z['price'] as double;
      if ((price - level).abs() / level <= 0.0005) {
        final target = resistances.where((r) => (r['price'] as double) > price).firstOrNull;
        if (target != null && signal.direction == VelocityDirection.bullish) return {'buy': true};
      }
    }
    for (final z in resistances) {
      final level = z['price'] as double;
      if ((price - level).abs() / level <= 0.0005) {
        final target = supports.where((r) => (r['price'] as double) < price).firstOrNull;
        if (target != null && signal.direction == VelocityDirection.bearish) return {'buy': false};
      }
    }
    return null;
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

    final active = _findActivePosition(strategyPositions);
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
    double desiredVolume = minVolume;
    if (tickSize != null && tickSize > 0 && tickValue != null && tickValue > 0) {
      final riskAmount = balance * (config.riskPercent / 100.0);
      final pipSize = await _pipSizeFromSpecification(specification);
      final stopDistance = config.reversalPips * pipSize;
      final lossPerLot = (stopDistance / tickSize) * tickValue;
      if (lossPerLot > 0) desiredVolume = (riskAmount / lossPerLot).clamp(minVolume, maxVolume);
    }
    desiredVolume = _floorToStep(desiredVolume, volumeStep);
    if (desiredVolume < minVolume) desiredVolume = minVolume;
    final marginBudget = freeMargin * 0.50;
    try {
      var margin = await api.calculateMargin(symbol: config.symbol, volume: desiredVolume, buy: buy, openPrice: _normalizePrice(buy ? ask : bid));
      var requiredMargin = _number(margin['margin']);
      if (requiredMargin != null && requiredMargin > marginBudget) {
        desiredVolume = _floorToStep(desiredVolume * marginBudget / requiredMargin, volumeStep);
        if (desiredVolume < minVolume) throw Exception('Broker minimum volume exceeds the 50% free-margin safety cap.');
        margin = await api.calculateMargin(symbol: config.symbol, volume: desiredVolume, buy: buy, openPrice: _normalizePrice(buy ? ask : bid));
        requiredMargin = _number(margin['margin']);
        if (requiredMargin != null && requiredMargin > marginBudget) throw Exception('Calculated position exceeds the 50% free-margin safety cap.');
      }
    } catch (e) {
      if (e.toString().contains('50% free-margin safety cap')) rethrow;
      desiredVolume = minVolume;
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
