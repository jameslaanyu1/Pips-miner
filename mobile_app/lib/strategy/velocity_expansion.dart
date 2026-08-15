import '../models/candle.dart';

enum VelocityDirection {
  bullish,
  bearish,
  neutral,
}

class VelocityExpansionResult {
  final VelocityDirection direction;
  final double currentVelocity;
  final double baselineVelocity;
  final double expansionRatio;
  final bool expanded;

  const VelocityExpansionResult({
    required this.direction,
    required this.currentVelocity,
    required this.baselineVelocity,
    required this.expansionRatio,
    required this.expanded,
  });
}

class VelocityExpansion {
  static VelocityExpansionResult analyze(
    List<Candle> candles, {
    int baselinePeriod = 14,
    double expansionThreshold = 1.5,
  }) {
    if (baselinePeriod <= 0 ||
        candles.length < baselinePeriod + 1) {
      return const VelocityExpansionResult(
        direction: VelocityDirection.neutral,
        currentVelocity: 0,
        baselineVelocity: 0,
        expansionRatio: 0,
        expanded: false,
      );
    }

    final current = candles[candles.length - 1];
    final previous = candles[candles.length - 2];

    // M1 directional velocity of the newest completed candle.
    final currentVelocity = current.close - previous.close;

    // Average absolute velocity of the PRECEDING baseline candles.
    // IMPORTANT: the newest/current velocity is NOT included.
    double totalVelocity = 0;

    // The current velocity is:
    // candles[n - 1].close - candles[n - 2].close
    //
    // Therefore the 14 preceding velocities are:
    // candles[n - 16] -> candles[n - 15]
    // ...
    // candles[n - 3]  -> candles[n - 2]
    //
    // The current velocity is deliberately excluded from the baseline.
    final baselineStart = candles.length - baselinePeriod - 1;
    final baselineEnd = candles.length - 2;

    for (int i = baselineStart; i <= baselineEnd; i++) {
      final velocity = candles[i].close - candles[i - 1].close;
      totalVelocity += velocity.abs();
    }

    final baselineVelocity = totalVelocity / baselinePeriod;

    if (baselineVelocity <= 0) {
      return VelocityExpansionResult(
        direction: VelocityDirection.neutral,
        currentVelocity: currentVelocity,
        baselineVelocity: baselineVelocity,
        expansionRatio: 0,
        expanded: false,
      );
    }

    final expansionRatio =
        currentVelocity.abs() / baselineVelocity;

    final expanded =
        expansionRatio >= expansionThreshold;

    VelocityDirection direction = VelocityDirection.neutral;

    if (expanded) {
      if (currentVelocity > 0) {
        direction = VelocityDirection.bullish;
      } else if (currentVelocity < 0) {
        direction = VelocityDirection.bearish;
      }
    }

    return VelocityExpansionResult(
      direction: direction,
      currentVelocity: currentVelocity,
      baselineVelocity: baselineVelocity,
      expansionRatio: expansionRatio,
      expanded: expanded,
    );
  }
}
