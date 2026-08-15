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

    try {
      await reconcile();
    } catch (_) {
      _running = false;
      rethrow;
    }
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

  Future<void> reconcile() async {
    if (!_running) return;

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

    /*
     * CRITICAL RULE:
     *
     * The reversal STOP itself becomes the new position.
     *
     * We never open a second market position after a reversal.
     */

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
          await _closeIfStillOpen(
            strategyPositions,
            previousPositionId,
          );
        }

        _activePositionId = active['id']?.toString();
        _activeDirection = detectedDirection;

        final detectedVolume = _number(
          active['volume'] ??
          active['lots'] ??
          active['currentVolume'],
        );

        if (detectedVolume != null && detectedVolume > 0) {
          _activeVolume = detectedVolume;
        }
      }
    }

    if (_activePositionId == null) {
      await _lookForInitialVelocityEntry();
      return;
    }

    /*
     * If our reversal order disappeared while the opposite position
     * appeared, the pending stop has been triggered and is now the
     * active position.
     */
    final expectedReversal = _opposite(_activeDirection!);

    final pending = strategyOrders
        .where((o) =>
            _orderDirection(o) == expectedReversal)
        .toList();

    if (pending.isEmpty) {
      await _createReversalStop(expectedReversal);
      return;
    }

    /*
     * There should be exactly one active reversal stop.
     * Cancel duplicates before continuing.
     */
    final primary = pending.first;

    for (final duplicate in pending.skip(1)) {
      final id = duplicate['id']?.toString();

      if (id != null) {
        await api.cancelOrder(id);
      }
    }

    _reversalOrderId = primary['id']?.toString();
    _reversalDirection = expectedReversal;

    await _trailReversalStop(primary);
  }

  Future<void> _lookForInitialVelocityEntry() async {
    final rawCandles = await api.candles(
      config.symbol,
      timeframe: '1m',
    );

    final candles = rawCandles
        .whereType<Map>()
        .map(
          (c) => Candle.fromJson(
            Map<String, dynamic>.from(c),
          ),
        )
        .toList();

    final signal = VelocityExpansion.analyze(
      candles,
      baselinePeriod: config.velocityBaselinePeriod,
      expansionThreshold:
          config.velocityExpansionThreshold,
    );

    if (!signal.expanded) return;

    if (signal.direction == VelocityDirection.neutral) {
      return;
    }

    final buy =
        signal.direction == VelocityDirection.bullish;

    final clientId =
        '${_clientPrefix}_${DateTime.now().millisecondsSinceEpoch}';

    await api.marketOrder(
      symbol: config.symbol,
      volume: _activeVolume,
      buy: buy,
      clientId: clientId,
      magic: magic,
    );

    /*
     * MetaApi returns the order result immediately, but the position
     * becomes visible in terminal state asynchronously. Re-read it.
     */
    for (int attempt = 0; attempt < 5; attempt++) {
      await Future<void>.delayed(
        const Duration(milliseconds: 300),
      );

      final positions = await api.positions();

      final match = positions
          .whereType<Map>()
          .map((p) => Map<String, dynamic>.from(p))
          .where(_isStrategyPosition)
          .where((p) => p['symbol'] == config.symbol)
          .where(
            (p) => _positionDirection(p) ==
                (buy
                    ? EnginePositionDirection.buy
                    : EnginePositionDirection.sell),
          )
          .firstOrNull;

      if (match != null) {
        _activePositionId = match['id']?.toString();
        _activeDirection = buy
            ? EnginePositionDirection.buy
            : EnginePositionDirection.sell;

        await _createReversalStop(
          _opposite(_activeDirection!),
        );

        return;
      }
    }

    throw Exception(
      'MetaApi market order succeeded but the new position '
      'was not visible after several terminal-state checks.',
    );
  }

  Future<void> _createReversalStop(
    EnginePositionDirection direction,
  ) async {
    if (_activePositionId == null) return;

    final price = await api.symbolPrice(config.symbol);
    final pipSize = await _pipSize();

    final currentBid = _number(
      price['bid'] ?? price['Bid'] ?? price['last'],
    );

    final currentAsk = _number(
      price['ask'] ?? price['Ask'] ?? price['last'],
    );

    if (currentBid == null || currentAsk == null) {
      throw Exception(
        'MetaApi current price did not contain bid/ask.',
      );
    }

    final distance = config.reversalPips * pipSize;

    final openPrice =
        direction == EnginePositionDirection.buy
            ? currentAsk + distance
            : currentBid - distance;

    final result = await api.stopOrder(
      symbol: config.symbol,
      volume: _activeVolume,
      buy: direction == EnginePositionDirection.buy,
      openPrice: _normalizePrice(openPrice),
      clientId:
          '${_clientPrefix}_REV_${DateTime.now().millisecondsSinceEpoch}',
      magic: magic,
    );

    _reversalOrderId = result['orderId']?.toString();
    _reversalDirection = direction;
    _lastReversalPrice = openPrice;
  }

  Future<void> _trailReversalStop(
    Map<String, dynamic> order,
  ) async {
    final orderId = order['id']?.toString();

    if (orderId == null) return;

    final price = await api.symbolPrice(config.symbol);
    final pipSize = await _pipSize();

    final bid = _number(
      price['bid'] ?? price['Bid'] ?? price['last'],
    );

    final ask = _number(
      price['ask'] ?? price['Ask'] ?? price['last'],
    );

    if (bid == null || ask == null) return;

    final distance = config.trailingPips * pipSize;

    final currentOrderPrice =
        _number(order['openPrice']);

    final proposed =
        _reversalDirection == EnginePositionDirection.buy
            ? ask + distance
            : bid - distance;

    /*
     * A reversal stop only moves in the profitable/trailing direction.
     *
     * BUY STOP: may move UP only.
     * SELL STOP: may move DOWN only.
     *
     * It must never loosen itself.
     */
    bool shouldMove = false;

    if (currentOrderPrice == null) {
      shouldMove = true;
    } else if (_reversalDirection ==
        EnginePositionDirection.buy) {
      shouldMove = proposed > currentOrderPrice;
    } else {
      shouldMove = proposed < currentOrderPrice;
    }

    if (!shouldMove) {
      _lastReversalPrice = currentOrderPrice;
      return;
    }

    final normalized = _normalizePrice(proposed);

    if (currentOrderPrice != null &&
        normalized == currentOrderPrice) {
      return;
    }

    await api.modifyOrder(
      orderId: orderId,
      openPrice: normalized,
    );

    _lastReversalPrice = normalized;
  }

  Future<void> _closeIfStillOpen(
    List<Map<String, dynamic>> positions,
    String positionId,
  ) async {
    final stillOpen = positions.any(
      (p) => p['id']?.toString() == positionId,
    );

    if (stillOpen) {
      await api.closePosition(positionId);
    }
  }

  Map<String, dynamic>? _findActivePosition(
    List<Map<String, dynamic>> positions,
  ) {
    if (positions.isEmpty) return null;

    /*
     * CRITICAL REVERSAL RULE:
     *
     * When the opposite stop is triggered, MetaApi may temporarily
     * expose BOTH positions:
     *
     *   old position
     *   new position created by the reversal stop
     *
     * The opposite-direction position MUST win.
     *
     * This allows reconcile() to detect the reversal immediately
     * and close the previous position.
     */
    if (_activeDirection != null) {
      final opposite = _opposite(_activeDirection!);

      for (final p in positions) {
        if (_positionDirection(p) == opposite) {
          return p;
        }
      }
    }

    /*
     * No reversal detected. Continue tracking the known position.
     */
    if (_activePositionId != null) {
      for (final p in positions) {
        if (p['id']?.toString() == _activePositionId) {
          return p;
        }
      }
    }

    return positions.first;
  }

  bool _isStrategyPosition(Map<String, dynamic> p) {
    final clientId =
        p['clientId']?.toString() ?? '';

    final magicValue =
        p['magic']?.toString();

    return clientId.startsWith(_clientPrefix) ||
        magicValue == magic.toString();
  }

  bool _isStrategyOrder(Map<String, dynamic> o) {
    final clientId =
        o['clientId']?.toString() ?? '';

    final magicValue =
        o['magic']?.toString();

    return clientId.startsWith(_clientPrefix) ||
        magicValue == magic.toString();
  }

  EnginePositionDirection? _positionDirection(
    Map<String, dynamic> p,
  ) {
    final type = p['type']?.toString();

    if (type == 'POSITION_TYPE_BUY') {
      return EnginePositionDirection.buy;
    }

    if (type == 'POSITION_TYPE_SELL') {
      return EnginePositionDirection.sell;
    }

    return null;
  }

  EnginePositionDirection? _orderDirection(
    Map<String, dynamic> o,
  ) {
    final type = o['type']?.toString();

    if (type == 'ORDER_TYPE_BUY_STOP') {
      return EnginePositionDirection.buy;
    }

    if (type == 'ORDER_TYPE_SELL_STOP') {
      return EnginePositionDirection.sell;
    }

    return null;
  }

  EnginePositionDirection _opposite(
    EnginePositionDirection direction,
  ) {
    return direction == EnginePositionDirection.buy
        ? EnginePositionDirection.sell
        : EnginePositionDirection.buy;
  }

  Future<double> _pipSize() async {
    final specification =
        await api.symbolSpecification(config.symbol);

    final point = _number(
      specification['point'],
    );

    final digits =
        int.tryParse(
          specification['digits']?.toString() ?? '',
        ) ??
        0;

    if (point == null || point <= 0) {
      throw Exception(
        'MetaApi symbol specification has no valid point size.',
      );
    }

    /*
     * Standard FX convention:
     * 5/3 digit symbols use 10 points per pip.
     * 2/4 digit symbols use 1 point per pip.
     *
     * This also avoids hard-coding XAUUSD price precision.
     */
    return (digits == 3 || digits == 5)
        ? point * 10
        : point;
  }

  double _normalizePrice(double price) {
    /*
     * MetaApi/broker validates the final price precision.
     * Keep enough precision here; broker-side symbol specification
     * remains authoritative.
     */
    return double.parse(price.toStringAsFixed(8));
  }

  double? _number(dynamic value) {
    if (value == null) return null;
    return double.tryParse(value.toString());
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;

    if (iterator.moveNext()) {
      return iterator.current;
    }

    return null;
  }
}
