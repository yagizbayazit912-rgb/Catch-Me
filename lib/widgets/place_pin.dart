import 'package:flutter/material.dart';

/// A claimable place pin shown on the map (e.g. a "territory" spot).
class PlacePin extends StatelessWidget {
  const PlacePin({
    super.key,
    this.color = const Color(0xFF00CFFF), // neon blue
    this.size = 34,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.location_on,
      color: color,
      size: size,
      shadows: [Shadow(color: color.withValues(alpha: 0.9), blurRadius: 16)],
    );
  }
}
