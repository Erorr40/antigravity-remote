import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/transcript_step.dart';
import '../../core/auth/biometric_service.dart';
import '../../core/notifications/notification_service.dart';
import 'host_provider.dart';
import 'session_provider.dart';

final biometricServiceProvider = Provider((ref) => BiometricService());
final notificationServiceProvider = Provider((ref) => NotificationService());

class TranscriptStreamState {
  final String? sessionId;
  final List<TranscriptStep> steps;
  final bool isLive;
  final bool isLoading;
  final bool isSendingPrompt;
  final String? streamingThinking;
  final String? streamingContent;
  final String? activeTaskId;

  TranscriptStreamState({
    this.sessionId,
    this.steps = const [],
    this.isLive = false,
    this.isLoading = false,
    this.isSendingPrompt = false,
    this.streamingThinking,
    this.streamingContent,
    this.activeTaskId,
  });

  TranscriptStreamState copyWith({
    String? sessionId,
    List<TranscriptStep>? steps,
    bool? isLive,
    bool? isLoading,
    bool? isSendingPrompt,
    String? streamingThinking,
    String? streamingContent,
    String? activeTaskId,
  }) {
    return TranscriptStreamState(
      sessionId: sessionId ?? this.sessionId,
      steps: steps ?? this.steps,
      isLive: isLive ?? this.isLive,
      isLoading: isLoading ?? this.isLoading,
      isSendingPrompt: isSendingPrompt ?? this.isSendingPrompt,
      streamingThinking: streamingThinking,
      streamingContent: streamingContent,
      activeTaskId: activeTaskId ?? this.activeTaskId,
    );
  }
}

class TranscriptStreamNotifier extends StateNotifier<TranscriptStreamState> {
  final Ref ref;
  StreamSubscription? _subscription;

  TranscriptStreamNotifier(this.ref) : super(TranscriptStreamState()) {
    _listenToSessionChanges();
  }

  void _listenToSessionChanges() {
    ref.listen<SessionState>(sessionProvider, (prev, next) {
      if (next.selectedSessionId != null && next.selectedSessionId != state.sessionId) {
        syncSession(next.selectedSessionId!);
      }
    });
  }

  Future<void> syncSession(String sessionId) async {
    _subscription?.cancel();
    state = state.copyWith(sessionId: sessionId, isLoading: true, steps: []);

    final hostNotifier = ref.read(hostProvider.notifier);
    final client = hostNotifier.relayClient;
    final sessionKey = hostNotifier.activeSessionKey;

    if (client == null || sessionKey == null) {
      state = state.copyWith(isLoading: false);
      return;
    }

    final e2ee = ref.read(e2eeServiceProvider);
    final notifications = ref.read(notificationServiceProvider);

    _subscription = client.onEnvelope.listen((envelope) async {
      if (envelope['type'] == 'ENCRYPTED_CONTAINER') {
        final enc = envelope['encryptedPayload'] as Map<String, dynamic>;
        try {
          final inner = await e2ee.decryptPayload(
            sessionKey: sessionKey,
            nonceBase64: enc['nonce'] as String,
            ciphertextBase64: enc['ciphertext'] as String,
            sequenceNumber: (enc['sequenceNumber'] as num).toInt(),
          );

          if (inner['sessionId'] != state.sessionId) {
            return;
          }

          final action = inner['action'] as String;
          final payload = inner['payload'] as Map<String, dynamic>;

          if (action == 'RESP_TRANSCRIPT_SNAPSHOT') {
            final rawSteps = payload['steps'] as List;
            final steps = rawSteps.map((s) => TranscriptStep.fromJson(s as Map<String, dynamic>)).toList();
            state = state.copyWith(
              steps: steps,
              isLive: payload['isLive'] as bool? ?? false,
              isLoading: false,
            );
          } else if (action == 'EVT_TRANSCRIPT_DELTA') {
            _handleDelta(payload, notifications);
          }
        } catch (_) {}
      }
    });

    // Request full snapshot from step 0
    await hostNotifier.sendEncryptedCommand(
      'REQ_TRANSCRIPT_SYNC',
      {'sessionId': sessionId, 'fromStepIndex': 0},
      sessionId: sessionId,
    );
  }

  void _handleDelta(Map<String, dynamic> delta, NotificationService notifications) {
    final kind = delta['kind'] as String;
    final stepIndex = (delta['stepIndex'] as num?)?.toInt() ?? -1;

    if (kind == 'APPEND_STEP' && delta['step'] != null) {
      final newStep = TranscriptStep.fromJson(delta['step'] as Map<String, dynamic>);
      final updatedSteps = List<TranscriptStep>.from(state.steps)..add(newStep);
      state = state.copyWith(
        steps: updatedSteps,
        streamingThinking: null,
        streamingContent: null,
      );

      // Check for notifications
      if (newStep.status == 'DONE' && newStep.source == 'MODEL') {
        notifications.showTaskComplete(
          id: stepIndex,
          title: 'Antigravity: Task Complete',
          body: (newStep.content?.trim().split('\n').first ?? 'Response ready.'),
        );
      } else if (newStep.toolCalls != null && newStep.toolCalls!.isNotEmpty) {
        notifications.showProgress(
          id: 999,
          title: 'Antigravity Executing Tool',
          body: newStep.toolCalls!.first.toolName,
        );
      }
    } else if (kind == 'STREAM_THINKING') {
      final chunk = delta['textChunk'] as String? ?? '';
      state = state.copyWith(
        streamingThinking: (state.streamingThinking ?? '') + chunk,
      );
    } else if (kind == 'STREAM_CONTENT') {
      final chunk = delta['textChunk'] as String? ?? '';
      state = state.copyWith(
        streamingContent: (state.streamingContent ?? '') + chunk,
      );
    }
  }

  /// Dispatch prompt to active session with mandatory Biometric check
  Future<bool> sendPrompt(String text) async {
    if (state.sessionId == null || text.trim().isEmpty) return false;

    // 1. Biometric Authentication Gate
    final bio = ref.read(biometricServiceProvider);
    final authenticated = await bio.authenticate(
      reason: 'Biometric authorization required to execute prompt on remote laptop',
    );

    if (!authenticated) {
      return false;
    }

    state = state.copyWith(isSendingPrompt: true);

    try {
      final hostNotifier = ref.read(hostProvider.notifier);
      await hostNotifier.sendEncryptedCommand(
        'CMD_DISPATCH_PROMPT',
        {
          'sessionId': state.sessionId,
          'prompt': text.trim(),
          'createNewSession': false,
        },
        sessionId: state.sessionId,
      );

      // Optimistically append user message to feed
      final optimisticStep = TranscriptStep(
        stepIndex: state.steps.length,
        source: 'USER_EXPLICIT',
        type: 'USER_INPUT',
        status: 'DONE',
        createdAt: DateTime.now().toIso8601String(),
        content: text.trim(),
      );

      state = state.copyWith(
        steps: [...state.steps, optimisticStep],
        isSendingPrompt: false,
      );
      return true;
    } catch (_) {
      state = state.copyWith(isSendingPrompt: false);
      return false;
    }
  }

  /// Abort running agent run or subagent task
  Future<void> abortTask({String? taskId}) async {
    if (state.sessionId == null) return;
    final hostNotifier = ref.read(hostProvider.notifier);
    await hostNotifier.sendEncryptedCommand(
      'CMD_ABORT_TASK',
      {
        'sessionId': state.sessionId,
        'taskId': taskId,
        'reason': 'Aborted from mobile client',
      },
      sessionId: state.sessionId,
    );
  }

  /// Interactive tool approval or rejection
  Future<void> respondToTool({
    required String callId,
    required String action, // "approve", "reject", "send_input"
    String? inputText,
  }) async {
    if (state.sessionId == null) return;
    final hostNotifier = ref.read(hostProvider.notifier);
    await hostNotifier.sendEncryptedCommand(
      'CMD_SEND_TOOL_INPUT',
      {
        'sessionId': state.sessionId,
        'callId': callId,
        'action': action,
        'inputText': inputText,
      },
      sessionId: state.sessionId,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final transcriptStreamProvider =
    StateNotifierProvider<TranscriptStreamNotifier, TranscriptStreamState>((ref) {
  return TranscriptStreamNotifier(ref);
});
