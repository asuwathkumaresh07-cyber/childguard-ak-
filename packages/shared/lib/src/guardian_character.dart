import 'dart:math' as math;
import 'package:flutter/material.dart';

enum GuardianMood {
  safe,
  alert,
  happy,
}

/// An animated, interactive vector mascot ("Aegis the Cyber Guardian")
/// tailored specifically for Family Guard's digital safety and family protection theme.
class GuardianCharacter extends StatefulWidget {
  const GuardianCharacter({
    super.key,
    this.size = 80.0,
    this.mood = GuardianMood.safe,
    this.showBadge = true,
    this.onTap,
  });

  final double size;
  final GuardianMood mood;
  final bool showBadge;
  final VoidCallback? onTap;

  @override
  State<GuardianCharacter> createState() => _GuardianCharacterState();
}

class _GuardianCharacterState extends State<GuardianCharacter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  int _tapCount = 0;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _handleTap() {
    setState(() => _tapCount++);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) {
          final t = _anim.value;
          // Idle breathing bob
          final bob = math.sin(t * math.pi * 2) * (s * 0.05);
          // Shield satellite orbiting
          final satelliteAngle = t * math.pi * 2;
          final satX = math.cos(satelliteAngle) * (s * 0.42);
          final satY = math.sin(satelliteAngle) * (s * 0.18) - (s * 0.05);

          // Blink effect: eyes blink for 5% of the cycle
          final blinkProgress = (t % 0.5) * 2;
          final isBlinking = blinkProgress > 0.92;

          return SizedBox(
            width: s * 1.3,
            height: s * 1.25,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Floating shadow under character
                Positioned(
                  bottom: s * 0.02,
                  child: Container(
                    width: s * 0.65 + math.sin(t * math.pi * 2) * (s * 0.06),
                    height: s * 0.12,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.12),
                      borderRadius: BorderRadius.all(Radius.elliptical(s * 0.65, s * 0.12)),
                    ),
                  ),
                ),

                // Character body with vertical floating
                Transform.translate(
                  offset: Offset(0, bob),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Mascot vector rendering
                      CustomPaint(
                        size: Size(s, s),
                        painter: _GuardianPainter(
                          mood: widget.mood,
                          isBlinking: isBlinking,
                          animProgress: t,
                          isDark: isDark,
                        ),
                      ),

                      // Orbiting mini shield companion satellite
                      Transform.translate(
                        offset: Offset(satX + (s * 0.38), satY - (s * 0.2)),
                        child: _MiniShieldSatellite(
                          mood: widget.mood,
                          size: s * 0.28,
                          phase: t,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MiniShieldSatellite extends StatelessWidget {
  const _MiniShieldSatellite({
    required this.mood,
    required this.size,
    required this.phase,
  });

  final GuardianMood mood;
  final double size;
  final double phase;

  @override
  Widget build(BuildContext context) {
    final color = mood == GuardianMood.alert
        ? const Color(0xFFE53935)
        : const Color(0xFF26A69A);

    return Container(
      width: size,
      height: size * 1.15,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(size * 0.35),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Icon(
          mood == GuardianMood.alert ? Icons.warning_amber_rounded : Icons.security,
          size: size * 0.65,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _GuardianPainter extends CustomPainter {
  _GuardianPainter({
    required this.mood,
    required this.isBlinking,
    required this.animProgress,
    required this.isDark,
  });

  final GuardianMood mood;
  final bool isBlinking;
  final double animProgress;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final primaryColor = switch (mood) {
      GuardianMood.alert => const Color(0xFFE53935),
      GuardianMood.happy => const Color(0xFF00ACC1),
      GuardianMood.safe => const Color(0xFF2A8B7F),
    };

    final coreGlowColor = switch (mood) {
      GuardianMood.alert => const Color(0xFFFF5252),
      GuardianMood.happy => const Color(0xFF80DEEA),
      GuardianMood.safe => const Color(0xFF4DB6AC),
    };

    // 1. Cat/Lion cyber ear antennas
    final earPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [primaryColor, primaryColor.withValues(alpha: 0.7)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    // Left Ear
    final leftEar = Path()
      ..moveTo(w * 0.22, h * 0.32)
      ..lineTo(w * 0.12, h * 0.12)
      ..lineTo(w * 0.36, h * 0.24)
      ..close();
    canvas.drawPath(leftEar, earPaint);

    // Right Ear
    final rightEar = Path()
      ..moveTo(w * 0.78, h * 0.32)
      ..lineTo(w * 0.88, h * 0.12)
      ..lineTo(w * 0.64, h * 0.24)
      ..close();
    canvas.drawPath(rightEar, earPaint);

    // Ear tip glowing lights
    canvas.drawCircle(Offset(w * 0.12, h * 0.12), w * 0.035, Paint()..color = coreGlowColor);
    canvas.drawCircle(Offset(w * 0.88, h * 0.12), w * 0.035, Paint()..color = coreGlowColor);

    // 2. Shield Armor Body (Lower torso)
    final bodyPath = Path()
      ..moveTo(w * 0.25, h * 0.60)
      ..lineTo(w * 0.75, h * 0.60)
      ..lineTo(w * 0.68, h * 0.90)
      ..quadraticBezierTo(w * 0.50, h * 0.98, w * 0.32, h * 0.90)
      ..close();

    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [const Color(0xFF1E3535), const Color(0xFF132223)]
            : [const Color(0xFFE2F4F1), const Color(0xFFBCE6DF)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(bodyPath, bodyPaint);

    // Body outline
    canvas.drawPath(
      bodyPath,
      Paint()
        ..color = primaryColor.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // Chest Shield Core (Glowing emblem)
    final coreCenter = Offset(w * 0.5, h * 0.75);
    final coreRadius = w * 0.08 + math.sin(animProgress * math.pi * 2) * (w * 0.015);
    canvas.drawCircle(
      coreCenter,
      coreRadius * 1.5,
      Paint()..color = coreGlowColor.withValues(alpha: 0.3),
    );
    canvas.drawCircle(
      coreCenter,
      coreRadius,
      Paint()..color = coreGlowColor,
    );

    // Inner core icon (Checkmark for safe, exclamation for alert)
    if (mood == GuardianMood.alert) {
      canvas.drawCircle(coreCenter, coreRadius * 0.4, Paint()..color = Colors.white);
    } else {
      final markPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(coreCenter.dx - 3, coreCenter.dy), Offset(coreCenter.dx - 1, coreCenter.dy + 3), markPaint);
      canvas.drawLine(Offset(coreCenter.dx - 1, coreCenter.dy + 3), Offset(coreCenter.dx + 4, coreCenter.dy - 3), markPaint);
    }

    // 3. Head Helmet (Rounded cyber head)
    final headRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.42), width: w * 0.68, height: h * 0.46),
      Radius.circular(w * 0.22),
    );

    final headPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [const Color(0xFF244443), const Color(0xFF162A2A)]
            : [Colors.white, const Color(0xFFE0F2F1)],
      ).createShader(headRect.outerRect);

    canvas.drawShadow(Path()..addRRect(headRect), Colors.black.withValues(alpha: 0.2), 6.0, true);
    canvas.drawRRect(headRect, headPaint);

    // Head border
    canvas.drawRRect(
      headRect,
      Paint()
        ..color = primaryColor.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // 4. Visor Screen (Dark digital screen)
    final visorRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.44), width: w * 0.54, height: h * 0.24),
      Radius.circular(w * 0.10),
    );
    canvas.drawRRect(visorRect, Paint()..color = const Color(0xFF0F1E1E));

    // 5. Visor Eyes (Animated cyan or amber LED lights)
    final eyePaint = Paint()
      ..color = coreGlowColor
      ..style = PaintingStyle.fill;

    if (isBlinking) {
      // Slit eyes while blinking
      canvas.drawLine(
        Offset(w * 0.36, h * 0.44),
        Offset(w * 0.44, h * 0.44),
        Paint()
          ..color = coreGlowColor
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        Offset(w * 0.56, h * 0.44),
        Offset(w * 0.64, h * 0.44),
        Paint()
          ..color = coreGlowColor
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    } else if (mood == GuardianMood.happy) {
      // Smiling curved eyes ^ ^
      final happyLeft = Path()
        ..moveTo(w * 0.36, h * 0.46)
        ..quadraticBezierTo(w * 0.40, h * 0.40, w * 0.44, h * 0.46);
      final happyRight = Path()
        ..moveTo(w * 0.56, h * 0.46)
        ..quadraticBezierTo(w * 0.60, h * 0.40, w * 0.64, h * 0.46);
      final archPaint = Paint()
        ..color = coreGlowColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(happyLeft, archPaint);
      canvas.drawPath(happyRight, archPaint);
    } else if (mood == GuardianMood.alert) {
      // Focused alert eyes
      canvas.drawCircle(Offset(w * 0.40, h * 0.44), w * 0.045, eyePaint);
      canvas.drawCircle(Offset(w * 0.60, h * 0.44), w * 0.045, eyePaint);
      // Warning crest on helmet forehead
      final tri = Path()
        ..moveTo(w * 0.50, h * 0.24)
        ..lineTo(w * 0.46, h * 0.30)
        ..lineTo(w * 0.54, h * 0.30)
        ..close();
      canvas.drawPath(tri, Paint()..color = const Color(0xFFFF5252));
    } else {
      // Normal friendly oval eyes with small twinkle pupil
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(w * 0.40, h * 0.44), width: w * 0.075, height: h * 0.11),
          const Radius.circular(5),
        ),
        eyePaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(w * 0.60, h * 0.44), width: w * 0.075, height: h * 0.11),
          const Radius.circular(5),
        ),
        eyePaint,
      );
      // Eye highlights
      canvas.drawCircle(Offset(w * 0.41, h * 0.42), w * 0.015, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(w * 0.61, h * 0.42), w * 0.015, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _GuardianPainter oldDelegate) =>
      oldDelegate.mood != mood ||
      oldDelegate.isBlinking != isBlinking ||
      oldDelegate.animProgress != animProgress ||
      oldDelegate.isDark != isDark;
}
