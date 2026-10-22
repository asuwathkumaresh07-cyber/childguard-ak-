import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A vibrant, animated red warning triangle with smooth harmonic motion
/// (bobbing, tilting, and glowing pulse rings) to signal live alerts.
class AnimatedAlertTriangle extends StatefulWidget {
  const AnimatedAlertTriangle({
    super.key,
    this.size = 40.0,
    this.showPulseRings = true,
    this.tiltIntensity = 1.0,
    this.primaryColor = const Color(0xFFE53935),
    this.accentColor = const Color(0xFFFF8A80),
  });

  final double size;
  final bool showPulseRings;
  final double tiltIntensity;
  final Color primaryColor;
  final Color accentColor;

  @override
  State<AnimatedAlertTriangle> createState() => _AnimatedAlertTriangleState();
}

class _AnimatedAlertTriangleState extends State<AnimatedAlertTriangle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        // Harmonic bob: up and down
        final bob = math.sin(t * math.pi * 2) * (widget.size * 0.08);
        // Harmonic tilt: warning tilt oscillation
        final tilt = math.sin(t * math.pi * 2) * 0.12 * widget.tiltIntensity;
        // Pulse scale
        final scale = 1.0 + math.sin(t * math.pi * 2) * 0.04;

        return SizedBox(
          width: widget.size * (widget.showPulseRings ? 1.6 : 1.1),
          height: widget.size * (widget.showPulseRings ? 1.6 : 1.1),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Radiating danger pulse rings
              if (widget.showPulseRings) ...[
                _buildPulseRing(t, 0.0),
                _buildPulseRing((t + 0.5) % 1.0, 0.5),
              ],

              // Moving triangle body
              Transform.translate(
                offset: Offset(0, bob),
                child: Transform.rotate(
                  angle: tilt,
                  child: Transform.scale(
                    scale: scale,
                    child: CustomPaint(
                      size: Size(widget.size, widget.size),
                      painter: _AlertTrianglePainter(
                        primaryColor: widget.primaryColor,
                        accentColor: widget.accentColor,
                        pulseProgress: t,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPulseRing(double progress, double phase) {
    final ringRadius = widget.size * (0.6 + progress * 0.7);
    final alpha = (1.0 - progress).clamp(0.0, 0.8) * 0.45;
    return IgnorePointer(
      child: Container(
        width: ringRadius * 2,
        height: ringRadius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: widget.primaryColor.withValues(alpha: alpha),
            width: 2.0 * (1.0 - progress * 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: widget.accentColor.withValues(alpha: alpha * 0.5),
              blurRadius: 8 * progress,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertTrianglePainter extends CustomPainter {
  _AlertTrianglePainter({
    required this.primaryColor,
    required this.accentColor,
    required this.pulseProgress,
  });

  final Color primaryColor;
  final Color accentColor;
  final double pulseProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Triangle vertices with rounded corners
    final top = Offset(w * 0.5, h * 0.08);
    final bottomLeft = Offset(w * 0.08, h * 0.92);
    final bottomRight = Offset(w * 0.92, h * 0.92);

    final path = Path();
    const cornerRadius = 6.0;

    // Construct smooth rounded triangle
    path.moveTo(top.dx, top.dy + cornerRadius);
    path.quadraticBezierTo(top.dx, top.dy, top.dx + cornerRadius * 0.86, top.dy + cornerRadius * 0.5);
    path.lineTo(bottomRight.dx - cornerRadius * 0.86, bottomRight.dy - cornerRadius * 0.5);
    path.quadraticBezierTo(bottomRight.dx, bottomRight.dy, bottomRight.dx - cornerRadius, bottomRight.dy);
    path.lineTo(bottomLeft.dx + cornerRadius, bottomLeft.dy);
    path.quadraticBezierTo(bottomLeft.dx, bottomLeft.dy, bottomLeft.dx + cornerRadius * 0.14, bottomLeft.dy - cornerRadius * 0.5);
    path.lineTo(top.dx - cornerRadius * 0.86, top.dy + cornerRadius * 0.5);
    path.quadraticBezierTo(top.dx, top.dy, top.dx, top.dy + cornerRadius);
    path.close();

    // Shadow
    canvas.drawShadow(path, primaryColor.withValues(alpha: 0.6), 8.0, true);

    // Gradient fill
    final paintFill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [accentColor, primaryColor],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paintFill);

    // Stroke border
    final paintBorder = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawPath(path, paintBorder);

    // Exclamation mark (!) inside triangle
    final textPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Vertical exclamation stem
    final stemRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.5 - (w * 0.05), h * 0.38, w * 0.10, h * 0.26),
      const Radius.circular(3),
    );
    canvas.drawRRect(stemRect, textPaint);

    // Exclamation dot
    canvas.drawCircle(Offset(w * 0.5, h * 0.74), w * 0.055, textPaint);
  }

  @override
  bool shouldRepaint(covariant _AlertTrianglePainter oldDelegate) =>
      oldDelegate.pulseProgress != pulseProgress ||
      oldDelegate.primaryColor != primaryColor;
}
