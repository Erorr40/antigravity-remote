class PairedHost {
  final String hostDeviceId;
  final String hostName;
  final String relayUrl;
  final String hostPublicKeyRawBase64;
  final int pairedAt;
  bool isOnline;
  String? activeSessionId;
  int activeTasksCount;
  String? hostOs;
  int? uptimeSeconds;

  PairedHost({
    required this.hostDeviceId,
    required this.hostName,
    required this.relayUrl,
    required this.hostPublicKeyRawBase64,
    required this.pairedAt,
    this.isOnline = false,
    this.activeSessionId,
    this.activeTasksCount = 0,
    this.hostOs,
    this.uptimeSeconds,
  });

  Map<String, dynamic> toJson() => {
    'hostDeviceId': hostDeviceId,
    'hostName': hostName,
    'relayUrl': relayUrl,
    'hostPublicKeyRawBase64': hostPublicKeyRawBase64,
    'pairedAt': pairedAt,
  };

  factory PairedHost.fromJson(Map<String, dynamic> json) => PairedHost(
    hostDeviceId: json['hostDeviceId'] as String,
    hostName: json['hostName'] as String,
    relayUrl: json['relayUrl'] as String,
    hostPublicKeyRawBase64: json['hostPublicKeyRawBase64'] as String,
    pairedAt: (json['pairedAt'] as num).toInt(),
  );
}
