class ToolCall {
  final String toolName;
  final String? toolAction;
  final String? toolSummary;
  final String? callId;
  final Map<String, dynamic>? arguments;
  final dynamic result;
  final bool isError;

  ToolCall({
    required this.toolName,
    this.toolAction,
    this.toolSummary,
    this.callId,
    this.arguments,
    this.result,
    this.isError = false,
  });

  factory ToolCall.fromJson(Map<String, dynamic> json) => ToolCall(
    toolName: json['tool_name'] as String? ?? 'unknown_tool',
    toolAction: json['tool_action'] as String?,
    toolSummary: json['tool_summary'] as String?,
    callId: json['call_id'] as String?,
    arguments: json['arguments'] != null ? Map<String, dynamic>.from(json['arguments'] as Map) : null,
    result: json['result'],
    isError: json['is_error'] as bool? ?? false,
  );
}
