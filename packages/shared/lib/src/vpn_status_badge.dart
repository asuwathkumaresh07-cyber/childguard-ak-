import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'models.dart';
import 'live_icon.dart';

/// Shows device-reported protection, including the freshness of that report.
class VpnStatusBadge extends StatelessWidget {
  const VpnStatusBadge({super.key, this.status});

  final ChildDeviceStatus? status;

  @override
  Widget build(BuildContext context) {
    final report = status;
    final stale = report != null &&
        DateTime.now().difference(report.lastSeenAt).inMinutes >= 3;
    final enabled = report?.vpnEnabled == true;
    final color = report == null || stale
        ? Colors.blue
        : enabled
            ? Colors.blue
            : Colors.red;
    final label = report == null
        ? 'VPN status unknown'
        : stale
            ? 'Last reported: VPN ${enabled ? "ON" : "OFF"}'
            : 'VPN ${enabled ? "ON" : "OFF"}';
    final icon = LiveIcon(
      report == null || stale
          ? Icons.shield_outlined
          : enabled
              ? Icons.verified_user_rounded
              : Icons.gpp_bad_rounded,
      color: color,
      size: 22,
      loop: report != null && !stale,
    );
    return Semantics(
      label: label,
      child: Row(children: [
        icon,
        const SizedBox(width: 8),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          if (report != null)
            Text(
                DateFormat('MMM d, h:mm a').format(report.lastSeenAt.toLocal()),
                style: Theme.of(context).textTheme.labelSmall),
        ])),
      ]),
    );
  }
}
