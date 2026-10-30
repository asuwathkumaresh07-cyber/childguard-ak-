import 'dart:async';

import 'package:flutter/material.dart';

/// A simple focus timer for homework, reading, or another calm activity.
class FocusTimerDialog extends StatefulWidget {
  const FocusTimerDialog({super.key, this.onCompleted});
  final VoidCallback? onCompleted;

  @override
  State<FocusTimerDialog> createState() => _FocusTimerDialogState();
}

class _FocusTimerDialogState extends State<FocusTimerDialog>
    with WidgetsBindingObserver {
  Timer? _timer;
  int _minutes = 10;
  int _remaining = 0;
  bool _finished = false;
  bool _active = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
  }

  bool get _running => _remaining > 0;

  void _start() {
    _timer?.cancel();
    setState(() {
      _remaining = _minutes * 60;
      _finished = false;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      if (!_active) return;
      if (_remaining <= 1) {
        timer.cancel();
        setState(() {
          _remaining = 0;
          _finished = true;
        });
        widget.onCompleted?.call();
      } else {
        setState(() => _remaining--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _remaining ~/ 60;
    final seconds = _remaining % 60;
    return AlertDialog(
      title: const Text('Focus timer'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_running ? Icons.timer_outlined : Icons.task_alt_outlined,
              size: 48, color: Colors.teal.shade700),
          const SizedBox(height: 12),
          Text(_running
              ? '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'
              : _finished
                  ? 'Well done! Your focus session is complete.'
                  : 'Pick a short, calm block for homework or reading.'),
          const SizedBox(height: 12),
          if (!_running)
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 5, label: Text('5 min')),
                ButtonSegment(value: 10, label: Text('10 min')),
                ButtonSegment(value: 15, label: Text('15 min')),
              ],
              selected: {_minutes},
              onSelectionChanged: (value) =>
                  setState(() => _minutes = value.first),
            ),
          if (!_running) ...[
            const SizedBox(height: 10),
            const Text('When the timer ends, take a sip of water and stretch.'),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_running ? 'Close' : 'Skip')),
        if (!_running)
          FilledButton(onPressed: _start, child: const Text('Start timer')),
      ],
    );
  }
}
