import '../models/candle.dart';
import '../models/trading_config.dart';
import '../strategy/velocity_expansion.dart';
import 'metaapi_service.dart';

enum EnginePositionDirection {
  buy,
  sell,
}

class VelocityReversalEngine {
  VelocityReversalEngine({
    required this.api,
    required this.config,
    this.magic = 26081501,
  });

  final MetaApiService api;
  final TradingConfig config;
  final int magic;

  static const String _clientPrefix = 'PIPSMINER';

  bool _running = false;
  bool _busy = false;

  String? _activePositionId;
  EnginePositionDirection? _activeDirection;
  double _activeVolume = 0.01;

  String? _reversalOrderId;
  EnginePositionDirection? _reversalDirection;
  double? _lastReversalPrice;

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

  void stop() {
    _running = false;
  }

  Future<void> tick() async {
    if (!_running || _busy) return;
    _busy = true;
    try {
      await reconcile();
    } finally {
      _busy = false;
    }
  }

  Future<void> cleanupManagedExposure() async {
    final positions = await api.positions();
    final orders = await api.orders();

    for (final raw in positions) {
      if (raw is! Map) continue;
      final position = Map<String, dynamic>.from(raw);
      if (!_isStrategyPosition(position)) continue;
      if (position['symbol']?.toString() != config.symbol) continue;
      final id = position['id']?.toString();
      if (id == null || id.isEmpty) continue;
      await api.closePosition(id);
    }

    for (final raw in orders) {
      if (raw is! Map) continue;
      final order = Map<String, dynamic>.from(raw);
      if (!_isStrategyOrder(order)) continue;
      if (order['symbol']?.toString() != config.symbol) continue;
      final id = order['id']?.toString();
      if (id == null || id.isEmpty) continue;
      await api.cancelOrder(id);
    }

    final remainingPositions = await api.positions();
    final remainingOrders = await api.orders();
    final remainingStrategyPositions = remainingPositions
        .whereType<Map>()
        .map((p) => Map<String, dynamic>.from(p))
        .where(_isStrategyPosition)
        .where((p) => p['symbol']?.toString() == config.symbol)
        .toList();
    final remainingStrategyOrders = remainingOrders
        .whereType<Map>()
        .map((o) => Map<String, dynamic>.from(o))
        .where(_isStrategyOrder)
        .where((o) => o['symbol']?.toString() == config.symbol)
        .toList();

    if (remainingStrategyPositions.isNotEmpty || remainingStrategyOrders.isNotEmpty) {
      throw Exception(
        'Pips Miner cleanup incomplete: positions=${remainingStrategyPositions.length}, orders=${remainingStrategyOrders.length}',
      );
    }

    _activePositionId = null;
    _activeDirection = null;
    _reversalOrderId = null;
    _reversalDirection = null;
    _lastReversalPrice = null;
  }

  Future<void> reconcile() async {
    if (!_running) return;

    final rawCandles = await api.candles(config.symbol, timeframe: '1m');
    final candles = rawCandles
        .whereType<Map>()
        .map((c) => Candle.fromJson(Map<String, dynamic>.from(c)))
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    if (candles.length < config.velocityBaselinePeriod + 1) return;

    final positions = await api.positions();
    final orders = await api.orders();
    final strategyPositions = positions
        .whereType<Map>()
        .map((p) => Map<String, dynamic>.from(p))
        .where(_isStrategyPosition)
        .where((p) => p['symbol'] == config.symbol)
        .toList();
    final strategyOrders = orders
        .whereType<Map>()
        .map((o) => Map<String, dynamic>.from(o))
        .where(_isStrategyOrder)
        .where((o) => o['symbol'] == config.symbol)
        .toList();

    final active = _findActivePosition(strategyPositions);
    if (active != null) {
      final detectedDirection = _positionDirection(active);
      if (detectedDirection != null) {
        final previousPositionId = _activePositionId;
        final reversalTriggered =
            _activeDirection != null &&
            detectedDirection != _activeDirection &&
            _reversalOrderId != null;
        if (reversalTriggered &&
            previousPositionId != null &&
            previousPositionId != active['id'].toString()) {
          await _closeIfStillOpen(strategyPositions, previousPositionId);
        }
        _activePositionId = active['id']?.toString();
        _activeDirection = detectedDirection;
        final detectedVolume = _number(
          active['volume'] ?? active['lots'] ?? active['currentVolume'],
        );
        if (detectedVolume != null && detectedVolume > 0) {
          _activeVolume = detectedVolume;
        }
      }
    }

    if (_activePositionId == null) {
      await _lookForInitialVelocityEntry(candles);
      return;
    }

    final expectedReversal = _opposite(_activeDirection!);
    final pending = strategyOrders
        .where((o) => _orderDirection(o) == expectedReversal)
        .toList();
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
    // The candle feed provides history. The live quote supplies the forming
    // candle's intrabar price so entry can happen before the M1 candle closes.
    final live = await api.symbolPrice(config.symbol);
    final bid = _number(live['bid'] ?? live['Bid'] ?? live['last']);
    final ask = _number(live['ask'] ?? live['Ask'] ?? live['last']);
    if (bid == null || ask == null || bid <= 0 || ask <= 0) {
      throw Exception('Live ${config.symbol} quote is unavailable.');
    }

    final signal = VelocityExpansion.analyze(
      candles,
      baselinePeriod: config.velocityBaselinePeriod,
      expansionThreshold: config.velocityExpansionThreshold,
      volumeBaselinePeriod: config.volumeBaselinePeriod,
      volumeExpansionThreshold: config.volumeExpansionThreshold,
      livePrice: (bid + ask) / 2.0,
    );

    if (!signal.expanded || signal.direction == VelocityDirection.neutral) return;

    final buy = signal.direction == VelocityDirection.bullish;
    _activeVolume = await _calculatePositionVolume(buy: buy);

    final clientId = '${_clientPrefix}_${DateTime.now().millisecondsSinceEpoch}';
    await api.marketOrder(
      symbol: config.symbol,
      volume: _activeVolume,
      buy: buy,
      clientId: clientId,
      magic: magic,
    );

    for (int attempt = 0; attempt < 5; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final currentPositions = await api.positions();
      final match = currentPositions
          .whereType<Map>()
          .map((p) => Map<String, dynamic>.from(p))
          .where(_isStrategyPosition)
          .where((p) => p['symbol'] == config.symbol)
          .where(
            (p) => _positionDirection(p) ==
                (buy ? EnginePositionDirection.buy : EnginePositionDirection.sell),
          )
          .firstOrNull;
      if (match != null) {
        _activePositionId = match['id']?.toString();
        _activeDirection = buy
            ? EnginePositionDirection.buy
            : EnginePositionDirection.sell;
        final actualVolume = _number(
          match['volume'] ?? match['lots'] ?? match['currentVolume'],
        );
        if (actualVolume != null && actualVolume > 0) _activeVolume = actualVolume;
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
    if (minVolume <= 0 || maxVolume < minVolume || volumeStep <= 0) {
      throw Exception('Invalid broker volume limits for ${config.symbol}.');
    }

    final bid = _number(price['bid'] ?? price['Bid'] ?? price['last']);
    final ask = _number(price['ask'] ?? price['Ask'] ?? price['last']);
    if (bid == null || ask == null || bid <= 0 || ask <= 0) {
      throw Exception('MetaApi did not return a valid bid/ask for ${config.symbol}.');
    }

    // Tick-value fields are taken from symbol specification first. Some
    // brokers do not expose them in the current-price response.
    final tickSize = _number(
      specification['tickSize'] ?? specification['tradeTickSize'] ?? specification['point'],
    );
    final tickValue = _number(
      specification['tradeTickValue'] ??
          specification['tickValue'] ??
          specification['tickValueLoss'] ??
          specification['tickValueProfit'] ??
          specification['tradeTickValueLoss'] ??
          specification['tradeTickValueProfit'] ??
          price['lossTickValue'] ??
          price['profitTickValue'],
    );

    double desiredVolume = minVolume;
    if (tickSize != null && tickSize > 0 && tickValue != null && tickValue > 0) {
      final riskAmount = balance * (config.riskPercent / 100.0);
      final pipSize = await _pipSizeFromSpecification(specification);
      final stopDistance = config.reversalPips * pipSize;
      final ticksToStop = stopDistance / tickSize;
      final lossPerLot = ticksToStop * tickValue;
      if (lossPerLot > 0) {
        desiredVolume = (riskAmount / lossPerLot).clamp(minVolume, maxVolume);
      }
    }

    desiredVolume = _floorToStep(desiredVolume, volumeStep);
    if (desiredVolume < minVolume) desiredVolume = minVolume;

    // Preserve the existing margin safety check. If the optional margin
    // endpoint is unavailable, fall back to broker minimum volume rather than
    // preventing all entries because a sizing helper is unavailable.
    final marginBudget = freeMargin * 0.50;
    final openPrice = buy ? ask : bid;
    try {
      var margin = await api.calculateMargin(
        symbol: config.symbol,
        volume: desiredVolume,
        buy: buy,
        openPrice: _normalizePrice(openPrice),
      );
      var requiredMargin = _number(margin['margin']);
      if (requiredMargin != null && requiredMargin > marginBudget) {
        final scale = marginBudget / requiredMargin;
        desiredVolume = _floorToStep(desiredVolume * scale, volumeStep);
        if (desiredVolume < minVolume) {
          throw Exception('Broker minimum volume exceeds the 50% free-margin safety cap.');
        }
        margin = await api.calculateMargin(
          symbol: config.symbol,
          volume: desiredVolume,
          buy: buy,
          openPrice: _normalizePrice(openPrice),
        );
        requiredMargin = _number(margin['margin']);
        if (requiredMargin != null && requiredMargin > marginBudget) {
          throw Exception('Calculated position exceeds the 50% free-margin safety cap.');
        }
      }
    } catch (e) {
      if (e.toString().contains('50% free-margin safety cap')) rethrow;
      desiredVolume = minVolume;
    }

    return double.parse(desiredVolume.toStringAsFixed(8));
  }

  double _floorToStep(double value, double step) {
    if (step <= 0) return value;
    return (value / step).floor() * step;
  }

  Future<double> _pipSizeFromSpecification(Map<String, dynamic> specification) async {
    final explicitPipSize = _number(specification['pipSize']);
    if (explicitPipSize != null && explicitPipSize > 0) return explicitPipSize;
    final point = _number(specification['point']);
    final digits = int.tryParse(specification['digits']?.toString() ?? '') ?? 0;
    if (point == null || point <= 0) throw Exception('MetaApi symbol specification has no valid point size.');
    return (digits == 3 || digits == 5) ? point * 10 : point;
  }

  Future<void> _createReversalStop(EnginePositionDirection direction) async {
    if (_activePositionId == null) return;
    final price = await api.symbolPrice(config.symbol);
    final pipSize = await _pipSize();
    final currentBid = _number(price['bid'] ?? price['Bid'] ?? price['last']);
    final currentAsk = _number(price['ask'] ?? price['Ask'] ?? price['last']);
    if (currentBid == null || currentAsk == null) throw Exception('MetaApi current price did not contain bid/ask.');
    final distance = config.reversalPips * pipSize;
    final openPrice = direction == EnginePositionDirection.buy
        ? currentAsk + distance
        : currentBid - distance;
    final result = await api.stopOrder(
      symbol: config.symbol,
      volume: _activeVolume,
      buy: direction == EnginePositionDirection.buy,
      openPrice: _normalizePrice(openPrice),
      clientId: '${_clientPrefix}_REV_${DateTime.now().millisecondsSinceEpoch}',
      magic: magic,
    );
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
    final distance = config.trailingPips * pipSize;
    final currentOrderPrice = _number(order['openPrice']);
    final proposed = _reversalDirection == EnginePositionDirection.buy
        ? ask + distance
        : bid - distance;
    bool shouldMove = false;
    if (currentOrderPrice == null) {
      shouldMove = true;
    } else if (_reversalDirection == EnginePositionDirection.buy) {
      shouldMove = proposed > currentOrderPrice;
    } else {
      shouldMove = proposed < currentOrderPrice;
    }
    if (!shouldMove) {
      _lastReversalPrice = currentOrderPrice;
      return;
    }
    final normalized = _normalizePrice(proposed);
    if (currentOrderPrice != null && normalized == currentOrderPrice) return;
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
      for (final p in positions) {
        if (_positionDirection(p) == opposite) return p;
      }
    }
    if (_activePositionId != null) {
      for (final p in positions) {
        if (p['id']?.toString() == _activePositionId) return p;
      }
    }
    return positions.first;
  }

  bool _isStrategyPosition(Map<String, dynamic> p) {
    final clientId = p['clientId']?.toString() ?? '';
    final magicValue = p['magic']?.toString();
    return clientId.startsWith(_clientPrefix) || magicValue == magic.toString();
  }

  bool _isStrategyOrder(Map<String, dynamic> o) {
    final clientId = o['clientId']?.toString() ?? '';
    final magicValue = o['magic']?.toString();
    return clientId.startsWith(_clientPrefix) || magicValue == magic.toString();
  }

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

  EnginePositionDirection _opposite(EnginePositionDirection direction) {
    return direction == EnginePositionDirection.buy
        ? EnginePositionDirection.sell
        : EnginePositionDirection.buy;
  }

  Future<double> _pipSize() async {
    final specification = await api.symbolSpecification(config.symbol);
    return _pipSizeFromSpecification(specification);
  }

  double _normalizePrice(double price) => double.parse(price.toStringAsFixed(8));

  double? _number(dynamic value) {
    if (value == null) return null;
    return double.tryParse(value.toString());
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) return iterator.current;
    return null;
  }
}
