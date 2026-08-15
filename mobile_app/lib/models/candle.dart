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
    return Candle(
      time: DateTime.tryParse(json['time']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      open: _number(json['open']),
      high: _number(json['high']),
      low: _number(json['low']),
      close: _number(json['close']),
      volume: _number(json['volume']),
    );
  }

  static double _number(dynamic value) {
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
