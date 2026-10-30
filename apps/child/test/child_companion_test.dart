import 'dart:io';
import 'dart:ui' as ui;
import 'package:child/main.dart';
import 'package:child/widgets/child_companion.dart';
import 'package:child/widgets/companion_check_in.dart';
import 'package:child/widgets/companion_break.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _frame(Widget child) => MaterialApp(
    theme: Platform.environment['SAVE_CHILD_PREVIEW'] == '1'
        ? AppPalette.theme().copyWith(
            textTheme:
                AppPalette.theme().textTheme.apply(fontFamily: 'ChildPreview'))
        : AppPalette.theme(),
    builder: (context, page) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              disableAnimations: true, textScaler: TextScaler.linear(1.3)),
          child: page!,
        ),
    home: RepaintBoundary(
        key: const ValueKey('child-buddy-preview'),
        child: Scaffold(
            body: SingleChildScrollView(
                child: Padding(
                    padding: const EdgeInsets.all(16), child: child)))));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'breathing break fits a small screen and finishes after 30 seconds',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_frame(Builder(
        builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
                context: context, builder: (_) => const CompanionBreakDialog()),
            child: const Text('Open break')))));
    await tester.tap(find.text('Open break'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('All done. Nice and easy.'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(CompanionBreakDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('old dark-mode preference cannot darken the child app',
      (tester) async {
    SharedPreferences.setMockInitialValues({'child_dark_mode': true});
    await tester.pumpWidget(const ChildApp());
    await tester.pump(const Duration(milliseconds: 100));
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.light);
    expect(app.theme!.brightness, Brightness.light);
    expect(app.theme!.appBarTheme.backgroundColor, Colors.white);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('task reminders use assigned tasks and pet options use a grid',
      (tester) async {
    if (Platform.environment['SAVE_CHILD_PREVIEW'] == '1') {
      await tester.runAsync(() async {
        for (final font in {
          'ChildPreview': 'C:/Windows/Fonts/segoeui.ttf',
          'MaterialIcons':
              'C:/Users/Acer/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
        }.entries) {
          final file = File(font.value);
          if (await file.exists()) {
            final loader = FontLoader(font.key)
              ..addFont(
                  Future.value(ByteData.sublistView(await file.readAsBytes())));
            await loader.load();
          }
        }
      });
    }
    tester.view.physicalSize = const Size(360, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var openedTasks = false;
    await tester.pumpWidget(_frame(ChildCompanionCard(
        childId: 'child-a',
        vpnEnabled: true,
        permissionsReady: true,
        checkInDue: false,
        onTasks: () => openedTasks = true,
        onProtection: () {},
        onPermissions: () {},
        onCheckIn: () {},
        tasks: [
          ChildTask(
            id: 'task',
            familyId: 'family',
            childId: 'child-a',
            title: 'Read a chapter',
            description: '',
            taskType: 'homework',
            dueAt: DateTime.now().add(const Duration(hours: 1)),
            points: 5,
            status: 'assigned',
            createdAt: DateTime.now(),
            submissionPhotoPath: null,
            submissionNote: null,
          )
        ])));
    await tester.pumpAndSettle();
    expect(find.textContaining('Read a chapter'), findsOneWidget);
    await tester.runAsync(() => precacheImage(
        AssetImage(CompanionPet.corgi.assetPath),
        tester.element(find.byType(ChildCompanionCard))));
    await tester.pump();
    if (Platform.environment['SAVE_CHILD_PREVIEW'] == '1') {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('child-buddy-preview')));
      await tester.runAsync(() async {
        final picture = await boundary.toImage(pixelRatio: 2);
        final data = await picture.toByteData(format: ui.ImageByteFormat.png);
        final file = File('../../artifacts/child-buddy-preview.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data!.buffer.asUint8List());
        picture.dispose();
      });
    }
    expect(find.byType(GridView), findsOneWidget);
    await tester.ensureVisible(find.text('My tasks'));
    await tester.tap(find.text('My tasks'));
    expect(openedTasks, isTrue);
    await tester.ensureVisible(find.byTooltip('Choose a pet'));
    await tester.tap(find.byTooltip('Choose a pet'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Summer outfit'));
    await tester.tap(find.text('Summer outfit'));
    await tester.pumpAndSettle();
    expect(find.text('Milo, your buddy'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('child_companion_child-a'), 'summer');
    expect(preferences.getString('child_companion_child-b'), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'protection reminder routes to controls without switching VPN itself',
      (tester) async {
    var openedProtection = false;
    await tester.pumpWidget(_frame(ChildCompanionCard(
        childId: 'child',
        tasks: const [],
        vpnEnabled: false,
        permissionsReady: true,
        checkInDue: true,
        onTasks: () {},
        onProtection: () => openedProtection = true,
        onPermissions: () {},
        onCheckIn: () {})));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Ask your parent for an ON code'), findsOneWidget);
    await tester.ensureVisible(find.text('Protection'));
    await tester.tap(find.text('Protection'));
    expect(openedProtection, isTrue);
  });

  testWidgets(
      'grid check-in returns mood homework help and optional note only on share',
      (tester) async {
    CompanionCheckIn? response;
    await tester.pumpWidget(_frame(Builder(
        builder: (context) => TextButton(
            onPressed: () async {
              response = await showDialog<CompanionCheckIn>(
                  context: context,
                  builder: (_) => const CompanionCheckInDialog());
            },
            child: const Text('Open check-in')))));
    await tester.tap(find.text('Open check-in'));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsNWidgets(3));
    expect(response, isNull);
    await tester.tap(find.text('Great'));
    await tester.ensureVisible(find.text('Working on it'));
    await tester.tap(find.text('Working on it'));
    await tester.ensureVisible(find.text('I want to talk'));
    await tester.tap(find.text('I want to talk'));
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Please help with maths.');
    await tester.tap(find.text('Share with parent'));
    await tester.pumpAndSettle();
    expect(response!.mood, 'great');
    expect(response!.note, contains('Homework: Working on it'));
    expect(response!.note, contains('Help: I would like to talk'));
    expect(response!.note, contains('Please help with maths.'));
  });
}
