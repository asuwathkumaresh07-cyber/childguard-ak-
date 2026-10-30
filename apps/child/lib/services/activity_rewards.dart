import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BuddyActivity { quiz, breathing, focus, water, checkIn }

class ActivityProgress {
  ActivityProgress(
      {this.earned = 0,
      this.spent = 0,
      this.activeReward,
      Map<String, int>? daily,
      Set<String>? unlocked})
      : daily = daily ?? {},
        unlocked = unlocked ?? {};
  int earned;
  int spent;
  String? activeReward;
  final Map<String, int> daily;
  final Set<String> unlocked;
  int get balance => earned - spent;
  int pointsToday(DateTime now) =>
      daily['${now.year}-${now.month}-${now.day}/points'] ?? 0;
  static const rewards = {'star': 30, 'rainbow': 60, 'champion': 100};
  static const rewardLabels = {
    'star': 'Star buddy badge',
    'rainbow': 'Rainbow buddy theme',
    'champion': 'Champion crown',
  };
}

/// Device-local encouragement points. These never grant protection bypasses or
/// mix with parent-approved task rewards. Daily limits prevent repeated taps
/// and replaying one activity from farming points.
class ActivityRewards {
  static final changed = ValueNotifier<int>(0);
  static Future<void> _queue = Future.value();
  static String _key(String childId) => 'buddy_activity_rewards_v1_$childId';
  static Future<ActivityProgress> load(String childId) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_key(childId));
      if (raw == null) return ActivityProgress();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return ActivityProgress(
        earned: (data['earned'] as num).toInt(),
        spent: (data['spent'] as num).toInt(),
        activeReward: data['activeReward'] as String?,
        daily: Map<String, int>.from(data['daily'] as Map),
        unlocked: Set<String>.from(data['unlocked'] as List),
      );
    } catch (_) {
      return ActivityProgress();
    }
  }

  static Future<void> _save(String childId, ActivityProgress state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key(childId),
        jsonEncode({
          'earned': state.earned,
          'spent': state.spent,
          'activeReward': state.activeReward,
          'daily': state.daily,
          'unlocked': state.unlocked.toList(),
        }));
    changed.value++;
  }

  static Future<T> _serial<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static Future<int> record(String childId, BuddyActivity activity,
          {int correctAnswers = 0, DateTime? now}) =>
      _serial(() async {
        final state = await load(childId);
        final date = now ?? DateTime.now();
        final day = '${date.year}-${date.month}-${date.day}';
        final key = '$day/${activity.name}';
        final cap = activity == BuddyActivity.water ? 4 : 1;
        if ((state.daily[key] ?? 0) >= cap) return 0;
        final points = switch (activity) {
          BuddyActivity.quiz => correctAnswers.clamp(0, 5) * 2,
          BuddyActivity.breathing => 5,
          BuddyActivity.focus => 10,
          BuddyActivity.water => 2,
          BuddyActivity.checkIn => 5,
        };
        if (points == 0) return 0;
        state.daily[key] = (state.daily[key] ?? 0) + 1;
        final scoreKey = '$day/points';
        state.daily[scoreKey] = (state.daily[scoreKey] ?? 0) + points;
        state.earned += points;
        await _save(childId, state);
        return points;
      });

  static Future<bool> redeem(String childId, String reward) =>
      _serial(() async {
        final cost = ActivityProgress.rewards[reward];
        if (cost == null) return false;
        final state = await load(childId);
        if (!state.unlocked.contains(reward)) {
          if (state.balance < cost) return false;
          state.spent += cost;
          state.unlocked.add(reward);
        }
        state.activeReward = reward;
        await _save(childId, state);
        return true;
      });
}
