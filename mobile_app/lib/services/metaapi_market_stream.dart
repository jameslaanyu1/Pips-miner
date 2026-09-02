import 'dart:async';
import 'dart:math';
import 'package:socket_io_client/socket_io_client.dart' as io;

class MetaApiMarketStream {
  MetaApiMarketStream({required this.token, required this.accountId, required this.streamUrl});
  final String token;
  final String accountId;
  final String streamUrl;
  io.Socket? _socket;
  bool _authenticated = false;
  bool _closed = false;
  int _requestCounter = 0;
  Timer? _connectTimeout;
  final StreamController<Map<String, dynamic>> _pricesController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Object> _errorsController = StreamController<Object>.broadcast();
  Stream<Map<String, dynamic>> get prices => _pricesController.stream;
  Stream<Object> get errors => _errorsController.stream;
  bool get connected => _socket?.connected == true && _authenticated;

  String _requestId() => '${DateTime.now().microsecondsSinceEpoch}_${_requestCounter++}_${Random().nextInt(1 << 20)}';

  Future<void> connect(String symbol) async {
    if (_closed) throw StateError('MetaApi market stream is closed.');
    if (connected) return;
    final url = streamUrl.endsWith('/') ? streamUrl.substring(0, streamUrl.length - 1) : streamUrl;
    final socket = io.io(url, io.OptionBuilder()
      .setTransports(['websocket'])
      .setPath('/ws')
      .setQuery({'auth-token': token})
      .disableAutoConnect()
      .enableReconnection()
      .setReconnectionAttempts(20)
      .setReconnectionDelay(250)
      .setReconnectionDelayMax(2000)
      .build());
    _socket = socket;
    final completer = Completer<void>();
    _connectTimeout = Timer(const Duration(seconds: 20), () {
      if (!completer.isCompleted) completer.completeError(TimeoutException('MetaApi real-time stream connection timed out.'));
    });
    socket.onConnect((_) => _sendRequest({'type': 'subscribe', 'accountId': accountId, 'requestId': _requestId(), 'application': 'MetaApi'}));
    socket.on('synchronization', (raw) {
      if (raw is! Map) return;
      final data = Map<String, dynamic>.from(raw);
      final type = data['type']?.toString();
      if (type == 'authenticated') {
        _authenticated = true;
        _sendRequest({'type': 'synchronize', 'accountId': accountId, 'requestId': _requestId(), 'application': 'MetaApi', 'version': 2});
        return;
      }
      if (type == 'prices') {
        final values = data['prices'];
        if (values is List) {
          for (final rawPrice in values) {
            if (rawPrice is! Map) continue;
            final price = Map<String, dynamic>.from(rawPrice);
            if (price['symbol']?.toString().toUpperCase() == symbol.toUpperCase()) _pricesController.add(price);
          }
        }
        if (!completer.isCompleted) completer.complete();
      }
      if (type == 'status' && data['connected'] != true && !_closed) _errorsController.add(StateError('MetaApi terminal is not connected to the broker.'));
      if (type == 'subscriptionDowngraded' && !_closed) _errorsController.add(StateError('MetaApi downgraded the market-data subscription.'));
    });
    socket.onDisconnect((reason) {
      _authenticated = false;
      if (!_closed) _errorsController.add(StateError('MetaApi market stream disconnected: $reason'));
    });
    socket.onError((error) {
      if (!completer.isCompleted) completer.completeError(error);
      if (!_closed) _errorsController.add(StateError(error.toString()));
    });
    socket.on('processingError', (error) { if (!_closed) _errorsController.add(StateError(error.toString())); });
    socket.connect();
    try { await completer.future; } finally { _connectTimeout?.cancel(); }
    _sendRequest({'type': 'subscribeToMarketData', 'accountId': accountId, 'requestId': _requestId(), 'application': 'MetaApi', 'symbol': symbol, 'subscriptions': const [
      {'type': 'quotes', 'intervalInMilliseconds': 0},
      {'type': 'ticks'},
      {'type': 'candles', 'timeframe': '1m'},
    ]});
  }

  void _sendRequest(Map<String, dynamic> request) {
    final socket = _socket;
    if (socket == null || !socket.connected || _closed) return;
    socket.emit('request', request);
  }

  Future<void> close() async {
    _closed = true;
    _connectTimeout?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    await _pricesController.close();
    await _errorsController.close();
  }
}
