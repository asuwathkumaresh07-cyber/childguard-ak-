import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('category domain lists are non-empty', () {
    expect(CategoryDomainLists.domains[BlockCategory.social], isNotEmpty);
    expect(DemoCredentials.password, '1234');
    expect(DemoCredentials.pairCode, '1234');
  });

  test('normalize via block category labels', () {
    expect(BlockCategory.adult.label, contains('Adult'));
    expect(BlockCategoryX.fromId('social'), BlockCategory.social);
  });

  test('parses one-use parent protection codes', () {
    final code = ProtectionControlCode.fromJson({
      'code': '2A54B87F',
      'requested_action': 'enable',
      'expires_at': '2026-10-16T18:00:00.000Z',
    });

    expect(code.code, '2A54B87F');
    expect(code.requestedAction, 'enable');
    expect(code.expiresAt, DateTime.parse('2026-10-16T18:00:00.000Z'));
  });

  test('parses child device status and tamper events', () {
    final status = ChildDeviceStatus.fromJson({
      'child_id': 'child-id',
      'family_id': 'family-id',
      'vpn_enabled': true,
      'usage_access_enabled': false,
      'accessibility_enabled': true,
      'last_seen_at': '2026-10-16T18:00:00.000Z',
    });
    final event = ChildTamperEvent.fromJson({
      'id': 'event-id',
      'child_id': 'child-id',
      'family_id': 'family-id',
      'event_type': 'usage_access_revoked',
      'occurred_at': '2026-10-16T18:01:00.000Z',
    });

    expect(status.vpnEnabled, isTrue);
    expect(status.usageAccessEnabled, isFalse);
    expect(status.accessibilityEnabled, isTrue);
    expect(event.eventType, 'usage_access_revoked');
  });

  test('parses child location, zone and weekly insight records', () {
    final location = ChildLocation.fromJson({
      'id': 'location-id',
      'family_id': 'family-id',
      'child_id': 'child-id',
      'latitude': 12.5,
      'longitude': 77.6,
      'accuracy_meters': 8,
      'recorded_at': '2026-10-16T18:00:00.000Z',
    });
    final zone = FamilyZone.fromJson({
      'id': 'zone-id',
      'family_id': 'family-id',
      'name': 'School',
      'zone_type': 'school',
      'latitude': 12.5,
      'longitude': 77.6,
      'radius_meters': 250,
    });
    final insight = ChildWeeklyInsight.fromJson({
      'id': 'insight-id',
      'family_id': 'family-id',
      'child_id': 'child-id',
      'week_start': '2026-10-12',
      'summary': 'Good focus this week.',
      'trust_score': 76,
      'mood_alert': true,
      'mood_alert_reason': 'Consider a supportive check-in.',
    });

    expect(location.latitude, 12.5);
    expect(location.accuracyMeters, 8);
    expect(zone.radiusMeters, 250);
    expect(insight.trustScore, 76);
    expect(insight.moodAlert, isTrue);
    expect(insight.moodAlertReason, 'Consider a supportive check-in.');
  });

  test('parses a suggested trade on an extra-time request', () {
    final request = ExtraTimeRequest.fromJson({
      'id': 'request-id',
      'family_id': 'family-id',
      'child_id': 'child-id',
      'package_name': 'com.example.app',
      'app_label': 'Example',
      'requested_minutes': 20,
      'granted_minutes': null,
      'status': 'pending',
      'requested_at': '2026-10-16T18:00:00.000Z',
      'resolved_at': null,
      'resolved_by': null,
      'trade_suggestion': 'Complete a 15-minute task first.',
    });

    expect(request.status, 'pending');
    expect(request.tradeSuggestion, 'Complete a 15-minute task first.');
  });

  test('parses temporary task-reward app unlocks', () {
    final unlock = ChildTemporaryAppUnlock.fromJson({
      'id': 'unlock-id',
      'family_id': 'family-id',
      'child_id': 'child-id',
      'package_name': 'com.example.app',
      'expires_at': '2026-10-16T18:15:00.000Z',
    });

    expect(unlock.packageName, 'com.example.app');
    expect(unlock.expiresAt, DateTime.parse('2026-10-16T18:15:00.000Z'));
  });

  test('parses task submission relation and streak rewards', () {
    final task = ChildTask.fromJson({
      'id': 'task-id',
      'family_id': 'family-id',
      'child_id': 'child-id',
      'title': 'Read for 20 minutes',
      'description': '',
      'due_at': null,
      'points': 10,
      'status': 'submitted',
      'created_at': '2026-10-16T18:00:00.000Z',
      'task_submissions': [
        {'photo_path': 'child-id/task-id/proof.jpg', 'note': 'Finished'},
      ],
    });
    final streak = ChildStreak.fromJson({
      'child_id': 'child-id',
      'family_id': 'family-id',
      'current_streak': 4,
      'best_streak': 6,
      'total_points': 80,
      'bonus_time_minutes': 10,
      'app_unlock_credits': 1,
    });

    expect(task.submissionPhotoPath, 'child-id/task-id/proof.jpg');
    expect(task.submissionNote, 'Finished');
    expect(streak.currentStreak, 4);
    expect(streak.totalPoints, 80);
    expect(streak.bonusTimeMinutes, 10);
    expect(streak.appUnlockCredits, 1);
  });

  test('parses parent-configured trust autonomy settings', () {
    final settings = ChildAutonomySettings.fromJson({
      'child_id': 'child-id',
      'family_id': 'family-id',
      'enabled': true,
      'min_trust_score': 85,
      'daily_extra_minutes_cap': 20,
    });

    expect(settings.enabled, isTrue);
    expect(settings.minTrustScore, 85);
    expect(settings.dailyExtraMinutesCap, 20);
  });

  test('local sign-in reaches auth listeners created by other services',
      () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('family-guard-');
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async => directory.path);
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, null);
      await directory.delete(recursive: true);
    });
    await SupabaseConfig.init();
    await SupabaseConfig.saveCustomConfig(
      'https://example.com',
      'dummy',
    );

    final registration = AuthService();
    await registration.signUp(
      email: 'parent@example.com',
      password: 'password123',
      role: 'parent',
      displayName: 'Parent',
    );
    await registration.signOut();

    final signedIn = Completer<Profile>();
    final subscription = AuthService().authStateChanges.listen((profile) {
      if (profile != null && !signedIn.isCompleted) {
        signedIn.complete(profile);
      }
    });
    addTearDown(subscription.cancel);

    final profile = await AuthService().signIn(
      email: 'parent@example.com',
      password: 'password123',
    );

    expect(await signedIn.future, profile);
  });
}
