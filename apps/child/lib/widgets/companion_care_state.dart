import 'dart:convert';

enum CareReminder { water, checkIn, eyes }

/// Counts foreground use, so sleeping or backgrounding the app adds no time.
class CompanionCareState {
  static const checkInInterval = Duration(hours: 10);
  CompanionCareState(DateTime now) : day = _day(now);
  String day;
  int waterSeconds = 0;
  int checkInSeconds = 0;
  int eyeSeconds = 0;
  int waterBreaks = 0;
  int eyeBreaks = 0;
  int waterMinutes = 30;
  bool waterEnabled = true;
  bool checkInEnabled = true;
  bool eyesEnabled = true;
  DateTime? lastPrompt;
  final Map<CareReminder, DateTime> snoozed = {};
  static String _day(DateTime time) => '${time.year}-${time.month}-${time.day}';
  void advance(Duration elapsed, DateTime now) {
    if (day != _day(now)) {
      day = _day(now);
      waterBreaks = 0;
      eyeBreaks = 0;
    }
    final seconds = elapsed.inSeconds;
    if (seconds <= 0) return;
    waterSeconds += seconds;
    checkInSeconds += seconds;
    eyeSeconds += seconds;
  }

  CareReminder? due(DateTime now, {bool canCheckIn = true}) {
    if (lastPrompt != null &&
        now.difference(lastPrompt!) < const Duration(minutes: 3)) {
      return null;
    }
    final candidates = [
      if (waterEnabled && waterSeconds >= waterMinutes * 60) CareReminder.water,
      if (eyesEnabled && eyeSeconds >= 20 * 60) CareReminder.eyes,
      if (checkInEnabled &&
          canCheckIn &&
          checkInSeconds >= checkInInterval.inSeconds)
        CareReminder.checkIn,
    ];
    for (final kind in candidates) {
      if (snoozed[kind] == null || !now.isBefore(snoozed[kind]!)) return kind;
    }
    return null;
  }

  void prompted(CareReminder kind, DateTime now) {
    lastPrompt = now;
  }

  void snooze(CareReminder kind, DateTime now) {
    snoozed[kind] = now.add(const Duration(minutes: 5));
  }

  void complete(CareReminder kind, DateTime now) {
    advance(Duration.zero, now);
    snoozed.remove(kind);
    switch (kind) {
      case CareReminder.water:
        waterSeconds = 0;
        waterBreaks++;
      case CareReminder.checkIn:
        checkInSeconds = 0;
      case CareReminder.eyes:
        eyeSeconds = 0;
        eyeBreaks++;
    }
  }

  String encode() => jsonEncode({
        'day': day,
        'waterSeconds': waterSeconds,
        'checkInSeconds': checkInSeconds,
        'eyeSeconds': eyeSeconds,
        'waterBreaks': waterBreaks,
        'eyeBreaks': eyeBreaks,
        'waterMinutes': waterMinutes,
        'waterEnabled': waterEnabled,
        'checkInEnabled': checkInEnabled,
        'eyesEnabled': eyesEnabled,
        'lastPrompt': lastPrompt?.toIso8601String(),
        'snoozed': snoozed
            .map((key, value) => MapEntry(key.name, value.toIso8601String())),
      });
  factory CompanionCareState.decode(String? raw, DateTime now) {
    final state = CompanionCareState(now);
    if (raw == null) return state;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      int number(String key) =>
          (data[key] as num?)?.toInt().clamp(0, 31536000) ?? 0;
      state.day = data['day'] as String? ?? state.day;
      state.waterSeconds = number('waterSeconds');
      state.checkInSeconds = number('checkInSeconds');
      state.eyeSeconds = number('eyeSeconds');
      state.waterBreaks = number('waterBreaks');
      state.eyeBreaks = number('eyeBreaks');
      final minutes = number('waterMinutes');
      state.waterMinutes = [15, 30, 60].contains(minutes) ? minutes : 30;
      state.waterEnabled = data['waterEnabled'] as bool? ?? true;
      state.checkInEnabled = data['checkInEnabled'] as bool? ?? true;
      state.eyesEnabled = data['eyesEnabled'] as bool? ?? true;
      state.lastPrompt = DateTime.tryParse(data['lastPrompt'] as String? ?? '');
      final saved = data['snoozed'] as Map<String, dynamic>? ?? {};
      for (final kind in CareReminder.values) {
        final until = DateTime.tryParse(saved[kind.name] as String? ?? '');
        if (until != null) state.snoozed[kind] = until;
      }
      state.advance(Duration.zero, now);
    } catch (_) {
      return CompanionCareState(now);
    }
    return state;
  }
}
