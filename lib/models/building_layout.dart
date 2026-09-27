/// Screen-space layout whose ground anchor is always the hex centre.
/// Dimensions are proportional to the projected hex, never fixed pixels.
class BuildingLayout {
  BuildingLayout({
    required double centerX,
    required double centerY,
    required double hexWidth,
  }) : width = hexWidth * 0.72 * 150 / 92.72,
       height = hexWidth * 0.72 * 180 / 92.72,
       left = centerX - hexWidth * 0.72 * 150 / 92.72 / 2,
       top = centerY - hexWidth * 0.72 * 180 / 92.72 * 0.90;
  final double width;
  final double height;
  final double left;
  final double top;
}
