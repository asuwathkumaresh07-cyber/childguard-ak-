import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared/shared.dart';

class ParentPushService {
  static bool _initialized = false;
  static StreamSubscription<String>? _tokenSubscription;
  static String? _registeredToken;

  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _senderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');

  static bool get isConfigured =>
      _apiKey.isNotEmpty &&
      _appId.isNotEmpty &&
      _projectId.isNotEmpty &&
      _senderId.isNotEmpty;
  static bool get isInitialized => _initialized;

  static Future<void> initialize() async {
    if (_initialized || !isConfigured) return;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: _apiKey,
          appId: _appId,
          projectId: _projectId,
          messagingSenderId: _senderId,
        ),
      );
      _initialized = true;
    } catch (error, stackTrace) {
      debugPrint('Could not initialize parent push notifications: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<bool> registerCurrentParent() async {
    if (!_initialized) return false;

    final permission = await FirebaseMessaging.instance.requestPermission();
    if (permission.authorizationStatus == AuthorizationStatus.denied) {
      return false;
    }

    await _tokenSubscription?.cancel();
    final registered = Completer<void>();
    _tokenSubscription = FirebaseMessaging.instance.onRegistered.listen(
      (token) {
        if (registered.isCompleted) {
          unawaited(_registerToken(token));
        } else {
          unawaited(_registerInitialToken(token, registered));
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!registered.isCompleted) {
          registered.completeError(error, stackTrace);
        }
      },
    );
    try {
      await FirebaseMessaging.instance.register();
      await registered.future.timeout(const Duration(seconds: 30));
      return true;
    } catch (_) {
      await _tokenSubscription?.cancel();
      _tokenSubscription = null;
      rethrow;
    }
  }

  static Future<void> unregisterCurrentParent() async {
    if (!_initialized) return;
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;
    await FirebaseMessaging.instance.unregister();
    final token = _registeredToken;
    _registeredToken = null;
    if (token != null && token.isNotEmpty) {
      await SupabaseService.instance.removeParentPushToken(token);
    }
  }

  static Future<void> _registerInitialToken(
    String token,
    Completer<void> registered,
  ) async {
    try {
      await SupabaseService.instance.registerParentPushToken(token);
      _registeredToken = token;
      registered.complete();
    } catch (error, stackTrace) {
      registered.completeError(error, stackTrace);
    }
  }

  static Future<void> _registerToken(String token) async {
    try {
      await SupabaseService.instance.registerParentPushToken(token);
      _registeredToken = token;
    } catch (error, stackTrace) {
      debugPrint('Could not refresh the parent push token: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
