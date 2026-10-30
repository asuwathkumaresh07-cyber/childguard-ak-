import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
        'Daily and Hourly stay legible in $brightness and switch graphs',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          theme: AppPalette.theme(brightness: brightness),
          home: const Scaffold(
              body: SingleChildScrollView(
                  child: Padding(
                      padding: EdgeInsets.all(16),
                      child: DualUsageChart(
                          logs: [], primaryColor: Colors.white))))));
      for (final mode in ['daily', 'hourly']) {
        final pill = find.byKey(ValueKey('usage-mode-$mode'));
        await tester.tap(pill);
        await tester.pumpAndSettle();
        final box = tester.widget<AnimatedContainer>(find.descendant(
            of: pill, matching: find.byType(AnimatedContainer)));
        final background = (box.decoration! as BoxDecoration).color!;
        final icon = tester.widget<Icon>(
            find.descendant(of: pill, matching: find.byType(Icon)));
        final text = tester.widget<Text>(
            find.descendant(of: pill, matching: find.byType(Text)));
        for (final foreground in [icon.color!, text.style!.color!]) {
          final a = background.computeLuminance();
          final b = foreground.computeLuminance();
          expect((math.max(a, b) + .05) / (math.min(a, b) + .05),
              greaterThanOrEqualTo(4.5));
        }
        expect(
            find.textContaining(
                mode == 'daily' ? 'Daily Usage (Bar Graph)' : 'Hourly Usage'),
            findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
