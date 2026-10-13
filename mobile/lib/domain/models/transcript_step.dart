import 'tool_call.dart';

class TranscriptStep {
  final int stepIndex;
  final String source; // "USER_EXPLICIT", "MODEL", "SYSTEM"
  final String type; // "USER_INPUT", "PLANNER_RESPONSE", "TOOL_RESULT"
  final String status; // "DONE", "RUNNING", "ERROR"
  final String createdAt;
  String? content;
  String? thinking;
  List<ToolCall>? toolCalls;
  List<String>? truncatedFields;

  TranscriptStep({
    required this.stepIndex,
    required this.source,
    required this.type,
    required this.status,
    required this.createdAt,
    this.content,
    this.thinking,
    this.toolCalls,
    this.truncatedFields,
  });

  factory TranscriptStep.fromJson(Map<String, dynamic> json) {
    List<ToolCall>? tools;
    if (json['tool_calls'] is List) {
      tools = (json['tool_calls'] as List)
          .map((t) => ToolCall.fromJson(t as Map<String, dynamic>))
          .toList();
    }

    List<String>? trunc;
    if (json['truncated_fields'] is List) {
      trunc = (json['truncated_fields'] as List).map((s) => s.toString()).toList();
    }

    return TranscriptStep(
      stepIndex: (json['step_index'] as num?)?.toInt() ?? 0,
      source: json['source'] as String? ?? 'SYSTEM',
      type: json['type'] as String? ?? 'PLANNER_RESPONSE',
      status: json['status'] as String? ?? 'DONE',
      createdAt: json['created_at'] as String? ?? '',
      content: json['content'] as String?,
      thinking: json['thinking'] as String?,
      toolCalls: tools,
      truncatedFields: trunc,
    );
  }
}
