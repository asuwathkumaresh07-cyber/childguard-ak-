import 'dart:math';

import 'package:flutter/material.dart';

class _LearningQuestion {
  const _LearningQuestion({
    required this.prompt,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });

  final String prompt;
  final List<String> options;
  final int correctIndex;
  final String explanation;
}

/// A small rotating learning quest. Questions and answer order are generated
/// at the start of each round, so the quiz does not feel like a fixed script.
class LearningGame extends StatefulWidget {
  const LearningGame({super.key, this.onCompleted});
  final ValueChanged<int>? onCompleted;

  @override
  State<LearningGame> createState() => _LearningGameState();
}

class _LearningGameState extends State<LearningGame> {
  late List<_LearningQuestion> _questions;
  int _index = 0;
  int _score = 0;
  int? _answer;

  @override
  void initState() {
    super.initState();
    _questions = _makeQuestions();
  }

  List<_LearningQuestion> _makeQuestions() {
    final random = Random(DateTime.now().millisecondsSinceEpoch);
    final left = 4 + random.nextInt(8);
    final right = 2 + random.nextInt(8);
    final total = left + right;
    final mathOptions = <String>{
      '$total',
      '${total + 2}',
      '${max(0, total - 2)}',
    }.toList()
      ..shuffle(random);

    final questions = <_LearningQuestion>[
      _LearningQuestion(
        prompt: 'A stranger asks for your password. What do you do?',
        options: [
          'Keep it private and tell a trusted adult',
          'Send it to them',
          'Post it online',
        ],
        correctIndex: 0,
        explanation:
            'Passwords protect you. Keep them private, even from online friends.',
      ),
      _LearningQuestion(
        prompt: 'What is $left + $right?',
        options: mathOptions,
        correctIndex: mathOptions.indexOf('$total'),
        explanation: '$left + $right = $total. Nice bit of number practice!',
      ),
      _LearningQuestion(
        prompt: 'Which habit helps your body after screen time?',
        options: [
          'Skip sleep',
          'Keep scrolling',
          'Stretch and look into the distance',
        ],
        correctIndex: 2,
        explanation: 'Short breaks give your eyes and body a rest.',
      ),
      _LearningQuestion(
        prompt: 'Which planet do we live on?',
        options: ['Mars', 'Earth', 'Saturn'],
        correctIndex: 1,
        explanation:
            'Earth is our home. We can help protect it by saving water and reducing waste.',
      ),
      _LearningQuestion(
        prompt: 'A message says you won a prize and must click now.',
        options: [
          'Click immediately',
          'Share your address',
          'Ask a trusted adult first',
        ],
        correctIndex: 2,
        explanation:
            'Urgent prize messages can be tricks. Pause and check before clicking.',
      ),
    ];
    questions.shuffle(random);
    return questions;
  }

  void _playAgain() {
    setState(() {
      _questions = _makeQuestions();
      _index = 0;
      _score = 0;
      _answer = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final finished = _index == _questions.length;
    final question = finished ? _questions.first : _questions[_index];
    return AlertDialog(
      title: Text(finished
          ? 'Quest complete!'
          : 'Learning quest · ${_index + 1}/${_questions.length}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (finished)
              Text(
                  'You earned $_score of ${_questions.length} stars. Keep exploring!')
            else ...[
              LinearProgressIndicator(value: _index / _questions.length),
              const SizedBox(height: 16),
              Text(question.prompt),
              const SizedBox(height: 12),
              for (var i = 0; i < question.options.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    onPressed: _answer != null
                        ? null
                        : () => setState(() {
                              _answer = i;
                              if (i == question.correctIndex) _score++;
                            }),
                    child: Text(question.options[i]),
                  ),
                ),
              if (_answer != null)
                Text(
                    '${_answer == question.correctIndex ? 'Well done!' : 'Good try!'} ${question.explanation}'),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (!finished && _answer != null)
          FilledButton(
            onPressed: () => setState(() {
              _index++;
              _answer = null;
              if (_index == _questions.length) widget.onCompleted?.call(_score);
            }),
            child: const Text('Next'),
          ),
        if (finished)
          FilledButton(
            onPressed: _playAgain,
            child: const Text('Play again'),
          ),
      ],
    );
  }
}
