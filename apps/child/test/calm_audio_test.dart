import 'package:child/widgets/companion_break.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('breathing offers three native soundscapes and stops on pause',
      (tester) async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('com.familyguard.child/calm_audio');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: CompanionBreakDialog())));
    await tester.tap(find.text('Meadow chimes'));
    await tester.pumpAndSettle();
    expect(find.text('Moonlight lullaby'), findsOneWidget);
    expect(find.text('Ocean drift'), findsOneWidget);
    await tester.tap(find.text('Moonlight lullaby'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(calls.last.method, 'start');
    expect(calls.last.arguments, {'preset': 'moonlight'});
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(calls.last.method, 'stop');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
  });
}
