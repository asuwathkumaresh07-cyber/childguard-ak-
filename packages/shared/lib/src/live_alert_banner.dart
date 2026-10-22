import 'dart:async';
import 'package:flutter/material.dart';

import 'animated_alert_triangle.dart';

/// Interactive live notification banner featuring an animated moving red triangle.
class LiveAlertBanner extends StatelessWidget {
  const LiveAlertBanner({
    super.key,
    required this.title,
    required this.message,
    this.childName,
    this.timestamp,
    this.onView,
    this.onDismiss,
  });

  final String title;
  final String message;
  final String? childName;
  final DateTime? timestamp;
  final VoidCallback? onView;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2B1A1E) : const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE53935).withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE53935).withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Moving red triangle alert with live animation
              const AnimatedAlertTriangle(
                size: 38,
                showPulseRings: true,
              ),
              const SizedBox(width: 8),

              // Alert text content
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: isDark ? const Color(0xFFFF8A80) : const Color(0xFFC62828),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (childName != null && childName!.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE53935).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              childName!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFD32F2F),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.white70 : const Color(0xFF4A1E22),
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Action buttons
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onView != null)
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: const Color(0xFFE53935),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: onView,
                      child: const Text('Review', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  if (onDismiss != null)
                    GestureDetector(
                      onTap: onDismiss,
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Icon(
                          Icons.close,
                          size: 18,
                          color: isDark ? Colors.white60 : Colors.black45,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper to trigger a live floating alert toast with animated moving red triangle.
void showLiveAlertBanner({
  required BuildContext context,
  required String title,
  required String message,
  String? childName,
  VoidCallback? onView,
  Duration duration = const Duration(seconds: 8),
}) {
  final overlayState = Overlay.maybeOf(context);
  if (overlayState == null) return;

  late OverlayEntry entry;
  Timer? autoDismissTimer;

  void dismiss() {
    autoDismissTimer?.cancel();
    if (entry.mounted) {
      entry.remove();
    }
  }

  entry = OverlayEntry(
    builder: (context) => Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 0,
      right: 0,
      child: Material(
        color: Colors.transparent,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: -50.0, end: 0.0),
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutBack,
          builder: (context, offsetY, child) {
            return Transform.translate(
              offset: Offset(0, offsetY),
              child: child,
            );
          },
          child: LiveAlertBanner(
            title: title,
            message: message,
            childName: childName,
            onView: onView == null
                ? null
                : () {
                    dismiss();
                    onView();
                  },
            onDismiss: dismiss,
          ),
        ),
      ),
    ),
  );

  overlayState.insert(entry);
  autoDismissTimer = Timer(duration, dismiss);
}
