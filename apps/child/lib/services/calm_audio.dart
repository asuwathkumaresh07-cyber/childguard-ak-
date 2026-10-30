import 'package:flutter/services.dart';

/// A tiny platform-backed ambient tone used during the breathing break.
/// Unsupported platforms simply keep the visual breathing exercise working.
class CalmAudio {
  static const _channel = MethodChannel('com.familyguard.child/calm_audio');

  static Future<void> start({String preset = 'meadow'}) async {
    try {
      await _channel.invokeMethod<void>('start', {'preset': preset});
    } on MissingPluginException {
      // The widget is also used by desktop/web tests where no native player
      // exists.
    } on PlatformException {
      // Audio is optional; never block the breathing exercise.
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Optional platform feature.
    } on PlatformException {
      // Optional platform feature.
    }
  }
}
