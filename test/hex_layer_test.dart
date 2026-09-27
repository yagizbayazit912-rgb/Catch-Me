import 'dart:io';
import 'dart:ui' as ui;
import 'package:catch_me/services/hex_grid_service.dart';
import 'package:catch_me/widgets/hex_zone_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  testWidgets('ground anchor and size track projected hex across zooms', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const grid = HexGridService();
    final zone = grid
        .zoneForLocation(const LatLng(38.73, 35.48))
        .copyWith(ownerId: 'me', upgradeLevel: 2);
    final controller = MapController();
    const sceneKey = ValueKey('scene');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: sceneKey,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0005)
                ..rotateX(-0.50)
                ..multiply(Matrix4.diagonal3Values(1.4, 1.4, 1)),
              child: FlutterMap(
                mapController: controller,
                options: MapOptions(
                  initialCenter: zone.center,
                  initialZoom: 15,
                  backgroundColor: const Color(0xFFEDE9CE),
                ),
                children: [
                  HexZoneLayer(
                    zones: [zone],
                    userLocation: zone.center,
                    playerId: 'me',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final finder = find.byKey(ValueKey('building-${zone.id}'));
    final before = tester.widget<Positioned>(finder);
    controller.move(zone.center, 16);
    await tester.pumpAndSettle();
    final after = tester.widget<Positioned>(finder);
    expect(after.width, closeTo(before.width! * 2, 0.01));
    final center = controller.camera.latLngToScreenPoint(zone.center);
    expect(after.left! + after.width! / 2, closeTo(center.x, 0.01));
    expect(after.top! + after.height! * 0.90, closeTo(center.y, 0.01));
    expect(tester.takeException(), isNull);
    // Optional visual QA artifact, not a platform-sensitive golden assertion.
    if (const bool.fromEnvironment('VISUAL_QA')) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(sceneKey),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/qa').create(recursive: true);
        await File(
          'build/qa/hex_scene.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
