import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared/shared.dart';

import '../widgets/user_error.dart';

class ParentAlertsScreen extends StatefulWidget {
  const ParentAlertsScreen({
    super.key,
    required this.familyId,
    required this.children,
  });

  final String familyId;
  final List<FamilyMember> children;

  @override
  State<ParentAlertsScreen> createState() => _ParentAlertsScreenState();
}

class _ParentAlertsScreenState extends State<ParentAlertsScreen> {
  final _family = FamilyService();
  List<_ParentAlert> _alerts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final zones = await _family.fetchFamilyZones(widget.familyId);
      final tamperByChild = await Future.wait(
        widget.children.map(
          (child) => _family.fetchChildTamperEvents(
            familyId: widget.familyId,
            childId: child.profileId,
            limit: 30,
          ),
        ),
      );
      final zonesByChild = await Future.wait(
        widget.children.map(
          (child) => _family.fetchZoneEvents(
            familyId: widget.familyId,
            childId: child.profileId,
            limit: 30,
          ),
        ),
      );
      if (!mounted) return;
      final zoneNames = {for (final zone in zones) zone.id: zone.name};
      final alerts = <_ParentAlert>[
        for (var index = 0; index < widget.children.length; index++) ...[
          for (final event in tamperByChild[index])
            _ParentAlert(
              childName: _childName(widget.children[index]),
              message: _tamperLabel(event.eventType),
              occurredAt: event.occurredAt,
              icon: Icons.shield_outlined,
              color: const Color(0xFFDC3545),
              isCritical: true,
            ),
          for (final event in zonesByChild[index])
            _ParentAlert(
              childName: _childName(widget.children[index]),
              message: _zoneLabel(event, zoneNames),
              occurredAt: event.occurredAt,
              icon: event.eventType == 'off_task_app'
                  ? Icons.app_blocking_outlined
                  : Icons.location_on_outlined,
              color: event.eventType == 'off_task_app'
                  ? const Color(0xFFDC3545)
                  : const Color(0xFF172B4D),
              isCritical: event.eventType == 'off_task_app',
            ),
        ],
      ]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      setState(() {
        _alerts = alerts;
        _loading = false;
      });
    } catch (error) {
      reportAppError('load parent alerts', error);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userFacingError;
      });
    }
  }

  String _childName(FamilyMember child) {
    final name = child.profile?.displayName.trim() ?? '';
    return name.isEmpty ? 'Child' : name;
  }

  String _tamperLabel(String eventType) => switch (eventType) {
        'vpn_disabled' => 'VPN protection turned off',
        'vpn_enabled' => 'VPN protection restored',
        'usage_access_revoked' => 'App usage monitoring turned off',
        'usage_access_restored' => 'App usage monitoring restored',
        'accessibility_disabled' => 'App blocking turned off',
        'accessibility_restored' => 'App blocking restored',
        'location_sharing_disabled' => 'Location sharing turned off',
        'location_sharing_enabled' => 'Location sharing turned on',
        _ => 'Protection settings changed',
      };

  String _zoneLabel(ZoneEvent event, Map<String, String> zoneNames) {
    final zoneName = zoneNames[event.zoneId] ?? 'known place';
    return switch (event.eventType) {
      'entered' => 'Arrived at $zoneName',
      'exited' => 'Left $zoneName',
      'off_task_app' => 'Opened ${event.packageName ?? 'an app'} in $zoneName',
      _ => 'Activity recorded at $zoneName',
    };
  }

  @override
  Widget build(BuildContext context) {
    final hasCritical = _alerts.any((a) => a.isCritical);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Live Security Alerts'),
        actions: [
          IconButton(
            tooltip: 'Refresh alerts',
            onPressed: _load,
            icon: const LiveIcon(Icons.refresh),
          ),
        ],
      ),
      body: AmbientBackground(
        child: _loading
            ? const AppLoadingView(
                message: 'Loading device alerts',
                icon: Icons.notifications_outlined)
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    GlassCard(
                      child: Row(
                        children: [
                          LiveIcon(
                              hasCritical
                                  ? Icons.gpp_bad_rounded
                                  : Icons.shield_rounded,
                              size: 64,
                              color: hasCritical
                                  ? AppPalette.red
                                  : AppPalette.blue),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _alerts.isEmpty
                                      ? 'Family is Protected'
                                      : '${_alerts.length} Security Event${_alerts.length == 1 ? '' : 's'}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _alerts.isEmpty
                                      ? 'No critical alerts from your devices.'
                                      : 'Tap on any alert below to inspect.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_error != null)
                      Card(
                        child: ListTile(
                          leading: const LiveIcon(Icons.error_outline,
                              color: Colors.red),
                          title: Text(_error!),
                          trailing: IconButton(
                            onPressed: _load,
                            icon: const LiveIcon(Icons.refresh),
                          ),
                        ),
                      ),
                    if (_alerts.isEmpty && _error == null)
                      GlassCard(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          children: [
                            const LiveIcon(Icons.shield_rounded,
                                size: 72, color: AppPalette.blue),
                            const SizedBox(height: 12),
                            const Text(
                              'You’re all caught up!',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Protection status changes and geofence alerts will appear here in real time.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._alerts.map(
                        (alert) => GlassCard(
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          accentColor: alert.isCritical
                              ? const Color(0xFFDC3545)
                              : const Color(0xFF2563EB),
                          padding: const EdgeInsets.all(4),
                          child: ListTile(
                            leading: alert.isCritical
                                ? const AnimatedAlertTriangle(
                                    size: 32,
                                  )
                                : CircleAvatar(
                                    backgroundColor:
                                        alert.color.withValues(alpha: .12),
                                    child: LiveIcon(alert.icon,
                                        color: alert.color),
                                  ),
                            title: Text(
                              alert.message,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: alert.isCritical
                                    ? Colors.red.shade900
                                    : null,
                              ),
                            ),
                            subtitle: Text(
                              '${alert.childName} · ${DateFormat('MMM d, h:mm a').format(alert.occurredAt.toLocal())}',
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ParentAlert {
  const _ParentAlert({
    required this.childName,
    required this.message,
    required this.occurredAt,
    required this.icon,
    required this.color,
    this.isCritical = false,
  });

  final String childName;
  final String message;
  final DateTime occurredAt;
  final IconData icon;
  final Color color;
  final bool isCritical;
}
