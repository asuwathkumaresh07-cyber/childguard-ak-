import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared/shared.dart';
import '../services/calm_audio.dart';

class CompanionBreakDialog extends StatefulWidget {
  const CompanionBreakDialog({super.key, this.hindi = false, this.onCompleted});
  final bool hindi;
  final VoidCallback? onCompleted;
  @override
  State<CompanionBreakDialog> createState() => _CompanionBreakDialogState();
}

class _CompanionBreakDialogState extends State<CompanionBreakDialog>
    with WidgetsBindingObserver {
  Timer? _timer;
  int _elapsed = 0;
  bool _started = false;
  bool _music = true;
  String _preset = 'meadow';
  bool _active = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (!_active) {
      unawaited(CalmAudio.stop());
    } else if (_started && _elapsed < 30 && _music) {
      unawaited(CalmAudio.start(preset: _preset));
    }
  }

  String _text(String english, String hindi) => widget.hindi ? hindi : english;

  void _start() {
    if (_started) return;
    setState(() {
      _started = true;
      _elapsed = 0;
    });
    if (_music) unawaited(CalmAudio.start(preset: _preset));
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!_active) return;
      setState(() => _elapsed++);
      if (_elapsed >= 30) {
        timer.cancel();
        widget.onCompleted?.call();
        unawaited(CalmAudio.stop());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(CalmAudio.stop());
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
        const SizedBox(height: 10),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Calm music'),
          subtitle: const Text('Choose a soft melody for your break'),
          value: _music,
          onChanged: (value) {
            setState(() => _music = value);
            if (value && _started && !complete) {
              unawaited(CalmAudio.start(preset: _preset));
            } else if (!value) {
              unawaited(CalmAudio.stop());
            }
          },
        ),
        if (_music)
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _preset,
            decoration: const InputDecoration(labelText: 'Soundscape'),
            items: const [
              DropdownMenuItem(value: 'meadow', child: Text('Meadow chimes')),
              DropdownMenuItem(
                  value: 'moonlight', child: Text('Moonlight lullaby')),
              DropdownMenuItem(value: 'ocean', child: Text('Ocean drift')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _preset = value);
              if (_started && !complete && _active) {
                unawaited(CalmAudio.start(preset: value));
              }
            },
          ),
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
