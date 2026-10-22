import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'models.dart';

/// A comprehensive usage chart providing both:
/// 1. Daily Usage Bar Graph (7-day screen time with animated bars & duration labels)
/// 2. Hourly Usage Point Graph (24-hour scatter/point curve with peak points & tooltips)
class DualUsageChart extends StatefulWidget {
  const DualUsageChart({
    super.key,
    required this.logs,
    this.title = 'Screen Time & Usage Analytics',
    this.primaryColor,
    this.secondaryColor,
    this.initialMode = DualChartMode.both,
  });

  final List<AppUsageLog> logs;
  final String title;
  final Color? primaryColor;
  final Color? secondaryColor;
  final DualChartMode initialMode;

  @override
  State<DualUsageChart> createState() => _DualUsageChartState();
}

enum DualChartMode {
  both,
  dailyBar,
  hourlyPoint,
}

class _DualUsageChartState extends State<DualUsageChart> {
  late DualChartMode _mode = widget.initialMode;
  int _selectedDayIndex = 6; // Defaults to today (last of 7 days)
  int? _hoveredHour;

  String _formatDuration(int seconds) {
    final s = math.max(0, seconds);
    final hours = s ~/ 3600;
    final mins = (s % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${mins}m';
    if (mins > 0) return '${mins}m';
    return s > 0 ? '${s}s' : '0m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = widget.primaryColor ?? theme.colorScheme.primary;
    final secondary = widget.secondaryColor ?? const Color(0xFF00ACC1);

    final now = DateTime.now();
    // Last 7 days ending today
    final days = List.generate(
      7,
      (i) => DateTime(now.year, now.month, now.day).subtract(Duration(days: 6 - i)),
    );

    // Calculate daily seconds for the 7 days
    final dailySeconds = List<int>.generate(7, (i) {
      final day = days[i];
      return widget.logs.where((log) {
        final start = log.startedAt.toLocal();
        return start.year == day.year && start.month == day.month && start.day == day.day;
      }).fold<int>(
        0,
        (sum, log) => sum + math.max(0, log.durationSeconds ?? log.endedAt?.difference(log.startedAt).inSeconds ?? 0),
      );
    });

    final totalWeekSeconds = dailySeconds.fold<int>(0, (a, b) => a + b);
    final selectedDay = days[_selectedDayIndex.clamp(0, 6)];
    final selectedDaySeconds = dailySeconds[_selectedDayIndex.clamp(0, 6)];

    // Calculate 24-hour seconds for selected day
    final hourlySeconds = List<int>.filled(24, 0);
    for (final log in widget.logs) {
      final start = log.startedAt.toLocal();
      if (start.year != selectedDay.year || start.month != selectedDay.month || start.day != selectedDay.day) {
        continue;
      }
      final duration = math.max(0, log.durationSeconds ?? log.endedAt?.difference(log.startedAt).inSeconds ?? 0);
      var cursor = start;
      var remaining = duration;
      final dayEnd = DateTime(selectedDay.year, selectedDay.month, selectedDay.day + 1);

      while (remaining > 0 && cursor.isBefore(dayEnd)) {
        final nextHour = DateTime(cursor.year, cursor.month, cursor.day, cursor.hour + 1);
        final slice = math.min(remaining, nextHour.difference(cursor).inSeconds);
        hourlySeconds[cursor.hour] += slice;
        cursor = nextHour;
        remaining -= slice;
      }
    }

    // Peak hour
    var peakHour = 0;
    var peakSeconds = 0;
    for (var h = 0; h < 24; h++) {
      if (hourlySeconds[h] > peakSeconds) {
        peakSeconds = hourlySeconds[h];
        peakHour = h;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with title and stats
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${DateFormat('EEEE, MMM d').format(selectedDay)}: ${_formatDuration(selectedDaySeconds)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '7d: ${_formatDuration(totalWeekSeconds)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Mode switch pills: [Both Graphs] | [Daily Bar] | [Hourly Point]
        Container(
          height: 34,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              _buildModePill(DualChartMode.both, 'Both Graphs', primary),
              _buildModePill(DualChartMode.dailyBar, 'Daily Bar', primary),
              _buildModePill(DualChartMode.hourlyPoint, 'Hourly Points', primary),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 1. Daily Usage Bar Graph
        if (_mode == DualChartMode.both || _mode == DualChartMode.dailyBar) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Daily Usage (Bar Graph)',
                style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                'Tap bar to inspect day',
                style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 140,
            width: double.infinity,
            child: _DailyBarChartWidget(
              days: days,
              seconds: dailySeconds,
              selectedIndex: _selectedDayIndex,
              primaryColor: primary,
              isDark: isDark,
              onSelectDay: (index) {
                setState(() {
                  _selectedDayIndex = index;
                  _hoveredHour = null;
                });
              },
            ),
          ),
          const SizedBox(height: 6),
        ],

        if (_mode == DualChartMode.both) const SizedBox(height: 18),

        // 2. Hourly Usage Point Graph
        if (_mode == DualChartMode.both || _mode == DualChartMode.hourlyPoint) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Hourly Usage (Point Graph)',
                style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (peakSeconds > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: secondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Peak: $peakHour:00 (${_formatDuration(peakSeconds)})',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: secondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 130,
            width: double.infinity,
            child: _HourlyPointChartWidget(
              values: hourlySeconds,
              hoveredHour: _hoveredHour,
              pointColor: secondary,
              gridColor: isDark ? Colors.white12 : Colors.black12,
              isDark: isDark,
              onHoverHour: (h) => setState(() => _hoveredHour = h),
            ),
          ),
          // Hour axis labels
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('00h', style: TextStyle(fontSize: 10, color: Colors.grey)),
                Text('04h', style: TextStyle(fontSize: 10, color: Colors.grey)),
                Text('08h', style: TextStyle(fontSize: 10, color: Colors.grey)),
                Text('12h', style: TextStyle(fontSize: 10, color: Colors.grey)),
                Text('16h', style: TextStyle(fontSize: 10, color: Colors.grey)),
                Text('20h', style: TextStyle(fontSize: 10, color: Colors.grey)),
                Text('23h', style: TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
          if (_hoveredHour != null) ...[
            const SizedBox(height: 6),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$_hoveredHour:00 - ${_hoveredHour! + 1}:00 : ${_formatDuration(hourlySeconds[_hoveredHour!])}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: secondary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildModePill(DualChartMode mode, String label, Color activeColor) {
    final active = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.35),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    )
                  ]
                : null,
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
      ),
    );
  }
}

// ==========================================
// Daily Usage Bar Chart
// ==========================================
class _DailyBarChartWidget extends StatelessWidget {
  const _DailyBarChartWidget({
    required this.days,
    required this.seconds,
    required this.selectedIndex,
    required this.primaryColor,
    required this.isDark,
    required this.onSelectDay,
  });

  final List<DateTime> days;
  final List<int> seconds;
  final int selectedIndex;
  final Color primaryColor;
  final bool isDark;
  final ValueChanged<int> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final maxSec = math.max(3600, seconds.fold<int>(0, math.max));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(7, (i) {
        final sec = seconds[i];
        final day = days[i];
        final isSelected = i == selectedIndex;
        final heightFactor = (sec / maxSec).clamp(0.04, 1.0);
        final hrs = sec / 3600;

        return Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelectDay(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Value label on top of bar
                  Text(
                    hrs >= 1.0 ? '${hrs.toStringAsFixed(1)}h' : (sec > 0 ? '${(sec ~/ 60)}m' : '0'),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                      color: isSelected ? primaryColor : (isDark ? Colors.white60 : Colors.black54),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Animated Bar
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: heightFactor,
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: isSelected
                                  ? [primaryColor, primaryColor.withValues(alpha: 0.6)]
                                  : [
                                      primaryColor.withValues(alpha: 0.45),
                                      primaryColor.withValues(alpha: 0.20),
                                    ],
                            ),
                            border: isSelected
                                ? Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.5)
                                : null,
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: primaryColor.withValues(alpha: 0.4),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Day of week label
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected ? primaryColor.withValues(alpha: 0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      DateFormat('E').format(day),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? primaryColor : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ==========================================
// Hourly Usage Point / Scatter Curve Chart
// ==========================================
class _HourlyPointChartWidget extends StatelessWidget {
  const _HourlyPointChartWidget({
    required this.values,
    required this.hoveredHour,
    required this.pointColor,
    required this.gridColor,
    required this.isDark,
    required this.onHoverHour,
  });

  final List<int> values;
  final int? hoveredHour;
  final Color pointColor;
  final Color gridColor;
  final bool isDark;
  final ValueChanged<int> onHoverHour;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (details) => _detectHour(details.localPosition, context.size),
      onPanUpdate: (details) => _detectHour(details.localPosition, context.size),
      child: CustomPaint(
        size: Size.infinite,
        painter: _HourlyPointChartPainter(
          values: values,
          hoveredHour: hoveredHour,
          pointColor: pointColor,
          gridColor: gridColor,
          isDark: isDark,
        ),
      ),
    );
  }

  void _detectHour(Offset localPosition, Size? size) {
    if (size == null || size.width <= 0) return;
    const left = 14.0;
    const right = 14.0;
    final chartWidth = size.width - left - right;
    final clampedX = (localPosition.dx - left).clamp(0.0, chartWidth);
    final hour = (clampedX / chartWidth * 23).round().clamp(0, 23);
    onHoverHour(hour);
  }
}

class _HourlyPointChartPainter extends CustomPainter {
  _HourlyPointChartPainter({
    required this.values,
    required this.hoveredHour,
    required this.pointColor,
    required this.gridColor,
    required this.isDark,
  });

  final List<int> values;
  final int? hoveredHour;
  final Color pointColor;
  final Color gridColor;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 14.0;
    const right = 14.0;
    const top = 12.0;
    const bottom = 12.0;
    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;
    final maxValue = math.max(600, values.fold<int>(0, math.max)); // At least 10 min scale

    // 1. Grid horizontal lines
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = top + chartHeight * i / 2;
      canvas.drawLine(Offset(left, y), Offset(size.width - right, y), gridPaint);
    }

    // 2. Compute points for 24 hours
    final points = <Offset>[];
    for (var h = 0; h < values.length; h++) {
      final x = left + chartWidth * (h / (values.length - 1));
      final y = top + chartHeight * (1.0 - (values[h] / maxValue));
      points.add(Offset(x, y));
    }

    // 3. Draw area gradient fill under points
    final areaPath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final p0 = points[i - 1];
      final p1 = points[i];
      final cx = (p0.dx + p1.dx) / 2;
      areaPath.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
    }
    areaPath.lineTo(points.last.dx, top + chartHeight);
    areaPath.lineTo(points.first.dx, top + chartHeight);
    areaPath.close();

    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          pointColor.withValues(alpha: 0.25),
          pointColor.withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(0, top, size.width, chartHeight));
    canvas.drawPath(areaPath, areaPaint);

    // 4. Draw connecting smooth curve
    final curvePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final p0 = points[i - 1];
      final p1 = points[i];
      final cx = (p0.dx + p1.dx) / 2;
      curvePath.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
    }
    final linePaint = Paint()
      ..color = pointColor
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(curvePath, linePaint);

    // 5. Draw distinct CIRCULAR POINTS on each hour
    for (var h = 0; h < points.length; h++) {
      final pt = points[h];
      final val = values[h];
      final isHovered = hoveredHour == h;
      final isPeak = val == maxValue && val > 0;

      if (val > 0 || isHovered) {
        // Outer halo
        canvas.drawCircle(
          pt,
          isHovered ? 7.5 : (isPeak ? 5.5 : 4.0),
          Paint()..color = pointColor.withValues(alpha: isHovered ? 0.35 : 0.2),
        );
        // Solid core
        canvas.drawCircle(
          pt,
          isHovered ? 4.5 : (isPeak ? 3.5 : 2.5),
          Paint()..color = isHovered ? Colors.white : pointColor,
        );
        if (isHovered) {
          canvas.drawCircle(
            pt,
            4.5,
            Paint()
              ..color = pointColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        }
      } else {
        // Small baseline dot for inactive hours
        canvas.drawCircle(
          pt,
          1.5,
          Paint()..color = pointColor.withValues(alpha: 0.4),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HourlyPointChartPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.hoveredHour != hoveredHour ||
      oldDelegate.pointColor != pointColor ||
      oldDelegate.gridColor != gridColor;
}
