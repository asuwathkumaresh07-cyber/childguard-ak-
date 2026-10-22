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
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final primaryColor = widget.waveColor ?? theme.colorScheme.primary;
    final secondaryColor = theme.colorScheme.secondary;

    // Detect whether Red is dominant (Parent App) or Blue is dominant (Child App)
    final isRedDominant = (primaryColor.r * 255).round() > (primaryColor.b * 255).round();

    return Stack(
      fit: StackFit.expand,
      children: [
        // Base ambient gradient (White, Blue, and Neon Red palette)
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isRedDominant
                  ? const [
                      Color(0xFFFFFFFF),
                      Color(0xFFFCFDFE),
                      Color(0xFFFFF4F6),
                      Color(0xFFF2F6FE),
                    ]
                  : (dark
                      ? const [
                          Color(0xFF070E1A),
                          Color(0xFF0A1528),
                          Color(0xFF0D1B34),
                          Color(0xFF060B14),
                        ]
                      : const [
                          Color(0xFFFFFFFF),
                          Color(0xFFF3F7FE),
                          Color(0xFFEBF3FD),
                          Color(0xFFFFF5F7),
                        ]),
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
                    secondaryColor: secondaryColor,
                    isRedDominant: isRedDominant,
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
    required this.secondaryColor,
    required this.isRedDominant,
  });

  final double progress;
  final bool isDark;
  final Color primaryColor;
  final Color secondaryColor;
  final bool isRedDominant;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final width = size.width;
    final height = size.height;
    final phase = progress * math.pi * 2;

    const neonRed = Color(0xFFFF1744);
    const cyberBlue = Color(0xFF0066FF);

    if (isRedDominant) {
      // ========================================================
      // PARENT APP: White, Blue, and Neon Red (RED DOMINANT)
      // ========================================================
      // 1. Glowing ambient orbs (Neon Red dominant + Cyber Blue accents)
      _drawGlowingOrb(
        canvas,
        Offset(-20 + math.sin(phase) * 35, height * 0.18 + math.cos(phase) * 30),
        150,
        neonRed.withValues(alpha: 0.20),
      );
      _drawGlowingOrb(
        canvas,
        Offset(width + 20 + math.cos(phase * 0.7) * 40, height * 0.45 + math.sin(phase * 0.7) * 35),
        160,
        cyberBlue.withValues(alpha: 0.16),
      );
      _drawGlowingOrb(
        canvas,
        Offset(width * 0.35 + math.sin(phase * 0.5) * 30, height * 0.78 + math.cos(phase * 0.5) * 25),
        130,
        const Color(0xFFFF3D71).withValues(alpha: 0.14),
      );

      // 2. 3 Flowing Sinusoidal Waves
      // Bottom Wave 1: Dominant Neon Red wave
      _drawSineWave(
        canvas: canvas,
        size: size,
        baseY: height * 0.88,
        amplitude: 28,
        wavelength: width * 1.1,
        phaseOffset: phase * 1.0,
        colors: [
          neonRed.withValues(alpha: 0.20),
          const Color(0xFFFF5277).withValues(alpha: 0.08),
        ],
      );

      // Mid Wave 2: Cyber Blue counter wave
      _drawSineWave(
        canvas: canvas,
        size: size,
        baseY: height * 0.92,
        amplitude: 22,
        wavelength: width * 0.85,
        phaseOffset: -phase * 1.35 + math.pi / 3,
        colors: [
          cyberBlue.withValues(alpha: 0.15),
          const Color(0xFF40C4FF).withValues(alpha: 0.06),
        ],
      );

      // Front Wave 3: Intense Neon Red ripple wave
      _drawSineWave(
        canvas: canvas,
        size: size,
        baseY: height * 0.95,
        amplitude: 16,
        wavelength: width * 0.65,
        phaseOffset: phase * 1.8 + math.pi / 2,
        colors: [
          neonRed.withValues(alpha: 0.24),
          const Color(0xFFFF3D71).withValues(alpha: 0.10),
        ],
      );
    } else {
      // ========================================================
      // CHILD APP: Blue, White, and Neon Red (BLUE DOMINANT)
      // ========================================================
      // 1. Glowing ambient orbs (Cyber Blue dominant + Neon Red accents)
      _drawGlowingOrb(
        canvas,
        Offset(-20 + math.sin(phase) * 35, height * 0.18 + math.cos(phase) * 30),
        150,
        cyberBlue.withValues(alpha: isDark ? 0.30 : 0.22),
      );
      _drawGlowingOrb(
        canvas,
        Offset(width + 20 + math.cos(phase * 0.7) * 40, height * 0.45 + math.sin(phase * 0.7) * 35),
        160,
        neonRed.withValues(alpha: isDark ? 0.22 : 0.15),
      );
      _drawGlowingOrb(
        canvas,
        Offset(width * 0.35 + math.sin(phase * 0.5) * 30, height * 0.78 + math.cos(phase * 0.5) * 25),
        130,
        const Color(0xFF00B0FF).withValues(alpha: isDark ? 0.26 : 0.16),
      );

      // 2. 3 Flowing Sinusoidal Waves
      // Bottom Wave 1: Dominant Cyber Blue wave
      _drawSineWave(
        canvas: canvas,
        size: size,
        baseY: height * 0.88,
        amplitude: 28,
        wavelength: width * 1.1,
        phaseOffset: phase * 1.0,
        colors: [
          cyberBlue.withValues(alpha: isDark ? 0.32 : 0.22),
          const Color(0xFF00B0FF).withValues(alpha: isDark ? 0.18 : 0.10),
        ],
      );

      // Mid Wave 2: Neon Red accent counter wave
      _drawSineWave(
        canvas: canvas,
        size: size,
        baseY: height * 0.92,
        amplitude: 22,
        wavelength: width * 0.85,
        phaseOffset: -phase * 1.35 + math.pi / 3,
        colors: [
          neonRed.withValues(alpha: isDark ? 0.20 : 0.14),
          const Color(0xFFFF5277).withValues(alpha: isDark ? 0.10 : 0.06),
        ],
      );

      // Front Wave 3: Electric Blue ripple wave
      _drawSineWave(
        canvas: canvas,
        size: size,
        baseY: height * 0.95,
        amplitude: 16,
        wavelength: width * 0.65,
        phaseOffset: phase * 1.8 + math.pi / 2,
        colors: [
          const Color(0xFF0052CC).withValues(alpha: isDark ? 0.34 : 0.24),
          cyberBlue.withValues(alpha: isDark ? 0.20 : 0.12),
        ],
      );
    }

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
      final alpha = (0.25 + math.sin(phase * 2 + seed).abs() * 0.35).clamp(0.0, 0.6);

      // Alternating Neon Red & Cyber Blue particles
      final color = (i % 2 == 0)
          ? (isRedDominant ? const Color(0xFFFF1744) : const Color(0xFF0066FF))
          : (isRedDominant ? const Color(0xFF0066FF) : const Color(0xFFFF1744));
      paint.color = color.withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavyLivePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.isDark != isDark ||
      oldDelegate.primaryColor != primaryColor ||
      oldDelegate.secondaryColor != secondaryColor ||
      oldDelegate.isRedDominant != isRedDominant;
}
