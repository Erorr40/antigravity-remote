import 'dart:convert';
import 'package:flutter/material.dart';
import '../../domain/models/tool_call.dart';

class ToolCallCard extends StatefulWidget {
  final ToolCall toolCall;
  final Function(String action, String? input)? onAction;

  const ToolCallCard({
    super.key,
    required this.toolCall,
    this.onAction,
  });

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard> {
  bool _isArgsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDestructive = widget.toolCall.toolName.contains('command') ||
        widget.toolCall.toolName.contains('delete') ||
        widget.toolCall.toolName.contains('write');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.toolCall.isError
              ? Colors.redAccent.withOpacity(0.5)
              : theme.colorScheme.outlineVariant,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDestructive
                        ? Colors.deepOrange.withOpacity(0.12)
                        : theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _getToolIcon(widget.toolCall.toolName),
                    size: 18,
                    color: isDestructive ? Colors.deepOrange : theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.toolCall.toolSummary ?? widget.toolCall.toolName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      if (widget.toolCall.toolAction != null)
                        Text(
                          widget.toolCall.toolAction!,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _isArgsExpanded ? Icons.code_off : Icons.code,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _isArgsExpanded = !_isArgsExpanded),
                  tooltip: 'View Arguments',
                ),
              ],
            ),
          ),

          if (_isArgsExpanded && widget.toolCall.arguments != null)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                const JsonEncoder.withIndent('  ').convert(widget.toolCall.arguments),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),

          // Interactive response buttons if callId present
          if (widget.toolCall.callId != null && widget.onAction != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.2),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Reject'),
                    onPressed: () => widget.onAction!('reject', null),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Approve'),
                    onPressed: () => widget.onAction!('approve', null),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  IconData _getToolIcon(String toolName) {
    if (toolName.contains('file') || toolName.contains('view')) return Icons.description_outlined;
    if (toolName.contains('command')) return Icons.terminal_outlined;
    if (toolName.contains('search')) return Icons.search_outlined;
    if (toolName.contains('question')) return Icons.help_outline;
    return Icons.build_outlined;
  }
}
