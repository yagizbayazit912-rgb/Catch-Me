import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/zone.dart';

/// Nokta-üst (pointy-top) altıgen ızgara — dış bağımlılık gerektirmez.
///
/// Izgara derece uzayında tanımlanır, bu nedenle Mercator projeksiyonunda
/// düzgün altıgenler olarak görünür. [hexSizeDeg] merkez→köşe mesafesidir.
class HexGridService {
  const HexGridService({this.hexSizeDeg = 0.0015, this.ringSize = 2});

  final double hexSizeDeg; // ~167 m Türkiye enleminde
  final int ringSize; // merkez dahil toplam: (3k²+3k+1) hücre

  // ---------------------------------------------------------------------------
  // Eksen koordinatı ↔ coğrafi dönüşümler
  // ---------------------------------------------------------------------------

  /// Eksen (q, r) → dünya koordinatı (lat, lng).
  LatLng axialToLatLng(int q, int r) {
    final lng = (q + r / 2.0) * math.sqrt(3) * hexSizeDeg;
    final lat = r * 1.5 * hexSizeDeg;
    return LatLng(lat, lng);
  }

  /// Dünya koordinatı → en yakın eksen (q, r) — küp yuvarlama kullanır.
  (int, int) latLngToAxial(LatLng point) {
    final r = point.latitude / (1.5 * hexSizeDeg);
    final q = point.longitude / (math.sqrt(3) * hexSizeDeg) - r / 2.0;
    return _cubeRound(q, r);
  }

  (int, int) _cubeRound(double q, double r) {
    final s = -q - r;
    var rq = q.round();
    var rr = r.round();
    var rs = s.round();
    final dq = (rq - q).abs();
    final dr = (rr - r).abs();
    final ds = (rs - s).abs();
    if (dq > dr && dq > ds) {
      rq = -rr - rs;
    } else if (dr > ds) {
      rr = -rq - rs;
    }
    return (rq, rr);
  }

  // ---------------------------------------------------------------------------
  // Altıgen geometrisi
  // ---------------------------------------------------------------------------

  /// Eksen (q, r)'deki altıgenin 6 köşesini döner.
  /// Nokta-üst (pointy-top): lat → sin, lng → cos — ızgara aralığıyla hizalı.
  List<LatLng> hexVertices(int q, int r) {
    final center = axialToLatLng(q, r);
    return List.generate(6, (i) {
      final angleDeg = 60.0 * i + 30.0; // 30, 90, 150, 210, 270, 330
      final angleRad = angleDeg * math.pi / 180.0;
      return LatLng(
        center.latitude + hexSizeDeg * math.sin(angleRad), // y → lat
        center.longitude + hexSizeDeg * math.cos(angleRad), // x → lng
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Halka üretimi
  // ---------------------------------------------------------------------------

  /// Kullanıcı konumu etrafında [ringSize] yarıçaplı halkanın tüm
  /// eksen koordinatlarını döner.
  List<(int, int)> ringAround(LatLng userLocation) {
    final (cq, cr) = latLngToAxial(userLocation);
    final k = ringSize;
    final cells = <(int, int)>[];
    for (int dq = -k; dq <= k; dq++) {
      final rMin = math.max(-k, -dq - k);
      final rMax = math.min(k, -dq + k);
      for (int dr = rMin; dr <= rMax; dr++) {
        cells.add((cq + dq, cr + dr));
      }
    }
    return cells;
  }

  // ---------------------------------------------------------------------------
  // Zone üretimi — sahiplik Firestore'dan gelir, ızgara sadece geometri üretir
  // ---------------------------------------------------------------------------

  static const _poiOffsets = {
    '2:1': 'Merkezi Çarşı',
    '-2:2': 'Belediye Parkı',
    '3:-1': 'Üniversite Kampüsü',
    '-1:-3': 'Şehir Stadyumu',
    '0:3': 'Alışveriş Merkezi',
  };

  /// (q, r) için sahipsiz bir zone iskeleti üretir.
  Zone zoneAt(int q, int r, {int? originQ, int? originR}) {
    final poiKey = (originQ != null && originR != null)
        ? '${q - originQ}:${r - originR}'
        : null;
    return Zone(
      id: '$q:$r',
      q: q,
      r: r,
      center: axialToLatLng(q, r),
      boundary: hexVertices(q, r),
      poiName: poiKey == null ? null : _poiOffsets[poiKey],
    );
  }

  /// Konumun düştüğü hücreyi döner (sahiplik yok).
  Zone zoneForLocation(LatLng location) {
    final (q, r) = latLngToAxial(location);
    return zoneAt(q, r);
  }

  /// Kullanıcı konumu etrafındaki boş bölgeleri üretir.
  /// Sahiplik burada yazılmaz — Firestore overlay'i ekler.
  List<Zone> generateZones(LatLng userLocation, {String? userId}) {
    final (cq, cr) = latLngToAxial(userLocation);
    return ringAround(userLocation)
        .map((cell) => zoneAt(cell.$1, cell.$2, originQ: cq, originR: cr))
        .toList();
  }
}
