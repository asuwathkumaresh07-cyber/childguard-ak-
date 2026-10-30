import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

ExtraTimeRequest reward(DateTime now,
        {String? resolver = 'parent',
        String status = 'approved',
        int ageMinutes = 0}) =>
    ExtraTimeRequest(
        id: 'reward',
        familyId: 'family',
        childId: 'child',
        packageName: 'books',
        appLabel: 'Books',
        requestedMinutes: 15,
        grantedMinutes: 15,
        status: status,
        requestedAt: now.subtract(const Duration(minutes: 20)),
        resolvedAt: now.subtract(Duration(minutes: ageMinutes)),
        resolvedBy: resolver);
AppUsageLog log(String id, String app, DateTime start, int minutes) =>
    AppUsageLog(
        id: id,
        familyId: 'family',
        childId: 'child',
        packageName: app.toLowerCase(),
        appLabel: app,
        startedAt: start,
        durationSeconds: minutes * 60);

void main() {
  final now = DateTime(2026, 10, 24, 12);
  test(
      'time rewards require the family parent; legacy automatic and pending rewards are ignored',
      () {
    for (final request in [
      reward(now, resolver: null),
      reward(now, resolver: 'child'),
      reward(now, status: 'pending')
    ]) {
      expect(parentApprovedExtraSeconds([request], 'parent', now), isEmpty);
      expect(parentApprovedAppAccess([request], 'parent', now), isEmpty);
    }
    expect(parentApprovedExtraSeconds([reward(now)], 'parent', now),
        {'books': 900});
    expect(parentApprovedAppAccess([reward(now)], 'parent', now), {'books'});
    expect(
        parentApprovedAppAccess([reward(now, ageMinutes: 16)], 'parent', now),
        isEmpty);
    expect(
        parentApprovedExtraSeconds(
            [reward(now, ageMinutes: 24 * 60)], 'parent', now),
        isEmpty);
  });
  test('usage splits at midnight and merges duplicate/overlapping sessions',
      () {
    final day = DateTime(2026, 10, 24);
    final result = UsageBreakdown.between([
      log('midnight', 'Books', day.subtract(const Duration(minutes: 30)), 60),
      log('duplicate', 'Books', day, 30),
      log('math', 'Math', day.add(const Duration(minutes: 20)), 40),
    ], day, day.add(const Duration(days: 1)));
    expect(result.totalSeconds, 3600);
    expect(result.apps.first.label, 'Math');
    expect(result.apps.first.seconds, 2400);
    expect(result.apps.last.seconds, 1800);
  });
  testWidgets(
      'tapping Today opens total time, per-app times, and session details',
      (tester) async {
    final date = DateTime.now();
    final today = DateTime(date.year, date.month, date.day);
    await tester.pumpWidget(MaterialApp(
        theme: AppPalette.theme(),
        home: Scaffold(
            body: SingleChildScrollView(
                child: DualUsageChart(logs: [
          log('one', 'Books', today.add(const Duration(hours: 9)), 60),
          log('two', 'Math', today.add(const Duration(hours: 11)), 30)
        ])))));
    await tester.tap(find.byKey(const ValueKey('usage-day-6')));
    await tester.pumpAndSettle();
    expect(find.text('1h 30m total recorded screen time'), findsNWidgets(2));
    expect(find.text('Books'), findsNWidgets(2));
    await tester.tap(find.text('Books').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('9:00 AM – 10:00 AM'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
