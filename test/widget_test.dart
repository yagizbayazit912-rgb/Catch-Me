import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:catch_me/theme/kingdom_theme.dart';
import 'package:catch_me/visual_preview.dart';

void main() {
  testWidgets('Small-screen preview upgrades and captures without backend', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: KingdomTheme.data,
        home: const KingdomPreviewScreen(showTiles: false),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Yükselt'));
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('Son seviye'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Ele geçir'));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Yükselt'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
