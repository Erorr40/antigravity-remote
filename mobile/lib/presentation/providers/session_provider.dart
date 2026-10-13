import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/session_item.dart';
import '../../core/network/relay_client.dart';
import 'host_provider.dart';

class SessionState {
  final List<SessionItem> sessions;
  final String? selectedSessionId;
  final bool isLoading;
  final String? errorMessage;

  SessionState({
    this.sessions = const [],
    this.selectedSessionId,
    this.isLoading = false,
    this.errorMessage,
  });

  SessionState copyWith({
    List<SessionItem>? sessions,
    String? selectedSessionId,
    bool? isLoading,
    String? errorMessage,
  }) {
    return SessionState(
      sessions: sessions ?? this.sessions,
      selectedSessionId: selectedSessionId ?? this.selectedSessionId,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class SessionNotifier extends StateNotifier<SessionState> {
  final Ref ref;

  SessionNotifier(this.ref) : super(SessionState()) {
    _listenToInbound();
  }

  void _listenToInbound() {
    ref.listen(hostProvider, (prev, next) {
      final client = ref.read(hostProvider.notifier).relayClient;
      if (client != null && prev?.relayStatus != next.relayStatus && next.relayStatus == ConnectionStatus.connected) {
        fetchSessions();
      }
    });
  }

  Future<void> fetchSessions() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    final hostNotifier = ref.read(hostProvider.notifier);
    final client = hostNotifier.relayClient;
    final sessionKey = hostNotifier.activeSessionKey;

    if (client == null || sessionKey == null) {
      state = state.copyWith(isLoading: false, errorMessage: 'Host not connected');
      return;
    }

    final e2ee = ref.read(e2eeServiceProvider);

    // Listen for encrypted RESP_SESSION_LIST
    final sub = client.onEnvelope.listen((envelope) async {
      if (envelope['type'] == 'ENCRYPTED_CONTAINER') {
        final enc = envelope['encryptedPayload'] as Map<String, dynamic>;
        try {
          final inner = await e2ee.decryptPayload(
            sessionKey: sessionKey,
            nonceBase64: enc['nonce'] as String,
            ciphertextBase64: enc['ciphertext'] as String,
            sequenceNumber: (enc['sequenceNumber'] as num).toInt(),
          );

          if (inner['action'] == 'RESP_SESSION_LIST') {
            final list = inner['payload']['sessions'] as List;
            final sessions = list.map((s) => SessionItem.fromJson(s as Map<String, dynamic>)).toList();
            state = state.copyWith(
              sessions: sessions,
              isLoading: false,
              selectedSessionId: state.selectedSessionId ?? (sessions.isNotEmpty ? sessions.first.sessionId : null),
            );
          }
        } catch (_) {}
      }
    });

    await hostNotifier.sendEncryptedCommand('REQ_SESSION_LIST', {'limit': 40});

    // Timeout safety
    Future.delayed(const Duration(seconds: 5), () {
      if (state.isLoading) {
        state = state.copyWith(isLoading: false);
        sub.cancel();
      }
    });
  }

  void selectSession(String sessionId) {
    state = state.copyWith(selectedSessionId: sessionId);
  }
}

final sessionProvider = StateNotifierProvider<SessionNotifier, SessionState>((ref) {
  return SessionNotifier(ref);
});
