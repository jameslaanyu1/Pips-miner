import 'package:flutter_test/flutter_test.dart';
import 'package:pips_miner_app/models/candle.dart';
import 'package:pips_miner_app/strategy/velocity_expansion.dart';

void main() {
  test('detects bullish live velocity expansion against recent baseline', () {
    final baseTime = DateTime.utc(2026, 1, 1);
    final closes = <double>[100.0, 100.5, 100.4, 100.6, 103.0];
    final candles = List<Candle>.generate(closes.length, (i) {
      final close = closes[i];
      return Candle(
        time: baseTime.add(Duration(minutes: i)),
        open: close - 0.05,
        high: close + 0.1,
        low: close - 0.1,
        close: close,
        volume: 100,
      );
    });

    final result = VelocityExpansion.analyze(
      candles,
      baselinePeriod: 2,
      expansionThreshold: 1.5,
      volumeBaselinePeriod: 2,
      volumeExpansionThreshold: 1.5,
      livePrice: 103.5,
    );

    expect(result.velocityExpanded, isTrue);
    expect(result.direction, VelocityDirection.bullish);
    expect(result.expanded, isTrue);
  });
}
