import 'dart:math' as math;
import 'models.dart';

class UsageSession {
  const UsageSession(this.start, this.end);
  final DateTime start;
  final DateTime end;
  int get seconds => end.difference(start).inSeconds;
}

List<UsageSession> _merge(List<UsageSession> sessions) {
  sessions.sort((a, b) => a.start.compareTo(b.start));
  final merged = <UsageSession>[];
  for (final session in sessions) {
    if (merged.isEmpty || session.start.isAfter(merged.last.end)) {
      merged.add(session);
    } else if (session.end.isAfter(merged.last.end)) {
      merged[merged.length - 1] = UsageSession(merged.last.start, session.end);
    }
  }
  return merged;
}

class AppUsageBreakdown {
  AppUsageBreakdown(this.packageName, this.label, this.sessions);
  final String packageName;
  final String label;
  final List<UsageSession> sessions;
  int get seconds => sessions.fold(0, (sum, session) => sum + session.seconds);
}

class UsageBreakdown {
  UsageBreakdown._(this.totalSeconds, this.apps);
  final int totalSeconds;
  final List<AppUsageBreakdown> apps;
  factory UsageBreakdown.between(
      List<AppUsageLog> logs, DateTime from, DateTime to) {
    final grouped = <String, List<UsageSession>>{};
    final labels = <String, String>{};
    for (final log in logs) {
      final start = log.startedAt.toLocal();
      final duration = math.max(
          0,
          log.durationSeconds ??
              log.endedAt?.difference(log.startedAt).inSeconds ??
              0);
      final end = start.add(Duration(seconds: duration));
      final clippedStart = start.isAfter(from) ? start : from;
      final clippedEnd = end.isBefore(to) ? end : to;
      if (!clippedEnd.isAfter(clippedStart)) continue;
      grouped
          .putIfAbsent(log.packageName, () => [])
          .add(UsageSession(clippedStart, clippedEnd));
      if (log.appLabel.trim().isNotEmpty) {
        labels[log.packageName] = log.appLabel.trim();
      }
    }
    final apps = grouped.entries
        .map((entry) => AppUsageBreakdown(
            entry.key, labels[entry.key] ?? entry.key, _merge(entry.value)))
        .toList()
      ..sort((a, b) {
        final order = b.seconds.compareTo(a.seconds);
        return order != 0 ? order : a.label.compareTo(b.label);
      });
    final total = _merge(apps.expand((app) => app.sessions).toList())
        .fold<int>(0, (sum, session) => sum + session.seconds);
    return UsageBreakdown._(total, apps);
  }
}
