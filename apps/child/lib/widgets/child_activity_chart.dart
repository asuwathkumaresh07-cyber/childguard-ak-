import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared/shared.dart';

class ChildActivityChart extends StatelessWidget {
  const ChildActivityChart({super.key, required this.logs, this.locale = 'en'});

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
    final now = DateTime.now();
    final days = List.generate(
      7,
      (index) => DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: 6 - index)),
    );
    final daySeconds = [
      for (final day in days)
        logs.where((log) {
          final local = log.startedAt.toLocal();
          return local.year == day.year &&
              local.month == day.month &&
              local.day == day.day;
        }).fold<int>(
          0,
          (sum, log) => sum + math.max(log.durationSeconds ?? 0, 0),
        ),
    ];
    final today = days.last;
    final todaySeconds = <int>[for (var hour = 0; hour < 24; hour++) 0];
    for (final log in logs) {
      final start = log.startedAt.toLocal();
      if (start.year != today.year ||
          start.month != today.month ||
          start.day != today.day) {
        continue;
      }
      final duration = math.max(
        log.durationSeconds ??
            log.endedAt?.difference(log.startedAt).inSeconds ??
            0,
        0,
      );
      var cursor = start;
      var remaining = duration;
      final dayEnd = DateTime(today.year, today.month, today.day + 1);
      while (remaining > 0 && cursor.isBefore(dayEnd)) {
        final nextHour = DateTime(
          cursor.year,
          cursor.month,
          cursor.day,
          cursor.hour + 1,
        );
        final slice =
            math.min(remaining, nextHour.difference(cursor).inSeconds);
        todaySeconds[cursor.hour] += slice;
        cursor = nextHour;
        remaining -= slice;
      }
    }
    final totalSeconds = daySeconds.fold<int>(0, (sum, value) => sum + value);
    final maxDaySeconds = math.max(1, daySeconds.fold<int>(0, math.max));

    final summaries = <String, _AppUsageSummary>{};
    final weekStart = days.first;
    for (final log in logs) {
      final start = log.startedAt.toLocal();
      if (start.isBefore(weekStart)) continue;
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
      summary.weekSeconds += duration;
      if (DateUtils.isSameDay(start, today)) summary.todaySeconds += duration;
      final dayIndex = DateUtils.dateOnly(start)
          .difference(DateUtils.dateOnly(weekStart))
          .inDays;
      if (dayIndex >= 0 && dayIndex < summary.daySeconds.length) {
        summary.daySeconds[dayIndex] += duration;
      }
    }
    final appSummaries = summaries.values.toList()
      ..sort((a, b) => b.weekSeconds.compareTo(a.weekSeconds));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _hindi ? 'आपका स्क्रीन समय' : 'Your screen time',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              _duration(totalSeconds),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 128,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < days.length; index++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: daySeconds[index] == 0
                                  ? .025
                                  : (daySeconds[index] / maxDaySeconds)
                                      .clamp(.04, 1)
                                      .toDouble(),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(9),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Theme.of(context).colorScheme.primary,
                                      Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: .55),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          DateFormat('E', locale).format(days[index]),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _hindi
              ? 'पिछले 7 दिनों का उपयोग'
              : 'Daily activity over the last 7 days',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),
        Text(
          _hindi ? 'आज का घंटेवार उपयोग' : 'Hourly usage today',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 112,
          width: double.infinity,
          child: CustomPaint(
            painter: _HourlyUsagePainter(
              values: todaySeconds,
              color: Theme.of(context).colorScheme.secondary,
              gridColor: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final hour in const [0, 6, 12, 18, 24])
              Text(
                hour.toString().padLeft(2, '0'),
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
        const SizedBox(height: 22),
        Text(
          _hindi ? 'ऐप के अनुसार गतिविधि' : 'Activity by app',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (appSummaries.isEmpty)
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
          for (final app in appSummaries)
            _AppUsageTile(
              app: app,
              durationFormatter: _duration,
              hindi: _hindi,
            ),
      ],
    );
  }
}

class _AppUsageSummary {
  _AppUsageSummary({required this.packageName, required this.appLabel});

  final String packageName;
  final String appLabel;
  final List<AppUsageLog> logs = [];
  final List<int> daySeconds = List.filled(7, 0);
  int todaySeconds = 0;
  int weekSeconds = 0;
}

class _AppUsageTile extends StatelessWidget {
  const _AppUsageTile({
    required this.app,
    required this.durationFormatter,
    required this.hindi,
  });

  final _AppUsageSummary app;
  final String Function(int) durationFormatter;
  final bool hindi;

  @override
  Widget build(BuildContext context) {
    final sortedLogs = app.logs.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final maxDay = math.max(1, app.daySeconds.fold<int>(0, math.max));
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        child: Icon(
          Icons.apps_rounded,
          size: 19,
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
      title: Text(app.appLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${hindi ? 'आज' : 'Today'} ${durationFormatter(app.todaySeconds)} · ${hindi ? '7 दिन' : '7d'} ${durationFormatter(app.weekSeconds)}',
      ),
      trailing: SizedBox(
        width: 48,
        height: 28,
        child: CustomPaint(
          painter: _SparklinePainter(
            values: app.daySeconds,
            maxValue: maxDay,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      children: [
        for (final log in sortedLogs.take(5))
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 8, right: 4),
            leading: const Icon(Icons.history, size: 18),
            title: Text(
              DateFormat('EEE, h:mm a', hindi ? 'hi' : 'en')
                  .format(log.startedAt.toLocal()),
            ),
            subtitle: Text(
              log.durationSeconds == null
                  ? (hindi ? 'खोला गया' : 'Opened')
                  : '${hindi ? 'उपयोग अवधि' : 'Session'} · ${durationFormatter(log.durationSeconds!)}',
            ),
          ),
      ],
    );
  }
}

class _HourlyUsagePainter extends CustomPainter {
  const _HourlyUsagePainter({
    required this.values,
    required this.color,
    required this.gridColor,
  });

  final List<int> values;
  final Color color;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 4.0;
    const right = 4.0;
    const top = 8.0;
    const bottom = 8.0;
    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;
    final maxValue = math.max(1, values.fold<int>(0, math.max));
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var row = 0; row < 3; row++) {
      final y = top + chartHeight * row / 2;
      canvas.drawLine(
          Offset(left, y), Offset(size.width - right, y), gridPaint);
    }
    final points = <Offset>[
      for (var index = 0; index < values.length; index++)
        Offset(
          left + chartWidth * index / (values.length - 1),
          top + chartHeight * (1 - values[index] / maxValue),
        ),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    for (final point in points) {
      canvas.drawCircle(point, 2.1, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _HourlyUsagePainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.color != color ||
      oldDelegate.gridColor != gridColor;
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.values,
    required this.maxValue,
    required this.color,
  });

  final List<int> values;
  final int maxValue;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final points = <Offset>[
      for (var index = 0; index < values.length; index++)
        Offset(
          size.width * index / (values.length - 1),
          size.height * (1 - values[index] / maxValue),
        ),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    for (final point in points) {
      canvas.drawCircle(point, 1.8, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.maxValue != maxValue ||
      oldDelegate.color != color;
}
