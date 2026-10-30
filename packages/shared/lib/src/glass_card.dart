import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'app_palette.dart';

/// A readable card with a quiet border and no moving surface effects.
class GlassCard extends StatelessWidget {
  const GlassCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16),
      this.margin = const EdgeInsets.symmetric(vertical: 6),
      this.borderRadius = 18,
      this.accentColor,
      this.onTap});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            side: BorderSide(
                color: accentColor?.withValues(alpha: .3) ??
                    scheme.outlineVariant)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

/// Live status uses a small fading dot; no radiating rings or wave effects.
class LivePulseBadge extends StatelessWidget {
  const LivePulseBadge(
      {super.key,
      required this.label,
      this.color = AppPalette.blue,
      this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    Widget dot = Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle));
    if (!MediaQuery.disableAnimationsOf(context)) {
      dot = dot
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .fade(begin: .4, end: 1, duration: 1200.ms);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) Icon(icon, size: 12, color: color) else dot,
        const SizedBox(width: 5),
        Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w700))),
      ]),
    );
  }
}
