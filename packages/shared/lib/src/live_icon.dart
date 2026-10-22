import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:not_static_icons/not_static_icons.dart' as animated;

/// Prebuilt animated paths for feature icons; controls retain their own gestures.
class LiveIcon extends StatelessWidget {
  const LiveIcon(this.icon,
      {super.key, this.size, this.color, this.semanticLabel, this.loop = true});
  final IconData icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;
  final bool loop;

  @override
  Widget build(BuildContext context) {
    final dimension = size ?? IconTheme.of(context).size ?? 24;
    final tint = color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.primary;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final repeat = loop && !reduced;
    Widget result;
    if (reduced || !loop) {
      result = Icon(icon, size: dimension, color: tint);
    } else if ({
      Icons.shield,
      Icons.shield_outlined,
      Icons.shield_rounded,
      Icons.security,
      Icons.verified_user_rounded
    }.contains(icon)) {
      result = animated.BadgeCheckIcon(
          size: dimension,
          color: tint,
          infiniteLoop: repeat,
          interactive: false,
          animationDuration: const Duration(milliseconds: 2200));
    } else if ({
      Icons.notifications,
      Icons.notifications_none_rounded,
      Icons.notifications_outlined,
      Icons.warning_rounded,
      Icons.warning_amber_rounded,
      Icons.warning_amber,
      Icons.gpp_bad_rounded
    }.contains(icon)) {
      result = animated.BellRingIcon(
          size: dimension,
          color: tint,
          infiniteLoop: repeat,
          interactive: false,
          animationDuration: const Duration(milliseconds: 2200));
    } else if ({Icons.bar_chart_rounded, Icons.bar_chart, Icons.insights}
        .contains(icon)) {
      result = animated.ChartColumnIcon(
          size: dimension,
          color: tint,
          infiniteLoop: repeat,
          interactive: false,
          animationDuration: const Duration(milliseconds: 2400));
    } else if ({Icons.apps, Icons.apps_rounded, Icons.category_outlined}
        .contains(icon)) {
      result = animated.Grid2x2Icon(
          size: dimension,
          color: tint,
          infiniteLoop: repeat,
          interactive: false,
          animationDuration: const Duration(milliseconds: 2400));
    } else if ({Icons.public, Icons.language}.contains(icon)) {
      result = animated.GlobeIcon(
          size: dimension,
          color: tint,
          infiniteLoop: repeat,
          interactive: false,
          animationDuration: const Duration(milliseconds: 2800));
    } else if ({
      Icons.location_on,
      Icons.location_on_outlined,
      Icons.radar,
      Icons.radar_rounded,
      Icons.my_location
    }.contains(icon)) {
      result = animated.CompassIcon(
          size: dimension,
          color: tint,
          infiniteLoop: repeat,
          interactive: false,
          animationDuration: const Duration(milliseconds: 2800));
    } else if ({
      Icons.checklist_outlined,
      Icons.checklist,
      Icons.task_alt,
      Icons.check_circle_outline,
      Icons.check_circle
    }.contains(icon)) {
      result = animated.ClipboardCheckIcon(
          size: dimension,
          color: tint,
          infiniteLoop: repeat,
          interactive: false,
          animationDuration: const Duration(milliseconds: 2400));
    } else if ({
      Icons.history_rounded,
      Icons.list_alt_rounded,
      Icons.monitor_heart_outlined
    }.contains(icon)) {
      result = animated.ActivityIcon(
          size: dimension,
          color: tint,
          infiniteLoop: repeat,
          interactive: false,
          animationDuration: const Duration(milliseconds: 2400));
    } else if ({Icons.settings, Icons.tune}.contains(icon)) {
      result = animated.CogIcon(
          size: dimension,
          color: tint,
          infiniteLoop: repeat,
          interactive: false,
          animationDuration: const Duration(milliseconds: 3000));
    } else if ({Icons.more_horiz, Icons.more_vert}.contains(icon)) {
      result = animated.EllipsisIcon(
          size: dimension,
          color: tint,
          infiniteLoop: repeat,
          interactive: false,
          animationDuration: const Duration(milliseconds: 2600));
    } else if ({Icons.favorite, Icons.favorite_outline, Icons.mood}
        .contains(icon)) {
      result = animated.HeartIcon(
          size: dimension,
          color: tint,
          infiniteLoop: repeat,
          interactive: false,
          animationDuration: const Duration(milliseconds: 2200));
    } else if ({
      Icons.timer_outlined,
      Icons.more_time,
      Icons.access_time,
      Icons.schedule
    }.contains(icon)) {
      result = animated.ClockIcon(
          size: dimension,
          color: tint,
          infiniteLoop: repeat,
          interactive: false,
          animationDuration: const Duration(milliseconds: 3000));
    } else if ({Icons.person, Icons.person_outline, Icons.child_care_outlined}
        .contains(icon)) {
      result = animated.CircleUserRoundIcon(
          size: dimension,
          color: tint,
          infiniteLoop: repeat,
          interactive: false,
          animationDuration: const Duration(milliseconds: 2600));
    } else {
      result = Icon(icon, size: dimension, color: tint);
      if (dimension >= 40) {
        result = result
            .animate(
                onPlay: repeat
                    ? (controller) => controller.repeat(reverse: true)
                    : null)
            .scaleXY(begin: .94, end: 1, duration: 1600.ms);
      }
    }
    return Semantics(
        label: semanticLabel,
        excludeSemantics: semanticLabel == null,
        child: IgnorePointer(child: RepaintBoundary(child: result)));
  }
}
