import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/zone.dart';
import 'auth_service.dart';
import 'hex_grid_service.dart';
import 'zone_repository.dart';

/// Location is sampled on the device, but capture, time credits, rent and
/// reclaim decisions are made by the Firebase transaction in recordPresence.
class PresenceService extends ChangeNotifier {
  PresenceService._();
  static final instance = PresenceService._();

  static const _hex = HexGridService();
  static const _notify = MethodChannel('catch_me/notify');

  StreamSubscription<Position>? _positionStream;
  Timer? _notifyTimer;
  Timer? _heartbeatTimer;
  Timer? _captureDeadline;
  int _zoneGeneration = 0;
  DateTime? _lastRequestAt;
  bool _captureSynced = false;
  SharedPreferences? _prefs;
  bool _started = false;
  bool _heartbeatInFlight = false;
  Position? _lastPosition;
  bool _debugLock = false;
  String _lastNotifKey = '';

  LatLng _location = const LatLng(38.7312, 35.4787);
  Zone? _zone;
  DateTime? _enteredAt;
  int _requiredSeconds = 30;
  String? _permissionHint;
  bool _alwaysAllowed = false;
  Map<String, dynamic> _profile = {};

  LatLng get location => _location;
  Zone? get zone => _zone;
  DateTime? get enteredAt => _enteredAt;
  int get requiredSeconds => _requiredSeconds;
  String? get permissionHint => _permissionHint;
  bool get alwaysAllowed => _alwaysAllowed;
  bool get hasFreshPosition => _lastPosition != null;
  bool get isCapturing =>
      _zone != null &&
      _zone!.ownerId != AuthService.uid &&
      _enteredAt != null &&
      (!_zone!.isOwned || ownerInactive(_zone!));

  bool get captureWaitingForServer => isCapturing && secondsLeft == 0;
  bool get captureSyncing => isCapturing && !_captureSynced && !_debugLock;
  String get captureLabel => captureSyncing
      ? 'Konum doğrulanıyor…'
      : captureWaitingForServer
      ? 'Doğrulanıyor…'
      : '$secondsLeft sn';

  int get secondsLeft {
    if (!isCapturing || _enteredAt == null) return 0;
    if (captureSyncing) return _requiredSeconds;
    final elapsed =
        DateTime.now().difference(_enteredAt!).inMilliseconds / 1000;
    return (_requiredSeconds - elapsed).ceil().clamp(0, _requiredSeconds);
  }

  double get progress {
    if (!isCapturing || _enteredAt == null) return 0;
    if (captureSyncing) return 0;
    final elapsed =
        DateTime.now().difference(_enteredAt!).inMilliseconds / 1000;
    return (elapsed / _requiredSeconds).clamp(0.0, 1.0);
  }

  String? lastEvent;

  static int captureDuration(Zone zone) {
    if (!zone.isOwned) return 30;
    final level = zone.upgradeLevel.clamp(0, kSiegeSeconds.length - 1);
    return kSiegeSeconds[level];
  }

  static bool ownerInactive(Zone zone, {DateTime? now}) {
    if (!zone.isOwned) return false;
    final last = zone.lastOwnerPresenceAt;
    return last == null ||
        (now ?? DateTime.now()).difference(last).inHours >= 72;
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _prefs = await SharedPreferences.getInstance();
    await _initLocation();
  }

  void updateProfile(Map<String, dynamic> profile) => _profile = profile;

  /// Local-only visual test. It never writes Firebase.
  Future<void> debugOccupy(Zone zone) async {
    _captureDeadline?.cancel();
    _zoneGeneration++;
    _debugLock = true;
    _zone = zone;
    _enteredAt = DateTime.now();
    _requiredSeconds = 4;
    lastEvent = null;
    _startHeartbeatTicker();
    notifyListeners();
  }

  void clearDebugLock() {
    _debugLock = false;
    _zone = null;
    final position = _lastPosition;
    if (position != null) onPosition(position);
  }

  Future<void> _initLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _permissionHint = 'Konum servisi kapalı.';
      notifyListeners();
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _permissionHint = 'Konum izni verilmedi.';
      notifyListeners();
      return;
    }

    _alwaysAllowed = permission == LocationPermission.always;
    _permissionHint = _alwaysAllowed
        ? null
        : 'Arka plan için Ayarlar → Konum → Her zaman izin ver';

    final settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
            intervalDuration: const Duration(seconds: 10),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'Catch Me krallığın çalışıyor',
              notificationText:
                  'Bölgelerin, zamanın ve kira hareketlerin takip ediliyor.',
              notificationChannelName: 'Catch Me konum',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : Platform.isIOS
        ? AppleSettings(
            accuracy: LocationAccuracy.high,
            activityType: ActivityType.fitness,
            distanceFilter: 10,
            pauseLocationUpdatesAutomatically: false,
            showBackgroundLocationIndicator: true,
            allowBackgroundLocationUpdates: true,
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          );

    try {
      final initial = await Geolocator.getCurrentPosition(
        locationSettings: settings,
      );
      await onPosition(initial);
    } catch (_) {
      _permissionHint = 'Konum alınamadı; GPS sinyalini kontrol et.';
      notifyListeners();
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(onPosition);
    _startNotifyLoop();
  }

  void _startHeartbeatTicker() {
    _heartbeatTimer?.cancel();
    // Five seconds keeps the authoritative 30-second capture responsive
    // without turning every GPS update into a network request.
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_debugLock) {
        _debugHeartbeat();
      } else {
        _heartbeat();
      }
    });
  }

  void _startNotifyLoop() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _notifyTimer?.cancel();
    _pushNotification(force: true);
    _notifyTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _pushNotification();
    });
  }

  Future<void> _pushNotification({bool force = false}) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final zone = _zone;
    final label = zone?.poiName ?? zone?.id ?? 'bölge';
    String title;
    String body;
    var progress = -1;
    var max = _requiredSeconds;
    if (isCapturing) {
      final left = secondsLeft;
      final done = (_requiredSeconds - left).clamp(0, _requiredSeconds);
      progress = done;
      title = zone!.isOwned ? 'Bölge kuşatılıyor' : 'Bölge sahipleniliyor';
      body = '$label · $captureLabel';
    } else if (zone != null && zone.ownerId == AuthService.uid) {
      title = 'Krallığın çalışıyor';
      body = '$label · zaman ve inşaat ilerlemesi sürüyor';
    } else {
      title = 'Catch Me açık';
      body = 'Günlük güzergâhındaki bölgeler takip ediliyor.';
    }
    final key = '$title|$body|$progress';
    if (!force && key == _lastNotifKey) return;
    _lastNotifKey = key;
    try {
      await _notify.invokeMethod('update', {
        'title': title,
        'body': body,
        'progress': progress,
        'max': max,
      });
    } catch (_) {}
  }

  Future<void> _alert(String title, String body) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await _notify.invokeMethod('alert', {'title': title, 'body': body});
    } catch (_) {}
  }

  Future<void> onPosition(Position position) async {
    _lastPosition = position;
    _location = LatLng(position.latitude, position.longitude);
    notifyListeners();

    if (_debugLock) {
      _debugHeartbeat();
      return;
    }
    if (position.accuracy <= 0 || position.accuracy > 90) {
      _permissionHint = 'GPS doğruluğu düşük; bölge işlemi bekliyor.';
      notifyListeners();
      return;
    }
    _permissionHint = _alwaysAllowed
        ? null
        : 'Arka plan için Ayarlar → Konum → Her zaman izin ver';

    final skeleton = _hex.zoneForLocation(_location);
    if (skeleton.id != _zone?.id) {
      Zone live;
      try {
        live = await ZoneRepository.loadZone(skeleton);
      } catch (_) {
        // Keep the map responsive while Firestore reconnects. The next
        // heartbeat still requires the live server document before capture.
        live = skeleton;
        lastEvent = 'Sunucu bekleniyor; bölge bilgisi yenilenecek.';
      }
      await _enterZone(live);
    } else {
      await _heartbeat();
    }
  }

  Future<void> _enterZone(Zone zone) async {
    _zoneGeneration++;
    _captureDeadline?.cancel();
    _captureSynced = false;
    _lastRequestAt = null;
    _zone = zone;
    _enteredAt = DateTime.now();
    _requiredSeconds = captureDuration(zone).clamp(30, 24 * 60 * 60);
    lastEvent = null;
    await _prefs?.setString('last_zone_id', zone.id);
    _startHeartbeatTicker();
    await _heartbeat();
    await _pushNotification(force: true);
    notifyListeners();
  }

  Future<void> _heartbeat({bool force = false}) async {
    if (_debugLock ||
        _heartbeatInFlight ||
        _zone == null ||
        _lastPosition == null) {
      return;
    }
    final position = _lastPosition!;
    if (position.accuracy <= 0 || position.accuracy > 90) return;
    if (!force &&
        _lastRequestAt != null &&
        DateTime.now().difference(_lastRequestAt!).inMilliseconds < 4000) {
      return;
    }
    final generation = _zoneGeneration;
    final requestedZone = _zone!;
    _lastRequestAt = DateTime.now();
    _heartbeatInFlight = true;
    try {
      final result = await ZoneRepository.recordPresence(
        zoneId: requestedZone.id,
        location: _location,
        accuracy: position.accuracy,
      );
      if (generation != _zoneGeneration) return;
      final captured = result['captured'] == true;
      final siegeCompleted = result['siegeCompleted'] == true;
      if (!captured &&
          !siegeCompleted &&
          result['ownerId'] != requestedZone.ownerId) {
        final live = await ZoneRepository.loadZone(requestedZone);
        if (generation != _zoneGeneration) return;
        _zone = live;
        if (!isCapturing) _captureDeadline?.cancel();
      }
      final rentPaid = (result['rentPaidSec'] as num?)?.toInt() ?? 0;
      final progress = (result['siegeProgressSec'] as num?)?.toInt() ?? 0;
      final required = (result['siegeRequiredSec'] as num?)?.toInt() ?? 0;
      if (isCapturing && !captured && !siegeCompleted) {
        final verified = requestedZone.isOwned
            ? (result['siegeProgressSec'] as num?)?.toDouble() ?? 0
            : (result['captureProgressSec'] as num?)?.toDouble() ?? 0;
        _requiredSeconds = requestedZone.isOwned && required > 0
            ? required
            : captureDuration(requestedZone);
        _enteredAt = DateTime.now().subtract(
          Duration(milliseconds: (verified * 1000).round()),
        );
        _captureSynced = true;
        _captureDeadline?.cancel();
        final remainingMs = ((_requiredSeconds - verified) * 1000).ceil();
        _captureDeadline = Timer(
          Duration(milliseconds: remainingMs.clamp(200, 86400000)),
          () {
            _heartbeat(force: true);
          },
        );
      }
      if (captured || siegeCompleted) {
        _captureDeadline?.cancel();
        final uid = AuthService.uid;
        _zone = _zone!.copyWith(
          ownerId: uid,
          ownerName: _profile['displayName'] as String? ?? 'Sen',
          ownerColor: AuthService.colorFromHex(
            _profile['colorHex'] as String? ?? '#3C7650',
          ),
          upgradeLevel: 0,
          siegeProgressSec: 0,
          siegeRequiredSec: 0,
        );
        _enteredAt = null;
        lastEvent = captured
            ? '🏰  ${_zone!.poiName ?? 'Bölge'} krallığına katıldı'
            : '⚔️  ${_zone!.poiName ?? 'Bölge'} kuşatmayla alındı';
        await _alert('Yeni toprak', _zone!.poiName ?? 'Bölge senin');
      } else if (rentPaid > 0) {
        lastEvent = '⏳  ${AuthService.formatTime(rentPaid)} kira ödendi';
        await _alert('Zaman kirası ödendi', AuthService.formatTime(rentPaid));
      } else if (progress > 0 && required > 0) {
        lastEvent =
            '⚔️  Kuşatma ${AuthService.formatTime(progress)} / ${AuthService.formatTime(required)}';
      }
      notifyListeners();
    } catch (error) {
      debugPrint('recordPresence HATASI: $error');
      if (generation != _zoneGeneration) return;
      // A network failure pauses the authoritative timer; it never grants a
      // local capture. The UI remains usable and retries on the next heartbeat.
      lastEvent = 'Sunucu bekleniyor; konum doğrulaması yeniden denenecek.';
      _captureSynced = false;
      _captureDeadline?.cancel();
      notifyListeners();
    } finally {
      _heartbeatInFlight = false;
    }
  }

  void _debugHeartbeat() {
    if (_zone == null || _enteredAt == null) return;
    final elapsed = DateTime.now().difference(_enteredAt!).inSeconds;
    if (elapsed >= _requiredSeconds && _zone!.ownerId != AuthService.uid) {
      _zone = _zone!.copyWith(
        ownerId: AuthService.uid,
        ownerName: 'Sen',
        ownerColor: const Color(0xFF3C7650),
        upgradeLevel: 0,
      );
      _enteredAt = null;
      lastEvent = '🏰  Önizleme toprağı alındı';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _captureDeadline?.cancel();
    _heartbeatTimer?.cancel();
    _notifyTimer?.cancel();
    _positionStream?.cancel();
    super.dispose();
  }
}
