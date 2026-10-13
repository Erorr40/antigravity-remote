import 'package:flutter/material.dart';
import '../../core/network/relay_client.dart';

class ConnectionBadge extends StatelessWidget {
  final ConnectionStatus status;
  final bool isHostOnline;

  const ConnectionBadge({
    super.key,
    required this.status,
    required this.isHostOnline,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;

    if (status != ConnectionStatus.connected) {
      color = Colors.orange;
      label = status == ConnectionStatus.connecting ? 'Connecting...' : 'Relay Offline';
    } else if (!isHostOnline) {
      color = Colors.redAccent;
      label = 'Host Disconnected';
    } else {
      color = Colors.green;
      label = 'Host Online';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
