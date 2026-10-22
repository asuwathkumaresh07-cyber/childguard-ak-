import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'animated_alert_triangle.dart';
import 'guardian_character.dart';
import 'models.dart';

enum LogCategory {
  live,
  usage,
}

enum UsagePeriod {
  daily,
  hourly,
  monthly,
}

/// A dual-category activity viewer:
/// 1. Live Log: Real-time event stream (tamper alerts, web visits, app launches) with live pulse
/// 2. Usage Log: Comprehensive app usage categorized by Daily, Hourly, and Monthly periods
class CategorizedLogsView extends StatefulWidget {
  const CategorizedLogsView({
    super.key,
    required this.appLogs,
    this.domainLogs = const [],
    this.tamperEvents = const [],
    this.childName = 'Child',
    this.onBlockDomain,
    this.onBlockApp,
    this.isDomainBlocked,
    this.isAppBlocked,
  });

  final List<AppUsageLog> appLogs;
  final List<DomainLog> domainLogs;
  final List<ChildTamperEvent> tamperEvents;
  final String childName;
  final ValueChanged<String>? onBlockDomain;
  final void Function(String packageName, String label)? onBlockApp;
  final bool Function(String domain)? isDomainBlocked;
  final bool Function(String packageName)? isAppBlocked;

  @override
  State<CategorizedLogsView> createState() => _CategorizedLogsViewState();
}

class _CategorizedLogsViewState extends State<CategorizedLogsView> {
  LogCategory _category = LogCategory.live;
  UsagePeriod _usagePeriod = UsagePeriod.daily;

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
        // 1. Top Primary Category Selector: [ ● Live Log ] vs [ 📊 Usage Log ]
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
            ),
          ),
          child: Row(
            children: [
              _buildCategoryTab(
                category: LogCategory.live,
                label: 'Live Log',
                iconWidget: const _LivePulseDot(),
                active: _category == LogCategory.live,
                activeColor: const Color(0xFF00897B),
              ),
              _buildCategoryTab(
                category: LogCategory.usage,
                label: 'Usage Log (Day/Hr/Mo)',
                iconWidget: const Icon(Icons.bar_chart_rounded, size: 18),
                active: _category == LogCategory.usage,
                activeColor: primary,
              ),
            ],
          ),
        ),

        // 2. Search & Filter Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: _category == LogCategory.live ? 'Filter live events...' : 'Search apps...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1F2A2E) : Colors.white.withValues(alpha: 0.8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                ),
              ),
              if (_category == LogCategory.usage) ...[
                const SizedBox(width: 8),
                // Period Switcher: Daily | Hourly | Monthly
                Container(
                  height: 38,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildPeriodPill(UsagePeriod.daily, 'Daily'),
                      _buildPeriodPill(UsagePeriod.hourly, 'Hourly'),
                      _buildPeriodPill(UsagePeriod.monthly, 'Monthly'),
                    ],
                  ),
                ),
              ],
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
          child: _category == LogCategory.live ? _buildLiveLogView() : _buildUsageLogView(),
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
          duration: const Duration(milliseconds: 220),
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
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.white : (Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodPill(UsagePeriod period, String label) {
    final active = _usagePeriod == period;
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: () => setState(() => _usagePeriod = period),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : (Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87),
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
        subtitle: d.isBlocked ? 'Blocked by web shield' : 'Allowed website visit',
        isWarning: d.isBlocked,
        rawEvent: d,
      ));
    }

    // 3. Add app logs
    for (final a in widget.appLogs) {
      final name = a.appLabel.isEmpty ? a.packageName : a.appLabel;
      final dur = a.durationSeconds != null ? _formatDuration(a.durationSeconds!) : '';
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
              const GuardianCharacter(size: 70, mood: GuardianMood.safe),
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
                ? (isDark ? const Color(0xFF331A1C) : const Color(0xFFFFF0F0))
                : (isDark ? const Color(0xFF172427) : Colors.white.withValues(alpha: 0.85)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: item.isWarning
                  ? Colors.red.withValues(alpha: 0.35)
                  : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
              width: item.isWarning ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              // Event icon or animated red triangle for alerts
              if (item.isWarning)
                const AnimatedAlertTriangle(
                  size: 32,
                  showPulseRings: false,
                )
              else if (item.type == _LiveEventType.domain)
                CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xFFE0F2F1),
                  child: Icon(Icons.public, color: Theme.of(context).colorScheme.primary, size: 19),
                )
              else
                CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xFFE1F5FE),
                  child: const Icon(Icons.smartphone, color: Color(0xFF0288D1), size: 19),
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
                              color: item.isWarning ? Colors.red.shade800 : null,
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
              if (item.type == _LiveEventType.domain && widget.onBlockDomain != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Block domain',
                  icon: const Icon(Icons.shield_outlined, size: 18, color: Colors.red),
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
  // Category 2: Usage Log (Daily, Hourly, Monthly)
  // ==========================================
  Widget _buildUsageLogView() {
    switch (_usagePeriod) {
      case UsagePeriod.daily:
        return _buildDailyUsageList();
      case UsagePeriod.hourly:
        return _buildHourlyUsageList();
      case UsagePeriod.monthly:
        return _buildMonthlyUsageList();
    }
  }

  // Daily Usage grouping
  Widget _buildDailyUsageList() {
    final dailyGroups = <String, _DayUsageGroup>{};
    for (final log in widget.appLogs) {
      final dateKey = DateFormat('yyyy-MM-dd').format(log.startedAt.toLocal());
      final group = dailyGroups.putIfAbsent(
        dateKey,
        () => _DayUsageGroup(date: log.startedAt.toLocal()),
      );
      final dur = math.max(0, log.durationSeconds ?? log.endedAt?.difference(log.startedAt).inSeconds ?? 0);
      group.totalSeconds += dur;

      final appKey = log.packageName;
      final summary = group.apps.putIfAbsent(
        appKey,
        () => _AppUsageItem(
          packageName: appKey,
          appLabel: log.appLabel.isEmpty ? appKey : log.appLabel,
        ),
      );
      summary.seconds += dur;
      summary.sessionCount++;
    }

    final sortedDays = dailyGroups.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    if (sortedDays.isEmpty) {
      return _buildEmptyUsage('No daily usage records available yet.');
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
      itemCount: sortedDays.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final day = sortedDays[i];
        final apps = day.apps.values.toList()
          ..sort((a, b) => b.seconds.compareTo(a.seconds));
        final filteredApps = _searchQuery.isEmpty
            ? apps
            : apps.where((a) => a.appLabel.toLowerCase().contains(_searchQuery)).toList();

        final isToday = DateUtils.isSameDay(day.date, DateTime.now());
        final isYesterday = DateUtils.isSameDay(day.date, DateTime.now().subtract(const Duration(days: 1)));
        final title = isToday ? 'Today' : (isYesterday ? 'Yesterday' : DateFormat('EEEE, MMM d').format(day.date));

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).brightness == Brightness.dark ? Colors.white12 : Colors.black12),
          ),
          child: ExpansionTile(
            initiallyExpanded: i == 0,
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(Icons.calendar_today, size: 18, color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text(
              'Total Screen Time: ${_formatDuration(day.totalSeconds)} · ${apps.length} apps',
              style: const TextStyle(fontSize: 12),
            ),
            children: [
              const Divider(height: 1),
              for (final app in filteredApps)
                _buildAppProgressRow(app, day.totalSeconds),
            ],
          ),
        );
      },
    );
  }

  // Hourly Usage grouping (Time Blocks)
  Widget _buildHourlyUsageList() {
    final now = DateTime.now();
    final todayLogs = widget.appLogs.where((l) => DateUtils.isSameDay(l.startedAt.toLocal(), now)).toList();

    // Group into 4 time blocks: Night (00-06), Morning (06-12), Afternoon (12-17), Evening (17-24)
    final timeBlocks = <_TimeBlock>[
      _TimeBlock(name: 'Morning (06:00 - 12:00)', startHour: 6, endHour: 12, icon: Icons.wb_sunny_outlined),
      _TimeBlock(name: 'Afternoon (12:00 - 17:00)', startHour: 12, endHour: 17, icon: Icons.wb_cloudy_outlined),
      _TimeBlock(name: 'Evening (17:00 - 21:00)', startHour: 17, endHour: 21, icon: Icons.nights_stay_outlined),
      _TimeBlock(name: 'Night (21:00 - 06:00)', startHour: 21, endHour: 24, icon: Icons.bedtime_outlined),
    ];

    for (final log in todayLogs) {
      final hour = log.startedAt.toLocal().hour;
      final dur = math.max(0, log.durationSeconds ?? log.endedAt?.difference(log.startedAt).inSeconds ?? 0);
      for (final block in timeBlocks) {
        if (block.matches(hour)) {
          block.totalSeconds += dur;
          final app = block.apps.putIfAbsent(
            log.packageName,
            () => _AppUsageItem(
              packageName: log.packageName,
              appLabel: log.appLabel.isEmpty ? log.packageName : log.appLabel,
            ),
          );
          app.seconds += dur;
          app.sessionCount++;
        }
      }
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
      itemCount: timeBlocks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final block = timeBlocks[i];
        final apps = block.apps.values.toList()..sort((a, b) => b.seconds.compareTo(a.seconds));

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).brightness == Brightness.dark ? Colors.white12 : Colors.black12),
          ),
          child: ExpansionTile(
            initiallyExpanded: block.totalSeconds > 0,
            leading: CircleAvatar(
              backgroundColor: const Color(0xFFE0F7FA),
              child: Icon(block.icon, size: 20, color: const Color(0xFF00838F)),
            ),
            title: Text(block.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text('Usage: ${_formatDuration(block.totalSeconds)} · ${apps.length} apps active'),
            children: [
              if (apps.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Text('No app activity during this hour block.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                )
              else
                for (final app in apps)
                  _buildAppProgressRow(app, block.totalSeconds),
            ],
          ),
        );
      },
    );
  }

  // Monthly Usage grouping
  Widget _buildMonthlyUsageList() {
    final monthlyGroups = <String, _MonthUsageGroup>{};
    for (final log in widget.appLogs) {
      final monthKey = DateFormat('yyyy-MM').format(log.startedAt.toLocal());
      final group = monthlyGroups.putIfAbsent(
        monthKey,
        () => _MonthUsageGroup(date: log.startedAt.toLocal()),
      );
      final dur = math.max(0, log.durationSeconds ?? log.endedAt?.difference(log.startedAt).inSeconds ?? 0);
      group.totalSeconds += dur;

      final appKey = log.packageName;
      final summary = group.apps.putIfAbsent(
        appKey,
        () => _AppUsageItem(
          packageName: appKey,
          appLabel: log.appLabel.isEmpty ? appKey : log.appLabel,
        ),
      );
      summary.seconds += dur;
      summary.sessionCount++;
    }

    final sortedMonths = monthlyGroups.values.toList()..sort((a, b) => b.date.compareTo(a.date));

    if (sortedMonths.isEmpty) {
      return _buildEmptyUsage('No monthly usage logs recorded yet.');
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
      itemCount: sortedMonths.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final month = sortedMonths[i];
        final apps = month.apps.values.toList()..sort((a, b) => b.seconds.compareTo(a.seconds));

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).brightness == Brightness.dark ? Colors.white12 : Colors.black12),
          ),
          child: ExpansionTile(
            initiallyExpanded: i == 0,
            leading: CircleAvatar(
              backgroundColor: const Color(0xFFEDE7F6),
              child: const Icon(Icons.date_range, size: 20, color: Color(0xFF512DA8)),
            ),
            title: Text(
              DateFormat('MMMM yyyy').format(month.date),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            subtitle: Text('Total Month Time: ${_formatDuration(month.totalSeconds)} · ${apps.length} apps'),
            children: [
              for (var index = 0; index < apps.length; index++) ...[
                _buildAppProgressRow(apps[index], month.totalSeconds, rank: index + 1),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildAppProgressRow(_AppUsageItem app, int totalGroupSeconds, {int? rank}) {
    final pct = totalGroupSeconds > 0 ? (app.seconds / totalGroupSeconds).clamp(0.0, 1.0) : 0.0;
    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (rank != null) ...[
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: rank <= 3 ? primary : Colors.grey.shade400,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$rank',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  app.appLabel,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _formatDuration(app.seconds),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(width: 6),
              Text(
                '(${(pct * 100).toStringAsFixed(0)}%)',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 5,
              backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
              valueColor: AlwaysStoppedAnimation<Color>(primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyUsage(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hourglass_empty, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
      ),
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

class _DayUsageGroup {
  _DayUsageGroup({required this.date});
  final DateTime date;
  int totalSeconds = 0;
  final Map<String, _AppUsageItem> apps = {};
}

class _MonthUsageGroup {
  _MonthUsageGroup({required this.date});
  final DateTime date;
  int totalSeconds = 0;
  final Map<String, _AppUsageItem> apps = {};
}

class _AppUsageItem {
  _AppUsageItem({required this.packageName, required this.appLabel});
  final String packageName;
  final String appLabel;
  int seconds = 0;
  int sessionCount = 0;
}

class _TimeBlock {
  _TimeBlock({
    required this.name,
    required this.startHour,
    required this.endHour,
    required this.icon,
  });

  final String name;
  final int startHour;
  final int endHour;
  final IconData icon;
  int totalSeconds = 0;
  final Map<String, _AppUsageItem> apps = {};

  bool matches(int hour) {
    if (startHour == 21) {
      return hour >= 21 || hour < 6;
    }
    return hour >= startHour && hour < endHour;
  }
}

class _LivePulseDot extends StatefulWidget {
  const _LivePulseDot();

  @override
  State<_LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<_LivePulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final scale = 0.8 + _ctrl.value * 0.4;
        final alpha = 0.5 + _ctrl.value * 0.5;
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: const Color(0xFF00E676).withValues(alpha: alpha),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E676).withValues(alpha: alpha * 0.6),
                blurRadius: 4 * scale,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}
