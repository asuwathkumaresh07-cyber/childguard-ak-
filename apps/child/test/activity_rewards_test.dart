import 'package:child/services/activity_rewards.dart';
import 'package:child/widgets/activity_rewards_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final day = DateTime(2026, 10, 24, 12);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('awards are capped per day and scoped to each child', () async {
    expect(
        await ActivityRewards.record('alice', BuddyActivity.quiz,
            correctAnswers: 5, now: day),
        10);
    expect(
        await ActivityRewards.record('alice', BuddyActivity.quiz,
            correctAnswers: 5, now: day),
        0);
    expect((await ActivityRewards.load('alice')).balance, 10);
    expect((await ActivityRewards.load('bob')).balance, 0);
    expect(
        await ActivityRewards.record('alice', BuddyActivity.quiz,
            correctAnswers: 5, now: day.add(const Duration(days: 1))),
        10);
    expect((await ActivityRewards.load('alice')).pointsToday(day), 10);
  });
  test('concurrent awards cannot exceed daily caps or lose points', () async {
    final awards = await Future.wait(List.generate(8,
        (_) => ActivityRewards.record('alice', BuddyActivity.water, now: day)));
    expect(awards.fold<int>(0, (a, b) => a + b), 8);
    expect((await ActivityRewards.load('alice')).earned, 8);
  });
  test('collectible spends points once and can be equipped again', () async {
    expect(await ActivityRewards.redeem('alice', 'star'), false);
    await ActivityRewards.record('alice', BuddyActivity.quiz,
        correctAnswers: 5, now: day);
    await ActivityRewards.record('alice', BuddyActivity.focus, now: day);
    await ActivityRewards.record('alice', BuddyActivity.breathing, now: day);
    await ActivityRewards.record('alice', BuddyActivity.checkIn, now: day);
    expect(await ActivityRewards.redeem('alice', 'star'), true);
    expect(await ActivityRewards.redeem('alice', 'star'), true);
    final state = await ActivityRewards.load('alice');
    expect(state.balance, 0);
    expect(state.earned, 30);
    expect(state.activeReward, 'star');
    expect(state.unlocked, {'star'});
    expect(await ActivityRewards.redeem('alice', 'rainbow'), false);
  });
  testWidgets(
      'child progress card updates after activity and fits a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.3)),
          child: child!),
      home: const Scaffold(
          body: SingleChildScrollView(
              child: ActivityRewardsCard(childId: 'alice', tasks: []))),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('0 buddy points available'), findsOneWidget);
    await tester.runAsync(() => ActivityRewards.record('alice', BuddyActivity.breathing));
    await tester.pumpAndSettle();
    expect(find.textContaining('5 buddy points available'), findsOneWidget);
    await tester.ensureVisible(find.text('Champion crown'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
