import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared/shared.dart';

class ChildActivityChart extends StatelessWidget {
  const ChildActivityChart({
    super.key,
    required this.logs,
    this.locale = 'en',
  });

  final List<AppUsageLog> logs;
  final String locale;

  bool get _hindi => locale == 'hi';

  String _duration(int seconds) {
    final safeSeconds = math.max(seconds, 0);
    final hours = safeSeconds ~/ 3600;
    final minutes = (safeSeconds % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m';
    return '<1m';
  }

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final firstDay = today.subtract(const Duration(days: 6));
    final summaries = <String, _AppUsageSummary>{};
    for (final log in logs) {
      final start = log.startedAt.toLocal();
      if (DateUtils.dateOnly(start).isBefore(firstDay)) continue;
      final summary = summaries.putIfAbsent(
        log.packageName,
        () => _AppUsageSummary(
          packageName: log.packageName,
          appLabel: log.appLabel.isEmpty ? log.packageName : log.appLabel,
        ),
      );
      final duration = math.max(
        log.durationSeconds ??
            log.endedAt?.difference(log.startedAt).inSeconds ??
            0,
        0,
      );
      summary.logs.add(log);
      if (DateUtils.isSameDay(start, today)) {
        summary.todaySeconds += duration;
        summary.todaySessions++;
      }
    }
    final apps = summaries.values.toList()
      ..sort((a, b) => b.todaySeconds.compareTo(a.todaySeconds));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DualUsageChart(
          showAppBreakdown: false,
          logs: logs,
          title: _hindi ? 'आपका स्क्रीन समय' : 'Your screen time',
          initialMode: DualChartMode.daily,
        ),
        const SizedBox(height: 20),
        Text(
          _hindi ? 'ऐप के अनुसार गतिविधि' : 'Activity by app',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (apps.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _hindi
                  ? 'ऐप का उपयोग दिखाने के लिए Usage access चालू करें।'
                  : 'App activity will appear here once Usage access is enabled.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          )
        else
          for (final app in apps) _AppUsageTile(app: app, duration: _duration),
      ],
    );
  }
}

class _AppUsageSummary {
  _AppUsageSummary({required this.packageName, required this.appLabel});

  final String packageName;
  final String appLabel;
  final List<AppUsageLog> logs = [];
  int todaySeconds = 0;
  int todaySessions = 0;
}

class _AppUsageTile extends StatelessWidget {
  const _AppUsageTile({required this.app, required this.duration});

  final _AppUsageSummary app;
  final String Function(int) duration;

  @override
  Widget build(BuildContext context) {
    final sortedLogs = app.logs.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        child: LiveIcon(
          Icons.apps_rounded,
          size: 19,
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
      title: Text(app.appLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        'Today ${duration(app.todaySeconds)} · ${app.todaySessions} sessions',
      ),
      children: [
        for (final log in sortedLogs.take(5))
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 8, right: 4),
            leading: const LiveIcon(Icons.history, size: 18),
            title: Text(
              DateFormat('EEE, h:mm a').format(log.startedAt.toLocal()),
            ),
            subtitle: Text(
              log.durationSeconds == null
                  ? 'Opened'
                  : 'Session · ${duration(log.durationSeconds!)}',
            ),
          ),
      ],
    );
  }
}
