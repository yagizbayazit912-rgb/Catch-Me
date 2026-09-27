import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/zone.dart';
import '../services/auth_service.dart';
import '../services/hex_grid_service.dart';
import '../services/presence_service.dart';
import '../services/zone_repository.dart';
import '../widgets/hex_zone_layer.dart';
import '../widgets/radar_pulse.dart';
import '../theme/kingdom_theme.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  static const _hexService = HexGridService(hexSizeDeg: 0.0015, ringSize: 2);
  static const _fallback = LatLng(38.7312, 35.4787);

  final MapController _mapController = MapController();
  final _presence = PresenceService.instance;

  StreamSubscription<List<Zone>>? _zoneStream;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileStream;
  Timer? _uiTick;
  LatLng? _lastSubscribeLocation;
  bool _didCenterMap = false;

  List<Zone> _zones = [];
  Map<String, dynamic> _userProfile = {};
  String? _lastShownEvent;
  bool _debugMode = false;
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
    WidgetsBinding.instance.addObserver(this);
    _presence.addListener(_onPresence);
    _subscribeToProfile();
    _subscribeToZones(_presence.location);
    _startUiTick();
    // Activity hazır olduktan sonra GPS + görünür bildirim
    _presence.start();
    if (AuthService.startupWarning != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AuthService.startupWarning!)));
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presence.removeListener(_onPresence);
    _zoneStream?.cancel();
    _profileStream?.cancel();
    _uiTick?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPositionAfterResume();
    }
  }

  Future<void> _refreshPositionAfterResume() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      await _presence.onPosition(position);
    } catch (_) {
      // The live stream will retry; a synthetic position is never trusted.
    }
  }

  void _onPresence() {
    if (!mounted) return;
    final loc = _presence.location;
    if (!_didCenterMap) {
      _didCenterMap = true;
      try {
        _mapController.move(loc, _mapController.camera.zoom);
      } catch (_) {}
    }

    final last = _lastSubscribeLocation;
    final dist = last == null
        ? double.infinity
        : Geolocator.distanceBetween(
            last.latitude,
            last.longitude,
            loc.latitude,
            loc.longitude,
          );
    if (dist > 100) {
      _lastSubscribeLocation = loc;
      _subscribeToZones(loc);
    }

    final event = _presence.lastEvent;
    if (event != null && event != _lastShownEvent) {
      _lastShownEvent = event;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(event),
            backgroundColor: event.startsWith('🏰') || event.startsWith('⚔️')
                ? KingdomTheme.green.withValues(alpha: 0.9)
                : event.startsWith('⏳')
                ? KingdomTheme.gold.withValues(alpha: 0.95)
                : KingdomTheme.ink,
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
    }

    setState(() {});
  }

  void _startUiTick() {
    _uiTick = Timer.periodic(const Duration(seconds: 1), (_) {
      // Construction deadlines must repaint even when standing on owned land.
      if (mounted) setState(() {});
    });
  }

  void _subscribeToProfile() {
    _profileStream = AuthService.profileStream().listen((snap) {
      if (snap.exists && mounted) {
        final data = snap.data() ?? {};
        _presence.updateProfile(data);
        setState(() => _userProfile = data);
      }
    });
  }

  void _subscribeToZones(LatLng location) {
    _zoneStream?.cancel();
    _zoneStream = ZoneRepository.zonesAroundStream(location).listen((zones) {
      if (mounted) setState(() => _zones = zones);
    });
  }

  void _onMapTap(LatLng tapped) {
    final (q, r) = _hexService.latLngToAxial(tapped);
    final zone = _zones.where((z) => z.id == '$q:$r').firstOrNull;
    if (zone == null) return;

    if (_debugMode) {
      _presence.debugOccupy(zone);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🧪 ${zone.poiName ?? zone.id} — evde test'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.deepPurple.shade800,
        ),
      );
      return;
    }

    if (zone.ownerId == AuthService.uid) {
      _showOwnedZoneSheet(zone);
    } else {
      _showZoneInfoSheet(zone);
    }
  }

  void _showZoneInfoSheet(Zone zone) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StreamBuilder<int>(
        stream: Stream.periodic(const Duration(seconds: 1), (tick) => tick),
        builder: (_, _) {
          final live = _zones.where((z) => z.id == zone.id).firstOrNull ?? zone;
          final occupying =
              _presence.zone?.id == zone.id && _presence.isCapturing;
          return _ZoneInfoSheet(
            zone: live,
            isOccupying: occupying,
            captureProgress: occupying ? _presence.progress : 0,
            captureSecondsLeft: occupying ? _presence.secondsLeft : 0,
            captureTotalSeconds: occupying
                ? _presence.requiredSeconds
                : PresenceService.captureDuration(live),
          );
        },
      ),
    );
  }

  void _showOwnedZoneSheet(Zone zone) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _OwnedZoneSheet(zone: zone),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = _presence.location;
    final capturing = _presence.isCapturing;

    return Scaffold(
      backgroundColor: KingdomTheme.paper,
      body: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0005)
                ..rotateX(-0.50)
                ..multiply(Matrix4.diagonal3Values(1.4, 1.4, 1)),
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                  initialCenter: loc.latitude == 0 ? _fallback : loc,
                  initialZoom: 15.8,
                  maxZoom: 18,
                  onTap: (_, latLng) => _onMapTap(latLng),
                ),
                children: [
                  TileLayer(
                    urlTemplate: KingdomTheme.tileUrl,
                    maxNativeZoom: 19,
                    userAgentPackageName: 'com.example.catch_me',
                  ),
                  if (_zones.isNotEmpty)
                    HexZoneLayer(
                      zones: _zones,
                      playerId: AuthService.uid,
                      userLocation: loc,
                      captureZoneId: capturing ? _presence.zone?.id : null,
                      captureProgress: _presence.progress,
                      captureSecondsLeft: _presence.secondsLeft,
                    ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: loc,
                        width: 120,
                        height: 120,
                        child: const RadarPulse(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          _buildStatsBar(),
          if (_presence.permissionHint != null) _buildPermissionBanner(),
          _buildPresenceChip(),
          Positioned(bottom: 32, right: 16, child: _buildDebugButton()),
          const Positioned(
            bottom: 4,
            left: 8,
            right: 8,
            child: Text(
              KingdomTheme.attribution,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: KingdomTheme.muted,
                fontSize: 9,
                backgroundColor: KingdomTheme.parchment,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    final name = _userProfile['displayName'] as String? ?? 'Gezgin';
    final timeSeconds = AuthService.timeBalanceSeconds(_userProfile);
    final owned = (_userProfile['zonesOwned'] as num?)?.toInt() ?? 0;
    return Positioned(
      top: 0,
      left: 12,
      right: 12,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(14),
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
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CATCH ME',
                      style: TextStyle(
                        fontSize: 17,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w900,
                        color: KingdomTheme.ink,
                      ),
                    ),
                    Text(
                      '$name · $owned bölge',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: KingdomTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: KingdomTheme.paper,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.hourglass_bottom_rounded,
                      color: KingdomTheme.gold,
                      size: 19,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      AuthService.formatTime(timeSeconds),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: KingdomTheme.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresenceChip() {
    final capturing = _presence.isCapturing;
    final always = _presence.alwaysAllowed;
    final label = capturing
        ? 'Sahipleniliyor · ${_presence.captureLabel}'
        : always
        ? 'Arka plan açık  ·  günlük güzergâh'
        : 'Sadece uygulama açıkken';

    return Positioned(
      top: 92,
      left: 12,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: KingdomTheme.parchment,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: capturing
                  ? KingdomTheme.green
                  : always
                  ? KingdomTheme.green.withValues(alpha: 0.4)
                  : Colors.orange.withValues(alpha: 0.6),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: capturing ? KingdomTheme.green : KingdomTheme.muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionBanner() {
    return Positioned(
      top: 135,
      left: 16,
      right: 16,
      child: SafeArea(
        child: GestureDetector(
          onTap: () => Geolocator.openAppSettings(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: KingdomTheme.parchment,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange),
            ),
            child: Text(
              _presence.permissionHint!,
              style: const TextStyle(color: KingdomTheme.ink, fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDebugButton() {
    final capturing = _presence.isCapturing;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (capturing)
          FloatingActionButton.extended(
            heroTag: 'debug_progress',
            backgroundColor: KingdomTheme.parchment,
            foregroundColor: KingdomTheme.green,
            onPressed: null,
            label: Text(
              _presence.captureLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            icon: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                value: _presence.progress,
                strokeWidth: 2,
                color: KingdomTheme.green,
              ),
            ),
          )
        else
          FloatingActionButton.extended(
            heroTag: 'debug_toggle',
            backgroundColor: _debugMode
                ? Colors.deepPurple
                : KingdomTheme.parchment,
            foregroundColor: _debugMode ? Colors.white : KingdomTheme.green,
            onPressed: () {
              setState(() => _debugMode = !_debugMode);
              if (!_debugMode) _presence.clearDebugLock();
            },
            label: Text(
              _debugMode ? '🧪 Zone\'a dokun' : '🧪 Evde test',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            icon: Icon(
              _debugMode ? Icons.touch_app : Icons.science_outlined,
              size: 18,
            ),
          ),
      ],
    );
  }
}

class _ZoneInfoSheet extends StatelessWidget {
  const _ZoneInfoSheet({
    required this.zone,
    required this.isOccupying,
    required this.captureProgress,
    required this.captureSecondsLeft,
    required this.captureTotalSeconds,
  });

  final Zone zone;
  final bool isOccupying;
  final double captureProgress;
  final int captureSecondsLeft;
  final int captureTotalSeconds;

  @override
  Widget build(BuildContext context) {
    final isEnemy = zone.isOwned;
    final ownerInactive = PresenceService.ownerInactive(zone);
    final accentColor = isEnemy
        ? (zone.ownerColor ?? Colors.orange)
        : KingdomTheme.green;
    final captureColor = isEnemy ? Colors.orange : KingdomTheme.green;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      decoration: BoxDecoration(
        color: KingdomTheme.parchment,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isEnemy ? Icons.shield_outlined : Icons.hexagon_outlined,
                color: accentColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  zone.poiName ?? 'Bölge ${zone.id}',
                  style: const TextStyle(
                    color: KingdomTheme.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (isEnemy) ...[
            Text(
              'Sahibi: ${zone.ownerName}',
              style: TextStyle(color: accentColor, fontSize: 13),
            ),
            Text(
              'Kira: ${zone.rentLabel}/giriş  ·  ${kUpgradeNames[zone.upgradeLevel.clamp(0, 5)]}',
              style: const TextStyle(color: KingdomTheme.muted, fontSize: 12),
            ),
          ] else
            const Text(
              'Bu bölge henüz sahipsiz.',
              style: TextStyle(color: KingdomTheme.muted, fontSize: 13),
            ),
          const SizedBox(height: 16),
          if (isOccupying)
            Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    value: captureProgress,
                    strokeWidth: 4,
                    backgroundColor: KingdomTheme.paper,
                    valueColor: AlwaysStoppedAnimation(captureColor),
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEnemy
                          ? '⚔️  Bölge ele geçiriliyor…'
                          : '🏁  Sahipleniliyor…',
                      style: TextStyle(
                        color: captureColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      captureSecondsLeft == 0
                          ? 'Sunucu doğruluyor…'
                          : '$captureSecondsLeft / $captureTotalSeconds sn kaldı',
                      style: const TextStyle(
                        color: KingdomTheme.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accentColor.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.timer_outlined, color: accentColor, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isEnemy
                          ? ownerInactive
                                ? 'Sahibi 72 saattir görünmüyor · '
                                      '$captureTotalSeconds sn kuşat'
                                : 'Sahibi aktif · girişte ${zone.rentLabel} '
                                      'zaman kirası ödersin'
                          : 'Günlük hayatta 30 sn durunca otomatik senin olur',
                      style: TextStyle(color: accentColor, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _OwnedZoneSheet extends StatefulWidget {
  const _OwnedZoneSheet({required this.zone});
  final Zone zone;

  @override
  State<_OwnedZoneSheet> createState() => _OwnedZoneSheetState();
}

class _OwnedZoneSheetState extends State<_OwnedZoneSheet> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accent = KingdomTheme.green;
    final zone = widget.zone;
    final nextLevel = zone.upgradeLevel + 1;
    final canUpgrade = nextLevel <= 5;
    final cost = canUpgrade ? kUpgradeCostsSeconds[nextLevel] : 0;
    final buildTime = canUpgrade ? kUpgradeBuildSeconds[nextLevel] : 0;
    final busy = zone.isUnderConstruction;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      decoration: BoxDecoration(
        color: KingdomTheme.parchment,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star_outline, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  zone.poiName ?? 'Senin Bölgen',
                  style: const TextStyle(
                    color: KingdomTheme.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${kUpgradeNames[zone.visualUpgradeLevel]}  ·  ${zone.rentLabel}/giriş zaman kirası',
            style: const TextStyle(color: KingdomTheme.muted, fontSize: 13),
          ),
          if (busy) ...[
            const SizedBox(height: 14),
            Text(
              'İnşaat sürüyor · ${_remaining(zone.upgradeReadyAt!)} kaldı',
              style: const TextStyle(
                color: KingdomTheme.gold,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (canUpgrade)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        try {
                          await ZoneRepository.upgradeZone(zone.id, nextLevel);
                          if (context.mounted) Navigator.pop(context);
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(error.toString())),
                            );
                          }
                        }
                      },
                icon: const Icon(Icons.construction_rounded),
                label: Text(
                  '${kUpgradeNames[nextLevel]} inşa et  ·  '
                  '${AuthService.formatTime(cost)} zaman  ·  ${AuthService.formatTime(buildTime)}',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: KingdomTheme.gold,
                  foregroundColor: KingdomTheme.ink,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            )
          else
            const Text(
              'Gökdelen seviyesine ulaştı! 🏙️',
              style: TextStyle(color: KingdomTheme.muted),
            ),
        ],
      ),
    );
  }

  static String _remaining(DateTime until) {
    final seconds = (until.difference(DateTime.now()).inMilliseconds / 1000)
        .ceil()
        .clamp(0, 999999999);
    return AuthService.formatTime(seconds);
  }
}
