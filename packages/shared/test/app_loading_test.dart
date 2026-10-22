import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  testWidgets('loading icon floats and supports drag-to-tilt', (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppPalette.theme(),
        home: const Scaffold(
          body: AppLoadingView(
              message: 'Loading child settings', icon: Icons.settings),
        )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final transforms = find.descendant(
        of: find.byType(LoadingIcon3D), matching: find.byType(Transform));
    final before = tester
        .widgetList<Transform>(transforms)
        .map((widget) => widget.transform.storage.toList())
        .toList();
    await tester.pump(const Duration(milliseconds: 700));
    final after = tester
        .widgetList<Transform>(transforms)
        .map((widget) => widget.transform.storage.toList())
        .toList();
    expect(after, isNot(equals(before)));
    final container = find.descendant(
        of: find.byType(LoadingIcon3D),
        matching: find.byType(AnimatedContainer));
    final resting =
        tester.widget<AnimatedContainer>(container).transform!.storage.toList();
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(LoadingIcon3D)));
    await gesture.moveBy(const Offset(30, 18));
    await tester.pump();
    expect(
        tester.widget<AnimatedContainer>(container).transform!.storage.toList(),
        isNot(equals(resting)));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
        tester.widget<AnimatedContainer>(container).transform!.storage.toList(),
        equals(resting));
    expect(find.text('Loading child settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('reduced motion stays still and fits a narrow viewport',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: AppPalette.theme(),
        home: const MediaQuery(
          data: MediaQueryData(
              disableAnimations: true, textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
              body: AppLoadingView(
                  message: 'Loading your family',
                  detail: 'Getting the latest device updates.')),
        )));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.text('Loading your family'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
