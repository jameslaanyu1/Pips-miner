class TradingConfig {
  final String symbol;

  // Velocity-expansion engine.
  final int velocityBaselinePeriod;
  final double velocityExpansionThreshold;

  // Agreed position-management distance.
  final double trailingPips;

  // Reversal stop distance.
  final double reversalPips;

  // Position sizing.
  final double riskPercent;
  final double minimumVolume;
  final double volumeStep;
  final double maximumVolume;

  const TradingConfig({
    this.symbol = 'XAUUSD',

    this.velocityBaselinePeriod = 14,
    this.velocityExpansionThreshold = 1.5,

    // AGREED: 100 pips.
    this.trailingPips = 100.0,

    // Opposite reversal stop follows the active position.
    this.reversalPips = 100.0,

    this.riskPercent = 1.0,
    this.minimumVolume = 0.01,
    this.volumeStep = 0.01,
    this.maximumVolume = 1.0,
  });
}
