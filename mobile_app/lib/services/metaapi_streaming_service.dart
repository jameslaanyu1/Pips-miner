import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;

/// Direct MetaApi real-time streaming client.
///
/// The app receives a narrowly-scoped MetaApi account token from the Pips-Miner
/// backend. The administrator MetaApi token is never shipped in the APK.
class MetaApiStreamingService {
  MetaApiStreamingService({required this.token, required this.accountId});

  final String token;
  final String accountId;

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

    final socket = IO.io(
      'https://mt-client-api-v1.agiliumtrade.agiliumtrade.ai',
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setQuery({'auth-token': token.trim()})
          .disableAutoConnect()
          .enableForceNew()
          .build(),
    );
    _socket = socket;

    final ready = Completer<void>();
    var synchronized = false;
    var marketSubscribed = false;

    socket.onConnect((_) {
      socket.emit('request', {
        'accountId': accountId,
        'type': 'subscribe',
        'requestId': _requestId(),
      });
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
          'startHistoryTime': DateTime.now()
              .subtract(const Duration(days: 1))
              .toUtc()
              .toIso8601String(),
        });
      }

      if (type == 'prices') {
        final prices = data['prices'];
        if (prices is List) {
          for (final rawPrice in prices) {
            if (rawPrice is! Map) continue;
            final price = Map<String, dynamic>.from(rawPrice);
            if (price['symbol']?.toString().toUpperCase() != symbol.toUpperCase()) continue;
            _prices.add(price);
          }
        }
      }

      if (type == 'synchronizationFinished') {
        synchronized = true;
      }

      // Some MetaApi deployments emit the terminal state synchronization
      // events without a single final marker. A valid price packet is enough
      // to establish that the stream is usable for the trading engine.
      if (synchronized && !marketSubscribed) {
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
    });

    socket.on('response', (raw) {
      if (raw is! Map) return;
      final data = Map<String, dynamic>.from(raw);
      _events.add(data);
      if (data['type']?.toString() == 'response' &&
          !marketSubscribed &&
          synchronized) {
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
    });

    socket.on('processingError', (raw) {
      final message = raw?.toString() ?? 'MetaApi streaming error';
      if (!ready.isCompleted) ready.completeError(Exception(message));
      _events.add({'type': 'error', 'message': message});
    });

    socket.onConnectError((raw) {
      final error = Exception('MetaApi streaming connection failed: $raw');
      if (!ready.isCompleted) ready.completeError(error);
      _events.add({'type': 'error', 'message': error.toString()});
    });

    socket.onDisconnect((raw) {
      _events.add({'type': 'disconnected', 'reason': raw?.toString() ?? ''});
    });

    socket.connect();

    // Do not wait for historical synchronization indefinitely. The engine
    // can continue once the first live price packet arrives.
    await Future.any<void>([
      ready.future,
      Future<void>.delayed(const Duration(seconds: 20)),
    ]);
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
