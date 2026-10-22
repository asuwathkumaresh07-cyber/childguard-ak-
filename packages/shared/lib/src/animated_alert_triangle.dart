import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'app_palette.dart';

/// A compact warning symbol animated with library effects, without ripple rings.
class AnimatedAlertTriangle extends StatelessWidget {
  const AnimatedAlertTriangle(
      {super.key, this.size = 40, this.primaryColor = AppPalette.red});
  final double size;
  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    Widget warning =
        Icon(Icons.warning_amber_rounded, color: primaryColor, size: size);
    if (!MediaQuery.disableAnimationsOf(context)) {
      warning = warning
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .scaleXY(begin: .92, end: 1, duration: 1400.ms);
    }
    return Semantics(
        label: 'Protection alert',
        child: SizedBox(width: size, height: size, child: warning));
  }
}
