import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared/shared.dart';
import 'companion_care_state.dart';
import 'floating_pet.dart';
import '../services/activity_rewards.dart';

class CompanionCare extends StatefulWidget {
  const CompanionCare(
      {super.key,
      required this.child,
      this.childId,
      this.enabled = true,
      required this.vpnEnabled,
      required this.permissionsReady,
      this.pendingTasks = 0,
      this.latestCheckInAt,
      this.onCheckIn,
      required this.onProtection,
      required this.onTasks,
      this.now = DateTime.now});
  final Widget child;
  final String? childId;
  final bool enabled;
  final bool vpnEnabled;
  final bool permissionsReady;
  final int pendingTasks;
  final DateTime? latestCheckInAt;
  final Future<bool> Function()? onCheckIn;
  final VoidCallback onProtection;
  final VoidCallback onTasks;
  final DateTime Function() now;
  @override
  State<CompanionCare> createState() => _CompanionCareState();
}

class _CompanionCareState extends State<CompanionCare>
    with WidgetsBindingObserver {
  CompanionCareState? care;
  CareReminder? reminder;
  Timer? timer;
  DateTime? lastTick;
  bool foreground = true;
  bool busy = false;
  StateSetter? refreshSheet;
  bool _reminderEnabled(CareReminder kind) => switch (kind) {
        CareReminder.water => care?.waterEnabled ?? false,
        CareReminder.checkIn => care?.checkInEnabled ?? false,
        CareReminder.eyes => care?.eyesEnabled ?? false,
      };
  String? praise;
  Timer? praiseTimer;
  String get _key => 'child_companion_care_${widget.childId}';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _load();
    timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
  }

  @override
  void didUpdateWidget(CompanionCare oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId) {
      care = null;
      reminder = null;
      praise = null;
      _load();
    }
    if (oldWidget.enabled != widget.enabled) lastTick = widget.now();
    if (oldWidget.latestCheckInAt != widget.latestCheckInAt &&
        widget.latestCheckInAt != null &&
        care != null) {
      care!.complete(CareReminder.checkIn, widget.now());
      if (reminder == CareReminder.checkIn) reminder = null;
      unawaited(_save());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && care != null) refreshSheet?.call(() {});
    });
  }

  Future<void> _load() async {
    final id = widget.childId;
    if (id == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || id != widget.childId) return;
    setState(() {
      care = CompanionCareState.decode(prefs.getString(_key), widget.now());
      lastTick = widget.now();
      if (widget.latestCheckInAt != null &&
          widget.now().difference(widget.latestCheckInAt!) <
              CompanionCareState.checkInInterval) {
        care!.complete(CareReminder.checkIn, widget.now());
      }
    });
  }

  Future<void> _save() async {
    if (care == null || widget.childId == null) return;
    final key = _key;
    final value = care!.encode();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (foreground) _tick();
    foreground = state == AppLifecycleState.resumed;
    lastTick = widget.now();
    if (!foreground) {
      unawaited(_save());
    }
  }

  void _tick() {
    final now = widget.now();
    final elapsed =
        lastTick == null ? Duration.zero : now.difference(lastTick!);
    lastTick = now;
    if (!mounted || !foreground || !widget.enabled || care == null) return;
    setState(() {
      care!.advance(elapsed, now);
      if (reminder != null && !_reminderEnabled(reminder!)) reminder = null;
      if (reminder == null && !busy) {
        reminder = care!.due(now, canCheckIn: widget.onCheckIn != null);
        if (reminder != null) care!.prompted(reminder!, now);
      }
    });
    refreshSheet?.call(() {});
    unawaited(_save());
  }

  void _snooze(CareReminder kind) {
    if (care == null) return;
    setState(() {
      care!.snooze(kind, widget.now());
      reminder = null;
    });
    unawaited(_save());
  }

  void _complete(CareReminder kind) {
    if (care == null) return;
    if (widget.childId != null && kind != CareReminder.eyes) {
      unawaited(ActivityRewards.record(
          widget.childId!,
          kind == CareReminder.water
              ? BuddyActivity.water
              : BuddyActivity.checkIn));
    }
    setState(() {
      care!.complete(kind, widget.now());
      reminder = null;
      praise = kind == CareReminder.water
          ? 'Nice water break!'
          : kind == CareReminder.eyes
              ? 'Your eyes got a little rest!'
              : 'Thanks for checking in!';
    });
    praiseTimer?.cancel();
    praiseTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => praise = null);
    });
    unawaited(_save());
  }

  Future<void> _act(CareReminder kind) async {
    if (busy) return;
    if (kind == CareReminder.water) {
      _complete(kind);
      return;
    }
    setState(() => busy = true);
    bool complete = false;
    try {
      complete = kind == CareReminder.checkIn
          ? (await widget.onCheckIn?.call() ?? false)
          : (await showDialog<bool>(
                  context: context, builder: (_) => const EyeRestDialog()) ??
              false);
    } finally {
      if (mounted) {
        setState(() => busy = false);
        if (complete) {
          _complete(kind);
        } else {
          _snooze(kind);
        }
      }
    }
  }

  String _title(CareReminder kind) => switch (kind) {
        CareReminder.water => 'Time for a little water break?',
        CareReminder.checkIn => 'How are you feeling?',
        CareReminder.eyes => 'Give your eyes a little rest',
      };
  String _action(CareReminder kind) => switch (kind) {
        CareReminder.water => 'I had some water',
        CareReminder.checkIn => 'Check in',
        CareReminder.eyes => 'Start 20 seconds',
      };
  IconData _icon(CareReminder kind) => switch (kind) {
        CareReminder.water => Icons.water_drop_outlined,
        CareReminder.checkIn => Icons.mood,
        CareReminder.eyes => Icons.visibility_outlined,
      };
  Future<void> _showCare() async {
    if (care == null || busy) return;
    _tick();
    await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        builder: (sheetContext) => StatefulBuilder(builder: (context, refresh) {
              refreshSheet = refresh;
              void update(VoidCallback change) {
                setState(() {
                  change();
                  if (reminder != null && !_reminderEnabled(reminder!)) {
                    reminder = null;
                  }
                });
                refresh(() {});
                unawaited(_save());
              }

              return SafeArea(
                  child: SingleChildScrollView(
                      child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Your buddy is here for you',
                                    style:
                                        Theme.of(context).textTheme.titleLarge),
                                const SizedBox(height: 8),
                                Text(
                                    'Gentle reminders while Family Guard is open. You can skip any reminder.'),
                                const SizedBox(height: 12),
                                ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                        widget.vpnEnabled &&
                                                widget.permissionsReady
                                            ? Icons.verified_outlined
                                            : Icons.shield_outlined,
                                        color: AppPalette.blue),
                                    title: Text(widget.vpnEnabled
                                        ? 'Protection is on'
                                        : 'Protection needs attention'),
                                    subtitle: Text(widget.permissionsReady
                                        ? 'Device permissions are ready. Checked every 30 seconds.'
                                        : 'Some device permissions need attention.'),
                                    trailing: TextButton(
                                        onPressed: () {
                                          Navigator.pop(sheetContext);
                                          widget.onProtection();
                                        },
                                        child: const Text('Review'))),
                                ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading:
                                        const Icon(Icons.checklist_outlined),
                                    title: Text(
                                        '${widget.pendingTasks} task${widget.pendingTasks == 1 ? '' : 's'} waiting'),
                                    trailing: TextButton(
                                        onPressed: () {
                                          Navigator.pop(sheetContext);
                                          widget.onTasks();
                                        },
                                        child: const Text('My tasks'))),
                                const Divider(),
                                Text(
                                    'Today: ${care!.waterBreaks} water break${care!.waterBreaks == 1 ? '' : 's'} and ${care!.eyeBreaks} eye break${care!.eyeBreaks == 1 ? '' : 's'} logged on this device.'),
                                const SizedBox(height: 10),
                                for (final kind in CareReminder.values)
                                  Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: OutlinedButton.icon(
                                          onPressed: kind ==
                                                      CareReminder.checkIn &&
                                                  widget.onCheckIn == null
                                              ? null
                                              : () {
                                                  Navigator.pop(sheetContext);
                                                  unawaited(_act(kind));
                                                },
                                          icon: Icon(_icon(kind)),
                                          label: Text(_action(kind)))),
                                const Divider(),
                                SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Water reminders'),
                                    value: care!.waterEnabled,
                                    onChanged: (value) => update(
                                        () => care!.waterEnabled = value)),
                                Row(children: [
                                  const Expanded(
                                      child: Text('Water reminder interval')),
                                  DropdownButton<int>(
                                      value: care!.waterMinutes,
                                      items: [
                                        for (final minutes in [15, 30, 60])
                                          DropdownMenuItem(
                                              value: minutes,
                                              child: Text('$minutes min'))
                                      ],
                                      onChanged: (value) {
                                        if (value != null) {
                                          update(
                                              () => care!.waterMinutes = value);
                                        }
                                      })
                                ]),
                                SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Feeling check-ins'),
                                    subtitle: const Text(
                                        'Every 10 hours of active time'),
                                    value: care!.checkInEnabled,
                                    onChanged: (value) => update(
                                        () => care!.checkInEnabled = value)),
                                SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Eye-rest reminders'),
                                    subtitle: const Text(
                                        'Every 20 minutes of time in this app'),
                                    value: care!.eyesEnabled,
                                    onChanged: (value) => update(
                                        () => care!.eyesEnabled = value)),
                              ]))));
            }));
    refreshSheet = null;
  }

  @override
  void dispose() {
    timer?.cancel();
    praiseTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FloatingPet(
      childId: widget.enabled ? widget.childId : null,
      message: praise ??
          (reminder != null
              ? _title(reminder!)
              : !widget.vpnEnabled
                  ? 'Let us check protection'
                  : !widget.permissionsReady
                      ? 'One safety step left'
                      : null),
      onTap: () => unawaited(_showCare()),
      child: Stack(children: [
        widget.child,
        if (widget.enabled &&
            widget.childId != null &&
            reminder != null &&
            foreground)
          Positioned(
              left: 12,
              right: 12,
              bottom: 88,
              child: SafeArea(
                  child: Material(
                      color: Colors.white,
                      elevation: 8,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Icon(_icon(reminder!),
                                      color: AppPalette.blue),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Text(_title(reminder!),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700)))
                                ]),
                                const SizedBox(height: 8),
                                Text(reminder == CareReminder.checkIn
                                    ? 'Share how you are doing when you are ready.'
                                    : reminder == CareReminder.water
                                        ? 'Pause and have a few sips if you would like.'
                                        : 'Look away from the screen for a moment.'),
                                const SizedBox(height: 8),
                                Wrap(spacing: 8, children: [
                                  FilledButton(
                                      onPressed: busy
                                          ? null
                                          : () => unawaited(_act(reminder!)),
                                      child: Text(_action(reminder!))),
                                  TextButton(
                                      onPressed: () => _snooze(reminder!),
                                      child: const Text('In 5 minutes'))
                                ]),
                              ]))))),
      ]));
}

class EyeRestDialog extends StatefulWidget {
  const EyeRestDialog({super.key});
  @override
  State<EyeRestDialog> createState() => _EyeRestDialogState();
}

class _EyeRestDialogState extends State<EyeRestDialog>
    with WidgetsBindingObserver {
  int seconds = 20;
  bool active = true;
  late final Timer timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && active && seconds > 0) setState(() => seconds--);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    timer.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          backgroundColor: Colors.white,
          title:
              Text(seconds == 0 ? 'Nice little break!' : 'Look away and relax'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.visibility_outlined,
                size: 48, color: AppPalette.blue),
            const SizedBox(height: 12),
            Text(
                seconds == 0
                    ? 'You can return whenever you are ready.'
                    : 'Let your eyes rest on something away from the screen.\n\n$seconds seconds',
                textAlign: TextAlign.center)
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Maybe later')),
            if (seconds == 0)
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Done'))
          ]);
}
