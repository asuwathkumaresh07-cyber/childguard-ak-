import 'dart:io';
import 'dart:ui' as ui;
import 'package:child/widgets/animated_companion_pet.dart';
import 'package:child/widgets/companion_pet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('downloaded pet frames keep animating between actions',
      (tester) async {
    const key = ValueKey('living-pets');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: RepaintBoundary(
                    key: key,
                    child: ColoredBox(
                        color: Colors.white,
                        child: Wrap(children: [
                          for (final pet in CompanionPet.values)
                            AnimatedCompanionPet(pet: pet, size: 120),
                        ])))))));
    await tester.runAsync(() async {
      final context = tester.element(find.byKey(key));
      for (final pet in CompanionPet.values) {
        await precacheImage(AssetImage(pet.assetPath), context);
      }
    });
    await tester.pump();
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
    Future<Uint8List> pixels() async {
      final img = await boundary.toImage(pixelRatio: 2);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      return bytes!.buffer.asUint8List();
    }

    final first = await tester.runAsync(pixels);
    await tester.pump(const Duration(milliseconds: 2000));
    final next = await tester.runAsync(pixels);
    expect(listEquals(first, next), isFalse,
        reason:
            'Downloaded sprite frames must visibly change even without walking.');
    if (Platform.environment['SAVE_PET_PREVIEW'] == '1') {
      await tester.runAsync(() async {
        await File('../../artifacts/live-pets-preview.png')
            .writeAsBytes(first!);
      });
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion freezes automatic body animation',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!),
        home:
            const Scaffold(body: AnimatedCompanionPet(pet: CompanionPet.cat))));
    await tester.runAsync(() => precacheImage(
        AssetImage(CompanionPet.cat.assetPath),
        tester.element(find.byType(AnimatedCompanionPet))));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
