import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A rich, lively background with flowing sinusoidal waves, subtle floating
/// cyber-shield particles, and ambient atmospheric glow.
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({
    super.key,
    required this.child,
    this.showWaves = true,
    this.waveSpeed = 1.0,
    this.waveColor,
  });

  final Widget child;
  final bool showWaves;
  final double waveSpeed;
  final Color? waveColor;

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = widget.waveColor ?? Theme.of(context).colorScheme.primary;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Base ambient gradient
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? const [
                      Color(0xFF0F1718),
                      Color(0xFF131D1C),
                      Color(0xFF161F23),
                      Color(0xFF0D1418),
                    ]
                  : const [
                      Color(0xFFF0F8F6),
                      Color(0xFFEAF4FB),
                      Color(0xFFF3F2FB),
                      Color(0xFFEEF7F4),
                    ],
            ),
          ),
        ),

        // Live animated wave and orb layers
        if (widget.showWaves)
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _animation,
              builder: (context, _) {
                final progress = _animation.value;
                return CustomPaint(
                  painter: _WavyLivePainter(
                    progress: progress,
                    isDark: dark,
                    primaryColor: primaryColor,
                  ),
                  size: Size.infinite,
                );
              },
            ),
          ),

        // Foreground content
        widget.child,
      ],
    );
  }
}

class _WavyLivePainter extends CustomPainter {
  _WavyLivePainter({
    required this.progress,
    required this.isDark,
    required this.primaryColor,
  });

  final double progress;
  final bool isDark;
  final Color primaryColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final width = size.width;
    final height = size.height;

    // 1. Draw glowing background orbs
    final phase = progress * math.pi * 2;
    _drawGlowingOrb(
      canvas,
      Offset(-20 + math.sin(phase) * 35, height * 0.18 + math.cos(phase) * 30),
      140,
      (isDark ? const Color(0xFF1A5852) : const Color(0xFF8CE0D6)).withValues(alpha: isDark ? 0.35 : 0.30),
    );
    _drawGlowingOrb(
      canvas,
      Offset(width + 20 + math.cos(phase * 0.7) * 40, height * 0.45 + math.sin(phase * 0.7) * 35),
      170,
      (isDark ? const Color(0xFF1D4766) : const Color(0xFFA5D1F6)).withValues(alpha: isDark ? 0.30 : 0.28),
    );
    _drawGlowingOrb(
      canvas,
      Offset(width * 0.3 + math.sin(phase * 0.5) * 30, height * 0.75 + math.cos(phase * 0.5) * 25),
      120,
      (isDark ? const Color(0xFF38295E) : const Color(0xFFD6C8F6)).withValues(alpha: isDark ? 0.25 : 0.22),
    );

    // 2. Draw 3 distinct flowing sinusoidal waves
    // Bottom Wave 1 (Deep base wave)
    _drawSineWave(
      canvas: canvas,
      size: size,
      baseY: height * 0.88,
      amplitude: 28,
      wavelength: width * 1.1,
      phaseOffset: phase * 1.0,
      colors: isDark
          ? [
              const Color(0xFF154441).withValues(alpha: 0.30),
              const Color(0xFF16323B).withValues(alpha: 0.18),
            ]
          : [
              const Color(0xFF5AB6AA).withValues(alpha: 0.16),
              const Color(0xFF6FAEDB).withValues(alpha: 0.10),
            ],
    );

    // Mid Wave 2 (Flowing counter wave)
    _drawSineWave(
      canvas: canvas,
      size: size,
      baseY: height * 0.92,
      amplitude: 22,
      wavelength: width * 0.85,
      phaseOffset: -phase * 1.35 + math.pi / 3,
      colors: isDark
          ? [
              const Color(0xFF1C4258).withValues(alpha: 0.28),
              const Color(0xFF1A2B42).withValues(alpha: 0.16),
            ]
          : [
              const Color(0xFF61A8DD).withValues(alpha: 0.15),
              const Color(0xFF8672C7).withValues(alpha: 0.09),
            ],
    );

    // Front Wave 3 (Delicate ripple wave)
    _drawSineWave(
      canvas: canvas,
      size: size,
      baseY: height * 0.95,
      amplitude: 16,
      wavelength: width * 0.65,
      phaseOffset: phase * 1.8 + math.pi / 2,
      colors: isDark
          ? [
              const Color(0xFF225B54).withValues(alpha: 0.32),
              const Color(0xFF1B3D3B).withValues(alpha: 0.20),
            ]
          : [
              const Color(0xFF38A395).withValues(alpha: 0.18),
              const Color(0xFF4FA0DE).withValues(alpha: 0.12),
            ],
    );

    // 3. Subtle floating particles / cyber security sparkles
    _drawFloatingParticles(canvas, size, phase);
  }

  void _drawGlowingOrb(Canvas canvas, Offset center, double radius, Color color) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color, color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  void _drawSineWave({
    required Canvas canvas,
    required Size size,
    required double baseY,
    required double amplitude,
    required double wavelength,
    required double phaseOffset,
    required List<Color> colors,
  }) {
    final path = Path();
    path.moveTo(0, size.height);
    path.lineTo(0, baseY);

    const step = 8.0;
    for (double x = 0; x <= size.width + step; x += step) {
      final y = baseY +
          math.sin((x / wavelength) * 2 * math.pi + phaseOffset) * amplitude +
          math.cos((x / (wavelength * 0.5)) * 2 * math.pi + phaseOffset * 0.5) * (amplitude * 0.25);
      path.lineTo(x, y);
    }

    path.lineTo(size.width, size.height);
    path.close();

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
      ).createShader(Rect.fromLTWH(0, baseY - amplitude, size.width, size.height - (baseY - amplitude)));

    canvas.drawPath(path, paint);
  }

  void _drawFloatingParticles(Canvas canvas, Size size, double phase) {
    final paint = Paint()..style = PaintingStyle.fill;
    const particleCount = 7;
    for (var i = 0; i < particleCount; i++) {
      final seed = i * 1.618;
      final speed = 0.5 + (i % 3) * 0.3;
      final x = (size.width * (0.15 + (i * 0.12) % 0.8) + math.sin(phase * speed + seed) * 18) % size.width;
      final y = (size.height * (0.3 + (i * 0.11) % 0.6) - ((progress * speed + (i * 0.2)) % 1.0) * size.height * 0.5) % size.height;
      final radius = 2.0 + (i % 3) * 1.5;
      final alpha = (0.2 + math.sin(phase * 2 + seed).abs() * 0.3).clamp(0.0, 0.5);

      paint.color = (isDark ? const Color(0xFF6AE3D5) : const Color(0xFF28857B)).withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavyLivePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.isDark != isDark ||
      oldDelegate.primaryColor != primaryColor;
}
