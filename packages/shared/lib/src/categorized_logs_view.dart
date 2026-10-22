import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'animated_alert_triangle.dart';
import 'live_icon.dart';
import 'app_palette.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'models.dart';
import 'dual_usage_chart.dart';
import 'vpn_status_badge.dart';

enum LogCategory {
  live,
  usage,
}

/// A dual-category activity viewer:
/// 1. Live Log: Real-time event stream (tamper alerts, web visits, app launches) with live pulse
/// 2. Usage Log: App usage grouped by Daily or Hourly periods.
class CategorizedLogsView extends StatefulWidget {
  const CategorizedLogsView({
    super.key,
    required this.appLogs,
    this.domainLogs = const [],
    this.tamperEvents = const [],
    this.childName = 'Child',
    this.deviceStatus,
    this.onBlockDomain,
    this.onBlockApp,
    this.isDomainBlocked,
    this.isAppBlocked,
  });

  final List<AppUsageLog> appLogs;
  final List<DomainLog> domainLogs;
  final List<ChildTamperEvent> tamperEvents;
  final String childName;
  final ChildDeviceStatus? deviceStatus;
  final ValueChanged<String>? onBlockDomain;
  final void Function(String packageName, String label)? onBlockApp;
  final bool Function(String domain)? isDomainBlocked;
  final bool Function(String packageName)? isAppBlocked;

  @override
  State<CategorizedLogsView> createState() => _CategorizedLogsViewState();
}

class _CategorizedLogsViewState extends State<CategorizedLogsView> {
  LogCategory _category = LogCategory.live;

  String _liveFilter = 'all'; // 'all', 'alerts', 'web', 'apps'
  String _searchQuery = '';

  String _formatDuration(int seconds) {
    final s = math.max(0, seconds);
    final hours = s ~/ 3600;
    final mins = (s % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${mins}m';
    if (mins > 0) return '${mins}m';
    return s > 0 ? '${s}s' : '<1m';
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time.toLocal());
    if (diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d, h:mm a').format(time.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: VpnStatusBadge(status: widget.deviceStatus),
        ),
        // 1. Top Primary Category Selector: [ ● Live Log ] vs [ 📊 Usage Log ]
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color:
                isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white10
                  : Colors.black.withValues(alpha: 0.04),
            ),
          ),
          child: Row(
            children: [
              _buildCategoryTab(
                category: LogCategory.live,
                label: 'Live Log',
                iconWidget: const _LivePulseDot(),
                active: _category == LogCategory.live,
                activeColor: const Color(0xFF172B4D),
              ),
              _buildCategoryTab(
                category: LogCategory.usage,
                label: 'Usage Graph',
                iconWidget: const Icon(Icons.bar_chart_rounded, size: 18),
                active: _category == LogCategory.usage,
                activeColor: primary,
              ),
            ],
          ),
        ),

        // 2. Search & Filter Bar
        if (_category == LogCategory.live)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: _category == LogCategory.live
                          ? 'Filter live events...'
                          : 'Search apps...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 12),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF172B4D)
                          : Colors.white.withValues(alpha: 0.8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) =>
                        setState(() => _searchQuery = v.trim().toLowerCase()),
                  ),
                ),
              ],
            ),
          ),

        // Live Sub-Filter chips (when on Live category)
        if (_category == LogCategory.live)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildLiveChip('all', 'All Events'),
                  const SizedBox(width: 6),
                  _buildLiveChip('alerts', 'Alerts Only', isWarning: true),
                  const SizedBox(width: 6),
                  _buildLiveChip('web', 'Web Shield'),
                  const SizedBox(width: 6),
                  _buildLiveChip('apps', 'App Usage'),
                ],
              ),
            ),
          ),

        // 3. Category Body
        Expanded(
          child: _category == LogCategory.live
              ? _buildLiveLogView()
              : _buildUsageLogView(),
        ),
      ],
    );
  }

  Widget _buildCategoryTab({
    required LogCategory category,
    required String label,
    required Widget iconWidget,
    required bool active,
    required Color activeColor,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _category = category),
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconWidget,
              const SizedBox(width: 6),
              Flexible(
                  child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: active
                      ? Colors.white
                      : (Theme.of(context).brightness == Brightness.dark
                          ? Colors.white70
                          : Colors.black87),
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveChip(String key, String label, {bool isWarning = false}) {
    final active = _liveFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (_) => setState(() => _liveFilter = key),
      selectedColor: isWarning ? const Color(0xFFFFEBEE) : null,
      visualDensity: VisualDensity.compact,
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: active ? FontWeight.bold : FontWeight.w500,
        color: isWarning && active ? Colors.red.shade900 : null,
      ),
    );
  }

  // ==========================================
  // Category 1: Live Log Implementation
  // ==========================================
  Widget _buildLiveLogView() {
    final events = <_LiveEventItem>[];

    // 1. Add tamper events
    for (final t in widget.tamperEvents) {
      events.add(_LiveEventItem(
        type: _LiveEventType.tamper,
        timestamp: t.occurredAt,
        title: _tamperLabel(t.eventType),
        subtitle: 'Security event on child device',
        isWarning: true,
        rawEvent: t,
      ));
    }

    // 2. Add domain logs
    for (final d in widget.domainLogs) {
      events.add(_LiveEventItem(
        type: _LiveEventType.domain,
        timestamp: d.occurredAt,
        title: d.domain,
        subtitle:
            d.isBlocked ? 'Blocked by web shield' : 'Allowed website visit',
        isWarning: d.isBlocked,
        rawEvent: d,
      ));
    }

    // 3. Add app logs
    for (final a in widget.appLogs) {
      final name = a.appLabel.isEmpty ? a.packageName : a.appLabel;
      final dur =
          a.durationSeconds != null ? _formatDuration(a.durationSeconds!) : '';
      events.add(_LiveEventItem(
        type: _LiveEventType.app,
        timestamp: a.startedAt,
        title: name,
        subtitle: dur.isNotEmpty ? 'App session ($dur)' : 'App opened',
        isWarning: false,
        rawEvent: a,
      ));
    }

    // Sort descending by timestamp
    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Filter
    final filtered = events.where((e) {
      if (_liveFilter == 'alerts' && !e.isWarning) return false;
      if (_liveFilter == 'web' && e.type != _LiveEventType.domain) return false;
      if (_liveFilter == 'apps' && e.type != _LiveEventType.app) return false;
      if (_searchQuery.isNotEmpty) {
        final match = e.title.toLowerCase().contains(_searchQuery) ||
            e.subtitle.toLowerCase().contains(_searchQuery);
        if (!match) return false;
      }
      return true;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LiveIcon(Icons.shield_rounded,
                  size: 70, color: AppPalette.blue),
              const SizedBox(height: 12),
              const Text(
                'No events match your filter',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                'All activity from child devices will appear here in real time.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final item = filtered[i];
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: item.isWarning
                ? (isDark ? const Color(0xFF172B4D) : const Color(0xFFFFF0F0))
                : (isDark
                    ? const Color(0xFF172B4D)
                    : Colors.white.withValues(alpha: 0.85)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: item.isWarning
                  ? Colors.red.withValues(alpha: 0.35)
                  : (isDark
                      ? Colors.white10
                      : Colors.black.withValues(alpha: 0.05)),
              width: item.isWarning ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              // Event icon or animated red triangle for alerts
              if (item.isWarning)
                const AnimatedAlertTriangle(
                  size: 32,
                )
              else if (item.type == _LiveEventType.domain)
                CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xFFE0F2F1),
                  child: Icon(Icons.public,
                      color: Theme.of(context).colorScheme.primary, size: 19),
                )
              else
                CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xFFE1F5FE),
                  child: const Icon(Icons.smartphone,
                      color: Color(0xFF2563EB), size: 19),
                ),
              const SizedBox(width: 12),

              // Title and details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color:
                                  item.isWarning ? Colors.red.shade800 : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _relativeTime(item.timestamp),
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Quick action if domain/app is blockable
              if (item.type == _LiveEventType.domain &&
                  widget.onBlockDomain != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Block domain',
                  icon: const Icon(Icons.shield_outlined,
                      size: 18, color: Colors.red),
                  onPressed: () => widget.onBlockDomain!(item.title),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // Category 2: Usage Log (Daily, Hourly)
  // ==========================================
  Widget _buildUsageLogView() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        DualUsageChart(logs: widget.appLogs, title: '${widget.childName} usage')
      ],
    );
  }

  String _tamperLabel(String eventType) => switch (eventType) {
        'vpn_disabled' => 'VPN Protection Turned Off',
        'vpn_enabled' => 'VPN Protection Restored',
        'usage_access_revoked' => 'Usage Access Turned Off',
        'usage_access_restored' => 'Usage Access Restored',
        'accessibility_disabled' => 'App Blocker Disabled',
        'accessibility_restored' => 'App Blocker Restored',
        'location_sharing_disabled' => 'Location Sharing Turned Off',
        'location_sharing_enabled' => 'Location Sharing Restored',
        _ => 'Protection Setting Changed',
      };
}

// Helper models for live log and usage groupings
enum _LiveEventType { tamper, domain, app }

class _LiveEventItem {
  _LiveEventItem({
    required this.type,
    required this.timestamp,
    required this.title,
    required this.subtitle,
    required this.isWarning,
    required this.rawEvent,
  });

  final _LiveEventType type;
  final DateTime timestamp;
  final String title;
  final String subtitle;
  final bool isWarning;
  final dynamic rawEvent;
}

class _LivePulseDot extends StatelessWidget {
  const _LivePulseDot();

  @override
  Widget build(BuildContext context) {
    Widget dot = Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
            color: AppPalette.blue, shape: BoxShape.circle));
    if (!MediaQuery.disableAnimationsOf(context)) {
      dot = dot
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .fade(begin: .4, end: 1, duration: 1200.ms);
    }
    return dot;
  }
}
