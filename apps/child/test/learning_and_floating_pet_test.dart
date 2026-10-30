import 'package:child/widgets/floating_pet.dart';
import 'package:child/widgets/learning_game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('buddy roams left up right and down without leaving the screen',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: FloatingPet(childId: 'roamer', child: Scaffold())));
    await tester.pump();
    Offset target() {
      final position =
          tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned));
      return Offset(position.left!, position.top!);
    }

    var previous = target();
    final moves = <Offset>[];
    for (var i = 0; i < 9; i++) {
      await tester.pump(const Duration(seconds: 3));
      final next = target();
      if (next != previous) moves.add(next - previous);
      expect(next.dx, inInclusiveRange(0, 684));
      expect(next.dy, inInclusiveRange(0, 456));
      previous = next;
    }
    expect(moves.any((d) => d.dx < 0 && d.dy == 0), true);
    expect(moves.any((d) => d.dx > 0 && d.dy == 0), true);
    expect(moves.any((d) => d.dy < 0 && d.dx == 0), true);
    expect(moves.any((d) => d.dy > 0 && d.dx == 0), true);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('quest explains wrong answers and scores a complete round',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: LearningGame())));
    await tester.tap(find.byType(OutlinedButton).first);
    await tester.pump();
    expect(
        find.textContaining('Good try!').evaluate().length +
            find.textContaining('Well done!').evaluate().length,
        1);
    for (var round = 0; round < 4; round++) {
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.tap(find.byType(OutlinedButton).first);
      await tester.pump();
    }
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.textContaining('You earned '), findsOneWidget);
    await tester.tap(find.text('Play again'));
    await tester.pump();
    expect(find.textContaining('1/5'), findsOneWidget);
  });

  testWidgets('floating buddy stays on screen after dragging and scrolling',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!),
        home: FloatingPet(
            childId: 'test',
            child: Scaffold(
                body: ListView(
                    children: List.generate(
                        50,
                        (i) =>
                            SizedBox(height: 60, child: Text('Item $i'))))))));
    await tester.pump();
    final buddy = find.bySemanticsLabel(RegExp('.*Drag to move.*'));
    final before = tester.getTopLeft(buddy);
    await tester.drag(buddy, const Offset(130, 100));
    await tester.pumpAndSettle();
    final moved = tester.getTopLeft(buddy);
    expect(moved.dx, greaterThan(before.dx));
    await tester.drag(find.byType(ListView), const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(buddy), moved);
    await tester.drag(buddy, const Offset(2000, 2000));
    await tester.pumpAndSettle();
    final rect = tester.getRect(buddy);
    expect(rect.right, lessThanOrEqualTo(800));
    expect(rect.bottom, lessThanOrEqualTo(600));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
