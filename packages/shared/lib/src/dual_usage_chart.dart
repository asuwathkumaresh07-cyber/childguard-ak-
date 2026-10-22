import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'models.dart';

/// Daily totals and hourly usage points with a prior-day comparison.
class DualUsageChart extends StatefulWidget {
  const DualUsageChart({
    super.key,
    required this.logs,
    this.title = 'Screen Time & Usage Analytics',
    this.primaryColor,
    this.secondaryColor,
    this.initialMode = DualChartMode.daily,
  });

  final List<AppUsageLog> logs;
  final String title;
  final Color? primaryColor;
  final Color? secondaryColor;
  final DualChartMode initialMode;

  @override
  State<DualUsageChart> createState() => _DualUsageChartState();
}

enum DualChartMode { daily, hourly }

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
    final secondary = widget.secondaryColor ?? theme.colorScheme.secondary;

    final now = DateTime.now();
    // Last 7 days ending today
    final days = List.generate(
      7,
      (i) => DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: 6 - i)),
    );

    final dailySeconds = days
        .map((day) =>
            _secondsBetween(day, DateTime(day.year, day.month, day.day + 1)))
        .toList();
    final selectedDay = days[_selectedDayIndex.clamp(0, 6)];
    final selectedDaySeconds = dailySeconds[_selectedDayIndex.clamp(0, 6)];
    final previousDay =
        DateTime(selectedDay.year, selectedDay.month, selectedDay.day - 1);
    final previousDaySeconds = _secondsBetween(previousDay, selectedDay);
    final changeSeconds = selectedDaySeconds - previousDaySeconds;
    final changePercent = previousDaySeconds == 0
        ? null
        : changeSeconds.abs() / previousDaySeconds * 100;

    // Calculate 24-hour seconds for selected day
    final hourlySeconds = List.generate(
        24,
        (hour) => _secondsBetween(
              DateTime(
                  selectedDay.year, selectedDay.month, selectedDay.day, hour),
              DateTime(selectedDay.year, selectedDay.month, selectedDay.day,
                  hour + 1),
            ));

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
            _buildChangeIndicator(
              changeSeconds: changeSeconds,
              changePercent: changePercent,
              hasPreviousUsage: previousDaySeconds > 0,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // The selector chooses one graph at a time.
        Container(
          height: 44,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color:
                isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              _buildModePill(DualChartMode.daily, 'Daily', primary),
              _buildModePill(DualChartMode.hourly, 'Hourly', primary),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 1. Daily Usage Bar Graph
        if (_mode == DualChartMode.daily) ...[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                'Daily Usage (Bar Graph)',
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                'Tap bar to inspect day',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.hintColor),
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

        // 2. Hourly Usage Point Graph
        if (_mode == DualChartMode.hourly) ...[
          _buildHourlyDaySelector(days, primary),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                'Hourly Usage (Point Graph)',
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (peakSeconds > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
              children: ['00h', '04h', '08h', '12h', '16h', '20h', '23h']
                  .map((label) => Expanded(
                      child: Text(label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 9, color: Colors.grey))))
                  .toList(),
            ),
          ),
          if (_hoveredHour != null) ...[
            const SizedBox(height: 6),
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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

  int _secondsBetween(DateTime from, DateTime to) {
    var total = 0;
    for (final log in widget.logs) {
      final start = log.startedAt.toLocal();
      final seconds = math.max(
          0,
          log.durationSeconds ??
              log.endedAt?.difference(log.startedAt).inSeconds ??
              0);
      final end = start.add(Duration(seconds: seconds));
      final overlapStart = start.isAfter(from) ? start : from;
      final overlapEnd = end.isBefore(to) ? end : to;
      if (overlapEnd.isAfter(overlapStart)) {
        total += overlapEnd.difference(overlapStart).inSeconds;
      }
    }
    return total;
  }

  Widget _buildChangeIndicator({
    required int changeSeconds,
    required double? changePercent,
    required bool hasPreviousUsage,
  }) {
    final isIncrease = changeSeconds > 0;
    final isDecrease = changeSeconds < 0;
    final color = isIncrease
        ? const Color(0xFFDC3545)
        : isDecrease
            ? const Color(0xFF172B4D)
            : Theme.of(context).colorScheme.onSurfaceVariant;
    final icon = isIncrease
        ? Icons.trending_up
        : isDecrease
            ? Icons.trending_down
            : Icons.trending_flat;
    final value = hasPreviousUsage
        ? '${isIncrease ? "+" : isDecrease ? "−" : ""}${changePercent!.round()}%'
        : (changeSeconds > 0 ? 'New' : 'No change');

    return Tooltip(
      message:
          '${_formatDuration(changeSeconds.abs())} ${isIncrease ? "more" : isDecrease ? "less" : "change"} than the previous day',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 3),
            Text(
              '$value · ${_formatDuration(changeSeconds.abs())}',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHourlyDaySelector(List<DateTime> days, Color primary) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          for (var index = 0; index < days.length; index++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: ChoiceChip(
                  label: Text(DateFormat('E').format(days[index]),
                      style: const TextStyle(fontSize: 11)),
                  selected: _selectedDayIndex == index,
                  onSelected: (_) => setState(() {
                    _selectedDayIndex = index;
                    _hoveredHour = null;
                  }),
                  labelPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  selectedColor: primary.withValues(alpha: .16),
                  showCheckmark: false,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModePill(DualChartMode mode, String label, Color activeColor) {
    final active = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = mode),
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
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
              color: active
                  ? Colors.white
                  : (Theme.of(context).brightness == Brightness.dark
                      ? Colors.white70
                      : Colors.black87),
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
                    hrs >= 1.0
                        ? '${hrs.toStringAsFixed(1)}h'
                        : (sec > 0 ? '${(sec ~/ 60)}m' : '0'),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w500,
                      color: isSelected
                          ? primaryColor
                          : (isDark ? Colors.white60 : Colors.black54),
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
                                  ? [
                                      primaryColor,
                                      primaryColor.withValues(alpha: 0.6)
                                    ]
                                  : [
                                      primaryColor.withValues(alpha: 0.45),
                                      primaryColor.withValues(alpha: 0.20),
                                    ],
                            ),
                            border: isSelected
                                ? Border.all(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    width: 1.5)
                                : null,
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color:
                                          primaryColor.withValues(alpha: 0.4),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? primaryColor.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          DateFormat('E').format(day),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight:
                                isSelected ? FontWeight.w800 : FontWeight.w600,
                            color: isSelected
                                ? primaryColor
                                : (isDark ? Colors.white70 : Colors.black87),
                          ),
                        )),
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
      onPanUpdate: (details) =>
          _detectHour(details.localPosition, context.size),
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
    final maxValue =
        math.max(600, values.fold<int>(0, math.max)); // At least 10 min scale

    // 1. Grid horizontal lines
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = top + chartHeight * i / 2;
      canvas.drawLine(
          Offset(left, y), Offset(size.width - right, y), gridPaint);
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
