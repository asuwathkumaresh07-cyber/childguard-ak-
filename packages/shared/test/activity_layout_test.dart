import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  testWidgets(
      'activity fits a narrow phone with larger text and real VPN status',
      (tester) async {
    final preview = Platform.environment['SAVE_UI_PREVIEW'] == '1';
    if (preview) {
      await tester.runAsync(() async {
        for (final entry in {
          'AppPreview': 'C:/Windows/Fonts/segoeui.ttf',
          'MaterialIcons':
              'C:/Users/Acer/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        }.entries) {
          final file = File(entry.value);
          if (await file.exists()) {
            final loader = FontLoader(entry.key)
              ..addFont(
                  Future.value(ByteData.sublistView(await file.readAsBytes())));
            await loader.load();
          }
        }
      });
    }
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 9);
    final yesterday = DateTime(now.year, now.month, now.day - 1, 9);
    final logs = [
      AppUsageLog(
          id: 'today',
          childId: 'child',
          familyId: 'family',
          packageName: 'com.example.books',
          appLabel: 'Books',
          startedAt: start,
          durationSeconds: 2700),
      AppUsageLog(
          id: 'yesterday',
          childId: 'child',
          familyId: 'family',
          packageName: 'com.example.books',
          appLabel: 'Books',
          startedAt: yesterday,
          durationSeconds: 3600),
    ];
    final theme = AppPalette.theme();
    await tester.pumpWidget(MaterialApp(
        theme: preview
            ? theme.copyWith(
                textTheme: theme.textTheme.apply(fontFamily: 'AppPreview'))
            : theme,
        home: MediaQuery(
          data: const MediaQueryData(
              size: Size(320, 740),
              textScaler: TextScaler.linear(1.3),
              disableAnimations: true),
          child: RepaintBoundary(
              key: const ValueKey('activity-preview'),
              child: Scaffold(
                appBar: AppBar(
                    title: Text('Alex · Activity',
                        style: preview
                            ? const TextStyle(fontFamily: 'AppPreview')
                            : null)),
                body: AmbientBackground(
                    child: CategorizedLogsView(
                  appLogs: logs,
                  childName: 'Alex',
                  deviceStatus: ChildDeviceStatus(
                      childId: 'child',
                      familyId: 'family',
                      vpnEnabled: true,
                      usageAccessEnabled: true,
                      accessibilityEnabled: true,
                      lastSeenAt: now),
                )),
              )),
        )));
    await tester.pump();
    expect(find.text('VPN ON'), findsOneWidget);
    await tester.tap(find.text('Usage Graph'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(DualUsageChart), findsOneWidget);
    expect(find.textContaining('25%'), findsOneWidget);
    await tester.tap(find.text('Hourly'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Hourly Usage (Point Graph)'), findsOneWidget);
    await tester.tap(find.text('Daily'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Daily Usage (Bar Graph)'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
    if (Platform.environment['SAVE_UI_PREVIEW'] == '1') {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('activity-preview')));
      await tester.runAsync(() async {
        final picture = await boundary.toImage(pixelRatio: 2);
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        final output = File('../../artifacts/activity-preview.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      });
    }
  });
}
