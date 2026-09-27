import 'package:flutter/material.dart';

abstract final class KingdomTheme {
  static const parchment = Color(0xFFFFF8E9);
  static const paper = Color(0xFFF3E8CE);
  static const ink = Color(0xFF3D3526);
  static const muted = Color(0xFF7C735D);
  static const green = Color(0xFF3C7650);
  static const grass = Color(0xFF97B873);
  static const earth = Color(0xFFB58A59);
  static const gold = Color(0xFFC18B35);
  static const water = Color(0xFF90CADF);
  static const line = Color(0xFFD6C6A0);

  // Bright geographic map: blue water, green natural areas, warm roads.
  static const tileUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/'
      'World_Topo_Map/MapServer/tile/{z}/{y}/{x}';
  static const attribution =
      'Tiles © Esri · Esri, HERE, Garmin, USGS, OSM contributors';
  static const assets = <String?>[
    null,
    'assets/buildings/cottage.png',
    'assets/buildings/manor.png',
    'assets/buildings/castle.png',
  ];
  static const levels = ['Arsa', 'Çadır', 'Ev', 'Apartman', 'Otel', 'Gökdelen'];

  static BoxDecoration panel({double radius = 22}) => BoxDecoration(
    color: parchment,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: line, width: 1.4),
    boxShadow: const [
      BoxShadow(color: Color(0x223C3525), blurRadius: 18, offset: Offset(0, 6)),
    ],
  );

  static ThemeData get data => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: paper,
    colorScheme: ColorScheme.fromSeed(
      seedColor: green,
      brightness: Brightness.light,
      surface: parchment,
      primary: green,
      secondary: gold,
      onSurface: ink,
    ),
    textTheme: ThemeData.light().textTheme.apply(
      bodyColor: ink,
      displayColor: ink,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: green,
      contentTextStyle: TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
