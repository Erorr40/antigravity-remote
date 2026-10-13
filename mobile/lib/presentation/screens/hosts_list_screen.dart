import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/host_provider.dart';
import '../widgets/connection_badge.dart';
import 'qr_pairing_screen.dart';
import 'sessions_list_screen.dart';

class HostsListScreen extends ConsumerWidget {
  const HostsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostState = ref.watch(hostProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paired Host Laptops'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Pair New Laptop',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const QrPairingScreen()),
              );
            },
          ),
        ],
      ),
      body: hostState.hosts.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.laptop_chromebook,
                    size: 64,
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No Paired Laptops Yet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Run `antigravity-daemon --pair` on your laptop, then scan the QR code to pair.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan Pairing QR'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const QrPairingScreen()),
                      );
                    },
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: hostState.hosts.length,
              itemBuilder: (context, index) {
                final host = hostState.hosts[index];
                final isSelected = hostState.activeHost?.hostDeviceId == host.hostDeviceId;

                return Card(
                  elevation: isSelected ? 3 : 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      ref.read(hostProvider.notifier).connectToHost(host);
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SessionsListScreen()),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.computer,
                                color: theme.colorScheme.primary,
                                size: 24,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  host.hostName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              ConnectionBadge(
                                status: hostState.relayStatus,
                                isHostOnline: host.isOnline,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Device ID: ${host.hostDeviceId}',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            'Relay: ${host.relayUrl}',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (host.hostOs != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'OS: ${host.hostOs}',
                                style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                icon: const Icon(Icons.delete_outline, size: 16),
                                label: const Text('Unpair'),
                                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                                onPressed: () async {
                                  final storage = ref.read(storageServiceProvider);
                                  await storage.removePairedHost(host.hostDeviceId);
                                  ref.invalidate(hostProvider);
                                },
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                icon: const Icon(Icons.arrow_forward, size: 16),
                                label: const Text('Open Sessions'),
                                onPressed: () {
                                  ref.read(hostProvider.notifier).connectToHost(host);
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const SessionsListScreen()),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
