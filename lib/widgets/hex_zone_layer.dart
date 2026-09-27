import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../models/zone.dart';
import '../models/building_layout.dart';
import '../theme/kingdom_theme.dart';

/// Draws the territory fill, capture sweep and the five upgrade structures.
/// The building art is vector based so every level keeps one fixed isometric
/// camera and remains sharp at different map zooms.
class HexZoneLayer extends StatefulWidget {
  const HexZoneLayer({
    super.key,
    required this.zones,
    required this.userLocation,
    this.playerId,
    this.captureZoneId,
    this.captureProgress = 0,
    this.captureSecondsLeft = 0,
  });
  final List<Zone> zones;
  final LatLng userLocation;
  final String? playerId;
  final String? captureZoneId;
  final double captureProgress;
  final int captureSecondsLeft;

  @override
  State<HexZoneLayer> createState() => _HexZoneLayerState();
}

class _HexZoneLayerState extends State<HexZoneLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant HexZoneLayer old) {
    super.didUpdateWidget(old);
    _syncPulse();
  }

  void _syncPulse() {
    if (widget.captureZoneId != null &&
        !MediaQuery.disableAnimationsOf(context)) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final capture = widget.zones
        .where((z) => z.id == widget.captureZoneId)
        .firstOrNull;
    // Ownership paints the whole hex immediately. The first structure is the
    // tent upgrade, so level 0 remains a clean claimed tile.
    final buildings =
        widget.zones
            .where(
              (z) =>
                  z.isOwned &&
                  (z.visualUpgradeLevel > 0 || z.isUnderConstruction),
            )
            .toList()
          ..sort((a, b) => b.center.latitude.compareTo(a.center.latitude));
    return Stack(
      children: [
        RepaintBoundary(
          child: CustomPaint(
            size: Size(camera.size.x, camera.size.y),
            painter: _TerritoryPainter(
              camera: camera,
              zones: widget.zones,
              playerId: widget.playerId,
            ),
          ),
        ),
        if (capture != null)
          RepaintBoundary(
            child: CustomPaint(
              size: Size(camera.size.x, camera.size.y),
              painter: _CapturePainter(
                camera: camera,
                zone: capture,
                progress: widget.captureProgress,
                pulse: _pulse,
              ),
            ),
          ),
        for (final zone in buildings) _positionBuilding(camera, zone),
        MarkerLayer(
          markers: [
            if (capture != null)
              Marker(
                point: capture.center,
                width: 76,
                height: 76,
                child: _CaptureBadge(
                  progress: widget.captureProgress,
                  secondsLeft: widget.captureSecondsLeft,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _positionBuilding(MapCamera camera, Zone zone) {
    final center = camera.latLngToScreenPoint(zone.center);
    final hexWidth = _zonePath(camera, zone).getBounds().width;
    // Art's ground footprint is 92.72 / 150 of its design width.
    // This makes it cover 72% of the hex at every zoom, not a fixed pixel size.
    final layout = BuildingLayout(
      centerX: center.x,
      centerY: center.y,
      hexWidth: hexWidth,
    );
    return Positioned(
      key: ValueKey('building-${zone.id}'),
      left: layout.left,
      top: layout.top,
      width: layout.width,
      height: layout.height,
      child: IgnorePointer(
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: 150,
            height: 180,
            child: _Building(
              zone: zone,
              isMine: zone.ownerId == widget.playerId,
            ),
          ),
        ),
      ),
    );
  }
}

Path _zonePath(MapCamera camera, Zone zone) => Path()
  ..addPolygon([
    for (final point in zone.boundary)
      Offset(
        camera.latLngToScreenPoint(point).x,
        camera.latLngToScreenPoint(point).y,
      ),
  ], true);

class _TerritoryPainter extends CustomPainter {
  _TerritoryPainter({required this.camera, required this.zones, this.playerId});
  final MapCamera camera;
  final List<Zone> zones;
  final String? playerId;

  @override
  void paint(Canvas canvas, Size size) {
    for (final zone in zones) {
      final path = _zonePath(camera, zone);
      final bounds = path.getBounds();
      if (!bounds.overlaps(Offset.zero & size)) continue;
      final owned = zone.isOwned;
      final mine = owned && zone.ownerId == playerId;
      final tint = mine
          ? KingdomTheme.green
          : owned
          ? (zone.ownerColor ?? KingdomTheme.earth)
          : KingdomTheme.grass;
      // Extruded lower face gives the whole owned cell a raised 2.5D tile.
      final depth = bounds.width * (owned ? 0.075 : 0.012);
      canvas.drawPath(
        path.shift(Offset(0, depth)),
        Paint()
          ..color = Color.lerp(
            tint,
            Colors.black,
            0.45,
          )!.withValues(alpha: owned ? 0.72 : 0.14),
      );
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(bounds.topCenter, bounds.bottomCenter, [
            Color.lerp(
              tint,
              Colors.white,
              0.43,
            )!.withValues(alpha: owned ? 0.74 : 0.16),
            Color.lerp(
              tint,
              Colors.black,
              0.24,
            )!.withValues(alpha: owned ? 0.56 : 0.08),
          ]),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = owned ? 2.1 : 0.9
          ..color = owned
              ? tint.withValues(alpha: 0.92)
              : const Color(0xA0697651),
      );
      if (owned) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..color = KingdomTheme.parchment.withValues(alpha: 0.8),
        );
        // A small inner contour strengthens the raised tile silhouette.
        final inner = Path()
          ..addPolygon([
            for (final point in _insetPoints(zone, 0.08))
              Offset(
                camera.latLngToScreenPoint(point).x,
                camera.latLngToScreenPoint(point).y,
              ),
          ], true);
        canvas.drawPath(
          inner,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.65
            ..color = Colors.white.withValues(alpha: 0.38),
        );
      }
    }
  }

  List<LatLng> _insetPoints(Zone zone, double fraction) {
    final c = zone.center;
    return zone.boundary
        .map(
          (p) => LatLng(
            c.latitude + (p.latitude - c.latitude) * (1 - fraction),
            c.longitude + (p.longitude - c.longitude) * (1 - fraction),
          ),
        )
        .toList();
  }

  @override
  bool shouldRepaint(covariant _TerritoryPainter old) =>
      !identical(old.zones, zones) ||
      old.playerId != playerId ||
      old.camera.center != camera.center ||
      old.camera.zoom != camera.zoom ||
      old.camera.rotation != camera.rotation ||
      old.camera.size != camera.size;
}

class _CapturePainter extends CustomPainter {
  _CapturePainter({
    required this.camera,
    required this.zone,
    required this.progress,
    required this.pulse,
  }) : super(repaint: pulse);
  final MapCamera camera;
  final Zone zone;
  final double progress;
  final Animation<double> pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _zonePath(camera, zone);
    final bounds = path.getBounds();
    final color = zone.isOwned ? KingdomTheme.gold : KingdomTheme.green;
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.12));
    canvas.save();
    canvas.clipPath(path);
    for (var i = 0; i < 3; i++) {
      final t = (pulse.value + i / 3) % 1;
      canvas.drawCircle(
        bounds.center,
        bounds.longestSide * 0.72 * t,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = color.withValues(alpha: (1 - t) * 0.3),
      );
    }
    canvas.restore();
    for (final metric in path.computeMetrics()) {
      final line = metric.extractPath(0, metric.length * progress.clamp(0, 1));
      canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 8
          ..color = KingdomTheme.parchment,
      );
      canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 4
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CapturePainter old) =>
      old.zone != zone ||
      old.progress != progress ||
      old.camera.center != camera.center ||
      old.camera.zoom != camera.zoom ||
      old.camera.rotation != camera.rotation ||
      old.camera.size != camera.size;
}

class _Building extends StatefulWidget {
  const _Building({required this.zone, required this.isMine});
  final Zone zone;
  final bool isMine;
  @override
  State<_Building> createState() => _BuildingState();
}

class _BuildingState extends State<_Building>
    with SingleTickerProviderStateMixin {
  int? _lastVisualLevel;
  late final AnimationController _arrival = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 820),
  )..forward();

  @override
  void didUpdateWidget(covariant _Building old) {
    super.didUpdateWidget(old);
    if (_lastVisualLevel != widget.zone.visualUpgradeLevel ||
        old.zone.ownerId != widget.zone.ownerId) {
      _arrival.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _arrival.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final level = widget.zone.visualUpgradeLevel;
    _lastVisualLevel = level;
    final color = widget.isMine
        ? KingdomTheme.green
        : (widget.zone.ownerColor ?? KingdomTheme.earth);
    final reduced = MediaQuery.disableAnimationsOf(context);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _arrival,
        builder: (context, _) {
          final t = reduced ? 1.0 : _arrival.value;
          final eased = Curves.easeOutBack.transform(t);
          return Stack(
            alignment: Alignment.bottomCenter,
            children: [
              if (t < 1)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DustBurstPainter(t: t, color: color),
                  ),
                ),
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(0, -26 * (1 - eased)),
                  child: Transform.scale(
                    alignment: Alignment.bottomCenter,
                    scale: 0.74 + 0.26 * eased,
                    child: Opacity(
                      opacity: (t * 4).clamp(0, 1),
                      child: CustomPaint(
                        size: const Size(150, 180),
                        painter: KingdomBuildingPainter(
                          level: level,
                          color: color,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: KingdomTheme.parchment,
                    border: Border.all(color: color, width: 1.2),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    widget.zone.isUnderConstruction
                        ? 'İnşaat · ${widget.zone.upgradeReadyAt!.difference(DateTime.now()).inSeconds.clamp(0, 999999)} sn'
                        : kUpgradeNames[level],
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: KingdomTheme.ink,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A single vector art family for the five upgrade levels.
class KingdomBuildingPainter extends CustomPainter {
  const KingdomBuildingPainter({required this.level, required this.color});
  final int level;
  final Color color;

  Paint _p(
    Color c, {
    PaintingStyle style = PaintingStyle.fill,
    double width = 1,
  }) => Paint()
    ..color = c
    ..style = style
    ..strokeWidth = width
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;
  Path _poly(List<Offset> points) => Path()..addPolygon(points, true);
  Color get wall => const Color(0xFFF6E3B8);
  Color get roof => const Color(0xFFC9653C);
  Color get timber => const Color(0xFF70472E);
  Color get glass => const Color(0xFF6FA8A3);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.90);
    // A larger fixed marker plus this scale makes the buildings occupy most
    // of their hex while preserving a clear isometric, low-angle silhouette.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(1.22);
    canvas.translate(-c.dx, -c.dy);
    final ground = _poly([
      c.translate(0, -16),
      c.translate(38, 0),
      c.translate(0, 16),
      c.translate(-38, 0),
    ]);
    canvas.drawPath(
      ground.shift(const Offset(0, 6)),
      _p(const Color(0x663D3526)),
    );
    canvas.drawPath(ground, _p(const Color(0xFF9BBB73)));
    canvas.drawPath(
      ground,
      _p(const Color(0xFFC4D99A), style: PaintingStyle.stroke, width: 1.5),
    );

    switch (level) {
      case 0:
        canvas.drawLine(
          c.translate(-28, -6),
          c.translate(-28, -34),
          _p(timber, width: 4),
        );
        canvas.drawLine(
          c.translate(28, -6),
          c.translate(28, -34),
          _p(timber, width: 4),
        );
        canvas.drawLine(
          c.translate(-28, -28),
          c.translate(28, -28),
          _p(roof, width: 6),
        );
        break;
      case 1:
        _tent(canvas, c);
        break;
      case 2:
        _house(canvas, c);
        break;
      case 3:
        _apartment(canvas, c);
        break;
      case 4:
        _hotel(canvas, c);
        break;
      default:
        _skyscraper(canvas, c);
        break;
    }
    canvas.drawCircle(c.translate(-8, -53), 3, _p(KingdomTheme.gold));
    canvas.drawLine(
      c.translate(-8, -51),
      c.translate(-8, -18),
      _p(timber, width: 2.4),
    );
    final flag = _poly([
      c.translate(-7, -50),
      c.translate(17, -46),
      c.translate(13, -32),
      c.translate(-7, -36),
    ]);
    canvas.drawPath(flag, _p(color));
    canvas.drawPath(
      flag,
      _p(KingdomTheme.gold, style: PaintingStyle.stroke, width: 0.7),
    );
    canvas.restore();
  }

  void _tent(Canvas canvas, Offset c) {
    final front = _poly([
      c.translate(0, -66),
      c.translate(30, -8),
      c.translate(-30, -8),
    ]);
    canvas.drawPath(front, _p(const Color(0xFFD9A66A)));
    canvas.drawPath(
      _poly([c.translate(0, -66), c.translate(30, -8), c.translate(0, -3)]),
      _p(const Color(0xFFB8794F)),
    );
    canvas.drawLine(
      c.translate(0, -66),
      c.translate(0, -8),
      _p(timber, style: PaintingStyle.stroke, width: 2),
    );
    canvas.drawPath(front, _p(timber, style: PaintingStyle.stroke, width: 1.4));
    canvas.drawCircle(c.translate(0, -13), 4, _p(KingdomTheme.gold));
  }

  void _house(Canvas canvas, Offset c) {
    final body = _poly([
      c.translate(-28, -55),
      c.translate(22, -55),
      c.translate(22, -7),
      c.translate(-28, -7),
    ]);
    final side = _poly([
      c.translate(22, -55),
      c.translate(39, -45),
      c.translate(39, -2),
      c.translate(22, -7),
    ]);
    canvas.drawPath(body, _p(wall));
    canvas.drawPath(side, _p(const Color(0xFFD5B27C)));
    final roofFront = _poly([
      c.translate(-35, -54),
      c.translate(-3, -79),
      c.translate(30, -54),
    ]);
    canvas.drawPath(roofFront, _p(roof));
    canvas.drawPath(
      roofFront,
      _p(timber, style: PaintingStyle.stroke, width: 1.5),
    );
    canvas.drawRect(
      Rect.fromCenter(center: c.translate(-3, -25), width: 13, height: 25),
      _p(const Color(0xFF7A4D31)),
    );
    canvas.drawRect(
      Rect.fromCenter(center: c.translate(12, -38), width: 10, height: 11),
      _p(glass),
    );
    canvas.drawLine(
      c.translate(-27, -39),
      c.translate(20, -39),
      _p(timber, width: 2),
    );
  }

  void _apartment(Canvas canvas, Offset c) {
    final body = _poly([
      c.translate(-28, -85),
      c.translate(24, -85),
      c.translate(24, -7),
      c.translate(-28, -7),
    ]);
    final side = _poly([
      c.translate(24, -85),
      c.translate(42, -74),
      c.translate(42, -2),
      c.translate(24, -7),
    ]);
    canvas.drawPath(body, _p(wall));
    canvas.drawPath(side, _p(const Color(0xFFD2AD77)));
    for (var row = 0; row < 3; row++) {
      final y = -70 + row * 23.0;
      for (var col = 0; col < 3; col++) {
        canvas.drawRect(
          Rect.fromLTWH(c.dx - 19 + col * 14.0, c.dy + y, 8, 10),
          _p(glass),
        );
      }
      canvas.drawLine(
        c.translate(-28, y + 16),
        c.translate(24, y + 16),
        _p(timber, width: 1.8),
      );
    }
    canvas.drawPath(
      _poly([
        c.translate(-32, -85),
        c.translate(27, -85),
        c.translate(39, -76),
        c.translate(-20, -76),
      ]),
      _p(roof),
    );
    canvas.drawPath(
      _poly([
        c.translate(-32, -85),
        c.translate(27, -85),
        c.translate(39, -76),
        c.translate(-20, -76),
      ]),
      _p(timber, style: PaintingStyle.stroke, width: 1.3),
    );
  }

  void _hotel(Canvas canvas, Offset c) {
    final body = _poly([
      c.translate(-40, -82),
      c.translate(28, -82),
      c.translate(28, -7),
      c.translate(-40, -7),
    ]);
    final side = _poly([
      c.translate(28, -82),
      c.translate(45, -71),
      c.translate(45, -1),
      c.translate(28, -7),
    ]);
    canvas.drawPath(body, _p(wall));
    canvas.drawPath(side, _p(const Color(0xFFCFA36E)));
    for (var row = 0; row < 3; row++) {
      final y = -68 + row * 20.0;
      for (var col = 0; col < 4; col++) {
        canvas.drawRect(
          Rect.fromLTWH(c.dx - 33 + col * 16.0, c.dy + y, 9, 9),
          _p(glass),
        );
      }
      canvas.drawLine(
        c.translate(-40, y + 14),
        c.translate(28, y + 14),
        _p(timber, width: 1.8),
      );
    }
    canvas.drawRect(
      Rect.fromCenter(center: c.translate(-5, -22), width: 15, height: 30),
      _p(const Color(0xFF805134)),
    );
    canvas.drawPath(
      _poly([
        c.translate(-45, -82),
        c.translate(-5, -99),
        c.translate(34, -82),
      ]),
      _p(roof),
    );
    canvas.drawPath(
      _poly([
        c.translate(-45, -82),
        c.translate(-5, -99),
        c.translate(34, -82),
      ]),
      _p(timber, style: PaintingStyle.stroke, width: 1.5),
    );
    canvas.drawLine(
      c.translate(-49, -76),
      c.translate(38, -76),
      _p(KingdomTheme.gold, width: 2),
    );
  }

  void _skyscraper(Canvas canvas, Offset c) {
    final body = _poly([
      c.translate(-21, -112),
      c.translate(18, -112),
      c.translate(18, -7),
      c.translate(-21, -7),
    ]);
    final side = _poly([
      c.translate(18, -112),
      c.translate(34, -102),
      c.translate(34, -1),
      c.translate(18, -7),
    ]);
    canvas.drawPath(body, _p(const Color(0xFFE7D09B)));
    canvas.drawPath(side, _p(const Color(0xFFBF965E)));
    for (var row = 0; row < 5; row++) {
      final y = -99 + row * 19.0;
      for (var col = 0; col < 2; col++) {
        canvas.drawRect(
          Rect.fromLTWH(c.dx - 14 + col * 18.0, c.dy + y, 9, 11),
          _p(glass),
        );
      }
      canvas.drawLine(
        c.translate(-21, y + 15),
        c.translate(18, y + 15),
        _p(timber, width: 1.5),
      );
    }
    canvas.drawPath(
      _poly([
        c.translate(-25, -112),
        c.translate(15, -112),
        c.translate(27, -104),
        c.translate(-14, -104),
      ]),
      _p(roof),
    );
    canvas.drawLine(
      c.translate(-2, -112),
      c.translate(-2, -127),
      _p(timber, width: 2),
    );
    canvas.drawCircle(c.translate(-2, -130), 3, _p(KingdomTheme.gold));
  }

  @override
  bool shouldRepaint(covariant KingdomBuildingPainter old) =>
      old.level != level || old.color != color;
}

class _DustBurstPainter extends CustomPainter {
  const _DustBurstPainter({required this.t, required this.color});
  final double t;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.90);
    final fade = (1 - t).clamp(0.0, 1.0);
    for (var i = 0; i < 14; i++) {
      final angle = i * math.pi / 7;
      final distance = 8 + 42 * Curves.easeOutCubic.transform(t);
      final point =
          center +
          Offset(
            math.cos(angle) * distance,
            math.sin(angle) * distance * 0.32 - t * 16,
          );
      canvas.drawCircle(
        point,
        (2.4 - t * 1.4).clamp(0.4, 2.4),
        Paint()
          ..color = Color.lerp(
            KingdomTheme.parchment,
            color,
            i / 14,
          )!.withValues(alpha: fade),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DustBurstPainter old) => old.t != t;
}

class _CaptureBadge extends StatelessWidget {
  const _CaptureBadge({required this.progress, required this.secondsLeft});
  final double progress;
  final int secondsLeft;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(5),
    decoration: KingdomTheme.panel(radius: 50),
    child: Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 52,
          height: 52,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 900),
            builder: (_, value, _) => CircularProgressIndicator(
              value: value.clamp(0, 1),
              color: KingdomTheme.gold,
              backgroundColor: KingdomTheme.paper,
              strokeWidth: 3,
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              secondsLeft == 0 ? '✓…' : '$secondsLeft',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: KingdomTheme.ink,
              ),
            ),
            Text(
              secondsLeft == 0 ? 'doğrulanıyor' : 'saniye',
              style: TextStyle(fontSize: 8, color: KingdomTheme.muted),
            ),
          ],
        ),
      ],
    ),
  );
}
