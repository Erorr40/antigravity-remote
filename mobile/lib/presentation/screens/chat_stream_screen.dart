import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../providers/transcript_stream_provider.dart';
import '../providers/session_provider.dart';
import '../widgets/thinking_box.dart';
import '../widgets/tool_call_card.dart';
import 'artifact_viewer_screen.dart';

class ChatStreamScreen extends ConsumerStatefulWidget {
  const ChatStreamScreen({super.key});

  @override
  ConsumerState<ChatStreamScreen> createState() => _ChatStreamScreenState();
}

class _ChatStreamScreenState extends ConsumerState<ChatStreamScreen> {
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSend() async {
    final text = _promptController.text.trim();
    if (text.isEmpty) return;

    _promptController.clear();
    final sent = await ref.read(transcriptStreamProvider.notifier).sendPrompt(text);
    if (sent) {
      _scrollToBottom();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Prompt dispatch cancelled or biometric failed.')),
        );
      }
    }
  }

  void _confirmAbort() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abort Running Task?'),
        content: const Text(
          'This will send an immediate termination signal to the active Antigravity agent or subagent process on your laptop.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(transcriptStreamProvider.notifier).abortTask();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Abort signal sent.')),
              );
            },
            child: const Text('Abort Task'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final streamState = ref.watch(transcriptStreamProvider);
    final sessionState = ref.watch(sessionProvider);
    final theme = Theme.of(context);

    // Auto scroll when new steps or streaming text arrives
    ref.listen(transcriptStreamProvider, (prev, next) {
      if (prev?.steps.length != next.steps.length ||
          prev?.streamingContent != next.streamingContent) {
        _scrollToBottom();
      }
    });

    final currentSession = sessionState.sessions.firstWhere(
      (s) => s.sessionId == streamState.sessionId,
      orElse: () => sessionState.sessions.isNotEmpty
          ? sessionState.sessions.first
          : null as dynamic,
    );

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              currentSession.lastUserPrompt.isNotEmpty
                  ? currentSession.lastUserPrompt
                  : 'Live Transcript',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16),
            ),
            if (streamState.sessionId != null)
              Text(
                'ID: ${streamState.sessionId!.substring(0, 8)}...',
                style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
        actions: [
          if (streamState.sessionId != null)
            IconButton(
              icon: const Icon(Icons.folder_outlined),
              tooltip: 'Artifacts',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ArtifactViewerScreen(sessionId: streamState.sessionId!),
                  ),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent),
            tooltip: 'Abort Task',
            onPressed: _confirmAbort,
          ),
        ],
      ),
      body: Column(
        children: [
          if (streamState.isLoading)
            const LinearProgressIndicator(),

          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: streamState.steps.length +
                  (streamState.streamingThinking != null || streamState.streamingContent != null ? 1 : 0),
              itemBuilder: (context, index) {
                // If rendering live streaming chunk at the end
                if (index == streamState.steps.length) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (streamState.streamingThinking != null)
                        ThinkingBox(
                          thinkingText: streamState.streamingThinking!,
                          isStreaming: true,
                        ),
                      if (streamState.streamingContent != null)
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: MarkdownBody(data: streamState.streamingContent!),
                        ),
                    ],
                  );
                }

                final step = streamState.steps[index];
                final isUser = step.source == 'USER_EXPLICIT';

                if (isUser) {
                  return Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.82,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(4),
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                        ),
                      ),
                      child: Text(
                        step.content ?? '',
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                }

                // Model response or tool invocation
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Thinking section
                      if (step.thinking != null && step.thinking!.isNotEmpty)
                        ThinkingBox(thinkingText: step.thinking!),

                      // Tool calls
                      if (step.toolCalls != null)
                        for (final tool in step.toolCalls!)
                          ToolCallCard(
                            toolCall: tool,
                            onAction: (action, input) {
                              if (tool.callId != null) {
                                ref.read(transcriptStreamProvider.notifier).respondToTool(
                                  callId: tool.callId!,
                                  action: action,
                                  inputText: input,
                                );
                              }
                            },
                          ),

                      // Assistant markdown message
                      if (step.content != null && step.content!.trim().isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceVariant.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant.withOpacity(0.5),
                            ),
                          ),
                          child: MarkdownBody(
                            data: step.content!,
                            selectable: true,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Bottom Prompt Input Bar with Biometric Protection
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _promptController,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Prompt remote Antigravity...',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: streamState.isSendingPrompt
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.fingerprint), // Highlights biometric gate
                    tooltip: 'Send Prompt (Requires Biometric Auth)',
                    onPressed: streamState.isSendingPrompt ? null : _handleSend,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
