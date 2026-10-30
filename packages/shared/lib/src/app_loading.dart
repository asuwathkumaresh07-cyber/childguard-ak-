import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'app_palette.dart';
import 'live_icon.dart';

/// A floating, layered icon with perspective motion and optional drag-to-tilt.
/// Uses vector artwork and library effects, so it also works offline.
class LoadingIcon3D extends StatefulWidget {
  const LoadingIcon3D(
      {super.key,
      this.icon = Icons.shield_rounded,
      this.size = 96,
      this.interactive = true});
  final IconData icon;
  final double size;
  final bool interactive;

  @override
  State<LoadingIcon3D> createState() => _LoadingIcon3DState();
}

class _LoadingIcon3DState extends State<LoadingIcon3D> {
  Offset _tilt = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final small = widget.size < 40;
    final faceSize = widget.size * .72;
    final radius = BorderRadius.circular(faceSize * .25);
    final dragTransform = Matrix4.identity()
      ..setEntry(3, 2, .0015)
      ..rotateX(-_tilt.dy)
      ..rotateY(_tilt.dx);
    Widget artwork = SizedBox.square(
      dimension: widget.size,
      child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (!small)
              Positioned(
                  bottom: 0,
                  child: Container(
                    width: faceSize * .65,
                    height: widget.size * .07,
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(50),
                        color: AppPalette.blue.withValues(alpha: .08),
                        boxShadow: [
                          BoxShadow(
                              color: AppPalette.blue.withValues(alpha: .12),
                              blurRadius: 14,
                              spreadRadius: 1)
                        ]),
                  )),
            Transform.translate(
                offset: Offset(widget.size * .035, widget.size * .07),
                child: Container(
                  width: faceSize,
                  height: faceSize,
                  decoration: BoxDecoration(
                      color: const Color(0xFF1647B4), borderRadius: radius),
                )),
            Container(
              width: faceSize,
              height: faceSize,
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF7FB1FF),
                      AppPalette.blue,
                      Color(0xFF1B4DC7)
                    ]),
                border: Border.all(
                    color: Colors.white.withValues(alpha: .6),
                    width: small ? .7 : 1.5),
                boxShadow: [
                  BoxShadow(
                      color: AppPalette.blue.withValues(alpha: .18),
                      blurRadius: small ? 2 : 15,
                      offset: Offset(0, small ? 1 : 7))
                ],
              ),
              child: Center(
                  child: LiveIcon(widget.icon,
                      size: faceSize * .53,
                      color: Colors.white,
                      loop: !reduced)),
            ),
          ]),
    );
    if (!reduced) {
      artwork = artwork
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .flipH(
              begin: -.07,
              end: .07,
              perspective: .6,
              duration: 2200.ms,
              curve: Curves.easeInOut)
          .flipV(
              begin: -.035,
              end: .035,
              perspective: .6,
              duration: 2200.ms,
              curve: Curves.easeInOut)
          .moveY(
              begin: small ? -1 : -5,
              end: small ? 1 : 5,
              duration: 2200.ms,
              curve: Curves.easeInOut);
    }
    return RepaintBoundary(
        child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: widget.interactive && !small
          ? (details) => setState(() {
                _tilt = Offset(
                    (_tilt.dx + details.delta.dx / 100).clamp(-.35, .35),
                    (_tilt.dy + details.delta.dy / 100).clamp(-.35, .35));
              })
          : null,
      onPanEnd: widget.interactive && !small
          ? (_) => setState(() => _tilt = Offset.zero)
          : null,
      onPanCancel: widget.interactive && !small
          ? () => setState(() => _tilt = Offset.zero)
          : null,
      child: AnimatedContainer(
        duration: reduced ? Duration.zero : const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transformAlignment: Alignment.center,
        transform: dragTransform,
        child: artwork,
      ),
    ));
  }
}

/// Screen loading state. Shown only while the caller's real operation is pending.
class AppLoadingView extends StatelessWidget {
  const AppLoadingView(
      {super.key,
      this.message = 'Loading…',
      this.detail,
      this.icon = Icons.shield_rounded});
  final String message;
  final String? detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) => ColoredBox(
      color: Colors.white,
      child: Semantics(
        label: message,
        liveRegion: true,
        child: Center(
            child: SingleChildScrollView(
                child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ExcludeSemantics(child: LoadingIcon3D(icon: icon)),
            const SizedBox(height: 22),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700, color: AppPalette.navy)),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(detail!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF52647D))),
            ],
            const SizedBox(height: 16),
            const ExcludeSemantics(child: _LoadingDots()),
          ]),
        ))),
      ));
}

/// Compact version for sign-in, approval, and connection buttons.
class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator(
      {super.key,
      this.size = 24,
      this.label = 'Loading',
      this.icon = Icons.shield_rounded});
  final double size;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Semantics(
      label: label,
      liveRegion: true,
      child: ExcludeSemantics(
          child: LoadingIcon3D(size: size, icon: icon, interactive: false)));
}

class _LoadingDots extends StatelessWidget {
  const _LoadingDots();

  @override
  Widget build(BuildContext context) => Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        Widget dot = Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: const BoxDecoration(
                color: AppPalette.blue, shape: BoxShape.circle));
        if (!MediaQuery.disableAnimationsOf(context)) {
          dot = dot
              .animate(
                  delay: Duration(milliseconds: index * 160),
                  onPlay: (controller) => controller.repeat(reverse: true))
              .fade(begin: .25, end: 1, duration: 650.ms);
        }
        return dot;
      }));
}
