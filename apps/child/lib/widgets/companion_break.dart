import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

class CompanionBreakDialog extends StatefulWidget {
  const CompanionBreakDialog({super.key, this.hindi = false});
  final bool hindi;
  @override
  State<CompanionBreakDialog> createState() => _CompanionBreakDialogState();
}

class _CompanionBreakDialogState extends State<CompanionBreakDialog> {
  Timer? _timer;
  int _elapsed = 0;
  bool _started = false;
  String _text(String english, String hindi) => widget.hindi ? hindi : english;

  void _start() {
    if (_started) return;
    setState(() {
      _started = true;
      _elapsed = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _elapsed++);
      if (_elapsed >= 30) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final complete = _elapsed >= 30;
    final inhale = _elapsed % 8 < 4;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final grow = !reduced && _started && !complete && inhale;
    return AlertDialog(
      title: Text(_text('A little breathing break', 'थोड़ा साँस का विराम')),
      content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
            _text(
                'Breathe gently at your own pace. You can stop whenever you like.',
                'अपनी गति से धीरे साँस लें। जब चाहें रुक सकते हैं।'),
            textAlign: TextAlign.center),
        const SizedBox(height: 20),
        AnimatedContainer(
            duration: reduced ? Duration.zero : const Duration(seconds: 3),
            width: grow ? 100 : 82,
            height: grow ? 100 : 82,
            decoration: const BoxDecoration(
                color: AppPalette.paleBlue, shape: BoxShape.circle),
            child: Icon(complete ? Icons.check_rounded : Icons.air_rounded,
                color: AppPalette.blue, size: 38)),
        const SizedBox(height: 16),
        Text(
            complete
                ? _text('All done. Nice and easy.', 'पूरा हुआ। बहुत अच्छा।')
                : !_started
                    ? _text('30 seconds, just for you', 'आपके लिए 30 सेकंड')
                    : _text(inhale ? 'Breathe in' : 'Breathe out',
                        inhale ? 'साँस लें' : 'साँस छोड़ें'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        if (_started && !complete) Text('${30 - _elapsed}s'),
      ])),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_text(
                complete ? 'Done' : 'Close', complete ? 'पूरा' : 'बंद करें'))),
        if (!_started)
          FilledButton(
              onPressed: _start, child: Text(_text('Start', 'शुरू करें')))
      ],
    );
  }
}
