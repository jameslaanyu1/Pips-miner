import '../models/candle.dart';

enum TradeBias {
  bullish,
  bearish,
  neutral,
}

class VolatilityMomentumResult {
  final TradeBias bias;
  final double volatility;
  final double momentum;

  const VolatilityMomentumResult({
    required this.bias,
    required this.volatility,
    required this.momentum,
  });
}

class VolatilityMomentum {
  static VolatilityMomentumResult analyze(
    List<Candle> candles, {
    int volatilityPeriod = 14,
    int momentumPeriod = 14,
    double momentumThreshold = 0,
  }) {
    if (candles.length < momentumPeriod + 1) {
      return const VolatilityMomentumResult(
        bias: TradeBias.neutral,
        volatility: 0,
        momentum: 0,
      );
    }

    final recent = candles.length > volatilityPeriod
        ? candles.sublist(candles.length - volatilityPeriod)
        : candles;

    double volatility = 0;

    for (final candle in recent) {
      volatility += candle.high - candle.low;
    }

    volatility /= recent.length;

    final current = candles.last.close;
    final previous =
        candles[candles.length - momentumPeriod - 1].close;

    final momentum = current - previous;

    TradeBias bias;

    if (momentum > momentumThreshold) {
      bias = TradeBias.bullish;
    } else if (momentum < -momentumThreshold) {
      bias = TradeBias.bearish;
    } else {
      bias = TradeBias.neutral;
    }

    return VolatilityMomentumResult(
      bias: bias,
      volatility: volatility,
      momentum: momentum,
    );
  }
}
