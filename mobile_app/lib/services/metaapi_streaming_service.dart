import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;

/// Direct MetaApi real-time streaming client.
/// The APK receives only an account-scoped reader token, never the admin token.
class MetaApiStreamingService {
  MetaApiStreamingService({required this.token, required this.accountId, required this.streamUrl});

  final String token;
  final String accountId;
  final String streamUrl;
  IO.Socket? _socket;
  final StreamController<Map<String, dynamic>> _prices = StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _events = StreamController.broadcast();

  Stream<Map<String, dynamic>> get prices => _prices.stream;
  Stream<Map<String, dynamic>> get events => _events.stream;
  bool get connected => _socket?.connected == true;
  String _requestId() => '${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
  static int _counter = 0;

  Future<void> connect(String symbol) async {
    await disconnect();
    final ready = Completer<void>();
    final socket = IO.io(
      streamUrl.endsWith('/') ? streamUrl.substring(0, streamUrl.length - 1) : streamUrl,
      IO.OptionBuilder().setTransports(['websocket']).setPath('/ws').setQuery({'auth-token': token.trim()})
          .disableAutoConnect().enableForceNew().enableReconnection().setReconnectionAttempts(20)
          .setReconnectionDelay(250).setReconnectionDelayMax(2000).build(),
    );
    _socket = socket;
    var marketSubscribed = false;

    void fail(Object error) {
      _events.add({'type': 'error', 'message': error.toString()});
      if (!ready.isCompleted) ready.completeError(error);
    }

    void subscribeMarket() {
      if (marketSubscribed || !socket.connected) return;
      marketSubscribed = true;
      socket.emit('request', {
        'accountId': accountId,
        'type': 'subscribeToMarketData',
        'requestId': _requestId(),
        'symbol': symbol,
        'subscriptions': [
          {'type': 'ticks'},
          {'type': 'quotes', 'intervalInMilliseconds': 0},
          {'type': 'candles', 'timeframe': '1m', 'intervalInMilliseconds': 1000},
        ],
      });
    }

    socket.onConnect((_) {
      socket.emit('request', {'accountId': accountId, 'type': 'subscribe', 'requestId': _requestId()});
    });

    socket.on('synchronization', (raw) {
      if (raw is! Map) return;
      final data = Map<String, dynamic>.from(raw);
      _events.add(data);
      final type = data['type']?.toString();
      if (type == 'authenticated') {
        socket.emit('request', {
          'accountId': accountId,
          'type': 'synchronize',
          'requestId': _requestId(),
          'startHistoryTime': DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String(),
        });
        subscribeMarket();
      }
      if (type == 'prices') {
        final values = data['prices'];
        if (values is List) {
          for (final rawPrice in values) {
            if (rawPrice is! Map) continue;
            final price = Map<String, dynamic>.from(rawPrice);
            if (price['symbol']?.toString().toUpperCase() == symbol.toUpperCase()) _prices.add(price);
          }
        }
        if (!ready.isCompleted) ready.complete();
      }
    });

    socket.on('response', (raw) {
      if (raw is! Map) return;
      final data = Map<String, dynamic>.from(raw);
      _events.add(data);
      if (data['type']?.toString() == 'response' && data['requestId'] != null) subscribeMarket();
    });
    socket.on('processingError', fail);
    socket.onConnectError(fail);
    socket.onDisconnect((raw) {
      _events.add({'type': 'disconnected', 'reason': raw?.toString() ?? ''});
    });

    socket.connect();
    try {
      await ready.future.timeout(const Duration(seconds: 20));
      if (!connected) throw Exception('MetaApi live market stream disconnected during startup.');
    } on TimeoutException {
      throw Exception('MetaApi live market stream did not become ready within 20 seconds.');
    }
  }

  Future<void> disconnect() async {
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      socket.clearListeners();
      socket.disconnect();
      socket.dispose();
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await _prices.close();
    await _events.close();
  }
}
