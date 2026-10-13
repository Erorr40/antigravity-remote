class SessionItem {
  final String sessionId;
  final String projectDir;
  final int createdAtMs;
  final int updatedAtMs;
  final int totalSteps;
  final String lastUserPrompt;
  final String lastAgentStatus;
  final bool hasActiveTask;

  SessionItem({
    required this.sessionId,
    required this.projectDir,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.totalSteps,
    required this.lastUserPrompt,
    required this.lastAgentStatus,
    required this.hasActiveTask,
  });

  factory SessionItem.fromJson(Map<String, dynamic> json) => SessionItem(
    sessionId: json['sessionId'] as String,
    projectDir: json['projectDir'] as String? ?? '',
    createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
    totalSteps: (json['totalSteps'] as num?)?.toInt() ?? 0,
    lastUserPrompt: json['lastUserPrompt'] as String? ?? '',
    lastAgentStatus: json['lastAgentStatus'] as String? ?? 'idle',
    hasActiveTask: json['hasActiveTask'] as bool? ?? false,
  );
}

class ArtifactItem {
  final String fileName;
  final String filePath;
  final int sizeBytes;
  final int modifiedAt;
  final String mimeType;

  ArtifactItem({
    required this.fileName,
    required this.filePath,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.mimeType,
  });

  factory ArtifactItem.fromJson(Map<String, dynamic> json) => ArtifactItem(
    fileName: json['fileName'] as String,
    filePath: json['filePath'] as String,
    sizeBytes: (json['sizeBytes'] as num).toInt(),
    modifiedAt: (json['modifiedAt'] as num).toInt(),
    mimeType: json['mimeType'] as String? ?? 'text/plain',
  );
}
