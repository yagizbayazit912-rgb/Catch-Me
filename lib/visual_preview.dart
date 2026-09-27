import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'models/zone.dart';
import 'services/hex_grid_service.dart';
import 'theme/kingdom_theme.dart';
import 'widgets/hex_zone_layer.dart';

/// Art playground. No Firebase initialization, location permission or writes.
/// Run: flutter run -t lib/visual_preview.dart
void main() => runApp(const KingdomPreviewApp());

class KingdomPreviewApp extends StatelessWidget {
  const KingdomPreviewApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Catch Me · Krallık önizlemesi',
    theme: KingdomTheme.data,
    home: const KingdomPreviewScreen(),
  );
}

class KingdomPreviewScreen extends StatefulWidget {
  const KingdomPreviewScreen({super.key, this.showTiles = true});
  final bool showTiles;
  @override
  State<KingdomPreviewScreen> createState() => _KingdomPreviewScreenState();
}

class _KingdomPreviewScreenState extends State<KingdomPreviewScreen> {
  static const _hex = HexGridService();
  static const _anchor = LatLng(41.042, 29.040);
  static const _uid = 'visual-preview';
  final _map = MapController();
  late List<Zone> _zones;
  late String _selectedId;
  String? _capturingId;
  double _progress = 0;
  Timer? _timer;
  bool _artLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_artLoaded) {
      _artLoaded = true;
      for (final asset in KingdomTheme.assets.whereType<String>()) {
        precacheImage(ResizeImage(AssetImage(asset), width: 384), context);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    _timer?.cancel();
    _capturingId = null;
    _progress = 0;
    final center = _hex.zoneForLocation(_anchor);
    _selectedId = center.id;
    _zones = _hex.generateZones(_anchor).map((z) {
      final dq = z.q - center.q;
      final dr = z.r - center.r;
      if (dq == 0 && dr == 0) return _own(z, 1);
      if (dq == 1 && dr == -1) return _own(z, 5);
      if (dq == -1 && dr == 0) return _own(z, 3);
      if (dq == 1 && dr == 0) return _own(z, 0);
      return z;
    }).toList();
  }

  Zone _own(Zone zone, int level) => zone.copyWith(
    ownerId: _uid,
    ownerName: 'Sen',
    ownerColor: KingdomTheme.green,
    upgradeLevel: level,
  );

  Zone get _selected => _zones.firstWhere((z) => z.id == _selectedId);

  void _capture() {
    final target = _zones.where((z) => !z.isOwned).toList()
      ..sort(
        (a, b) => const Distance()
            .as(LengthUnit.Meter, a.center, _anchor)
            .compareTo(
              const Distance().as(LengthUnit.Meter, b.center, _anchor),
            ),
      );
    if (target.isEmpty) return;
    final id = target.first.id;
    setState(() {
      _capturingId = id;
      _progress = 0;
    });
    _map.move(target.first.center, _map.camera.zoom);
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      final t = timer.tick / 40;
      if (t >= 1) {
        timer.cancel();
        setState(() {
          _zones = _zones.map((z) => z.id == id ? _own(z, 0) : z).toList();
          _selectedId = id;
          _capturingId = null;
          _progress = 1;
        });
      } else {
        setState(() => _progress = t);
      }
    });
  }

  void _upgrade() {
    final z = _selected;
    if (!z.isOwned || z.upgradeLevel >= 5) return;
    setState(
      () => _zones = _zones
          .map(
            (item) => item.id == z.id
                ? item.copyWith(upgradeLevel: item.upgradeLevel + 1)
                : item,
          )
          .toList(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final level = selected.upgradeLevel.clamp(0, 5);
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              initialCenter: _hex.zoneForLocation(_anchor).center,
              initialZoom: 15.8,
              minZoom: 13,
              maxZoom: 18,
              backgroundColor: KingdomTheme.paper,
              onTap: (_, point) {
                final id = _hex.zoneForLocation(point).id;
                if (_zones.any((z) => z.id == id && z.isOwned)) {
                  setState(() => _selectedId = id);
                }
              },
            ),
            children: [
              if (widget.showTiles)
                TileLayer(
                  urlTemplate: KingdomTheme.tileUrl,
                  userAgentPackageName: 'com.example.catch_me',
                  maxNativeZoom: 19,
                ),
              HexZoneLayer(
                zones: _zones,
                userLocation: _anchor,
                playerId: _uid,
                captureZoneId: _capturingId,
                captureProgress: _progress,
                captureSecondsLeft: ((1 - _progress) * 4).ceil(),
              ),
            ],
          ),
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: KingdomTheme.panel(),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: KingdomTheme.green,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.castle_rounded,
                        color: KingdomTheme.parchment,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CATCH ME',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                          Text(
                            'Küçük adımlar. Büyük bir krallık.',
                            style: TextStyle(
                              fontSize: 10,
                              color: KingdomTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.toll_rounded, color: KingdomTheme.gold),
                    const SizedBox(width: 5),
                    const Text(
                      '100',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 98,
            left: 18,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: KingdomTheme.panel(radius: 20),
                child: const Text(
                  'Görsel önizleme · Örnek bölgeler',
                  style: TextStyle(
                    fontSize: 10,
                    color: KingdomTheme.green,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: KingdomTheme.panel(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.shield_outlined,
                          color: KingdomTheme.green,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'SENİN TOPRAĞIN',
                            style: TextStyle(
                              color: KingdomTheme.green,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Önizlemeyi sıfırla',
                          onPressed: () {
                            setState(_reset);
                            _map.move(
                              _hex.zoneForLocation(_anchor).center,
                              15.8,
                            );
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                        ),
                      ],
                    ),
                    Text(
                      KingdomTheme.levels[level],
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Haritadaki bir yapıya dokun ve geliştirmeyi dene.',
                      style: TextStyle(fontSize: 11, color: KingdomTheme.muted),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _capturingId == null && level < 5
                                ? _upgrade
                                : null,
                            icon: const Icon(
                              Icons.construction_rounded,
                              size: 17,
                            ),
                            label: Text(level < 5 ? 'Yükselt' : 'Son seviye'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _capturingId == null ? _capture : null,
                            icon: const Icon(Icons.flag_outlined, size: 17),
                            label: const Text('Ele geçir'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Positioned(
            bottom: 4,
            left: 4,
            right: 4,
            child: Text(
              KingdomTheme.attribution,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 8,
                color: KingdomTheme.ink,
                backgroundColor: KingdomTheme.parchment,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
