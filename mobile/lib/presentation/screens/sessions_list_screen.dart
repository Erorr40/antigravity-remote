import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/session_provider.dart';
import '../providers/host_provider.dart';
import 'chat_stream_screen.dart';

class SessionsListScreen extends ConsumerWidget {
  const SessionsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(sessionProvider);
    final hostState = ref.watch(hostProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Antigravity Sessions', style: TextStyle(fontSize: 18)),
            if (hostState.activeHost != null)
              Text(
                hostState.activeHost!.hostName,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(sessionProvider.notifier).fetchSessions(),
            tooltip: 'Refresh Sessions',
          ),
        ],
      ),
      body: sessionState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : sessionState.sessions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.forum_outlined,
                        size: 56,
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No Conversations Found',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh'),
                        onPressed: () => ref.read(sessionProvider.notifier).fetchSessions(),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: sessionState.sessions.length,
                  itemBuilder: (context, index) {
                    final item = sessionState.sessions[index];
                    final updatedDate = DateTime.fromMillisecondsSinceEpoch(item.updatedAtMs);
                    final formattedDate = DateFormat('MMM d, HH:mm').format(updatedDate);

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: item.hasActiveTask
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                          width: item.hasActiveTask ? 2 : 1,
                        ),
                      ),
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        title: Row(
                          children: [
                            if (item.hasActiveTask) ...[
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                item.lastUserPrompt.isEmpty
                                    ? item.sessionId.substring(0, 8)
                                    : item.lastUserPrompt,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              Text(
                                formattedDate,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '${item.totalSteps} steps',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              _buildStatusBadge(item.lastAgentStatus),
                            ],
                          ),
                        ),
                        onTap: () {
                          ref.read(sessionProvider.notifier).selectSession(item.sessionId);
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const ChatStreamScreen()),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color text;

    switch (status) {
      case 'thinking':
        bg = Colors.purple.withOpacity(0.15);
        text = Colors.purple;
        break;
      case 'tool_executing':
        bg = Colors.amber.withOpacity(0.15);
        text = Colors.orange[800]!;
        break;
      case 'done':
        bg = Colors.green.withOpacity(0.15);
        text = Colors.green[800]!;
        break;
      case 'error':
        bg = Colors.red.withOpacity(0.15);
        text = Colors.red;
        break;
      default:
        bg = Colors.grey.withOpacity(0.15);
        text = Colors.grey[700]!;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: text),
      ),
    );
  }
}
