import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../domain/models/session_item.dart';
import '../providers/host_provider.dart';

class ArtifactViewerScreen extends ConsumerStatefulWidget {
  final String sessionId;

  const ArtifactViewerScreen({super.key, required this.sessionId});

  @override
  ConsumerState<ArtifactViewerScreen> createState() => _ArtifactViewerScreenState();
}

class _ArtifactViewerScreenState extends ConsumerState<ArtifactViewerScreen> {
  List<ArtifactItem> _artifacts = [];
  ArtifactItem? _selectedArtifact;
  String? _fileContent;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchArtifacts();
  }

  Future<void> _fetchArtifacts() async {
    setState(() => _isLoading = true);
    final hostNotifier = ref.read(hostProvider.notifier);
    final client = hostNotifier.relayClient;
    final sessionKey = hostNotifier.activeSessionKey;

    if (client == null || sessionKey == null) {
      setState(() => _isLoading = false);
      return;
    }

    final e2ee = ref.read(e2eeServiceProvider);

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

          if (inner['action'] == 'RESP_ARTIFACT_LIST') {
            final rawList = inner['payload']['artifacts'] as List;
            final items = rawList.map((a) => ArtifactItem.fromJson(a as Map<String, dynamic>)).toList();
            setState(() {
              _artifacts = items;
              _isLoading = false;
              if (items.isNotEmpty && _selectedArtifact == null) {
                _loadArtifactContent(items.first);
              }
            });
          } else if (inner['action'] == 'RESP_ARTIFACT_CONTENT') {
            setState(() {
              _fileContent = inner['payload']['content'] as String?;
              _isLoading = false;
            });
          }
        } catch (_) {}
      }
    });

    await hostNotifier.sendEncryptedCommand(
      'REQ_ARTIFACT_LIST',
      {'sessionId': widget.sessionId},
      sessionId: widget.sessionId,
    );

    Future.delayed(const Duration(seconds: 4), () {
      if (_isLoading) {
        setState(() => _isLoading = false);
        sub.cancel();
      }
    });
  }

  Future<void> _loadArtifactContent(ArtifactItem item) async {
    setState(() {
      _selectedArtifact = item;
      _isLoading = true;
    });

    final hostNotifier = ref.read(hostProvider.notifier);
    await hostNotifier.sendEncryptedCommand(
      'REQ_ARTIFACT_CONTENT',
      {
        'sessionId': widget.sessionId,
        'fileName': item.filePath,
      },
      sessionId: widget.sessionId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedArtifact?.fileName ?? 'Session Artifacts'),
      ),
      drawer: Drawer(
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: theme.colorScheme.primaryContainer),
              child: const Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  'Workspace Files & Artifacts',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Expanded(
              child: _artifacts.isEmpty
                  ? const Center(child: Text('No artifacts generated yet'))
                  : ListView.builder(
                      itemCount: _artifacts.length,
                      itemBuilder: (context, index) {
                        final item = _artifacts[index];
                        final isSelected = _selectedArtifact?.filePath == item.filePath;
                        return ListTile(
                          selected: isSelected,
                          leading: Icon(_getFileIcon(item.mimeType)),
                          title: Text(item.fileName, style: const TextStyle(fontSize: 14)),
                          subtitle: Text('${(item.sizeBytes / 1024).toStringAsFixed(1)} KB'),
                          onTap: () {
                            Navigator.pop(context); // close drawer
                            _loadArtifactContent(item);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _selectedArtifact == null
              ? const Center(child: Text('Select an artifact from drawer'))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: _selectedArtifact!.mimeType.contains('markdown')
                      ? Markdown(
                          data: _fileContent ?? '',
                          selectable: true,
                        )
                      : SingleChildScrollView(
                          child: SelectableText(
                            _fileContent ?? '',
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                          ),
                        ),
                ),
    );
  }

  IconData _getFileIcon(String mime) {
    if (mime.contains('markdown')) return Icons.menu_book;
    if (mime.contains('json') || mime.contains('javascript')) return Icons.data_object;
    if (mime.contains('image')) return Icons.image;
    return Icons.insert_drive_file;
  }
}
