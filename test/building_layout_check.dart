// Standalone check also runs without Flutter dependencies.
// ignore: avoid_relative_lib_imports
import '../lib/models/building_layout.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  for (final width in [20.0, 70.0, 160.0, 400.0, 1200.0]) {
    final layout = BuildingLayout(centerX: 205, centerY: 400, hexWidth: width);
    check((layout.left + layout.width / 2 - 205).abs() < 1e-8, 'X anchor');
    check(
      (layout.top + layout.height * 0.90 - 400).abs() < 1e-8,
      'Ground anchor',
    );
    check(
      (layout.width * 92.72 / 150 / width - 0.72).abs() < 1e-8,
      '72% footprint',
    );
    final zoom = BuildingLayout(
      centerX: 205,
      centerY: 400,
      hexWidth: width * 2,
    );
    check(
      (zoom.width - layout.width * 2).abs() < 1e-8,
      'Zoom doubles structure',
    );
  }
  // ignore: avoid_print
  print('PASS: 20 anchor / footprint / zoom assertions');
}
