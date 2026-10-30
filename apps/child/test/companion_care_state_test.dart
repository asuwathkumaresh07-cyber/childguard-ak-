import 'package:child/widgets/companion_care_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 10, 23, 10);
  test('due reminders use active time, prioritize water, and space prompts',
      () {
    final care = CompanionCareState(start);
    care.advance(
        const Duration(minutes: 19), start.add(const Duration(minutes: 19)));
    expect(care.due(start.add(const Duration(minutes: 19))), isNull);
    care.advance(
        const Duration(minutes: 11), start.add(const Duration(minutes: 30)));
    final now = start.add(const Duration(minutes: 30));
    expect(care.due(now), CareReminder.water);
    care.prompted(CareReminder.water, now);
    care.complete(CareReminder.water, now);
    expect(care.waterBreaks, 1);
    expect(care.due(now.add(const Duration(minutes: 2))), isNull);
    expect(care.due(now.add(const Duration(minutes: 3))), CareReminder.eyes);
  });
  test('snoozing preserves the need without repeated immediate prompts', () {
    final care = CompanionCareState(start)
      ..eyesEnabled = false
      ..checkInEnabled = false;
    care.advance(const Duration(minutes: 30), start);
    care.snooze(CareReminder.water, start);
    expect(care.due(start.add(const Duration(minutes: 4))), isNull);
    expect(care.due(start.add(const Duration(minutes: 5))), CareReminder.water);
    expect(care.waterBreaks, 0);
  });
  test('stored progress, settings, and snoozes survive restart', () {
    final care = CompanionCareState(start)
      ..waterMinutes = 15
      ..eyesEnabled = false;
    care.advance(const Duration(minutes: 15), start);
    care.snooze(CareReminder.water, start);
    final restored = CompanionCareState.decode(care.encode(), start);
    expect(restored.waterMinutes, 15);
    expect(restored.eyesEnabled, isFalse);
    expect(restored.waterSeconds, 900);
    expect(restored.due(start), isNull);
    expect(restored.due(start.add(const Duration(minutes: 5))),
        CareReminder.water);
  });
  test('daily counts reset without creating a false water completion', () {
    final care = CompanionCareState(start);
    care.complete(CareReminder.water, start);
    care.complete(CareReminder.eyes, start);
    care.advance(Duration.zero, start.add(const Duration(days: 1)));
    expect(care.waterBreaks, 0);
    expect(care.eyeBreaks, 0);
    expect(care.checkInSeconds, 0);
  });
  test('unavailable or disabled check-ins do not prompt', () {
    final care = CompanionCareState(start)
      ..waterEnabled = false
      ..eyesEnabled = false;
    care.advance(const Duration(hours: 1), start);
    expect(care.due(start, canCheckIn: false), isNull);
    care.checkInEnabled = false;
    expect(care.due(start), isNull);
  });
  test('invalid saved data safely uses default reminder settings', () {
    final care = CompanionCareState.decode('not json', start);
    expect(care.waterMinutes, 30);
    expect(care.waterBreaks, 0);
  });
}
