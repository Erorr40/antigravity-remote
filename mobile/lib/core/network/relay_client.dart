import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';

enum ConnectionStatus { disconnected, connecting, connected }

class RelayClient {
  final String relayUrl;
  final String mobileDeviceId;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;

  ConnectionStatus _status = ConnectionStatus.disconnected;
  ConnectionStatus get status => _status;

  final _envelopeController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onEnvelope => _envelopeController.stream;

  final _statusController = StreamController<ConnectionStatus>.broadcast();
  Stream<ConnectionStatus> get onStatusChange => _statusController.stream;

  RelayClient({
    required this.relayUrl,
    required this.mobileDeviceId,
  });

  void connect() {
    if (_status == ConnectionStatus.connected || _status == ConnectionStatus.connecting) {
      return;
    }

    _updateStatus(ConnectionStatus.connecting);

    final cleanUrl = relayUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
    final uri = Uri.parse('$cleanUrl?deviceId=$mobileDeviceId&role=client');

    try {
      _channel = WebSocketChannel.connect(uri);

      _subscription = _channel!.stream.listen(
        (data) {
          if (_status != ConnectionStatus.connected) {
            _updateStatus(ConnectionStatus.connected);
            _startPingTimer();
          }

          try {
            final raw = data is String ? data : utf8.decode(data as List<int>);
            final envelope = jsonDecode(raw) as Map<String, dynamic>;
            _envelopeController.add(envelope);
          } catch (e) {
            // Malformed packet
          }
        },
        onError: (error) {
          _handleDisconnect();
        },
        onDone: () {
          _handleDisconnect();
        },
      );
    } catch (e) {
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _updateStatus(ConnectionStatus.disconnected);
    _stopPingTimer();
    _subscription?.cancel();
    _subscription = null;
    _channel = null;

    // Schedule auto-reconnect
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 4), () {
      connect();
    });
  }

  void _updateStatus(ConnectionStatus newStatus) {
    _status = newStatus;
    _statusController.add(_status);
  }

  void _startPingTimer() {
    _stopPingTimer();
    _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      sendEnvelope(
        type: 'HEARTBEAT_PING',
        targetId: '*',
        plainPayload: {'clientTime': DateTime.now().millisecondsSinceEpoch},
      );
    });
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// Dispatch generic envelope to relay
  void sendEnvelope({
    required String type,
    required String targetId,
    Map<String, dynamic>? plainPayload,
    Map<String, dynamic>? encryptedPayload,
  }) {
    if (_status != ConnectionStatus.connected || _channel == null) {
      return;
    }

    final envelope = {
      'messageId': const Uuid().v4(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'type': type,
      'senderId': mobileDeviceId,
      'targetId': targetId,
      if (plainPayload != null) 'plainPayload': plainPayload,
      if (encryptedPayload != null) 'encryptedPayload': encryptedPayload,
    };

    _channel!.sink.add(jsonEncode(envelope));
  }

  void dispose() {
    _stopPingTimer();
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _envelopeController.close();
    _statusController.close();
  }
}
