import 'dart:ui';

import 'package:flutter/material.dart';

/// A premium, ultra-modern Glassmorphic container with real BackdropFilter blur,
/// specular glass gradient reflection, glowing neon halo shadows, and optional live shimmer.
class GlassCard extends StatefulWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.symmetric(vertical: 6),
    this.borderRadius = 22,
    this.blurSigma = 16.0,
    this.accentColor,
    this.showShimmer = false,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blurSigma;
  final Color? accentColor;
  final bool showShimmer;
  final VoidCallback? onTap;

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController? _shimmerController;

  @override
  void initState() {
    super.initState();
    if (widget.showShimmer) {
      _shimmerController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 3200),
      )..repeat();
    } else {
      _shimmerController = null;
    }
  }

  @override
  void dispose() {
    _shimmerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = widget.accentColor ?? theme.colorScheme.primary;

    final content = ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: widget.blurSigma,
          sigmaY: widget.blurSigma,
        ),
        child: Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      const Color(0xFF162032).withValues(alpha: 0.85),
                      const Color(0xFF0F1728).withValues(alpha: 0.70),
                      const Color(0xFF131D2E).withValues(alpha: 0.80),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.88),
                      Colors.white.withValues(alpha: 0.65),
                      Colors.white.withValues(alpha: 0.78),
                    ],
            ),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.95),
              width: 1.4,
            ),
            boxShadow: [
              // Ambient soft diffuse shadow
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
              // Subtle neon halo glow around the card
              BoxShadow(
                color: primary.withValues(alpha: isDark ? 0.18 : 0.10),
                blurRadius: 16,
                spreadRadius: 0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Foreground child
              widget.child,

              // Optional live light shimmer sweep across the glass surface
              if (widget.showShimmer && _shimmerController != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _shimmerController,
                      builder: (context, _) {
                        final val = _shimmerController.value;
                        return ShaderMask(
                          shaderCallback: (bounds) {
                            return LinearGradient(
                              begin: Alignment(-2.0 + val * 4.0, -1.0),
                              end: Alignment(-1.0 + val * 4.0, 1.0),
                              colors: const [
                                Colors.transparent,
                                Colors.white24,
                                Colors.white54,
                                Colors.white24,
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.4, 0.5, 0.6, 1.0],
                            ).createShader(bounds);
                          },
                          blendMode: BlendMode.srcOver,
                          child: Container(color: Colors.transparent),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (widget.margin != null) {
      return Padding(
        padding: widget.margin!,
        child: widget.onTap != null
            ? GestureDetector(onTap: widget.onTap, child: content)
            : content,
      );
    }

    return widget.onTap != null
        ? GestureDetector(onTap: widget.onTap, child: content)
        : content;
  }
}

/// A live pulsating status badge with radiating concentric radar rings.
class LivePulseBadge extends StatefulWidget {
  const LivePulseBadge({
    super.key,
    required this.label,
    this.color = const Color(0xFF00C853),
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  State<LivePulseBadge> createState() => _LivePulseBadgeState();
}

class _LivePulseBadgeState extends State<LivePulseBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.color.withValues(alpha: 0.35),
          width: 1.1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Concentric animated pulsing dot
          SizedBox(
            width: 12,
            height: 12,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 6 + t * 6,
                      height: 6 + t * 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.color.withValues(alpha: (1.0 - t) * 0.5),
                      ),
                    ),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.color,
                        boxShadow: [
                          BoxShadow(
                            color: widget.color.withValues(alpha: 0.6),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 6),
          if (widget.icon != null) ...[
            Icon(widget.icon, size: 12, color: widget.color),
            const SizedBox(width: 4),
          ],
          Text(
            widget.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: widget.color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
