import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

class CompanionCheckIn {
  const CompanionCheckIn(
      {required this.mood, this.homework, this.help, this.thoughts = ''});
  final String mood;
  final String? homework;
  final String? help;
  final String thoughts;

  String get note => [
        if (homework != null) 'Homework: $homework',
        if (help != null) 'Help: $help',
        if (thoughts.trim().isNotEmpty) 'My note: ${thoughts.trim()}',
      ].join('\n');
}

class CompanionCheckInDialog extends StatefulWidget {
  const CompanionCheckInDialog({super.key, this.hindi = false});
  final bool hindi;

  @override
  State<CompanionCheckInDialog> createState() => _CompanionCheckInDialogState();
}

class _CompanionCheckInDialogState extends State<CompanionCheckInDialog> {
  final _note = TextEditingController();
  String? _mood;
  String? _homework;
  String? _help;
  String _text(String english, String hindi) => widget.hindi ? hindi : english;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Widget _options(
          {required List<(String, String, IconData)> options,
          required String? selected,
          required ValueChanged<String> onSelect}) =>
      GridView(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: 110 *
                  MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.5)),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: options.map((option) {
            final active = selected == option.$1;
            return Semantics(
                button: true,
                selected: active,
                child: Material(
                  color: active ? AppPalette.paleBlue : Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                          color: active ? AppPalette.blue : AppPalette.border,
                          width: active ? 1.5 : 1)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                      onTap: () => onSelect(option.$1),
                      child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(option.$3,
                                    color: AppPalette.blue, size: 24),
                                const SizedBox(height: 5),
                                Flexible(
                                    child: Text(option.$2,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontWeight: active
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            fontSize: 12))),
                              ]))),
                ));
          }).toList());

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_text('Your buddy’s check-in', 'आपके साथी का चेक-इन')),
        content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                      _text(
                          'Optional. Your parent can see what you choose to share.',
                          'वैकल्पिक। जो आप भेजेंगे, वह माता-पिता देख सकते हैं।'),
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 18),
                  Text(
                      _text(
                          'How are you feeling?', 'आप कैसा महसूस कर रहे हैं?'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  _options(
                      options: [
                        (
                          'great',
                          _text('Great', 'बहुत अच्छा'),
                          Icons.sentiment_very_satisfied
                        ),
                        (
                          'okay',
                          _text('Okay', 'ठीक'),
                          Icons.sentiment_satisfied
                        ),
                        (
                          'low',
                          _text('A little low', 'थोड़ा उदास'),
                          Icons.sentiment_dissatisfied
                        ),
                        (
                          'stressed',
                          _text('Stressed', 'तनाव में'),
                          Icons.sentiment_very_dissatisfied
                        ),
                      ],
                      selected: _mood,
                      onSelect: (value) => setState(() => _mood = value)),
                  const SizedBox(height: 18),
                  Text(_text('How is homework going?', 'पढ़ाई कैसी चल रही है?'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  _options(
                      options: [
                        (
                          'Not started yet',
                          _text('Not started', 'अभी शुरू नहीं'),
                          Icons.pending_actions
                        ),
                        (
                          'Working on it',
                          _text('Working on it', 'कर रहा हूँ'),
                          Icons.edit_note
                        ),
                        ('Done', _text('Done', 'पूरा'), Icons.task_alt),
                        (
                          'No homework today',
                          _text('None today', 'आज नहीं है'),
                          Icons.event_available
                        ),
                      ],
                      selected: _homework,
                      onSelect: (value) => setState(() => _homework = value)),
                  const SizedBox(height: 18),
                  Text(
                      _text(
                          'Would you like some help?', 'क्या आपको मदद चाहिए?'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  _options(
                      options: [
                        (
                          'I am okay',
                          _text('I’m okay', 'मैं ठीक हूँ'),
                          Icons.thumb_up_outlined
                        ),
                        (
                          'Help with homework',
                          _text('Homework help', 'पढ़ाई में मदद'),
                          Icons.school_outlined
                        ),
                        (
                          'I would like to talk',
                          _text('I want to talk', 'बात करनी है'),
                          Icons.chat_bubble_outline
                        ),
                        (
                          'Help with protection',
                          _text('Protection help', 'सुरक्षा में मदद'),
                          Icons.shield_outlined
                        ),
                      ],
                      selected: _help,
                      onSelect: (value) => setState(() => _help = value)),
                  const SizedBox(height: 18),
                  TextField(
                      controller: _note,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 280,
                      decoration: InputDecoration(
                          labelText: _text('Anything else? (optional)',
                              'कुछ और? (वैकल्पिक)'),
                          alignLabelWithHint: true)),
                ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_text('Later', 'बाद में'))),
          FilledButton(
              onPressed: _mood == null
                  ? null
                  : () => Navigator.pop(
                      context,
                      CompanionCheckIn(
                          mood: _mood!,
                          homework: _homework,
                          help: _help,
                          thoughts: _note.text)),
              child: Text(_text('Share with parent', 'माता-पिता को भेजें'))),
        ],
      );
}
