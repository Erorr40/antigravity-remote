import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cryptography/cryptography.dart';
import '../../core/storage/storage_service.dart';
import '../../core/crypto/e2ee_service.dart';
import '../../core/network/relay_client.dart';
import '../../domain/models/paired_host.dart';

final storageServiceProvider = Provider((ref) => StorageService());
final e2eeServiceProvider = Provider((ref) => E2eeService());

class HostState {
  final List<PairedHost> hosts;
  final PairedHost? activeHost;
  final ConnectionStatus relayStatus;
  final bool isPairing;
  final String? errorMessage;

  HostState({
    this.hosts = const [],
    this.activeHost,
    this.relayStatus = ConnectionStatus.disconnected,
    this.isPairing = false,
    this.errorMessage,
  });

  HostState copyWith({
    List<PairedHost>? hosts,
    PairedHost? activeHost,
    ConnectionStatus? relayStatus,
    bool? isPairing,
    String? errorMessage,
  }) {
    return HostState(
      hosts: hosts ?? this.hosts,
      activeHost: activeHost ?? this.activeHost,
      relayStatus: relayStatus ?? this.relayStatus,
      isPairing: isPairing ?? this.isPairing,
      errorMessage: errorMessage,
    );
  }
}

class HostNotifier extends StateNotifier<HostState> {
  final Ref ref;
  RelayClient? _relayClient;
  SimpleKeyPair? _mobileKeyPair;
  SecretKey? _activeSessionKey;
  int _sequenceNumber = 0;

  HostNotifier(this.ref) : super(HostState()) {
    _init();
  }

  Future<void> _init() async {
    final storage = ref.read(storageServiceProvider);
    final e2ee = ref.read(e2eeServiceProvider);

    // Load or generate persistent keypair
    _mobileKeyPair = await e2ee.generateKeyPair();

    final hosts = await storage.getPairedHosts();
    state = state.copyWith(
      hosts: hosts,
      activeHost: hosts.isNotEmpty ? hosts.first : null,
    );

    if (state.activeHost != null) {
      connectToHost(state.activeHost!);
    }
  }

  Future<void> connectToHost(PairedHost host) async {
    _relayClient?.dispose();
    state = state.copyWith(activeHost: host);

    final storage = ref.read(storageServiceProvider);
    final mobileId = await storage.getOrCreateDeviceId();

    _relayClient = RelayClient(
      relayUrl: host.relayUrl,
      mobileDeviceId: mobileId,
    );

    _relayClient!.onStatusChange.listen((status) {
      state = state.copyWith(relayStatus: status);
    });

    _relayClient!.onEnvelope.listen((envelope) {
      _handleInboundEnvelope(envelope);
    });

    _relayClient!.connect();

    // Derive E2EE session key for this host
    final e2ee = ref.read(e2eeServiceProvider);
    _activeSessionKey = await e2ee.deriveSessionKey(
      mobileKeyPair: _mobileKeyPair!,
      hostPublicKeyRawBase64: host.hostPublicKeyRawBase64,
    );
  }

  void _handleInboundEnvelope(Map<String, dynamic> envelope) {
    final type = envelope['type'] as String?;

    if (type == 'HEARTBEAT_PONG') {
      final senderId = envelope['senderId'] as String?;
      final plain = envelope['plainPayload'] as Map<String, dynamic>?;

      if (state.activeHost != null && senderId == state.activeHost!.hostDeviceId) {
        final updated = state.activeHost!;
        updated.isOnline = plain?['online'] as bool? ?? true;
        updated.activeSessionId = plain?['activeSessionId'] as String?;
        updated.activeTasksCount = (plain?['activeTasksCount'] as num?)?.toInt() ?? 0;
        updated.hostOs = plain?['hostOs'] as String?;
        updated.uptimeSeconds = (plain?['uptimeSeconds'] as num?)?.toInt();
        state = state.copyWith(activeHost: updated);
      }
    }
  }

  /// Pair with laptop using scanned QR payload
  Future<bool> pairWithQr(String qrJsonString) async {
    state = state.copyWith(isPairing: true, errorMessage: null);

    try {
      final qrData = jsonDecode(qrJsonString) as Map<String, dynamic>;
      final relayUrl = qrData['relayUrl'] as String;
      final hostDeviceId = qrData['hostDeviceId'] as String;
      final hostName = qrData['hostName'] as String;
      final hostPublicKey = qrData['hostPublicKey'] as String;
      final pairToken = qrData['pairToken'] as String;

      final storage = ref.read(storageServiceProvider);
      final e2ee = ref.read(e2eeServiceProvider);
      final mobileId = await storage.getOrCreateDeviceId();

      final mobilePubBase64 = await e2ee.exportPublicKeyRawBase64(_mobileKeyPair!);

      // Connect temporary client to complete handshake
      final tempClient = RelayClient(relayUrl: relayUrl, mobileDeviceId: mobileId);
      tempClient.connect();

      // Wait for socket open
      await Future.delayed(const Duration(milliseconds: 800));

      tempClient.sendEnvelope(
        type: 'PAIRING_REQUEST',
        targetId: hostDeviceId,
        plainPayload: {
          'pairToken': pairToken,
          'mobileDeviceId': mobileId,
          'deviceName': 'Android Client (Mobile)',
          'mobilePublicKey': mobilePubBase64,
        },
      );

      final responseEnvelope = await tempClient.onEnvelope
          .firstWhere((env) => env['type'] == 'PAIRING_RESPONSE')
          .timeout(const Duration(seconds: 10));

      tempClient.dispose();

      final plain = responseEnvelope['plainPayload'] as Map<String, dynamic>;
      if (plain['success'] == true) {
        final newHost = PairedHost(
          hostDeviceId: hostDeviceId,
          hostName: hostName,
          relayUrl: relayUrl,
          hostPublicKeyRawBase64: hostPublicKey,
          pairedAt: DateTime.now().millisecondsSinceEpoch,
          isOnline: true,
        );

        await storage.savePairedHost(newHost);
        final hosts = await storage.getPairedHosts();

        state = state.copyWith(
          hosts: hosts,
          activeHost: newHost,
          isPairing: false,
        );

        connectToHost(newHost);
        return true;
      } else {
        state = state.copyWith(
          isPairing: false,
          errorMessage: plain['errorMessage'] as String? ?? 'Pairing failed',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isPairing: false,
        errorMessage: 'Pairing error: ${e.toString()}',
      );
      return false;
    }
  }

  /// Send encrypted command to active host
  Future<void> sendEncryptedCommand(String action, Map<String, dynamic> payload, {String? sessionId}) async {
    if (_relayClient == null || _activeSessionKey == null || state.activeHost == null) {
      return;
    }

    _sequenceNumber++;
    final e2ee = ref.read(e2eeServiceProvider);

    final innerMsg = {
      'innerId': 'cmd-${DateTime.now().millisecondsSinceEpoch}',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'action': action,
      if (sessionId != null) 'sessionId': sessionId,
      'payload': payload,
    };

    final encrypted = await e2ee.encryptPayload(
      sessionKey: _activeSessionKey!,
      plaintextJson: innerMsg,
      sequenceNumber: _sequenceNumber,
    );

    _relayClient!.sendEnvelope(
      type: 'ENCRYPTED_CONTAINER',
      targetId: state.activeHost!.hostDeviceId,
      encryptedPayload: encrypted,
    );
  }

  RelayClient? get relayClient => _relayClient;
  SecretKey? get activeSessionKey => _activeSessionKey;
}

final hostProvider = StateNotifierProvider<HostNotifier, HostState>((ref) {
  return HostNotifier(ref);
});
