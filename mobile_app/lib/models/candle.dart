class Candle {
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  const Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  factory Candle.fromJson(Map<String, dynamic> json) {
    // MetaApi/MT5 commonly exposes tick volume as `tickVolume`, while
    // some feeds expose `volume` or `realVolume`. The velocity strategy
    // requires a non-zero volume series, so accept all supported forms.
    final rawVolume = json['volume'] ??
        json['tickVolume'] ??
        json['realVolume'] ??
        json['tick_volume'] ??
        json['real_volume'];

    return Candle(
      time: _dateTime(json['time']),
      open: _number(json['open']),
      high: _number(json['high']),
      low: _number(json['low']),
      close: _number(json['close']),
      volume: _number(rawVolume),
    );
  }

  static DateTime _dateTime(dynamic value) {
    if (value is num) {
      final milliseconds = value.abs() < 100000000000
          ? (value * 1000).round()
          : value.round();
      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    }

    final text = value?.toString() ?? '';
    return DateTime.tryParse(text) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  static double _number(dynamic value) {
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
