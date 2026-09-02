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
  final bool velocityExpanded;
  final double currentVolume;
  final double baselineVolume;
  final double volumeExpansionRatio;
  final bool volumeExpanded;
  final bool expanded;

  const VelocityExpansionResult({
    required this.direction,
    required this.currentVelocity,
    required this.baselineVelocity,
    required this.expansionRatio,
    required this.velocityExpanded,
    required this.currentVolume,
    required this.baselineVolume,
    required this.volumeExpansionRatio,
    required this.volumeExpanded,
    required this.expanded,
  });

  static const VelocityExpansionResult empty = VelocityExpansionResult(
    direction: VelocityDirection.neutral,
    currentVelocity: 0,
    baselineVelocity: 0,
    expansionRatio: 0,
    velocityExpanded: false,
    currentVolume: 0,
    baselineVolume: 0,
    volumeExpansionRatio: 0,
    volumeExpanded: false,
    expanded: false,
  );
}

class VelocityExpansion {
  static VelocityExpansionResult analyze(
    List<Candle> candles, {
    int baselinePeriod = 14,
    double expansionThreshold = 1.0,
    int volumeBaselinePeriod = 14,
    double volumeExpansionThreshold = 1.5,
  }) {
    if (baselinePeriod <= 0 ||
        volumeBaselinePeriod <= 0 ||
        candles.length < baselinePeriod + 1 ||
        candles.length < volumeBaselinePeriod + 1) {
      return VelocityExpansionResult.empty;
    }

    final current = candles[candles.length - 1];
    final previous = candles[candles.length - 2];
    final currentVelocity = current.close - previous.close;

    double totalVelocity = 0;
    final baselineStart = candles.length - baselinePeriod - 1;
    final baselineEnd = candles.length - 2;

    for (int i = baselineStart; i <= baselineEnd; i++) {
      final velocity = candles[i].close - candles[i - 1].close;
      totalVelocity += velocity.abs();
    }

    final baselineVelocity = totalVelocity / baselinePeriod;
    final expansionRatio = baselineVelocity > 0
        ? currentVelocity.abs() / baselineVelocity
        : 0.0;
    final velocityExpanded =
        baselineVelocity > 0 && expansionRatio > expansionThreshold;

    // New entry gate: intrabar M1 volatility expansion against the prior
    // two completed candles. The forming candle's high/low is used so the
    // detector can react before the M1 candle closes.
    const volatilityBaselinePeriod = 2;
    final volatilityStart = candles.length - volatilityBaselinePeriod - 1;
    final volatilityEnd = candles.length - 2;
    var totalRange = 0.0;

    for (int i = volatilityStart; i <= volatilityEnd; i++) {
      totalRange += (candles[i].high - candles[i].low).abs();
    }

    final baselineRange = totalRange / volatilityBaselinePeriod;
    final currentRange = (current.high - current.low).abs();
    final volatilityRatio =
        baselineRange > 0 ? currentRange / baselineRange : 0.0;
    final volatilityExpanded =
        baselineRange > 0 && volatilityRatio > 1.0;

    VelocityDirection direction = VelocityDirection.neutral;

    if (velocityExpanded) {
      if (currentVelocity > 0) {
        direction = VelocityDirection.bullish;
      } else if (currentVelocity < 0) {
        direction = VelocityDirection.bearish;
      }
    }

    // If velocity did not trigger, volatility expansion alone can trigger
    // an entry. Direction comes from the forming candle's live movement.
    if (direction == VelocityDirection.neutral && volatilityExpanded) {
      final upwardMove = current.high - current.open;
      final downwardMove = current.open - current.low;

      if (upwardMove > downwardMove && upwardMove > 0) {
        direction = VelocityDirection.bullish;
      } else if (downwardMove > upwardMove && downwardMove > 0) {
        direction = VelocityDirection.bearish;
      } else if (current.close > current.open) {
        direction = VelocityDirection.bullish;
      } else if (current.close < current.open) {
        direction = VelocityDirection.bearish;
      } else if (current.close > previous.close) {
        direction = VelocityDirection.bullish;
      } else if (current.close < previous.close) {
        direction = VelocityDirection.bearish;
      }
    }

    // Volume remains diagnostic only and is not an entry requirement.
    double totalVolume = 0;
    final volumeStart = candles.length - volumeBaselinePeriod - 1;
    final volumeEnd = candles.length - 2;

    for (int i = volumeStart; i <= volumeEnd; i++) {
      totalVolume += candles[i].volume;
    }

    final baselineVolume = totalVolume / volumeBaselinePeriod;
    final currentVolume = current.volume;
    final volumeExpansionRatio =
        baselineVolume > 0 ? currentVolume / baselineVolume : 0.0;
    final volumeExpanded =
        baselineVolume > 0 &&
        volumeExpansionRatio >= volumeExpansionThreshold;

    return VelocityExpansionResult(
      direction: direction,
      currentVelocity: currentVelocity,
      baselineVelocity: baselineVelocity,
      expansionRatio: velocityExpanded ? expansionRatio : volatilityRatio,
      velocityExpanded: velocityExpanded,
      currentVolume: currentVolume,
      baselineVolume: baselineVolume,
      volumeExpansionRatio: volumeExpansionRatio,
      volumeExpanded: volumeExpanded,
      // Entry gate: velocity expansion OR 2-candle volatility expansion.
      expanded: velocityExpanded || volatilityExpanded,
    );
  }
}