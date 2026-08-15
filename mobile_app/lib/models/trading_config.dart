class TradingConfig {
  final String symbol;
  final double riskPercent;
  final double reversalPips;
  final double minimumVolume;
  final double volumeStep;
  final double maximumVolume;
  final int volatilityPeriod;
  final double volatilityMultiplier;
  final int momentumPeriod;
  final double momentumThreshold;

  const TradingConfig({
    this.symbol = 'XAUUSD',
    this.riskPercent = 1.0,
    this.reversalPips = 100.0,
    this.minimumVolume = 0.01,
    this.volumeStep = 0.01,
    this.maximumVolume = 1.0,
    this.volatilityPeriod = 14,
    this.volatilityMultiplier = 1.0,
    this.momentumPeriod = 14,
    this.momentumThreshold = 0.0,
  });
}
